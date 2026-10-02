import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/export_menu.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../search/widgets/search_entry.dart';
import '../application/subject_actions.dart';
import '../application/subject_export.dart';

/// How the subjects list is shown.
enum SubjectsView { grid, list }

/// How the subjects list is ordered.
enum SubjectsSort {
  /// Most recently updated first.
  recent,

  /// Alphabetical by title.
  name,

  /// Most recently created first.
  created,
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

/// Whether the subjects screen shows archived subjects (kept for the
/// session).
final subjectsShowArchivedProvider =
    NotifierProvider<_ArchivedViewNotifier, bool>(_ArchivedViewNotifier.new);

class _ArchivedViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool archived) => state = archived;
}

/// [subjects] ordered by [sort] (pinned ones first when [pinnedFirst]).
List<Subject> sortSubjects(
  List<Subject> subjects,
  SubjectsSort sort, {
  bool pinnedFirst = true,
}) {
  int byName(Subject a, Subject b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  int byOrder(Subject a, Subject b) => switch (sort) {
    SubjectsSort.recent => b.updatedAt.compareTo(a.updatedAt),
    SubjectsSort.name => byName(a, b),
    SubjectsSort.created => b.createdAt.compareTo(a.createdAt),
  };
  return [...subjects]..sort((a, b) {
    if (pinnedFirst && a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final c = byOrder(a, b);
    if (c != 0) return c;
    final n = byName(a, b);
    return n != 0 ? n : a.id.compareTo(b.id);
  });
}

String _sortLabel(SubjectsSort sort) => switch (sort) {
  SubjectsSort.recent => 'Recent',
  SubjectsSort.name => 'Name',
  SubjectsSort.created => 'Created',
};

/// The user's own subjects as a grid or a compact list: pinned ones in
/// their own section first, sort (recent / name / created), and an
/// "Archived" view (archive / unarchive from each subject's menu).
class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedView = ref.watch(subjectsShowArchivedProvider);
    final subjects = ref.watch(
      archivedView ? archivedSubjectsProvider : subjectsProvider,
    );
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
        actions: [
          const SearchIconButton(),
          if (!wide) const SyncStatusButton(),
        ],
      ),
      body: AsyncValueView<List<Subject>>(
        value: subjects,
        onRetry: () => ref.invalidate(
          archivedView ? archivedSubjectsProvider : subjectsProvider,
        ),
        loading: const ContentContainer(
          maxWidth: ContentWidth.wide,
          child: LoadingSkeleton(rows: 4),
        ),
        data: (items) {
          if (items.isEmpty && archivedView) {
            return EmptyState(
              icon: Icons.archive_outlined,
              title: 'No archived subjects',
              message:
                  'Archive a subject from its menu to hide it from your '
                  'lists, the dashboard and the study queue.',
              action: OutlinedButton(
                key: const Key('subjects-show-active'),
                onPressed: () =>
                    ref.read(subjectsShowArchivedProvider.notifier).set(false),
                child: const Text('Back to subjects'),
              ),
            );
          }
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
                      action: Column(
                        children: [
                          FilledButton.icon(
                            key: const Key('new-subject-empty'),
                            onPressed: () => _create(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Create a subject'),
                          ),
                          Gaps.h8,
                          TextButton(
                            key: const Key('subjects-show-archived-empty'),
                            onPressed: () => ref
                                .read(subjectsShowArchivedProvider.notifier)
                                .set(true),
                            child: const Text('View archived subjects'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          final sorted = sortSubjects(items, sort);
          final pinned = archivedView
              ? const <Subject>[]
              : [
                  for (final s in sorted)
                    if (s.pinned) s,
                ];
          final rest = pinned.isEmpty
              ? sorted
              : [
                  for (final s in sorted)
                    if (!s.pinned) s,
                ];
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final side =
                  (w - math.min(w, ContentWidth.wide)) / 2 +
                  Breakpoints.gutter(context);
              Widget header(Widget child) => SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: side),
                sliver: SliverToBoxAdapter(child: child),
              );
              Widget section(List<Subject> list, {double bottom = Insets.md}) =>
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, Insets.xs, side, bottom),
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
                              (context, i) => SubjectCard(subject: list[i]),
                              childCount: list.length,
                            ),
                          )
                        : SliverList.builder(
                            itemCount: list.length,
                            itemBuilder: (context, i) =>
                                SubjectRow(subject: list[i]),
                          ),
                  );
              return RefreshIndicator(
                onRefresh: refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (pinned.isNotEmpty) ...[
                      header(
                        SectionHeader(
                          key: const Key('subjects-pinned-header'),
                          title: 'Pinned',
                          count: pinned.length,
                        ),
                      ),
                      section(pinned),
                    ],
                    header(
                      _Toolbar(
                        count: rest.length,
                        view: view,
                        sort: sort,
                        archived: archivedView,
                        onCreate: () => _create(context, ref),
                      ),
                    ),
                    section(rest, bottom: Insets.xxxl),
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
    required this.archived,
    required this.onCreate,
  });

  final int count;
  final SubjectsView view;
  final SubjectsSort sort;
  final bool archived;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final sortLabel = _sortLabel(sort);
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
        CheckedPopupMenuItem(
          value: SubjectsSort.created,
          checked: sort == SubjectsSort.created,
          child: const Text('Recently created'),
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
    void showArchived(bool value) =>
        ref.read(subjectsShowArchivedProvider.notifier).set(value);
    final Widget archiveToggle;
    if (archived) {
      archiveToggle = TextButton.icon(
        key: const Key('subjects-archived-toggle'),
        onPressed: () => showArchived(false),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(wide ? 'Back to subjects' : 'Back'),
      );
    } else if (wide) {
      archiveToggle = TextButton.icon(
        key: const Key('subjects-archived-toggle'),
        onPressed: () => showArchived(true),
        icon: Icon(Icons.archive_outlined, size: 18, color: colors.mutedText),
        label: Text('Archived', style: TextStyle(color: colors.mutedText)),
      );
    } else {
      archiveToggle = IconButton(
        key: const Key('subjects-archived-toggle'),
        tooltip: 'Archived subjects',
        icon: Icon(Icons.archive_outlined, size: 18, color: colors.mutedText),
        onPressed: () => showArchived(true),
      );
    }
    return SectionHeader(
      title: archived ? 'Archived' : 'All subjects',
      count: count,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          archiveToggle,
          Gaps.w4,
          sortMenu,
          Gaps.w4,
          viewToggle,
          if (!archived) ...[Gaps.w8, newButton],
        ],
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
              _StatusIcon(subject: subject),
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
      title: Row(
        children: [
          Flexible(
            child: Text(
              subject.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _StatusIcon(subject: subject),
        ],
      ),
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

/// Small pinned / archived marker after a subject's title.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final archived = subject.archivedAt != null;
    if (!subject.pinned && !archived) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: Insets.xs),
      child: Icon(
        archived ? Icons.archive_outlined : Icons.push_pin,
        key: ValueKey(archived ? 'subject-archived-icon' : 'subject-pin-icon'),
        size: 14,
        color: AppColors.of(context).faintText,
        semanticLabel: archived ? 'Archived' : 'Pinned',
      ),
    );
  }
}

