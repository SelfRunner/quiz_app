import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../application/subject_actions.dart';

/// How the subjects list is shown.
enum SubjectsView { grid, list }

/// How the subjects list is ordered.
enum SubjectsSort {
  /// Most recently updated first.
  recent,

  /// Alphabetical by title.
  name,
}

/// Grid or list (kept for the session).
final subjectsViewProvider = NotifierProvider<_ViewNotifier, SubjectsView>(
  _ViewNotifier.new,
);

/// Sort order (kept for the session).
final subjectsSortProvider = NotifierProvider<_SortNotifier, SubjectsSort>(
  _SortNotifier.new,
);

class _ViewNotifier extends Notifier<SubjectsView> {
  @override
  SubjectsView build() => SubjectsView.grid;

  void set(SubjectsView view) => state = view;
}

class _SortNotifier extends Notifier<SubjectsSort> {
  @override
  SubjectsSort build() => SubjectsSort.recent;

  void set(SubjectsSort sort) => state = sort;
}

/// [subjects] ordered by [sort].
List<Subject> sortSubjects(List<Subject> subjects, SubjectsSort sort) {
  final list = [...subjects];
  switch (sort) {
    case SubjectsSort.recent:
      list.sort((a, b) {
        final byTime = b.updatedAt.compareTo(a.updatedAt);
        return byTime != 0
            ? byTime
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    case SubjectsSort.name:
      list.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
  }
  return list;
}

/// The user's own subjects as a grid or a compact list.
class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider);
    final wide = Breakpoints.isMedium(context);
    final view = ref.watch(subjectsViewProvider);
    final sort = ref.watch(subjectsSortProvider);

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
      body: AsyncValueView<List<Subject>>(
        value: subjects,
        onRetry: () => ref.invalidate(subjectsProvider),
        loading: const ContentContainer(
          maxWidth: ContentWidth.wide,
          child: LoadingSkeleton(rows: 4),
        ),
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
                          'Subjects group your notes, quizzes and files. '
                          'Create one to get started — e.g. "Biology" or '
                          '"Spanish".',
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
          final sorted = sortSubjects(items, sort);
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final side =
                  (w - math.min(w, ContentWidth.wide)) / 2 +
                  Breakpoints.gutter(context);
              return RefreshIndicator(
                onRefresh: refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      sliver: SliverToBoxAdapter(
                        child: _Toolbar(
                          count: items.length,
                          view: view,
                          sort: sort,
                          onCreate: () => _create(context, ref),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        side,
                        Insets.xs,
                        side,
                        Insets.xxxl,
                      ),
                      sliver: view == SubjectsView.grid
                          ? SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 340,
                                    mainAxisExtent: 128,
                                    crossAxisSpacing: Insets.md,
                                    mainAxisSpacing: Insets.md,
                                  ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => SubjectCard(subject: sorted[i]),
                                childCount: sorted.length,
                              ),
                            )
                          : SliverList.builder(
                              itemCount: sorted.length,
                              itemBuilder: (context, i) =>
                                  SubjectRow(subject: sorted[i]),
                            ),
                    ),
                  ],
                ),
              );
            },
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

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.count,
    required this.view,
    required this.sort,
    required this.onCreate,
  });

  final int count;
  final SubjectsView view;
  final SubjectsSort sort;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final sortLabel = sort == SubjectsSort.recent ? 'Recent' : 'Name';
    final sortMenu = PopupMenuButton<SubjectsSort>(
      key: const Key('subjects-sort'),
      tooltip: 'Sort: $sortLabel',
      initialValue: sort,
      onSelected: (s) => ref.read(subjectsSortProvider.notifier).set(s),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: SubjectsSort.recent,
          checked: sort == SubjectsSort.recent,
          child: const Text('Recently updated'),
        ),
        CheckedPopupMenuItem(
          value: SubjectsSort.name,
          checked: sort == SubjectsSort.name,
          child: const Text('Name'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort, size: 18, color: colors.mutedText),
            if (wide) ...[
              Gaps.w4,
              Text(
                sortLabel,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: colors.mutedText),
              ),
            ],
          ],
        ),
      ),
    );
    final viewToggle = wide
        ? SegmentedButton<SubjectsView>(
            key: const Key('subjects-view'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: SubjectsView.grid,
                icon: Icon(Icons.grid_view_outlined, size: 18),
                tooltip: 'Grid',
              ),
              ButtonSegment(
                value: SubjectsView.list,
                icon: Icon(Icons.view_agenda_outlined, size: 18),
                tooltip: 'List',
              ),
            ],
            selected: {view},
            onSelectionChanged: (s) =>
                ref.read(subjectsViewProvider.notifier).set(s.first),
          )
        : IconButton(
            key: const Key('subjects-view'),
            tooltip: view == SubjectsView.grid
                ? 'Show as list'
                : 'Show as grid',
            icon: Icon(
              view == SubjectsView.grid
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_outlined,
              size: 18,
              color: colors.mutedText,
            ),
            onPressed: () => ref
                .read(subjectsViewProvider.notifier)
                .set(
                  view == SubjectsView.grid
                      ? SubjectsView.list
                      : SubjectsView.grid,
                ),
          );
    final newButton = wide
        ? FilledButton.icon(
            key: const Key('new-subject-fab'),
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New subject'),
          )
        : IconButton.filled(
            key: const Key('new-subject-fab'),
            tooltip: 'New subject',
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 20),
          );
    return SectionHeader(
      title: 'All subjects',
      count: count,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [sortMenu, Gaps.w4, viewToggle, Gaps.w8, newButton],
      ),
    );
  }
}

