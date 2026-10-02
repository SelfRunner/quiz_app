import 'package:meta/meta.dart';

import '../../../ai/ai_service.dart';
import '../../../ai/llm_provider.dart';

/// How generated flashcards are phrased.
enum DeckCardStyle {
  qa(
    'Q&A',
    'Question and answer: the front is a specific question, the back a '
        'concise answer (a word, phrase or 1-2 sentences).',
  ),
  term(
    'Term / definition',
    'Term and definition: the front is a key term, name or concept, the '
        'back its definition or explanation in 1-2 sentences.',
  ),
  cloze(
    'Cloze',
    'Cloze deletion: the front is a sentence from the material with one '
        'key word or phrase replaced by "____", the back is the missing '
        'word or phrase only.',
  );

  const DeckCardStyle(this.label, this.instruction);
  final String label;
  final String instruction;
}

/// Limits for the card-count option.
const int minDeckCards = 1;
const int maxDeckCards = 100;
const int defaultDeckCards = 20;

/// One generated card (no id yet).
@immutable
class CardDraft {
  const CardDraft({required this.front, required this.back, this.hint});

  final String front;
  final String back;
  final String? hint;
}

/// AI output for a flashcard deck, validated by [validateDeckDraft].
@immutable
class DeckDraft {
  const DeckDraft({
    required this.title,
    this.description,
    this.cards = const [],
  });

  final String title;
  final String? description;
  final List<CardDraft> cards;
}

const String deckSchemaName = 'DeckDraft';

/// JSON Schema of [DeckDraft] (strict-mode friendly like the quiz schema:
/// all properties required, nullables as `[type, 'null']`).
const Map<String, Object?> deckDraftJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'title': 'DeckDraft',
  'type': 'object',
  'additionalProperties': false,
  'required': ['title', 'description', 'cards'],
  'properties': {
    'title': {'type': 'string', 'description': 'Short deck title.'},
    'description': {
      'type': ['string', 'null'],
      'description': 'One-sentence summary of the deck.',
    },
    'cards': {
      'type': 'array',
      'minItems': 1,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['front', 'back', 'hint'],
        'properties': {
          'front': {'type': 'string', 'description': 'Prompt side.'},
          'back': {'type': 'string', 'description': 'Answer side.'},
          'hint': {
            'type': ['string', 'null'],
            'description':
                'Optional short hint that does not give the answer '
                'away; null when not useful.',
          },
        },
      },
    },
  },
};

const String deckSystemPrompt = '''
You are an expert teacher who writes accurate, high-quality flashcards for spaced-repetition study.

Rules:
- Output ONLY a JSON object that matches the provided schema exactly: keys "title", "description", "cards"; each card has "front", "back", "hint". No Markdown, no extra keys, no commentary.
- Base every card strictly on the provided source material. Do not invent facts that the source does not support.
- One idea per card (minimum information principle): short, atomic, unambiguous. The front must have exactly one correct answer, which is the back.
- Cover the most important ideas across the whole source; no duplicates or near-duplicates.
- Cards are self-contained: never reference "the text", "the video", source numbers, attachment labels or file names.
- "hint" is a short nudge that does not reveal the answer, or null.''';

/// The task line(s) of the user prompt.
String deckTask({required int count, required DeckCardStyle style}) =>
    'Create a flashcard deck with exactly $count cards.\n'
    'Card style: ${style.instruction}\n'
    'Give the deck a short, specific "title" and a one-sentence '
    '"description".';

StructuredGenerationRequest deckGenerationRequest({
  required List<AiSource> sources,
  required int count,
  required DeckCardStyle style,
  String? language,
  String? topic,
  String? extraInstructions,
  LlmProviderId? providerId,
  String? model,
}) => StructuredGenerationRequest(
  sources: sources,
  task: deckTask(count: count, style: style),
  systemPrompt: deckSystemPrompt,
  schema: deckDraftJsonSchema,
  schemaName: deckSchemaName,
  language: language,
  topic: topic,
  extraInstructions: extraInstructions,
  providerId: providerId,
  model: model,
);

String? _str(Object? v) => v is String ? v.trim() : null;

/// Validates and normalizes AI output: trims text, drops cards without a
/// front or back and exact duplicates, caps at [maxCards]. Fails when the
/// title is missing or no usable card remains.
DraftValidation<DeckDraft> validateDeckDraft(
  Map<String, dynamic> json, {
  int maxCards = maxDeckCards,
}) {
  final errors = <String>[];
  final title = _str(json['title']);
  if (title == null || title.isEmpty) {
    errors.add('"title" must be a non-empty string.');
  }
  final description = _str(json['description']);
  final raw = json['cards'];
  final cards = <CardDraft>[];
  final seen = <String>{};
  if (raw is! List) {
    errors.add('"cards" must be an array.');
  } else {
    for (final item in raw) {
      if (item is! Map) continue;
      final front = _str(item['front']) ?? '';
      final back = _str(item['back']) ?? '';
      if (front.isEmpty || back.isEmpty) continue;
      if (!seen.add('${front.toLowerCase()}\u0000${back.toLowerCase()}')) {
        continue;
      }
      final hint = _str(item['hint']);
      cards.add(
        CardDraft(
          front: front,
          back: back,
          hint: hint == null || hint.isEmpty ? null : hint,
        ),
      );
      if (cards.length >= maxCards) break;
    }
    if (cards.isEmpty) {
      errors.add(
        '"cards" must contain at least one card with a non-empty '
        '"front" and "back".',
      );
    }
  }
  if (errors.isNotEmpty) return DraftValidation(null, errors);
  return DraftValidation(
    DeckDraft(
      title: title!,
      description: description == null || description.isEmpty
          ? null
          : description,
      cards: cards,
    ),
    const [],
  );
}
