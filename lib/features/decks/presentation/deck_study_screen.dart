import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../study/due_queue.dart';
import '../domain/deck_format.dart';
import '../widgets/review_session.dart';

/// Studies one deck: today's due reviews and new cards (within the daily
/// new-card limit) in a [ReviewSession]. Own and shared decks.
class DeckStudyScreen extends ConsumerStatefulWidget {
  const DeckStudyScreen({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<DeckStudyScreen> createState() => _DeckStudyScreenState();
}

class _DeckStudyScreenState extends ConsumerState<DeckStudyScreen> {
  /// The session's cards, captured once so reviews don't reshuffle it.
  List<DueCard>? _session;
  int _round = 0;

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.deck(widget.deckId));
    }
  }

  void _start(List<DueCard> cards) => setState(() {
    _session = cards;
    _round++;
  });

  @override
  Widget build(BuildContext context) {
    final deck = ref.watch(deckProvider(widget.deckId));
    final queue = ref.watch(deckDueQueueProvider(widget.deckId));
    final title = deck.value?.title ?? 'Study';
    final loaded = queue.value;
    if (_session == null && deck.value != null && loaded != null) {
      final due = [...loaded.dueNow, ...loaded.newCards];
      // Captured once; later queue updates don't restart the session.
      if (due.isNotEmpty) {
        _session = due;
        _round++;
      }
    }

    final Widget body;
    if (_session != null) {
      body = ReviewSession(
        key: ValueKey('session-$_round'),
        cards: _session!,
        onDone: _close,
      );
    } else if (deck.hasValue && deck.value == null) {
      body = const NotFoundView(what: 'Deck');
    } else if (queue.hasError || deck.hasError) {
      body = EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load the deck',
        message: errorText(queue.error ?? deck.error!),
      );
    } else if (queue.value case final q? when deck.value != null) {
      body = _caughtUp(context, q, deck.value!.cards.length);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: body,
    );
  }

  Widget _caughtUp(BuildContext context, DueQueue q, int total) {
    if (total == 0) {
      return EmptyState(
        icon: Icons.style_outlined,
        title: 'This deck has no cards yet',
        action: OutlinedButton(
          onPressed: _close,
          child: const Text('Back to deck'),
        ),
      );
    }
    final later = q.laterToday;
    final newLimited = q.unseenTotal > 0 && q.newRemainingToday == 0;
    return EmptyState(
      key: const Key('deck-caught-up'),
      icon: Icons.check_circle_outline,
      title: 'All caught up',
      message: [
        if (later.isNotEmpty)
          '${plural(later.length, 'card')} will be due again later today.',
        if (newLimited)
          "You've reached today's new-card limit; "
              '${plural(q.unseenTotal, 'new card')} wait for tomorrow.',
        if (later.isEmpty && !newLimited) 'Nothing is due in this deck today.',
      ].join(' '),
      action: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.sm,
        alignment: WrapAlignment.center,
        children: [
          if (later.isNotEmpty)
            FilledButton.tonal(
              key: const Key('study-later-today'),
              onPressed: () => _start(later),
              child: const Text('Study them now'),
            ),
          OutlinedButton(onPressed: _close, child: const Text('Back to deck')),
        ],
      ),
    );
  }
}
