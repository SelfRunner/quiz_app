import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../application/subject_actions.dart';
import 'widgets/subject_visuals.dart';

/// The user's own subjects as a responsive grid.
class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider);
    final wide = Breakpoints.isMedium(context);
    final hasSubjects = subjects.value?.isNotEmpty ?? false;

    Future<void> refresh() async {
      try {
        await ref.read(syncEngineProvider).sync();
      } catch (_) {
        // Sync status shows problems.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subjects'),
        actions: [if (!wide) const SyncStatusButton()],
      ),
      floatingActionButton: hasSubjects
          ? FloatingActionButton.extended(
              key: const Key('new-subject-fab'),
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New subject'),
            )
          : null,
      body: AsyncValueView<List<Subject>>(
        value: subjects,
        onRetry: () => ref.invalidate(subjectsProvider),
        data: (items) {
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: refresh,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: EmptyState(
                      icon: Icons.library_books_outlined,
                      title: 'No subjects yet',
                      message:
                          'Subjects group your notes and quizzes. Create one '
                          'to get started — e.g. "Biology" or "Spanish".',
                      action: FilledButton.icon(
                        key: const Key('new-subject-empty'),
                        onPressed: () => _create(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Create a subject'),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 380,
                          mainAxisExtent: 152,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => SubjectCard(subject: items[i]),
                      childCount: items.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final subject = await SubjectActions.create(context, ref);
    if (subject != null && context.mounted) {
      await context.push(AppRoutes.subject(subject.id));
    }
  }
}

/// Grid card: color, title, description, note/quiz counts and a menu.
class SubjectCard extends ConsumerWidget {
  const SubjectCard({super.key, required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notes = ref.watch(notesBySubjectProvider(subject.id)).value?.length;
    final quizzes = ref
        .watch(quizzesBySubjectProvider(subject.id))
        .value
        ?.length;
    final color = subjectColor(context, subject.color);

    String count(int? n, String one, String many) =>
        n == null ? '– $many' : '$n ${n == 1 ? one : many}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => context.push(AppRoutes.subject(subject.id)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SubjectAvatar(subject: subject, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            subject.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _SubjectMenu(subject: subject),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        subject.description ?? '',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          count(notes, 'note', 'notes'),
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.quiz_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          count(quizzes, 'quiz', 'quizzes'),
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MenuAction { edit, delete }

class _SubjectMenu extends ConsumerWidget {
  const _SubjectMenu({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<_MenuAction>(
        tooltip: 'More',
        onSelected: (action) => switch (action) {
          _MenuAction.edit => SubjectActions.edit(context, ref, subject),
          _MenuAction.delete => SubjectActions.delete(context, ref, subject),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _MenuAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: _MenuAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      );
}
