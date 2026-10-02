import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'text_extractor.dart';

/// Kinds of input a model can take. See `AiCapabilities`.
enum AiInputKind {
  text('text'),
  pdf('PDF files'),
  image('images'),
  audio('audio'),
  video('video'),
  youtube('YouTube videos');

  const AiInputKind(this.plural);

  /// User-facing plural noun ("PDF files", "images", ...).
  final String plural;

  /// What a [FileSource] named [name] with [mimeType] is sent as, or null
  /// when the file type is not supported at all. Text files (.txt, .md,
  /// .docx, ...) are [text]: their text is extracted in-app and works with
  /// every model.
  static AiInputKind? ofFile(String name, String? mimeType) {
    if (TextExtractor.canExtract(name, mimeType)) return AiInputKind.text;
    final mime = normalizeMimeType(name, mimeType);
    if (mime == 'application/pdf') return AiInputKind.pdf;
    if (mime.startsWith('image/')) return AiInputKind.image;
    if (mime.startsWith('audio/')) return AiInputKind.audio;
    if (mime.startsWith('video/')) return AiInputKind.video;
    return null;
  }
}

const _mimeByExtension = {
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'flac': 'audio/flac',
  'aiff': 'audio/aiff',
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mpeg': 'video/mpeg',
  'mpg': 'video/mpeg',
  'avi': 'video/x-msvideo',
  'wmv': 'video/x-ms-wmv',
  '3gp': 'video/3gpp',
  'flv': 'video/x-flv',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'markdown': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

/// Lower-case file extension of [name] without the dot ('' if none).
String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// [mimeType] lower-cased without parameters; inferred from the extension of
/// [name] when missing or generic (`application/octet-stream`). Returns
/// `application/octet-stream` when unknown.
String normalizeMimeType(String name, String? mimeType) {
  var mime = (mimeType ?? '').split(';').first.trim().toLowerCase();
  if (mime == 'image/jpg') mime = 'image/jpeg';
  if (mime.isEmpty ||
      mime == 'application/octet-stream' ||
      mime == 'binary/octet-stream') {
    return _mimeByExtension[fileExtension(name)] ?? 'application/octet-stream';
  }
  return mime;
}

/// What an [AiSource] is, as reported in chat citations
/// (`ChatCitation.type`).
enum AiSourceType {
  text('text'),
  note('note'),
  file('file'),
  youtube('youtube');

  const AiSourceType(this.wireName);

  /// Stable lower-case name (`note`, `file`, ...), also used in prompts.
  final String wireName;
}

/// One piece of source material for AI generation.
///
/// * [TextSource]: pasted / typed text.
/// * [NoteSource]: an existing note (title + Markdown).
/// * [FileSource]: an attachment (PDF, image, audio, video, or a text file
///   such as .txt/.md/.docx whose text is extracted in-app).
/// * [YoutubeSource]: a YouTube URL (native for Gemini, transcript for
///   others).
///
/// [id] is optional and opaque to the AI layer: chat returns it in
/// citations (`ChatCitation.id`) so the UI can open the cited note / file.
@immutable
sealed class AiSource {
  const AiSource({this.id});

  /// Caller's id of the underlying entity (note id, attachment id, ...).
  final String? id;

  /// Name shown to the model (and usable in UI chips).
  String get label;

  /// Kind reported in chat citations.
  AiSourceType get type;
}

final class TextSource extends AiSource {
  const TextSource({
    required this.text,
    this.label = 'Pasted text',
    super.id,
    this.type = AiSourceType.text,
  });

  @override
  final String label;
  final String text;

  /// Defaults to [AiSourceType.text]; pass [AiSourceType.file] for text
  /// already extracted from an attachment so citations point at the file.
  @override
  final AiSourceType type;

  @override
  bool operator ==(Object other) =>
      other is TextSource &&
      other.label == label &&
      other.text == text &&
      other.id == id &&
      other.type == type;

  @override
  int get hashCode => Object.hash(label, text, id, type);
}

final class NoteSource extends AiSource {
  const NoteSource({required this.title, required this.markdown, super.id});

  final String title;
  final String markdown;

  @override
  String get label => title;

  @override
  AiSourceType get type => AiSourceType.note;

  @override
  bool operator ==(Object other) =>
      other is NoteSource &&
      other.title == title &&
      other.markdown == markdown &&
      other.id == id;

  @override
  int get hashCode => Object.hash(title, markdown, id);
}

final class FileSource extends AiSource {
  const FileSource({
    required this.name,
    required this.mimeType,
    required this.bytes,
    super.id,
  });

  /// File name including the extension (used for type detection and shown
  /// to the model).
  final String name;

  /// May be null/empty or `application/octet-stream`; the extension of
  /// [name] is used then.
  final String? mimeType;
  final Uint8List bytes;

  @override
  String get label => name;

  @override
  AiSourceType get type => AiSourceType.file;

  /// [mimeType] normalized (see [normalizeMimeType]).
  String get effectiveMimeType => normalizeMimeType(name, mimeType);

  /// How the file is sent; null = unsupported type.
  AiInputKind? get kind => AiInputKind.ofFile(name, mimeType);

  @override
  bool operator ==(Object other) =>
      other is FileSource &&
      other.name == name &&
      other.mimeType == mimeType &&
      other.id == id &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(name, mimeType, id, identityHashCode(bytes));
}

final class YoutubeSource extends AiSource {
  const YoutubeSource(this.url, {super.id, this.title});

  final String url;

  /// Video title if known (shown in chat source labels and citations).
  final String? title;

  @override
  String get label => title ?? 'YouTube video';

  @override
  AiSourceType get type => AiSourceType.youtube;

  @override
  bool operator ==(Object other) =>
      other is YoutubeSource &&
      other.url == url &&
      other.id == id &&
      other.title == title;

  @override
  int get hashCode => Object.hash(url, id, title);
}
