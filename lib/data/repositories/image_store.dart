import 'dart:typed_data';

import '../models/note_image_ref.dart';

/// Note images: saved locally first (works offline), uploaded to the
/// `note-images` bucket through the outbox.
abstract interface class ImageStore {
  /// Stores [bytes] locally for [noteId] (owned by the current user), queues
  /// the upload, and returns the reference whose `markdownUrl` goes into the
  /// note's Markdown. [extension] without dot, e.g. `png`.
  Future<NoteImageRef> saveNoteImage({
    required String noteId,
    required Uint8List bytes,
    required String extension,
  });

  /// Bytes for an image (local cache first, else downloaded from Storage and
  /// cached). Returns null if unavailable (e.g. offline and not cached).
  Future<Uint8List?> load(NoteImageRef ref);

  /// Removes the local copy and queues deletion from Storage.
  Future<void> delete(NoteImageRef ref);
}