String _count(int? n, String one, String many) =>
    n == null ? '– $many' : '$n ${n == 1 ? one : many}';

/// Grid card: color dot, title, description, note/quiz counts and a menu.
class SubjectCard extends ConsumerWidget {
  const SubjectCard({super.key, required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final notes = ref.watch(notesBySubjectProvider(subject.id)).value?.length;
    final quizzes = ref
        .watch(quizzesBySubjectProvider(subject.id))
        .value
        ?.length;
    final description = subject.description?.trim() ?? '';
    final meta = theme.textTheme.labelMedium?.copyWith(color: colors.mutedText);

    return AppCard(
      onTap: () => context.push(AppRoutes.subject(subject.id)),
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.xs,
        Insets.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SubjectColorDot(color: subject.color),
              Gaps.w8,
              Expanded(
                child: Text(
                  subject.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SubjectMenu(subject: subject),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: Insets.md),
              child: Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Row(
            children: [
              Flexible(
                child: Text(
                  _count(notes, 'note', 'notes'),
                  style: meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('  ·  ', style: meta),
              Flexible(
                child: Text(
                  _count(quizzes, 'quiz', 'quizzes'),
                  style: meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact list row for a subject.
class SubjectRow extends ConsumerWidget {
  const SubjectRow({super.key, required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesBySubjectProvider(subject.id)).value?.length;
    final quizzes = ref
        .watch(quizzesBySubjectProvider(subject.id))
        .value
        ?.length;
    final description = subject.description?.trim() ?? '';
    return ListRowTile(
      leading: SizedBox(
        width: 20,
        child: Center(child: SubjectColorDot(color: subject.color)),
      ),
      title: Text(subject.title),
      subtitle: description.isEmpty ? null : Text(description, maxLines: 1),
      trailing: Breakpoints.isMedium(context)
          ? Text(
              '${_count(notes, 'note', 'notes')}  ·  '
              '${_count(quizzes, 'quiz', 'quizzes')}',
            )
          : null,
      onTap: () => context.push(AppRoutes.subject(subject.id)),
      actions: [SubjectMenu(subject: subject)],
    );
  }
}

enum _MenuAction { edit, delete }

/// "More" menu of a subject (edit / delete).
class SubjectMenu extends ConsumerWidget {
  const SubjectMenu({super.key, required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<_MenuAction>(
        tooltip: 'More',
        icon: Icon(Icons.more_horiz, color: AppColors.of(context).mutedText),
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
