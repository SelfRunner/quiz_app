import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import '../../chat/widgets/chat_launcher.dart';
import '../../decks/widgets/deck_list_section.dart';
import '../../notes/presentation/widgets/note_tile.dart';
import '../../quizzes/widgets/quiz_list_section.dart';
import '../../sharing/widgets/share_actions.dart';
import '../application/subject_actions.dart';
import 'widgets/subject_files_tab.dart';

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

/// A subject's notes, quizzes, flashcard decks and files (tabs). Owners can edit, delete,
/// share and add content; shared subjects are read-only with a "copy to my
/// account" action.
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
        loading: const ContentContainer(child: LoadingSkeleton()),
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
    final theme = Theme.of(context);

    final actions = <Widget>[
      // Chats are private, so recipients of a shared subject can chat too.
      ChatLauncherButton(
        scopeType: ChatScopeType.subject,
        scopeId: subject.id,
        title: subject.title,
        compact: true,
      ),
      if (isOwner) ...[
        GenerateWithAiButton(subjectId: subject.id),
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
          icon: const Icon(Icons.more_horiz),
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
        Gaps.w4,
      ] else
        Padding(
          padding: const EdgeInsets.only(right: Insets.sm),
          child: CopyToAccountButton(
            type: ShareResourceType.subject,
            resourceId: subject.id,
          ),
        ),
    ];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              SubjectColorDot(color: subject.color, size: 12),
              Gaps.w12,
              Flexible(
                child: Text(
                  subject.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: actions,
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: _SubjectHeader(subject: subject, isOwner: isOwner),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                background: theme.scaffoldBackgroundColor,
                hairline: AppColors.of(context).hairline,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _NotesTab(subject: subject, isOwner: isOwner),
              SingleChildScrollView(
                key: const PageStorageKey('subject-quizzes'),
                padding: const EdgeInsets.only(
                  top: Insets.sm,
                  bottom: Insets.xxxl,
                ),
                child: ContentContainer(
                  child: QuizListSection(
                    subjectId: subject.id,
                    readOnly: !isOwner,
                  ),
                ),
              ),
              SingleChildScrollView(
                key: const PageStorageKey('subject-decks'),
                padding: const EdgeInsets.only(
                  top: Insets.sm,
                  bottom: Insets.xxxl,
                ),
                child: ContentContainer(
                  child: DeckListSection(
                    subjectId: subject.id,
                    readOnly: !isOwner,
                  ),
                ),
              ),
              SubjectFilesTab(subject: subject, isOwner: isOwner),
            ],
          ),
        ),
      ),
    );
  }
}

/// App-bar "Generate with AI" button: locked until AI is set up, then opens
/// a menu (quiz / flashcards / note) for [subjectId].
class GenerateWithAiButton extends StatelessWidget {
  const GenerateWithAiButton({super.key, required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context) {
    void go(AiGenerateKind kind) =>
        context.push(AppRoutes.generate(kind: kind, subjectId: subjectId));
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const Key('generate-quiz'),
          leadingIcon: const Icon(Icons.quiz_outlined, size: 18),
          onPressed: () => go(AiGenerateKind.quiz),
          child: const Text('Generate quiz'),
        ),
        MenuItemButton(
          key: const Key('generate-deck'),
          leadingIcon: const Icon(Icons.style_outlined, size: 18),
          onPressed: () => go(AiGenerateKind.deck),
          child: const Text('Generate flashcards'),
        ),
        MenuItemButton(
          key: const Key('generate-note'),
          leadingIcon: const Icon(Icons.description_outlined, size: 18),
          onPressed: () => go(AiGenerateKind.note),
          child: const Text('Generate note'),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        return AiGate(
          onReady: toggle,
          child: IconButton(
            key: const Key('generate-with-ai'),
            tooltip: 'Generate with AI',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: toggle,
          ),
        );
      },
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
    final colors = AppColors.of(context);
    final sharedBy = isOwner
        ? null
        : ref.watch(sharedByNameProvider(subject.ownerId));
    final description = subject.description?.trim() ?? '';
    if (description.isEmpty && isOwner) return Gaps.h4;
    return ContentContainer(
      child: Padding(
        padding: const EdgeInsets.only(top: Insets.xs, bottom: Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty)
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            if (!isOwner) ...[
              if (description.isNotEmpty) Gaps.h8,
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.xs,
                children: [
                  MetaChip(
                    icon: Icons.people_outline,
                    label: sharedBy == null
                        ? 'Shared with you'
                        : 'Shared by $sharedBy',
                  ),
                  const MetaChip(
                    icon: Icons.visibility_outlined,
                    label: 'Read-only',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small neutral label with an icon (e.g. "Read-only").
class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xxs + 1,
      ),
      decoration: BoxDecoration(
        borderRadius: Radii.smAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.mutedText),
          Gaps.w4,
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _NotesTab extends ConsumerWidget {
  const _NotesTab({required this.subject, required this.isOwner});

  final Subject subject;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesBySubjectProvider(subject.id));
    void generateNote() => context.push(
      AppRoutes.generate(kind: AiGenerateKind.note, subjectId: subject.id),
    );
    void newNote() => SubjectActions.newNote(context, ref, subject.id);

    final header = SectionHeader(
      title: 'Notes',
      count: notes.value?.length,
      trailing: isOwner
          ? FilledButton.tonalIcon(
              key: const Key('new-note-fab'),
              onPressed: newNote,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New note'),
            )
          : null,
    );

    final Widget body = AsyncValueView<List<Note>>(
      value: notes,
      loading: const LoadingSkeleton(),
      onRetry: () => ref.invalidate(notesBySubjectProvider(subject.id)),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            compact: true,
            icon: Icons.description_outlined,
            title: 'No notes yet',
            message: isOwner
                ? 'Write notes in Markdown, add images, or let AI draft '
                      'study notes for you.'
                : 'The owner has not added notes to this subject yet.',
            action: isOwner
                ? AiGate(
                    onReady: generateNote,
                    child: OutlinedButton.icon(
                      key: const Key('notes-generate-ai'),
                      onPressed: generateNote,
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Generate with AI'),
                    ),
                  )
                : null,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final n in items) NoteTile(note: n, canEdit: isOwner),
          ],
        );
      },
    );

    return RefreshIndicator(
      onRefresh: () async {
        try {
          await ref.read(syncEngineProvider).sync();
        } catch (_) {}
      },
      child: ListView(
        key: const PageStorageKey('subject-notes'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Insets.xxxl),
        children: [
          ContentContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, body],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({required this.background, required this.hairline});

  final Color background;
  final Color hairline;

  static const _tabBar = TabBar(
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    dividerHeight: 0,
    padding: EdgeInsets.zero,
    labelPadding: EdgeInsetsDirectional.only(end: Insets.xl),
    tabs: [
      Tab(text: 'Notes', height: 40),
      Tab(text: 'Quizzes', height: 40),
      Tab(text: 'Decks', height: 40),
      Tab(text: 'Files', height: 40),
    ],
  );

  @override
  double get minExtent => 41;

  @override
  double get maxExtent => 41;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      border: Border(bottom: BorderSide(color: hairline)),
    ),
    child: const ContentContainer(child: _tabBar),
  );

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.background != background || oldDelegate.hairline != hairline;
}
