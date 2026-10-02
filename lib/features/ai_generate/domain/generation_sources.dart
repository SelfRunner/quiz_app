import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../ai/ai_capabilities.dart';
import '../../../ai/ai_service.dart';
import '../../../ai/llm_provider.dart';
import '../../../ai/providers/attachment_support.dart' show ProviderLimits;
import '../../../ai/youtube_url.dart';
import '../../../data/models/models.dart';

/// Max characters of pasted text kept in `QuizSource.contextText`.
const int maxStoredContextChars = 20000;

/// Extensions offered by "Upload new". Text files (.txt/.md/.docx) are
/// converted to text in-app and work with every model; the rest depends on
/// what the model can read.
List<String> uploadExtensions(AiCapabilities caps) => [
  'txt',
  'md',
  'docx',
  if (caps.pdf) 'pdf',
  if (caps.image) ...['png', 'jpg', 'jpeg', 'webp', 'gif'],
  if (caps.audio) ...['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
  if (caps.video) ...['mp4', 'mov', 'webm', 'avi'],
];

/// "Text, Word, PDF and image files" for the upload hint.
String uploadKindsLabel(AiCapabilities caps) {
  final parts = [
    'text',
    'Word',
    if (caps.pdf) 'PDF',
    if (caps.image) 'image',
    if (caps.audio) 'audio',
    if (caps.video) 'video',
  ];
  final head = parts.sublist(0, parts.length - 1).join(', ');
  final label = '$head and ${parts.last} files';
  return label[0].toUpperCase() + label.substring(1);
}

/// Why a library file of [kind] can't be used with the current model, or
/// null when it can.
String? fileKindProblem(AttachmentKind kind, AiCapabilities caps) =>
    switch (kind) {
      AttachmentKind.text || AttachmentKind.docx => null,
      AttachmentKind.pdf when caps.pdf => null,
      AttachmentKind.image when caps.image => null,
      AttachmentKind.audio when caps.audio => null,
      AttachmentKind.video when caps.video => null,
      AttachmentKind.pdf =>
        "This model can't read PDFs — switch to Gemini/OpenAI/Claude in "
            'Settings.',
      AttachmentKind.image =>
        "This model can't read images — switch to Gemini/OpenAI/Claude in "
            'Settings.',
      AttachmentKind.audio =>
        "This model can't listen to audio — switch to Gemini in Settings.",
      AttachmentKind.video =>
        "This model can't watch videos — switch to Gemini in Settings.",
      AttachmentKind.other => "This file type can't be used with AI.",
    };

/// Whether the attachment is sent as extracted text (works everywhere).
bool isTextAttachment(Attachment a) =>
    a.kind == AttachmentKind.text || a.kind == AttachmentKind.docx;

IconData attachmentKindIcon(AttachmentKind kind) => switch (kind) {
  AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
  AttachmentKind.image => Icons.image_outlined,
  AttachmentKind.text => Icons.notes_outlined,
  AttachmentKind.docx => Icons.description_outlined,
  AttachmentKind.audio => Icons.audiotrack_outlined,
  AttachmentKind.video => Icons.movie_outlined,
  AttachmentKind.other => Icons.insert_drive_file_outlined,
};

/// Human-readable size (e.g. `14.2 MB`).
String formatFileSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < 1024) return '$bytes B';
  if (bytes < mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * mb) {
    final v = bytes / mb;
    return '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
}

/// Bytes of binary (non-text) files that are sent as attachments.
int binaryFileBytes(Iterable<Attachment> files) => files
    .where((a) => !isTextAttachment(a))
    .fold(0, (sum, a) => sum + a.sizeBytes);

/// Per-request attachment budget of [provider] (null = no fixed limit).
int? requestFileLimit(LlmProviderId provider) =>
    ProviderLimits.forProvider(provider).maxTotalBytes;

/// One-line plain-text preview of a note's Markdown.
String noteSnippet(String markdown, {int maxChars = 140}) {
  final text = markdown
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[#>*_`~|]+'), ' ')
      .replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length <= maxChars
      ? text
      : '${text.substring(0, maxChars).trimRight()}…';
}

/// Everything the user picked as source material.
@immutable
class SourceSelection {
  const SourceSelection({
    this.text = '',
    this.notes = const [],
    this.files = const [],
    this.youtubeUrl,
  });

  final String text;
  final List<Note> notes;
  final List<Attachment> files;

  /// Normalized YouTube URL, or null.
  final String? youtubeUrl;

  bool get hasText => text.trim().isNotEmpty;

  bool get isEmpty =>
      !hasText && notes.isEmpty && files.isEmpty && youtubeUrl == null;

  int get count =>
      (hasText ? 1 : 0) +
      notes.length +
      files.length +
      (youtubeUrl == null ? 0 : 1);

  /// Builds the request sources in a stable order: text, notes, files,
  /// YouTube. Text-like files (.txt/.md/.docx) with stored `extractedText`
  /// are sent as [TextSource]; other files are loaded with [loadBytes].
  Future<List<AiSource>> toAiSources(
    Future<Uint8List> Function(Attachment a) loadBytes,
  ) async {
    return [
      if (hasText) TextSource(text: text.trim()),
      for (final n in notes) NoteSource(title: n.title, markdown: n.contentMd),
      for (final a in files)
        if (isTextAttachment(a) && (a.extractedText ?? '').trim().isNotEmpty)
          TextSource(label: a.name, text: a.extractedText!)
        else
          FileSource(
            name: a.name,
            mimeType: a.mimeType,
            bytes: await loadBytes(a),
          ),
      if (youtubeUrl != null) YoutubeSource(youtubeUrl!),
    ];
  }

  /// Provenance saved with a generated quiz.
  QuizSource toQuizSource(AiSelection? used) {
    final t = text.trim();
    return QuizSource(
      contextText: t.isEmpty
          ? null
          : t.length <= maxStoredContextChars
          ? t
          : t.substring(0, maxStoredContextChars),
      youtubeUrl: youtubeUrl,
      provider: used?.providerId.wireName,
      model: used?.model,
      notes: [for (final n in notes) QuizSourceRef(id: n.id, name: n.title)],
      attachments: [
        for (final a in files) QuizSourceRef(id: a.id, name: a.name),
      ],
    );
  }
}

/// Normalized YouTube URL for [input], null when empty, or throws a
/// [FormatException] with a user-facing message when it isn't a video link.
String? parseYoutubeInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (YoutubeUrl.parseVideoId(text) == null) {
    throw const FormatException("That doesn't look like a YouTube video link.");
  }
  return YoutubeUrl.normalize(text);
}
