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

/// One piece of source material for AI generation.
///
/// * [TextSource]: pasted / typed text.
/// * [NoteSource]: an existing note (title + Markdown).
/// * [FileSource]: an attachment (PDF, image, audio, video, or a text file
///   such as .txt/.md/.docx whose text is extracted in-app).
/// * [YoutubeSource]: a YouTube URL (native for Gemini, transcript for
///   others).
@immutable
sealed class AiSource {
  const AiSource();

  /// Name shown to the model (and usable in UI chips).
  String get label;
}

final class TextSource extends AiSource {
  const TextSource({required this.text, this.label = 'Pasted text'});

  @override
  final String label;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is TextSource && other.label == label && other.text == text;

  @override
  int get hashCode => Object.hash(label, text);
}

final class NoteSource extends AiSource {
  const NoteSource({required this.title, required this.markdown});

  final String title;
  final String markdown;

  @override
  String get label => title;

  @override
  bool operator ==(Object other) =>
      other is NoteSource && other.title == title && other.markdown == markdown;

  @override
  int get hashCode => Object.hash(title, markdown);
}

final class FileSource extends AiSource {
  const FileSource({
    required this.name,
    required this.mimeType,
    required this.bytes,
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

  /// [mimeType] normalized (see [normalizeMimeType]).
  String get effectiveMimeType => normalizeMimeType(name, mimeType);

  /// How the file is sent; null = unsupported type.
  AiInputKind? get kind => AiInputKind.ofFile(name, mimeType);

  @override
  bool operator ==(Object other) =>
      other is FileSource &&
      other.name == name &&
      other.mimeType == mimeType &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(name, mimeType, identityHashCode(bytes));
}

final class YoutubeSource extends AiSource {
  const YoutubeSource(this.url);

  final String url;

  @override
  String get label => 'YouTube video';

  @override
  bool operator ==(Object other) => other is YoutubeSource && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
