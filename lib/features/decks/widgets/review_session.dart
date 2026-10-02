import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/card_review.dart';
import '../../../study/due_queue.dart';
import '../domain/deck_format.dart';

/// Cards in (re)learning due within this window come back in the same
/// session (like Anki's "learn ahead" limit).
const Duration learnAheadLimit = Duration(minutes: 20);

/// A flashcard review session over [cards] (a snapshot of a due queue, in
/// study order): front → reveal the back (Space / Enter / tap) → rate
/// Again / Hard / Good / Easy (keys 1–4) with each rating's next interval
/// from the scheduler preview. Every rating is saved immediately with
/// `ReviewRepository.recordReview` (local-first, works offline), cards that
/// land in a short (re)learning step come back at the end, and a summary is
/// shown when the queue is empty.
///
/// Works for own and shared decks (review state is always the user's).
class ReviewSession extends ConsumerStatefulWidget {
  const ReviewSession({
    super.key,
    required this.cards,
    required this.onDone,
    this.showDeckTitle = false,
    this.doneLabel = 'Done',
  });

  final List<DueCard> cards;

  /// Called from the summary's primary button.
  final VoidCallback onDone;

  /// Show which deck each card is from (merged queues).
  final bool showDeckTitle;
  final String doneLabel;

  @override
  ConsumerState<ReviewSession> createState() => _ReviewSessionState();
}

class _ReviewSessionState extends ConsumerState<ReviewSession> {
  final _focus = FocusNode(debugLabel: 'review-session');
  late List<DueCard> _queue;
  int _pos = 0;
  bool _revealed = false;
  bool _hintShown = false;
  bool _busy = false;
  int _reviews = 0;
  final Set<String> _studied = {};
  final Map<Rating, int> _counts = {for (final r in Rating.values) r: 0};
  late DateTime _startedAt;
  DateTime? _finishedAt;
  Map<Rating, Duration>? _intervals;
  int _previewToken = 0;

  DateTime _now() => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    _queue = [...widget.cards];
    _startedAt = _now();
    if (_queue.isEmpty) _finishedAt = _startedAt;
    _loadPreview();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  DueCard? get _current => _pos < _queue.length ? _queue[_pos] : null;

  Future<void> _loadPreview() async {
    final item = _current;
    final token = ++_previewToken;
    _intervals = null;
    if (item == null) return;
    try {
      final due = await ref
          .read(reviewRepositoryProvider)
          .previewDue(deckId: item.deck.id, cardId: item.card.id);
      if (!mounted || token != _previewToken) return;
      final now = _now();
      setState(
        () => _intervals = {
          for (final e in due.entries) e.key: e.value.difference(now),
        },
      );
    } on Object {
      // Labels are optional; rating still works (or reports the error).
    }
  }

  void _reveal() {
    if (_current == null || _revealed) return;
    setState(() => _revealed = true);
    _focus.requestFocus();
  }

  Future<void> _rate(Rating rating) async {
    final item = _current;
    if (item == null || !_revealed || _busy) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(reviewRepositoryProvider)
          .recordReview(
            deckId: item.deck.id,
            cardId: item.card.id,
            rating: rating,
          );
      if (!mounted) return;
      final relearn =
          (saved.state == CardState.learning ||
              saved.state == CardState.relearning) &&
          !saved.dueAt.isAfter(_now().add(learnAheadLimit));
      setState(() {
        _reviews++;
        _studied.add(item.key);
        _counts[rating] = _counts[rating]! + 1;
        if (relearn) {
          _queue.add(DueCard(deck: item.deck, card: item.card, review: saved));
        }
        _advance();
      });
    } on NotFoundException {
      if (!mounted) return;
      showSnack(context, 'This card no longer exists — skipped.');
      setState(_advance);
    } on Object catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  /// Moves to the next card (call inside setState).
  void _advance() {
    _pos++;
    _revealed = false;
    _hintShown = false;
    if (_current == null) _finishedAt = _now();
    _loadPreview();
  }

