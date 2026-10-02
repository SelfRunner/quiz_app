import 'package:flutter/material.dart';

/// Lists flashcard decks of a subject (when [noteId] is null: subject-level
/// decks) or of a note, with open / new / AI-generate / study actions.
///
/// Cross-feature entry point: subject and note screens embed this; the decks
/// feature owns the implementation.
class DeckListSection extends StatelessWidget {
  const DeckListSection({
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
