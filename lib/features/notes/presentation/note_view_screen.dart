import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class NoteViewScreen extends StatelessWidget {
  const NoteViewScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Note', subtitle: noteId);
}
