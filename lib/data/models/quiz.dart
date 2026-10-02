import 'package:freezed_annotation/freezed_annotation.dart';

import 'question.dart';
import 'quiz_source.dart';
import 'syncable.dart';

part 'quiz.freezed.dart';
part 'quiz.g.dart';

/// Row of `public.quizzes`. Belongs to a subject and optionally to a note.
/// Questions are embedded (jsonb array).
@freezed
abstract class Quiz with _$Quiz implements Syncable {
  const factory Quiz({
    required String id,
    required String subjectId,
    String? noteId,
    required String ownerId,
    required String title,
    String? description,
    QuizSource? source,
    @Default(<Question>[]) List<Question> questions,

    /// Normalized tags (see `normalizeTags`), owner's values (Wave 3).
    @Default(<String>[]) List<String> tags,

    /// Pinned to the top of lists (owner's value, Wave 3).
    @Default(false) bool pinned,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Quiz;

  factory Quiz.fromJson(Map<String, dynamic> json) => _$QuizFromJson(json);
}
