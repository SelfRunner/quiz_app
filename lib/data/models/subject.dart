import 'package:freezed_annotation/freezed_annotation.dart';

import 'syncable.dart';

part 'subject.freezed.dart';
part 'subject.g.dart';

/// Row of `public.subjects`. Top of the hierarchy: Subject -> Notes / Quizzes.
@freezed
abstract class Subject with _$Subject implements Syncable {
  const factory Subject({
    required String id,
    required String ownerId,
    required String title,
    String? description,

    /// ARGB32 color value (e.g. `0xFF3F51B5`), stored as `bigint`.
    int? color,

    /// Pinned to the top of lists (owner's value, Wave 3).
    @Default(false) bool pinned,

    /// Archived (hidden from default lists, the dashboard and the study
    /// queue, still accessible); null = active (Wave 3).
    DateTime? archivedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Subject;

  factory Subject.fromJson(Map<String, dynamic> json) =>
      _$SubjectFromJson(json);
}

extension SubjectArchiveX on Subject {
  bool get isArchived => archivedAt != null;
}
