import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class QuizPlayScreen extends StatelessWidget {
  const QuizPlayScreen({super.key, required this.quizId});

  final String quizId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Play quiz', subtitle: quizId);
}
