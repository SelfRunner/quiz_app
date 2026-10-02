import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../study/due_queue.dart';
import '../../../study/study_settings.dart';
import '../../decks/domain/deck_format.dart';
import '../../decks/domain/queue_groups.dart';
import '../../decks/widgets/review_session.dart';

/// "Due today" across every readable deck (own + shared), grouped by
/// subject and deck, with "Study all" running one [ReviewSession] over the
/// merged queue (reviews first, then new cards within the daily limit).
class StudyQueueScreen extends ConsumerStatefulWidget {
  const StudyQueueScreen({super.key});

  @override
  ConsumerState<StudyQueueScreen> createState() => _StudyQueueScreenState();
}

class _StudyQueueScreenState extends ConsumerState<StudyQueueScreen> {
  List<DueCard>? _session;
  int _round = 0;

  void _start(List<DueCard> cards) {
    if (cards.isEmpty) return;
    setState(() {
      _session = cards;
      _round++;
    });
  }

  void _end() => setState(() => _session = null);

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('end-session'),
            tooltip: 'End session',
            icon: const Icon(Icons.close),
            onPressed: _end,
          ),
          title: const Text('Study all'),
        ),
        body: ReviewSession(
          key: ValueKey('all-$_round'),
          cards: session,
          showDeckTitle: true,
          onDone: _end,
        ),
      );
    }

    final queue = ref.watch(dueQueueProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study'),
        actions: [
          IconButton(
            key: const Key('study-limits'),
            tooltip: 'Daily new-card limit',
            icon: const Icon(Icons.tune),
            onPressed: () => showNewCardLimitDialog(context, ref),
          ),
          Gaps.w8,
        ],
      ),
      body: AsyncValueView<DueQueue>(
        value: queue,
        loading: const ContentContainer(
          child: Padding(
            padding: EdgeInsets.only(top: Insets.xl),
            child: LoadingSkeleton(rows: 4),
          ),
        ),
        onRetry: () => ref.invalidate(dueQueueProvider),
        data: (q) => _QueueView(queue: q, onStudy: _start),
      ),
    );
  }
}

class _QueueView extends ConsumerWidget {
  const _QueueView({required this.queue, required this.onStudy});

  final DueQueue queue;
  final void Function(List<DueCard> cards) onStudy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final limit = ref.watch(
      studySettingsProvider.select((s) => s.newCardsPerDay),
    );
    final groups = groupDueQueue(queue);
    final now = [...queue.dueNow, ...queue.newCards];
    final limitReached = queue.unseenTotal > 0 && queue.newRemainingToday == 0;

    if (queue.isEmpty) {
      final hasDecks =
          ref
              .watch(accessibleDecksProvider)
              .value
              ?.any((d) => d.cards.isNotEmpty) ??
          true;
      return EmptyState(
        key: const Key('all-caught-up'),
        icon: Icons.check_circle_outline,
        title: hasDecks ? 'All caught up' : 'No flashcards yet',
        message: !hasDecks
            ? 'Create a flashcard deck in a subject or note (or let AI '
                  'generate one) and it will show up here when cards are due.'
            : limitReached
            ? "Nothing due. You've reached today's limit of "
                  '${plural(limit, 'new card')} — '
                  '${plural(queue.unseenTotal, 'new card')} wait for tomorrow.'
            : 'Nothing is due today. Come back tomorrow.',
        action: hasDecks
            ? null
            : OutlinedButton(
                onPressed: () => context.go(AppRoutes.subjects),
                child: const Text('Go to subjects'),
              ),
      );
    }

    final summary = AppCard(
      key: const Key('study-summary'),
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            now.isEmpty ? 'Nothing due right now' : plural(now.length, 'card'),
            key: const Key('study-count'),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Gaps.h4,
          Text(
            [
              plural(queue.dueNow.length, 'review'),
              plural(queue.newCards.length, 'new card'),
              if (queue.laterToday.isNotEmpty)
                '${queue.laterToday.length} later today',
            ].join(' · '),
            key: const Key('study-breakdown'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
          Gaps.h4,
          Text(
            'New cards today: ${queue.newIntroducedToday} of $limit'
            '${limitReached ? ' (limit reached)' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.faintText),
          ),
          Gaps.h16,
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (now.isNotEmpty)
                FilledButton.icon(
                  key: const Key('study-all'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 44),
                  ),
                  onPressed: () => onStudy(now),
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('Study all'),
                )
              else
                FilledButton.tonalIcon(
                  key: const Key('study-ahead'),
                  onPressed: () => onStudy(queue.laterToday),
                  icon: const Icon(Icons.fast_forward_outlined),
                  label: const Text('Study later-today cards now'),
                ),
            ],
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.xxxl),
      children: [
        ContentContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              for (final g in groups)
                _SubjectSection(group: g, onStudy: onStudy),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectSection extends ConsumerWidget {
  const _SubjectSection({required this.group, required this.onStudy});

  final SubjectDueGroup group;
  final void Function(List<DueCard> cards) onStudy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(subjectProvider(group.subjectId)).value;
    final colors = AppColors.of(context);
    return Column(
      key: ValueKey('study-subject-${group.subjectId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.xs),
          child: Row(
            children: [
              SubjectColorDot(color: subject?.color),
              Gaps.w8,
              Expanded(
                child: Text(
                  subject?.title ?? 'Subject',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                _counts(group.dueCount, group.newCount, group.laterCount),
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.mutedText),
              ),
            ],
          ),
        ),
        for (final d in group.decks)
          ListRowTile(
            key: ValueKey('study-deck-${d.deck.id}'),
            leading: const Icon(Icons.style_outlined),
            title: Text(d.deck.title),
            subtitle: Text(
              _counts(d.due.length, d.fresh.length, d.later.length),
            ),
            onTap: () => context.push(AppRoutes.deck(d.deck.id)),
            actions: [
              if (d.now.isNotEmpty)
                IconButton(
                  tooltip: 'Study this deck',
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => onStudy(d.now),
                ),
            ],
          ),
      ],
    );
  }

  static String _counts(int due, int fresh, int later) => [
    if (due > 0) '$due due',
    if (fresh > 0) '$fresh new',
    if (later > 0) '$later later',
  ].join(' · ');
}

/// Edits `StudySettings.newCardsPerDay` (applies to every deck).
Future<void> showNewCardLimitDialog(BuildContext context, WidgetRef ref) async {
  final value = await showDialog<int>(
    context: context,
    builder: (_) =>
        _LimitDialog(initial: ref.read(studySettingsProvider).newCardsPerDay),
  );
  if (value != null) {
    ref.read(studySettingsProvider.notifier).setNewCardsPerDay(value);
  }
}

class _LimitDialog extends StatefulWidget {
  const _LimitDialog({required this.initial});

  final int initial;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_controller.text.trim());
    if (n == null || n < 0 || n > StudySettings.maxNewCardsPerDay) {
      setState(
        () => _error =
            'Enter a number from 0 to ${StudySettings.maxNewCardsPerDay}.',
      );
      return;
    }
    Navigator.of(context).pop(n);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New cards per day'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'How many never-studied cards to introduce each day, across all '
            'decks. Reviews are not limited.',
          ),
          Gaps.h16,
          TextField(
            key: const Key('new-card-limit'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'New cards per day',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save-new-card-limit'),
        onPressed: _submit,
        child: const Text('Save'),
      ),
    ],
  );
}
