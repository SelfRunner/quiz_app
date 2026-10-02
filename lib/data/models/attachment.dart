import 'package:freezed_annotation/freezed_annotation.dart';

import 'syncable.dart';

part 'attachment.freezed.dart';
part 'attachment.g.dart';

/// Kind of an attached file (column `attachments.kind`, JSON = name).
enum AttachmentKind {
  @JsonValue('pdf')
  pdf,
  @JsonValue('image')
  image,

  /// Plain text / Markdown (`.txt`, `.md`).
  @JsonValue('text')
  text,
  @JsonValue('docx')
  docx,
  @JsonValue('audio')
  audio,
  @JsonValue('video')
  video,
  @JsonValue('other')
  other;

  String get wireName => name;

  /// Kind of a file, by extension first (contract table), then by MIME type.
  static AttachmentKind detect({required String fileName, String? mimeType}) {
    final byExt = _byExtension[fileExtension(fileName)];
    if (byExt != null) return byExt;
    final mime = (mimeType ?? '').toLowerCase().split(';').first.trim();
    if (mime.isEmpty) return AttachmentKind.other;
    if (mime == 'application/pdf') return AttachmentKind.pdf;
    if (mime == _docxMime) return AttachmentKind.docx;
    if (mime == 'text/plain' || mime == 'text/markdown') {
      return AttachmentKind.text;
    }
    if (mime.startsWith('image/') && mime != 'image/svg+xml') {
      return AttachmentKind.image;
    }
    if (mime.startsWith('audio/')) return AttachmentKind.audio;
    if (mime.startsWith('video/')) return AttachmentKind.video;
    return AttachmentKind.other;
  }

  static const Map<String, AttachmentKind> _byExtension = {
    'pdf': AttachmentKind.pdf,
    'png': AttachmentKind.image,
    'jpg': AttachmentKind.image,
    'jpeg': AttachmentKind.image,
    'gif': AttachmentKind.image,
    'webp': AttachmentKind.image,
    'heic': AttachmentKind.image,
    'bmp': AttachmentKind.image,
    'txt': AttachmentKind.text,
    'md': AttachmentKind.text,
    'docx': AttachmentKind.docx,
    'mp3': AttachmentKind.audio,
    'wav': AttachmentKind.audio,
    'm4a': AttachmentKind.audio,
    'aac': AttachmentKind.audio,
    'ogg': AttachmentKind.audio,
    'flac': AttachmentKind.audio,
    'mp4': AttachmentKind.video,
    'mov': AttachmentKind.video,
    'webm': AttachmentKind.video,
    'mkv': AttachmentKind.video,
    'avi': AttachmentKind.video,
  };
}

const String _docxMime =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

const Map<String, String> _mimeByExtension = {
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'docx': _docxMime,
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
};

/// Lowercase extension of [fileName] without the dot (`''` if none).
String fileExtension(String fileName) {
  final base = fileName.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return '';
  return base.substring(dot + 1).toLowerCase();
}

/// Best-effort MIME type for a file name (null when unknown).
String? mimeTypeForFileName(String fileName) =>
    _mimeByExtension[fileExtension(fileName)];

/// Row of `public.attachments`: a file in a subject's "Files" library.
///
/// The blob lives in the private Storage bucket `attachments` at
/// [storagePath] = `{ownerId}/{subjectId}/{id}/{sanitized file name}`
/// (see [Attachment.buildStoragePath]). [subjectId] and [storagePath] never
/// change after creation.
@freezed
abstract class Attachment with _$Attachment implements Syncable {
  const factory Attachment({
    required String id,
    required String subjectId,
    required String ownerId,

    /// Display name (original file name), 1..512 chars.
    required String name,
    String? mimeType,
    @Default(0) int sizeBytes,
    @JsonKey(unknownEnumValue: AttachmentKind.other)
    @Default(AttachmentKind.other)
    AttachmentKind kind,
    required String storagePath,

    /// Text extracted in-app (txt/md/docx), at most [maxExtractedTextLength].
    String? extractedText,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Attachment;

  const Attachment._();

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);

  /// Server limit for `extracted_text`.
  static const int maxExtractedTextLength = 200000;

  /// Server limit for `name`.
  static const int maxNameLength = 512;

  /// Storage bucket file size limit (50 MiB).
  static const int maxSizeBytes = 50 * 1024 * 1024;

  /// Object path in the `attachments` bucket.
  static String buildStoragePath({
    required String ownerId,
    required String subjectId,
    required String id,
    required String fileName,
  }) => '$ownerId/$subjectId/$id/${sanitizeFileName(fileName)}';

  /// One safe Storage path segment for [name]: keeps `[A-Za-z0-9._-]`,
  /// replaces everything else with `_`, at most 100 chars (extension kept),
  /// fallback `file`.
  static String sanitizeFileName(String name) {
    const maxLength = 100;
    final base = name.split(RegExp(r'[/\\]')).last.trim();
    var safe = base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    if (safe.length > maxLength) {
      final dot = safe.lastIndexOf('.');
      final ext = dot > 0 && safe.length - dot <= 16 ? safe.substring(dot) : '';
      safe = safe.substring(0, maxLength - ext.length) + ext;
    }
    if (safe.isEmpty || RegExp(r'^\.+$').hasMatch(safe)) return 'file';
    return safe;
  }

  /// The `{file}` segment of [storagePath].
  String get fileName => storagePath.split('/').last;
}
