/// FSRS (Free Spaced Repetition Scheduler), version 5 (FSRS-4.5 compatible
/// formulas, 19 weights) with Anki-style learning steps.
///
/// Pure Dart, no I/O: every function takes the current time explicitly. The
/// algorithm follows the reference implementation `py-fsrs` 5.x
/// (open-spaced-repetition), so the same review history yields the same
/// stability, difficulty and due dates (fuzz disabled).
///
/// Differences from py-fsrs, required by the `card_reviews` schema:
/// - Cards that were never reviewed are in [CardState.newCard] (py-fsrs uses
///   `Learning` with step 0 and no stability).
/// - The current learning/relearning step is not stored. It is derived from
///   the last scheduled interval (`due - lastReview`): the step is the
///   largest index whose step duration is `<=` that interval. This is exact
///   as long as the steps are strictly increasing (asserted).
/// - [FsrsCard] also counts `reps` and `lapses` (review -> again).
library;

import 'dart:math' as math;

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

/// Answer button pressed for a card.
enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);

  /// FSRS grade 1..4.
  final int value;
}

/// Learning state of a card (`card_reviews.state`: 0..3).
@JsonEnum(valueField: 'value')
enum CardState {
  /// Never reviewed (no `card_reviews` row yet, or a reset one).
  newCard(0),

  /// In the initial learning steps (minutes apart).
  learning(1),

  /// Graduated; scheduled in whole days.
  review(2),

  /// Forgotten during review; in the relearning steps.
  relearning(3);

  const CardState(this.value);

  /// Stored value (smallint).
  final int value;

  /// State for a stored value; unknown values map to [newCard].
  static CardState fromValue(int value) => CardState.values.firstWhere(
    (s) => s.value == value,
    orElse: () => CardState.newCard,
  );
}

/// Scheduling state of one card for one user. Immutable.
@immutable
class FsrsCard {
  const FsrsCard({
    this.state = CardState.newCard,
    required this.due,
    this.stability = 0,
    this.difficulty = 0,
    this.elapsedDays = 0,
    this.scheduledDays = 0,
    this.reps = 0,
    this.lapses = 0,
    this.lastReview,
  });

  /// A card that has never been reviewed, due at [now].
  factory FsrsCard.newCard(DateTime now) => FsrsCard(due: now);

  final CardState state;

  /// When the card is next due (UTC).
  final DateTime due;

  /// Memory stability in days (interval at which retrievability = 90 %).
  final double stability;

  /// Difficulty 1..10.
  final double difficulty;

  /// Whole days between the previous review and the last one.
  final int elapsedDays;

  /// Whole days of the last scheduled interval (0 for learning steps).
  final int scheduledDays;

  /// Number of reviews.
  final int reps;

  /// Number of times the card was forgotten in review (review -> again).
  final int lapses;

  /// Time of the last review, null when never reviewed.
  final DateTime? lastReview;

  /// The last scheduled interval (`due - lastReview`), null when new.
  Duration? get interval =>
      lastReview == null ? null : due.difference(lastReview!);

  FsrsCard copyWith({
    CardState? state,
    DateTime? due,
    double? stability,
    double? difficulty,
    int? elapsedDays,
    int? scheduledDays,
    int? reps,
    int? lapses,
    DateTime? lastReview,
  }) => FsrsCard(
    state: state ?? this.state,
    due: due ?? this.due,
    stability: stability ?? this.stability,
    difficulty: difficulty ?? this.difficulty,
    elapsedDays: elapsedDays ?? this.elapsedDays,
    scheduledDays: scheduledDays ?? this.scheduledDays,
    reps: reps ?? this.reps,
    lapses: lapses ?? this.lapses,
    lastReview: lastReview ?? this.lastReview,
  );

  @override
  bool operator ==(Object other) =>
      other is FsrsCard &&
      other.state == state &&
      other.due == due &&
      other.stability == stability &&
      other.difficulty == difficulty &&
      other.elapsedDays == elapsedDays &&
      other.scheduledDays == scheduledDays &&
      other.reps == reps &&
      other.lapses == lapses &&
      other.lastReview == lastReview;

  @override
  int get hashCode => Object.hash(
    state,
    due,
    stability,
    difficulty,
    elapsedDays,
    scheduledDays,
    reps,
    lapses,
    lastReview,
  );

  @override
  String toString() =>
      'FsrsCard(${state.name}, due: $due, s: $stability, d: $difficulty, '
      'reps: $reps, lapses: $lapses, last: $lastReview)';
}

