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
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Subject;

  factory Subject.fromJson(Map<String, dynamic> json) =>
      _$SubjectFromJson(json);
}
