import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class NoteEditScreen extends StatelessWidget {
  const NoteEditScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Edit note', subtitle: noteId);
}
