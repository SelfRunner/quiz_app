import '../../../ai/ai_tools_service.dart';

/// UI labels for the AI note tools.
extension NoteToolKindLabels on NoteToolKind {
  /// Menu label ("Summarize").
  String get label => switch (this) {
    NoteToolKind.summarize => 'Summarize',
    NoteToolKind.simplify => 'Simplify',
    NoteToolKind.expand => 'Expand',
    NoteToolKind.translate => 'Translate…',
    NoteToolKind.studyGuide => 'Study guide',
    NoteToolKind.fixFormatting => 'Fix formatting',
  };

  /// Short description under the menu label.
  String get description => switch (this) {
    NoteToolKind.summarize => 'Gist and key points',
    NoteToolKind.simplify => 'Plainer language, same facts',
    NoteToolKind.expand => 'More depth and examples',
    NoteToolKind.translate => 'Into another language',
    NoteToolKind.studyGuide => 'Concepts, pitfalls, self-check',
    NoteToolKind.fixFormatting => 'Clean up Markdown only',
  };

  /// Progress text ("Summarizing your note…").
  String get progress => switch (this) {
    NoteToolKind.summarize => 'Summarizing your note…',
    NoteToolKind.simplify => 'Simplifying your note…',
    NoteToolKind.expand => 'Expanding your note…',
    NoteToolKind.translate => 'Translating your note…',
    NoteToolKind.studyGuide => 'Writing a study guide…',
    NoteToolKind.fixFormatting => 'Fixing the formatting…',
  };

  /// Suffix for "Save as new note" titles.
  String get titleSuffix => switch (this) {
    NoteToolKind.summarize => 'Summary',
    NoteToolKind.simplify => 'Simplified',
    NoteToolKind.expand => 'Expanded',
    NoteToolKind.translate => 'Translation',
    NoteToolKind.studyGuide => 'Study guide',
    NoteToolKind.fixFormatting => 'Formatted',
  };
}

/// Panel title for a tool ("Translate to Spanish").
String noteToolTitle(NoteTool tool) => tool.kind == NoteToolKind.translate
    ? 'Translate to ${tool.targetLanguage}'
    : tool.kind.label;

/// Title for a note saved from a tool result: the original title plus a
/// suffix ("Cells (Summary)", "Células (Spanish)").
String noteToolNewTitle(
  String originalTitle,
  NoteTool tool, {
  String? suggested,
}) {
  final base = originalTitle.trim().isEmpty
      ? 'Untitled note'
      : originalTitle.trim();
  if (tool.kind == NoteToolKind.translate) {
    final translated = suggested?.trim();
    final title = translated == null || translated.isEmpty ? base : translated;
    return '$title (${tool.targetLanguage})';
  }
  return '$base (${tool.kind.titleSuffix})';
}

/// Languages offered by the translate picker.
const List<String> kTranslateLanguages = [
  'English',
  'Spanish',
  'French',
  'German',
  'Italian',
  'Portuguese',
  'Dutch',
  'Polish',
  'Russian',
  'Ukrainian',
  'Turkish',
  'Arabic',
  'Hindi',
  'Bengali',
  'Chinese (Simplified)',
  'Japanese',
  'Korean',
  'Indonesian',
  'Vietnamese',
];

/// [original] with [addition] appended as new block(s).
String appendMarkdown(String original, String addition) {
  final a = original.trimRight();
  final b = addition.trim();
  if (a.isEmpty) return '$b\n';
  return '$a\n\n$b\n';
}
