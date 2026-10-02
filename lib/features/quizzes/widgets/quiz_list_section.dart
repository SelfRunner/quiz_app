import 'package:flutter/material.dart';

/// Lists the quizzes of a subject (when [noteId] is null: subject-level
/// quizzes) or of a note, with actions to open, create and AI-generate.
///
/// Cross-feature entry point: subject and note screens embed this; the
/// quizzes feature owns the implementation.
class QuizListSection extends StatelessWidget {
  const QuizListSection({
    super.key,
    required this.subjectId,
    this.noteId,
    this.readOnly = false,
  });

  final String subjectId;
  final String? noteId;

  /// True when the parent is shared with (not owned by) the current user.
  final bool readOnly;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
