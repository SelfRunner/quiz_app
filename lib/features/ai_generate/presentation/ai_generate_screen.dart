import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

/// What to generate.
enum AiGenerateKind { quiz, note }

class AiGenerateScreen extends StatelessWidget {
  const AiGenerateScreen({
    super.key,
    required this.kind,
    this.subjectId,
    this.noteId,
  });

  final AiGenerateKind kind;

  /// Target subject (pre-selected); may be null to let the user pick.
  final String? subjectId;

  /// Attach a generated quiz to this note.
  final String? noteId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: kind == AiGenerateKind.quiz
        ? 'Generate quiz with AI'
        : 'Generate note with AI',
  );
}