enum _MenuAction { pin, archive, export, edit, delete }

/// "More" menu of a subject: pin / unpin, archive / unarchive, export as
/// Markdown (.zip), edit, delete.
class SubjectMenu extends ConsumerWidget {
  const SubjectMenu({super.key, required this.subject});

  final Subject subject;

  Future<void> _pin(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(organizationRepositoryProvider)
          .setSubjectPinned(subject.id, !subject.pinned);
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final org = ref.read(organizationRepositoryProvider);
    final archive = subject.archivedAt == null;
    try {
      if (archive) {
        await org.archiveSubject(subject.id);
      } else {
        await org.unarchiveSubject(subject.id);
      }
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        archive ? 'Archived "${subject.title}"' : 'Restored "${subject.title}"',
        action: archive
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () => org.unarchiveSubject(subject.id).ignore(),
              )
            : null,
      );
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = subject.archivedAt != null;
    PopupMenuItem<_MenuAction> item(
      _MenuAction value,
      IconData icon,
      String label,
    ) => PopupMenuItem(
      key: ValueKey('subject-menu-${value.name}'),
      value: value,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
      ),
    );
    return PopupMenuButton<_MenuAction>(
      key: ValueKey('subject-menu-${subject.id}'),
      tooltip: 'More',
      icon: Icon(Icons.more_horiz, color: AppColors.of(context).mutedText),
      onSelected: (action) => switch (action) {
        _MenuAction.pin => _pin(context, ref),
        _MenuAction.archive => _archive(context, ref),
        _MenuAction.export => runExport(
          context,
          ref,
          subjectExportItem(ref, subject),
        ),
        _MenuAction.edit => SubjectActions.edit(context, ref, subject),
        _MenuAction.delete => SubjectActions.delete(context, ref, subject),
      },
      itemBuilder: (_) => [
        if (!archived)
          item(
            _MenuAction.pin,
            subject.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            subject.pinned ? 'Unpin' : 'Pin',
          ),
        item(
          _MenuAction.archive,
          archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          archived ? 'Unarchive' : 'Archive',
        ),
        item(
          _MenuAction.export,
          Icons.file_download_outlined,
          'Export as Markdown (.zip)',
        ),
        const PopupMenuDivider(),
        item(_MenuAction.edit, Icons.edit_outlined, 'Edit'),
        item(_MenuAction.delete, Icons.delete_outline, 'Delete'),
      ],
    );
  }
}