/// The FSRS scheduler. Stateless apart from its configuration and the
/// optional random source used for fuzz.
class Fsrs {
  Fsrs({
    List<double> weights = defaultWeights,
    this.desiredRetention = 0.9,
    this.learningSteps = defaultLearningSteps,
    this.relearningSteps = defaultRelearningSteps,
    this.maximumInterval = 36500,
    this.enableFuzz = false,
    math.Random? random,
  }) : weights = List.unmodifiable(weights),
       _random = random ?? math.Random() {
    if (weights.length != 19) {
      throw ArgumentError.value(weights.length, 'weights', 'Expected 19');
    }
    if (desiredRetention <= 0 || desiredRetention >= 1) {
      throw ArgumentError.value(desiredRetention, 'desiredRetention');
    }
    if (maximumInterval < 1) {
      throw ArgumentError.value(maximumInterval, 'maximumInterval');
    }
    _checkSteps(learningSteps, 'learningSteps');
    _checkSteps(relearningSteps, 'relearningSteps');
  }

  /// FSRS-5 default weights (py-fsrs 5.x `DEFAULT_PARAMETERS`).
  static const List<double> defaultWeights = [
    0.40255,
    1.18385,
    3.173,
    15.69105,
    7.1949,
    0.5345,
    1.4604,
    0.0046,
    1.54575,
    0.1192,
    1.01925,
    1.9395,
    0.11,
    0.29605,
    2.2698,
    0.2315,
    2.9898,
    0.51655,
    0.6621,
  ];

  static const List<Duration> defaultLearningSteps = [
    Duration(minutes: 1),
    Duration(minutes: 10),
  ];

  static const List<Duration> defaultRelearningSteps = [Duration(minutes: 10)];

  /// Forgetting curve decay.
  static const double decay = -0.5;

  /// Chosen so that retrievability is 90 % after `stability` days.
  static final double factor = math.pow(0.9, 1 / decay) - 1;

  static const double _minStability = 0.1;

  final List<double> weights;

  /// Target recall probability at the due date (0.9 = 90 %).
  final double desiredRetention;

  /// Steps for new cards (strictly increasing). Empty = graduate at once.
  final List<Duration> learningSteps;

  /// Steps after a lapse (strictly increasing). Empty = stay in review.
  final List<Duration> relearningSteps;

  /// Upper bound for intervals, in days.
  final int maximumInterval;

  /// Randomizes review intervals (>= 3 days) slightly so cards learned
  /// together spread out. Off by default (deterministic).
  final bool enableFuzz;
  final math.Random _random;

