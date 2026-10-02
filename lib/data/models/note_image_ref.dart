/// Reference to an image embedded in a note's Markdown.
///
/// Markdown stores `![alt](note-image://{ownerId}/{noteId}/{fileName})`.
/// The Storage object path in bucket `note-images` is
/// `{ownerId}/{noteId}/{fileName}` where `fileName` is `{uuid}.{ext}`.
class NoteImageRef {
  const NoteImageRef({
    required this.ownerId,
    required this.noteId,
    required this.fileName,
  });

  static const String scheme = 'note-image';

  final String ownerId;
  final String noteId;
  final String fileName;

  /// Path inside the `note-images` bucket.
  String get storagePath => '$ownerId/$noteId/$fileName';

  /// URL to put in Markdown.
  String get markdownUrl => '$scheme://$storagePath';

  /// Parses a `note-image://` URL or a bare storage path. Returns null if the
  /// value does not have the `{owner}/{note}/{file}` shape.
  static NoteImageRef? tryParse(String value) {
    var path = value;
    const prefix = '$scheme://';
    if (path.startsWith(prefix)) path = path.substring(prefix.length);
    final parts = path.split('/');
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) return null;
    return NoteImageRef(
      ownerId: parts[0],
      noteId: parts[1],
      fileName: parts[2],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteImageRef && other.storagePath == storagePath;

  @override
  int get hashCode => storagePath.hashCode;

  @override
  String toString() => markdownUrl;
}
