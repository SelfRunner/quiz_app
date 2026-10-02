import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

class SubjectDetailScreen extends StatelessWidget {
  const SubjectDetailScreen({super.key, required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Subject', subtitle: subjectId);
}
