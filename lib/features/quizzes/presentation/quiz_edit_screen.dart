import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class QuizEditScreen extends StatelessWidget {
  const QuizEditScreen({super.key, required this.quizId});

  final String quizId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Edit quiz', subtitle: quizId);
}