  static final _digitRatings = {
    LogicalKeyboardKey.digit1: Rating.again,
    LogicalKeyboardKey.digit2: Rating.hard,
    LogicalKeyboardKey.digit3: Rating.good,
    LogicalKeyboardKey.digit4: Rating.easy,
    LogicalKeyboardKey.numpad1: Rating.again,
    LogicalKeyboardKey.numpad2: Rating.hard,
    LogicalKeyboardKey.numpad3: Rating.good,
    LogicalKeyboardKey.numpad4: Rating.easy,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _current == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isReveal =
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!_revealed) {
      if (isReveal) {
        _reveal();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyH && _current!.card.hint != null) {
        setState(() => _hintShown = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final rating = _digitRatings[key] ?? (isReveal ? Rating.good : null);
    if (rating == null) return KeyEventResult.ignored;
    _rate(rating);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: _current == null ? _summary(context) : _card(context, _current!),
    );
  }

  // --- Card -------------------------------------------------------------------

  Widget _card(BuildContext context, DueCard item) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final remaining = _queue.length - _pos;
    final total = _queue.length;
    final hint = item.card.hint?.trim() ?? '';

    final progress = Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: Radii.xsAll,
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : _pos / total,
              minHeight: 4,
              backgroundColor: colors.skeleton,
            ),
          ),
        ),
        Gaps.w12,
        Text(
          '$remaining left',
          key: const Key('review-remaining'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.mutedText,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    final meta = Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.showDeckTitle)
          Text(
            item.deck.title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
        _StateTag(state: item.state),
      ],
    );

    final card = AppCard(
      key: ValueKey('review-card-${item.key}-$_pos'),
      onTap: _revealed ? null : _reveal,
      padding: const EdgeInsets.all(Insets.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            meta,
            Gaps.h16,
            Text(
              item.card.front,
              key: const Key('review-front'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            if (hint.isNotEmpty && !_revealed) ...[
              Gaps.h16,
              Center(
                child: _hintShown
                    ? Text(
                        hint,
                        key: const Key('review-hint'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.mutedText,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : TextButton.icon(
                        key: const Key('review-show-hint'),
                        onPressed: () => setState(() => _hintShown = true),
                        icon: const Icon(Icons.lightbulb_outline, size: 16),
                        label: const Text('Hint'),
                      ),
              ),
            ],
            if (_revealed) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xl),
                child: Divider(height: 1, color: colors.hairline),
              ),
              Text(
                item.card.back,
                key: const Key('review-back'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (hint.isNotEmpty) ...[
                Gaps.h12,
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    final actions = _revealed
        ? _ratingBar(context)
        : Column(
            children: [
              FilledButton(
                key: const Key('review-reveal'),
                style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
                onPressed: _reveal,
                child: const Text('Show answer'),
              ),
              Gaps.h8,
              const KeyboardShortcutHint(keys: ['Space'], label: 'to reveal'),
            ],
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: Insets.lg),
      child: ContentContainer(
        maxWidth: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [progress, Gaps.h16, card, Gaps.h24, actions],
        ),
      ),
    );
  }

  Widget _ratingBar(BuildContext context) {
    final colors = AppColors.of(context);
    Color tone(Rating r) => switch (r) {
      Rating.again => colors.danger,
      Rating.hard => colors.warning,
      Rating.good => colors.success,
      Rating.easy => colors.info,
    };
    return Column(
      children: [
        Row(
          children: [
            for (final (i, r) in Rating.values.indexed) ...[
              if (i > 0) Gaps.w8,
              Expanded(
                child: _RatingButton(
                  key: Key('rate-${r.name}'),
                  label: ratingLabel(r),
                  interval: _intervals?[r],
                  shortcut: '${i + 1}',
                  color: tone(r),
                  onPressed: _busy ? null : () => _rate(r),
                ),
              ),
            ],
          ],
        ),
        Gaps.h8,
        Text(
          'Keys 1–4 to rate · Space = Good',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.faintText),
        ),
      ],
    );
  }

  // --- Summary ----------------------------------------------------------------

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final elapsed = (_finishedAt ?? _now()).difference(_startedAt);
    final minutes = elapsed.inMinutes;
    final again = _counts[Rating.again]!;
    final correct = _reviews == 0 ? null : (_reviews - again) / _reviews;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
      child: ContentContainer(
        maxWidth: 560,
        child: Column(
          key: const Key('review-summary'),
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: colors.success),
            Gaps.h16,
            Text(
              _reviews == 0 ? 'Nothing to review' : 'Session complete',
              style: theme.textTheme.headlineSmall,
            ),
            Gaps.h8,
            Text(
              _reviews == 0
                  ? 'All caught up for now.'
                  : '${plural(_studied.length, 'card')} · '
                        '${plural(_reviews, 'review')} · '
                        '${minutes < 1 ? 'under a minute' : plural(minutes, 'minute')}',
              key: const Key('review-summary-text'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.mutedText,
              ),
            ),
            if (_reviews > 0) ...[
              Gaps.h24,
              AppCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final r in Rating.values)
                      Column(
                        children: [
                          Text(
                            '${_counts[r]}',
                            key: Key('summary-${r.name}'),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            ratingLabel(r),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.mutedText,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (correct != null) ...[
                Gaps.h12,
                Text(
                  'Remembered ${(correct * 100).round()}% of reviews',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
              ],
            ],
            Gaps.h24,
            FilledButton(
              key: const Key('review-done'),
              style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
              onPressed: widget.onDone,
              child: Text(widget.doneLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    super.key,
    required this.label,
    required this.interval,
    required this.shortcut,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Duration? interval;
  final String shortcut;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.xs,
          vertical: Insets.sm,
        ),
        minimumSize: const Size(0, 60),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            interval == null ? '·' : formatInterval(interval!),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.mutedText,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Gaps.h2,
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
          Gaps.h2,
          Text(
            shortcut,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.faintText,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateTag extends StatelessWidget {
  const _StateTag({required this.state});

  final CardState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = switch (state) {
      CardState.newCard => colors.info,
      CardState.learning || CardState.relearning => colors.warning,
      CardState.review => colors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: Radii.smAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Gaps.w4,
          Text(
            cardStateLabel(state),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.mutedText),
          ),
        ],
      ),
    );
  }
}