  static void _checkSteps(List<Duration> steps, String name) {
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] <= Duration.zero || (i > 0 && steps[i] <= steps[i - 1])) {
        throw ArgumentError.value(
          steps,
          name,
          'Steps must be positive and strictly increasing',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// The card after answering it with [rating] at [now].
  FsrsCard review(FsrsCard card, Rating rating, DateTime now) {
    final isNew = card.state == CardState.newCard || card.stability <= 0;
    final last = isNew ? null : card.lastReview;
    final daysSince = last == null ? null : _wholeDays(now.difference(last));

    // Memory state.
    final double stability;
    final double difficulty;
    if (isNew) {
      stability = _initialStability(rating);
      difficulty = _initialDifficulty(rating);
    } else {
      final d = _clampDifficulty(card.difficulty);
      if (daysSince != null && daysSince < 1) {
        stability = _shortTermStability(card.stability, rating);
      } else {
        stability = _nextStability(
          d,
          card.stability,
          retrievability(card, now),
          rating,
        );
      }
      difficulty = _nextDifficulty(d, rating);
    }

    // Next state and interval.
    var state = isNew ? CardState.learning : card.state;
    var lapses = card.lapses;
    Duration interval;
    switch (state) {
      case CardState.newCard:
      case CardState.learning:
      case CardState.relearning:
        final steps = state == CardState.relearning
            ? relearningSteps
            : learningSteps;
        final step = isNew ? 0 : currentStep(card);
        if (steps.isEmpty ||
            rating == Rating.easy ||
            (rating == Rating.good && step + 1 >= steps.length)) {
          state = CardState.review;
          interval = Duration(days: nextIntervalDays(stability));
        } else {
          interval = switch (rating) {
            Rating.again => steps[0],
            Rating.hard => _hardStep(steps, step),
            Rating.good => steps[step + 1],
            Rating.easy => throw StateError('unreachable'),
          };
        }
      case CardState.review:
        if (rating == Rating.again) {
          lapses++;
          if (relearningSteps.isEmpty) {
            interval = Duration(days: nextIntervalDays(stability));
          } else {
            state = CardState.relearning;
            interval = relearningSteps[0];
          }
        } else {
          interval = Duration(days: nextIntervalDays(stability));
        }
    }
    if (enableFuzz && state == CardState.review) {
      interval = _fuzz(interval);
    }

    return FsrsCard(
      state: state,
      due: now.add(interval),
      stability: stability,
      difficulty: difficulty,
      elapsedDays: daysSince == null ? 0 : math.max(0, daysSince),
      scheduledDays: interval.inDays,
      reps: card.reps + 1,
      lapses: lapses,
      lastReview: now,
    );
  }

  /// The outcome of every rating (e.g. for "Again 1m / Good 10m" buttons).
  Map<Rating, FsrsCard> preview(FsrsCard card, DateTime now) => {
    for (final r in Rating.values) r: review(card, r, now),
  };

  /// Probability of recalling [card] at [now] (0 for new cards).
  double retrievability(FsrsCard card, DateTime now) {
    final last = card.lastReview;
    if (last == null || card.stability <= 0) return 0;
    final elapsed = math.max(0, _wholeDays(now.difference(last)));
    return math.pow(1 + factor * elapsed / card.stability, decay).toDouble();
  }

  /// Interval in whole days for [stability] at [desiredRetention], clamped
  /// to `1..maximumInterval`.
  int nextIntervalDays(double stability) {
    final raw =
        stability / factor * (math.pow(desiredRetention, 1 / decay) - 1);
    final days = roundHalfEven(raw);
    return days.clamp(1, maximumInterval);
  }

  /// Current (re)learning step of [card], derived from its last interval.
  int currentStep(FsrsCard card) {
    final steps = card.state == CardState.relearning
        ? relearningSteps
        : learningSteps;
    final interval = card.interval;
    if (interval == null || steps.isEmpty) return 0;
    var step = 0;
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] <= interval) step = i;
    }
    return step;
  }

  // ---------------------------------------------------------------------------
  // Formulas
  // ---------------------------------------------------------------------------

  double _w(int i) => weights[i];

  static double _clampDifficulty(double d) => d.clamp(1.0, 10.0);

  double _initialStability(Rating rating) =>
      math.max(_w(rating.value - 1), _minStability);

  double _initialDifficulty(Rating rating) =>
      _clampDifficulty(_w(4) - math.exp(_w(5) * (rating.value - 1)) + 1);

  double _shortTermStability(double stability, Rating rating) =>
      stability * math.exp(_w(17) * (rating.value - 3 + _w(18)));

  double _nextDifficulty(double difficulty, Rating rating) {
    final delta = -(_w(6) * (rating.value - 3));
    final damped = difficulty + (10.0 - difficulty) * delta / 9.0;
    final reverted =
        _w(7) * _initialDifficulty(Rating.easy) + (1 - _w(7)) * damped;
    return _clampDifficulty(reverted);
  }

  double _nextStability(double d, double s, double r, Rating rating) =>
      rating == Rating.again
      ? _nextForgetStability(d, s, r)
      : _nextRecallStability(d, s, r, rating);

  double _nextForgetStability(double d, double s, double r) {
    final longTerm =
        _w(11) *
        math.pow(d, -_w(12)) *
        (math.pow(s + 1, _w(13)) - 1) *
        math.exp((1 - r) * _w(14));
    final shortTerm = s / math.exp(_w(17) * _w(18));
    return math.min(longTerm.toDouble(), shortTerm);
  }

  double _nextRecallStability(double d, double s, double r, Rating rating) {
    final hardPenalty = rating == Rating.hard ? _w(15) : 1.0;
    final easyBonus = rating == Rating.easy ? _w(16) : 1.0;
    return s *
        (1 +
            math.exp(_w(8)) *
                (11 - d) *
                math.pow(s, -_w(9)) *
                (math.exp((1 - r) * _w(10)) - 1) *
                hardPenalty *
                easyBonus);
  }

  static Duration _hardStep(List<Duration> steps, int step) {
    if (step == 0 && steps.length == 1) return steps[0] * 1.5;
    if (step == 0) {
      return Duration(
        microseconds: ((steps[0] + steps[1]).inMicroseconds / 2).round(),
      );
    }
    return steps[step];
  }

  Duration _fuzz(Duration interval) {
    final days = interval.inDays;
    if (days < 2.5) return interval;
    var delta = 1.0;
    for (final (start, end, factor) in _fuzzRanges) {
      delta += factor * math.max(math.min(days.toDouble(), end) - start, 0.0);
    }
    var minIvl = roundHalfEven(days - delta);
    var maxIvl = roundHalfEven(days + delta);
    minIvl = math.max(2, minIvl);
    maxIvl = math.min(maxIvl, maximumInterval);
    minIvl = math.min(minIvl, maxIvl);
    final fuzzed = _random.nextDouble() * (maxIvl - minIvl + 1) + minIvl;
    return Duration(days: math.min(roundHalfEven(fuzzed), maximumInterval));
  }

  static const List<(double, double, double)> _fuzzRanges = [
    (2.5, 7.0, 0.15),
    (7.0, 20.0, 0.1),
    (20.0, double.infinity, 0.05),
  ];

  /// Floor of [d] in whole days (like Python's `timedelta.days`).
  static int _wholeDays(Duration d) {
    const perDay = Duration.microsecondsPerDay;
    final us = d.inMicroseconds;
    return us >= 0 ? us ~/ perDay : -((-us + perDay - 1) ~/ perDay);
  }
}

/// Rounds half to even (Python's `round`), so results match py-fsrs.
@visibleForTesting
int roundHalfEven(double x) {
  final floor = x.floorToDouble();
  final diff = x - floor;
  if (diff > 0.5) return floor.toInt() + 1;
  if (diff < 0.5) return floor.toInt();
  final f = floor.toInt();
  return f.isEven ? f : f + 1;
}
