import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/ai_tools_service.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/models/quiz_attempt.dart';
import '../../../data/models/quiz_source.dart';
import '../../../data/repositories/note_repository.dart';

/// What "Explain this" explains: a question, the user's answer (null when
/// unknown, e.g. from the Mistakes list) and the quiz it belongs to (its
/// notes ground the explanation).
@immutable
class ExplainTarget {
  const ExplainTarget({required this.question, this.answer, this.quiz});

  final Question question;
  final QuestionAnswer? answer;
  final Quiz? quiz;

  /// Cache key: the quiz, the question's content and the user's answer
  /// (question ids are re-keyed in combined sessions, so content is used).
  String get cacheKey {
    final q = question;
    final a = answer;
    final selected = [...?a?.selectedIndices]..sort();
    return [
      quiz?.id ?? '-',
      q.type.wireName,
      q.prompt,
      q.options.join('\u001f'),
      q.correctIndices.join(','),
      q.answerText ?? '',
      if (a == null) '<none>' else selected.join(','),
      a?.textAnswer?.trim() ?? '',
    ].join('\u001e');
  }
}

/// Maximum number of the quiz's notes sent as context.
const int maxExplainNotes = 5;

/// The quiz's source notes that are available locally (its `noteId` plus
/// `source.notes`), as AI sources. Missing, deleted, empty or unreadable
/// notes are skipped; never throws.
Future<List<NoteSource>> loadQuizNoteSources(
  NoteRepository notes,
  Quiz quiz,
) async {
  final ids = <String>{
    ?quiz.noteId,
    for (final ref in quiz.source?.notes ?? const <QuizSourceRef>[]) ref.id,
  };
  final out = <NoteSource>[];
  for (final id in ids) {
    if (out.length >= maxExplainNotes) break;
    try {
      final note = await notes.getById(id);
      if (note == null || note.deletedAt != null) continue;
      if (note.contentMd.trim().isEmpty) continue;
      out.add(
        NoteSource(id: note.id, title: note.title, markdown: note.contentMd),
      );
    } on Object catch (e) {
      debugPrint('Could not load note $id for an explanation: $e');
    }
  }
  return out;
}

/// In-memory cache of explanations for the app session (per signed-in
/// user). Concurrent requests for the same key share one call; failures
/// are not cached so "Try again" makes a new request.
class ExplanationCache {
  final Map<String, Future<AiExplanation>> _entries = {};

  /// Number of cached (or in-flight) explanations.
  int get length => _entries.length;

  /// The cached explanation for [key], if it already completed or is
  /// in flight.
  Future<AiExplanation>? peek(String key) => _entries[key];

  Future<AiExplanation> getOrCreate(
    String key,
    Future<AiExplanation> Function() create,
  ) {
    final existing = _entries[key];
    if (existing != null) return existing;
    final future = create();
    _entries[key] = future;
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_entries[key], future)) _entries.remove(key);
      },
    );
    return future;
  }

  void clear() => _entries.clear();
}

/// The session's explanation cache, rebuilt when the user changes.
final explanationCacheProvider = Provider<ExplanationCache>((ref) {
  ref.watch(currentUserIdProvider);
  return ExplanationCache();
});

/// Explains [target] (cached per question + answer). The quiz's local
/// notes are sent as sources when available. Throws the AI layer's typed
/// errors.
Future<AiExplanation> explainAnswer(WidgetRef ref, ExplainTarget target) =>
    _explain(
      ref.read(explanationCacheProvider),
      ref.read(aiToolsServiceProvider),
      ref.read(noteRepositoryProvider),
      target,
    );

Future<AiExplanation> _explain(
  ExplanationCache cache,
  AiToolsService tools,
  NoteRepository notes,
  ExplainTarget target,
) => cache.getOrCreate(target.cacheKey, () async {
  final quiz = target.quiz;
  final sources = quiz == null
      ? const <NoteSource>[]
      : await loadQuizNoteSources(notes, quiz);
  return tools.explainAnswer(target.question, target.answer, sources: sources);
});
