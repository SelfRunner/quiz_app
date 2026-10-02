import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import '../../notes/presentation/widgets/note_tile.dart';
import '../../quizzes/widgets/quiz_list_section.dart';
import '../../sharing/widgets/share_actions.dart';
import '../application/subject_actions.dart';
import 'widgets/subject_visuals.dart';

/// Display name of whoever shared [ownerId]'s content with the current user,
/// from the "shared with me" list (online only; null when unknown).
final sharedByNameProvider = Provider.autoDispose.family<String?, String>((
  ref,
  ownerId,
) {
  final shares = ref.watch(sharedWithMeProvider).value;
  if (shares == null) return null;
  for (final share in shares) {
    if (share.ownerId != ownerId) continue;
    final owner = share.owner;
    final name = owner?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (owner?.email != null) return owner!.email;
  }
  return null;
});

/// A subject's notes and quizzes. Owners can edit, delete, share and add
/// content; shared subjects are read-only with a "copy to my account" action.
class SubjectDetailScreen extends ConsumerWidget {
  const SubjectDetailScreen({super.key, required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(subjectProvider(subjectId));
    final value = subject.value;
    if (value != null) return _SubjectDetail(subject: value);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncValueView<Subject?>(
        value: subject,
        onRetry: () => ref.invalidate(subjectProvider(subjectId)),
        data: (_) => const NotFoundView(what: 'Subject'),
      ),
    );
  }
}

class _SubjectDetail extends ConsumerWidget {
  const _SubjectDetail({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = subject.isOwnedBy(ref.watch(currentUserIdProvider));
    final twoPane = Breakpoints.isExpanded(context);

    final actions = <Widget>[
      if (isOwner) ...[
        _GenerateMenu(subjectId: subject.id),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share_outlined),
          onPressed: () => showShareSheet(
            context,
            type: ShareResourceType.subject,
            resourceId: subject.id,
            title: subject.title,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (v) async {
            if (v == 'edit') {
              await SubjectActions.edit(context, ref, subject);
            } else if (v == 'delete') {
              final deleted = await SubjectActions.delete(
                context,
                ref,
                subject,
              );
              if (deleted && context.mounted) {
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.subjects);
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit subject'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete subject'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ] else
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: CopyToAccountButton(
            type: ShareResourceType.subject,
            resourceId: subject.id,
          ),
        ),
    ];

    final header = _SubjectHeader(subject: subject, isOwner: isOwner);
    final notesPane = _NotesPane(subject: subject, isOwner: isOwner);
    final quizzesPane = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: QuizListSection(subjectId: subject.id, readOnly: !isOwner),
    );

    final fab = isOwner
        ? FloatingActionButton.extended(
            key: const Key('new-note-fab'),
            onPressed: () => SubjectActions.newNote(context, ref, subject.id),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('New note'),
          )
        : null;

    if (twoPane) {
      return Scaffold(
        appBar: AppBar(title: Text(subject.title), actions: actions),
        floatingActionButton: fab,
        body: Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PaneWithTitle(
                      icon: Icons.description_outlined,
                      title: 'Notes',
                      child: notesPane,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _PaneWithTitle(
                      icon: Icons.quiz_outlined,
                      title: 'Quizzes',
                      child: quizzesPane,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(subject.title), actions: actions),
        floatingActionButton: fab,
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: header),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.description_outlined), text: 'Notes'),
                    Tab(icon: Icon(Icons.quiz_outlined), text: 'Quizzes'),
                  ],
                ),
                Theme.of(context).colorScheme.surface,
              ),
            ),
          ],
          body: TabBarView(children: [notesPane, quizzesPane]),
        ),
      ),
    );
  }
}

class _SubjectHeader extends ConsumerWidget {
  const _SubjectHeader({required this.subject, required this.isOwner});

  final Subject subject;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sharedBy = isOwner
        ? null
        : ref.watch(sharedByNameProvider(subject.ownerId));
    final description = subject.description?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubjectAvatar(subject: subject, size: 52),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.title, style: theme.textTheme.titleLarge),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (!isOwner) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.people_outline, size: 18),
                        label: Text(
                          sharedBy == null
                              ? 'Shared with you'
                              : 'Shared by $sharedBy',
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      const Chip(
                        avatar: Icon(Icons.visibility_outlined, size: 18),
                        label: Text('Read-only'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesPane extends ConsumerWidget {
  const _NotesPane({required this.subject, required this.isOwner});

  final Subject subject;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesBySubjectProvider(subject.id));
    return AsyncValueView<List<Note>>(
      value: notes,
      onRetry: () => ref.invalidate(notesBySubjectProvider(subject.id)),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.description_outlined,
            title: 'No notes yet',
            message: isOwner
                ? 'Write notes in Markdown, add images, or let AI draft '
                      'study notes for you.'
                : 'The owner has not added notes to this subject yet.',
            action: isOwner
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            SubjectActions.newNote(context, ref, subject.id),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('New note'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.push(
                          AppRoutes.generate(
                            kind: AiGenerateKind.note,
                            subjectId: subject.id,
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Generate with AI'),
                      ),
                    ],
                  )
                : null,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            try {
              await ref.read(syncEngineProvider).sync();
            } catch (_) {}
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            itemBuilder: (context, i) =>
                NoteTile(note: items[i], canEdit: isOwner),
          ),
        );
      },
    );
  }
}

class _GenerateMenu extends StatelessWidget {
  const _GenerateMenu({required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context) => PopupMenuButton<AiGenerateKind>(
    tooltip: 'Generate with AI',
    icon: const Icon(Icons.auto_awesome_outlined),
    onSelected: (kind) =>
        context.push(AppRoutes.generate(kind: kind, subjectId: subjectId)),
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: AiGenerateKind.quiz,
        child: ListTile(
          leading: Icon(Icons.quiz_outlined),
          title: Text('Generate quiz'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: AiGenerateKind.note,
        child: ListTile(
          leading: Icon(Icons.description_outlined),
          title: Text('Generate note'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
}

class _PaneWithTitle extends StatelessWidget {
  const _PaneWithTitle({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar, this.background);

  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.background != background;
}
