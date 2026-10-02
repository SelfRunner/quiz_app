import 'package:meta/meta.dart';

import '../data/models/question.dart';
import '../data/models/quiz_attempt.dart';
import 'ai_chat_service.dart';
import 'ai_service.dart';
import 'llm_provider.dart';

export 'ai_chat_service.dart'
    show ChatCitation, ChatCitations, ChatSourceRef, ChatSourceStatus;
export 'ai_source.dart';

/// AI note tools ([AiToolsService.transformNote]).
enum NoteToolKind {
  summarize,
  simplify,
  expand,
  translate,
  studyGuide,
  fixFormatting;

  /// Tools that must keep all of the note's content: the input is never
  /// shortened (too-long notes are rejected instead).
  bool get isFaithful => switch (this) {
    NoteToolKind.summarize || NoteToolKind.studyGuide => false,
    _ => true,
  };
}

/// A note tool plus its parameter (target language for translate).
@immutable
class NoteTool {
  const NoteTool._(this.kind, [this.targetLanguage]);

  /// Concise overview: gist + key points.
  static const summarize = NoteTool._(NoteToolKind.summarize);

  /// Plainer language for beginners; same facts and structure.
  static const simplify = NoteTool._(NoteToolKind.simplify);

  /// More depth, explanations and examples.
  static const expand = NoteTool._(NoteToolKind.expand);

  /// Overview, key concepts, details, pitfalls, self-check questions.
  static const studyGuide = NoteTool._(NoteToolKind.studyGuide);

  /// Markdown cleanup only; wording unchanged.
  static const fixFormatting = NoteTool._(NoteToolKind.fixFormatting);

  /// Faithful translation into [targetLanguage] (a language name or code,
  /// e.g. `Spanish`, `de`).
  factory NoteTool.translate(String targetLanguage) =>
      NoteTool._(NoteToolKind.translate, targetLanguage.trim());

  final NoteToolKind kind;

  /// Only for [NoteToolKind.translate].
  final String? targetLanguage;

  @override
  bool operator ==(Object other) =>
      other is NoteTool &&
      other.kind == kind &&
      other.targetLanguage == targetLanguage;

  @override
  int get hashCode => Object.hash(kind, targetLanguage);

  @override
  String toString() =>
      'NoteTool(${kind.name}${targetLanguage == null ? '' : ', $targetLanguage'})';
}

/// Output of a note tool: Markdown to preview, then save as a new note or
/// replace the original (the UI's choice; nothing is written here).
@immutable
class NoteToolResult {
  const NoteToolResult({
    required this.markdown,
    required this.selection,
    this.title,
    this.inputTruncated = false,
  });

  /// Suggested title (translated / "Summary: ..."), null = keep the note's.
  final String? title;
  final String markdown;
  final AiSelection selection;

  /// The note was longer than the input budget and only an excerpt was
  /// used (summarize / study guide only).
  final bool inputTruncated;
}

/// "Explain this" for a quiz question.
@immutable
class AiExplanation {
  const AiExplanation({
    required this.markdown,
    required this.selection,
    this.citations = const [],
    this.sources = const [],
  });

  /// Markdown, may contain `[S#]` markers when sources were given.
  final String markdown;
  final List<ChatCitation> citations;
  final List<ChatSourceRef> sources;
  final AiSelection selection;
}

/// Grade of a short answer.
enum GradeVerdict {
  correct('correct'),
  partial('partial'),
  incorrect('incorrect');

  const GradeVerdict(this.wireName);
  final String wireName;
}

/// Result of [AiToolsService.gradeShortAnswer].
@immutable
class ShortAnswerGrade {
  const ShortAnswerGrade({
    required this.verdict,
    required this.score,
    required this.feedback,
    this.selection,
  });

  final GradeVerdict verdict;

  /// 0..1, consistent with [verdict]: correct 0.8-1, partial 0.2-0.8,
  /// incorrect 0-0.2 (out-of-band model scores are clamped).
  final double score;

  /// One or two sentences for the learner.
  final String feedback;

  /// Null when graded locally (blank answer).
  final AiSelection? selection;

  /// Maps to `QuestionAnswer.isCorrect` (partial counts as wrong).
  bool get isCorrect => verdict == GradeVerdict.correct;
}

/// One-shot AI helpers for notes and quizzes (structured output, one repair
/// retry, never writes to the database).
///
/// Errors: `AiException` (missingApiKey, invalidApiKey, rateLimited,
/// invalidOutput, unsupported, provider), `ValidationException` (empty or
/// too-long note, missing target language), `NetworkException`.
abstract interface class AiToolsService {
  /// Applies [tool] to a note's Markdown and returns the new Markdown.
  ///
  /// Faithful tools (simplify, expand, translate, fixFormatting) reject
  /// notes over the input limit (60k chars) with `ValidationException`;
  /// summarize / studyGuide use an excerpt (`inputTruncated`).
  /// [language]: output language for non-translate tools (null = the
  /// note's language).
  Future<NoteToolResult> transformNote(
    String markdown,
    NoteTool tool, {
    String? title,
    String? language,
    String? extraInstructions,
    LlmProviderId? providerId,
    String? model,
  });

  /// Explains the correct answer of [question] and, when [userAnswer] is
  /// wrong, what went wrong. [sources] (e.g. the quiz's note) ground the
  /// explanation and come back as citations.
  Future<AiExplanation> explainAnswer(
    Question question,
    QuestionAnswer? userAnswer, {
    List<AiSource> sources = const [],
    String? language,
    LlmProviderId? providerId,
    String? model,
  });

  /// Grades a free-text answer against the expected [modelAnswer]. A blank
  /// [userAnswer] is graded locally (incorrect, 0) without a request.
  Future<ShortAnswerGrade> gradeShortAnswer(
    String question,
    String modelAnswer,
    String userAnswer, {
    String? language,
    LlmProviderId? providerId,
    String? model,
  });
}
