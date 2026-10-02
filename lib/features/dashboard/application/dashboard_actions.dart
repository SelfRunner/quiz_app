import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import '../../subjects/application/subject_actions.dart';

/// Quick-action flows of the dashboard.
abstract final class DashboardActions {
  /// Creates a subject and opens it.
  static Future<void> newSubject(BuildContext context, WidgetRef ref) async {
    final subject = await SubjectActions.create(context, ref);
    if (subject != null && context.mounted) {
      await context.push(AppRoutes.subject(subject.id));
    }
  }

  /// Asks for a subject (creating one when there is none yet), then creates
  /// an empty note in it and opens the editor.
  static Future<void> newNote(BuildContext context, WidgetRef ref) async {
    final subjects = ref.read(subjectsProvider).value ?? const <Subject>[];
    String? subjectId;
    if (subjects.isEmpty) {
      subjectId = (await SubjectActions.create(context, ref))?.id;
    } else if (subjects.length == 1) {
      subjectId = subjects.first.id;
    } else {
      subjectId = await _pickSubject(context, subjects, 'New note in…');
    }
    if (subjectId == null || !context.mounted) return;
    await SubjectActions.newNote(context, ref, subjectId);
  }

  /// Opens the AI generator (quiz by default).
  static void generate(
    BuildContext context, {
    AiGenerateKind kind = AiGenerateKind.quiz,
    String? subjectId,
  }) {
    context.push(AppRoutes.generate(kind: kind, subjectId: subjectId));
  }

  static Future<String?> _pickSubject(
    BuildContext context,
    List<Subject> subjects,
    String title,
  ) => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final s in subjects)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(s.id),
            child: Row(
              children: [
                SubjectColorDot(color: s.color),
                Gaps.w12,
                Expanded(child: Text(s.title, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
    ),
  );
}
