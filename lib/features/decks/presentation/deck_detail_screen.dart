import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/llm_provider.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/card_review.dart';
import '../../../data/models/deck.dart';
import '../../../data/models/quiz_source.dart';
import '../../../data/models/share.dart';
import '../../../data/models/syncable.dart';
import '../../../study/fsrs.dart';
import '../../quizzes/widgets/source_summary.dart';
import '../../sharing/widgets/share_actions.dart';
import '../../sharing/widgets/shared_by_chip.dart';
import '../application/deck_providers.dart';
import '../domain/deck_format.dart';

/// Overview of one deck: info, the user's progress, Study, the cards and
/// where they came from. Owners can edit, share and delete; shared decks
/// offer "Copy to my account".
class DeckDetailScreen extends ConsumerWidget {
  const DeckDetailScreen({super.key, required this.deckId});

  final String deckId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Deck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete deck?'),
        content: Text(
          '"${deck.title}" and its ${plural(deck.cards.length, 'card')} will '
          'be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-deck'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(deckRepositoryProvider).delete(deck.id);
      if (!context.mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.subject(deck.subjectId));
      }
    } on Object catch (e) {
      if (context.mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deckAsync = ref.watch(deckProvider(deckId));
    final userId = ref.watch(currentUserIdProvider);
    final deck = deckAsync.value;
    final owner = deck != null && deck.isOwnedBy(userId);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          deck?.title ?? 'Deck',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (deck != null && owner) ...[
            IconButton(
              key: const Key('share-deck'),
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => showShareSheet(
                context,
                type: ShareResourceType.deck,
                resourceId: deck.id,
                title: deck.title,
              ),
            ),
            IconButton(
              key: const Key('edit-deck'),
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(AppRoutes.deckEdit(deck.id)),
            ),
            PopupMenuButton<String>(
              key: const Key('deck-more'),
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) {
                if (v == 'delete') _delete(context, ref, deck);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete deck'),
                  ),
                ),
              ],
            ),
            Gaps.w8,
          ] else if (deck != null)
            Padding(
              padding: const EdgeInsets.only(right: Insets.sm),
              child: CopyToAccountButton(
                type: ShareResourceType.deck,
                resourceId: deck.id,
                compact: true,
              ),
            ),
        ],
      ),
      body: switch (deckAsync) {
        AsyncValue(:final value?) => _DetailBody(deck: value, owner: owner),
        AsyncValue(hasValue: true) => EmptyState(
          icon: Icons.search_off,
          title: 'Deck not found',
          message: 'It may have been deleted or is no longer shared with you.',
          action: OutlinedButton(
            onPressed: () => context.go(AppRoutes.subjects),
            child: const Text('Go to subjects'),
          ),
        ),
        AsyncValue(:final error?) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load the deck',
          message: errorText(error),
        ),
        _ => const ContentContainer(
          child: Padding(
            padding: EdgeInsets.only(top: Insets.xl),
            child: LoadingSkeleton(rows: 4),
          ),
        ),
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.deck, required this.owner});

  final Deck deck;
  final bool owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = Breakpoints.isMedium(context)
        ? Insets.pageWide
        : Insets.page;
    final s = deck.source;
    return SingleChildScrollView(
      child: ContentContainer(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoSection(deck: deck, owner: owner),
            _CardsSection(deck: deck, owner: owner),
            if (s != null && _SourceSection.hasContent(s))
              _SourceSection(deck: deck),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends ConsumerWidget {
  const _InfoSection({required this.deck, required this.owner});

  final Deck deck;
  final bool owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final subject = ref.watch(subjectProvider(deck.subjectId)).value;
    final note = deck.noteId == null
        ? null
        : ref.watch(noteProvider(deck.noteId!)).value;
    final stats = ref.watch(deckStatsProvider(deck.id)).value;
    final queue = ref.watch(deckDueQueueProvider(deck.id)).value;
    final reviews = ref.watch(deckReviewsProvider(deck.id)).value;
    final retention = ref.watch(
      studySettingsProvider.select((s) => s.desiredRetention),
    );
    final now = ref.watch(clockProvider)();
    final recall = _estimatedRecall(deck, reviews, retention, now);
    final count = deck.cards.length;
    final studyNow = queue == null
        ? null
        : queue.dueNow.length + queue.newCards.length;
    final description = deck.description?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Insets.xs,
          runSpacing: Insets.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (subject != null)
              _Crumb(
                leading: SubjectColorDot(color: subject.color),
                label: subject.title,
                onTap: () => context.push(AppRoutes.subject(subject.id)),
              ),
            if (subject != null && note != null)
              Icon(Icons.chevron_right, size: 16, color: colors.faintText),
            if (note != null)
              _Crumb(
                leading: Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: colors.mutedText,
                ),
                label: note.title,
                onTap: () => context.push(AppRoutes.note(note.id)),
              ),
            if (!owner) SharedByChip(ownerId: deck.ownerId),
          ],
        ),
        Gaps.h12,
        Text(deck.title, style: theme.textTheme.headlineMedium),
        if (description.isNotEmpty) ...[
          Gaps.h8,
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(color: colors.mutedText),
          ),
        ],
        Gaps.h24,
        AppCard(
          key: const Key('deck-stats'),
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg,
            vertical: Insets.md,
          ),
          child: Wrap(
            spacing: Insets.xxl,
            runSpacing: Insets.md,
            children: [
              _Stat(label: 'Cards', value: '$count'),
              _Stat(label: 'Due today', value: '${stats?.dueToday ?? '–'}'),
              _Stat(label: 'New', value: '${stats?.newCount ?? '–'}'),
              _Stat(label: 'Learning', value: '${stats?.learning ?? '–'}'),
              _Stat(
                label: 'Review',
                value: '${stats?.review ?? '–'}',
                detail: stats == null || stats.mature == 0
                    ? null
                    : '${stats.mature} mature',
              ),
              _Stat(
                label: 'Est. recall',
                value: recall == null ? '–' : '${(recall * 100).round()}%',
                tooltip:
                    'Average chance you remember a reviewed card right now '
                    '(FSRS estimate).',
              ),
            ],
          ),
        ),
        Gaps.h24,
        Wrap(
          spacing: Insets.md,
          runSpacing: Insets.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('study-deck'),
              style: FilledButton.styleFrom(minimumSize: const Size(140, 44)),
              onPressed: count == 0
                  ? null
                  : () => context.push(AppRoutes.deckStudy(deck.id)),
              icon: const Icon(Icons.school_outlined),
              label: Text(
                studyNow == null || studyNow == 0
                    ? 'Study'
                    : 'Study · $studyNow',
              ),
            ),
            if (count == 0 && owner)
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.deckEdit(deck.id)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add cards'),
              ),
          ],
        ),
        Gaps.h8,
        Text(
          count == 0
              ? (owner
                    ? 'Add cards to start studying.'
                    : 'This deck has no cards yet.')
              : studyNow == 0
              ? 'All caught up — nothing due in this deck right now.'
              : 'Your progress is private${owner ? '' : ', even on shared decks'}.',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedText),
        ),
      ],
    );
  }

  static double? _estimatedRecall(
    Deck deck,
    Map<String, CardReview>? reviews,
    double retention,
    DateTime now,
  ) {
    if (reviews == null) return null;
    final fsrs = Fsrs(desiredRetention: retention);
    final values = [
      for (final c in deck.cards)
        if (reviews[c.id] case final r?
            when r.state != CardState.newCard && r.lastReviewAt != null)
          fsrs.retrievability(r.toFsrs(), now),
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _CardsSection extends ConsumerStatefulWidget {
  const _CardsSection({required this.deck, required this.owner});

  final Deck deck;
  final bool owner;

  @override
  ConsumerState<_CardsSection> createState() => _CardsSectionState();
}

class _CardsSectionState extends ConsumerState<_CardsSection> {
  static const _preview = 20;
  bool _all = false;

  String _status(CardReview? r, DateTime now) {
    if (r == null || r.state == CardState.newCard) return 'New';
    final wait = r.dueAt.difference(now);
    if (wait <= Duration.zero) return 'Due now';
    return 'Due in ${formatInterval(wait)}';
  }

  Future<void> _reset(Flashcard card) async {
    try {
      await ref
          .read(reviewRepositoryProvider)
          .resetCard(deckId: widget.deck.id, cardId: card.id);
      if (mounted) showSnack(context, 'Progress reset — the card is new again');
    } on Object catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final cards = widget.deck.cards;
    final reviews = ref.watch(deckReviewsProvider(widget.deck.id)).value ?? {};
    final now = ref.watch(clockProvider)();
    final shown = _all ? cards : cards.take(_preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Cards',
          count: cards.isEmpty ? null : cards.length,
          padding: const EdgeInsets.only(top: Insets.xxl, bottom: Insets.sm),
          trailing: widget.owner && cards.isNotEmpty
              ? TextButton.icon(
                  onPressed: () =>
                      context.push(AppRoutes.deckEdit(widget.deck.id)),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit cards'),
                )
              : null,
        ),
        if (cards.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.style_outlined,
            title: 'No cards yet',
          )
        else ...[
          for (final c in shown)
            ListRowTile(
              key: ValueKey('deck-card-${c.id}'),
              dense: true,
              title: Text(
                c.front,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                c.back,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                _status(reviews[c.id], now),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
              actions: [
                if (reviews[c.id] != null)
                  IconButton(
                    tooltip: 'Reset progress',
                    icon: const Icon(Icons.restart_alt, size: 18),
                    onPressed: () => _reset(c),
                  ),
              ],
            ),
          if (cards.length > _preview)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('deck-cards-toggle'),
                onPressed: () => setState(() => _all = !_all),
                child: Text(
                  _all ? 'Show fewer' : 'Show all ${cards.length} cards',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SourceSection extends StatelessWidget {
  const _SourceSection({required this.deck});

  final Deck deck;

  static bool hasContent(QuizSource s) =>
      (s.contextText?.trim().isNotEmpty ?? false) ||
      (s.youtubeUrl?.trim().isNotEmpty ?? false) ||
      s.provider != null ||
      sourceSummaryOf(s).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final s = deck.source!;
    final provider = LlmProviderId.fromWireName(s.provider);
    final youtube = s.youtubeUrl?.trim() ?? '';
    final text = s.contextText?.trim() ?? '';
    final summary = [
      for (final e in sourceSummaryOf(s))
        if (youtube.isEmpty || e.label.trim() != youtube) e,
    ];
    return Column(
      key: const Key('deck-source'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Source',
          padding: const EdgeInsets.only(top: Insets.xxl, bottom: Insets.sm),
          subtitle: s.provider == null
              ? null
              : 'Generated with ${provider?.displayName ?? s.provider}'
                    '${s.model != null ? ' · ${s.model}' : ''}',
        ),
        for (final e in summary)
          ListRowTile(
            dense: true,
            leading: Icon(e.icon),
            title: Text(e.label),
            subtitle: e.detail == null ? null : Text(e.detail!),
            trailing: Text(e.kindLabel),
          ),
        if (youtube.isNotEmpty)
          ListRowTile(
            dense: true,
            leading: const Icon(Icons.smart_display_outlined),
            title: Text(youtube),
            trailing: const Text('YouTube'),
            actions: [
              IconButton(
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: youtube));
                  if (context.mounted) showSnack(context, 'Link copied');
                },
              ),
            ],
          ),
        if (text.isNotEmpty) ...[
          Gaps.h8,
          Container(
            width: double.infinity,
            padding: Insets.card,
            decoration: BoxDecoration(
              color: colors.sidebar,
              borderRadius: Radii.mdAll,
              border: Border.all(color: colors.hairline),
            ),
            child: Text(
              text,
              maxLines: 6,
              overflow: TextOverflow.fade,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedText,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Quiet breadcrumb link (subject / note).
class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.xs,
          vertical: Insets.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            Gaps.w8,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: AppColors.of(context).mutedText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.detail,
    this.tooltip,
  });

  final String label;
  final String value;
  final String? detail;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          detail == null ? label : '$label · $detail',
          style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedText),
        ),
      ],
    );
    return tooltip == null ? child : Tooltip(message: tooltip, child: child);
  }
}
