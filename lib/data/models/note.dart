import 'package:freezed_annotation/freezed_annotation.dart';

import 'syncable.dart';

part 'note.freezed.dart';
part 'note.g.dart';

/// Row of `public.notes`. Markdown body; images are referenced with
/// `note-image://` URLs (see `NoteImageRef`).
@freezed
abstract class Note with _$Note implements Syncable {
  const factory Note({
    required String id,
    required String subjectId,
    required String ownerId,
    required String title,
    @Default('') String contentMd,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}
