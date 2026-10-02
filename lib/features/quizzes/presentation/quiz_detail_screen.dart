import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class QuizDetailScreen extends StatelessWidget {
  const QuizDetailScreen({super.key, required this.quizId});

  final String quizId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Quiz', subtitle: quizId);
}
