import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/study/fsrs.dart';

import 'fsrs_reference_data.dart';

final DateTime t0 = DateTime.utc(2026, 1, 1, 12);

Rating rating(String c) => switch (c) {
  'a' => Rating.again,
  'h' => Rating.hard,
  'g' => Rating.good,
  'e' => Rating.easy,
  _ => throw ArgumentError(c),
};

/// Reviews [ratings] in order, each exactly when due. Returns every state.
List<FsrsCard> runAtDue(Fsrs fsrs, String ratings) {
  var card = FsrsCard.newCard(t0);
  var now = t0;
  final out = <FsrsCard>[];
  for (final c in ratings.split('')) {
    card = fsrs.review(card, rating(c), now);
    out.add(card);
    now = card.due;
  }
  return out;
}

void main() {
  final fsrs = Fsrs();

  group('known sequences (py-fsrs 5.1.3)', () {
    test('good x7, again x2, good x4 at due', () {
      final cards = runAtDue(fsrs, 'gggggggaagggg');
      expect(
        [for (final c in cards) c.interval!.inMinutes],
        [
          10,
          5760,
          20160,
          63360,
          180000,
          472320,
          1160640,
          10,
          10,
          12960,
          28800,
          61920,
          126720,
        ],
      );
      expect(
        [for (final c in cards) c.state],
        [
          CardState.learning,
          for (var i = 0; i < 6; i++) CardState.review,
          CardState.relearning,
          CardState.relearning,
          for (var i = 0; i < 4; i++) CardState.review,
        ],
      );
      expect(cards[0].stability, closeTo(3.173, 1e-9));
      expect(cards[0].difficulty, closeTo(5.282434, 1e-6));
      expect(cards[6].stability, closeTo(805.608294, 1e-5));
      expect(cards[7].stability, closeTo(12.688021, 1e-5));
      expect(cards[7].difficulty, closeTo(6.75918, 1e-5));
      expect(cards.last.stability, closeTo(88.367158, 1e-5));
      expect(cards.last.reps, 13);
      expect(cards.last.lapses, 1, reason: 'only review -> again is a lapse');
    });

    test('first rating: again 1m, hard 5.5m, good 10m, easy 16 days', () {
      final again = fsrs.review(FsrsCard.newCard(t0), Rating.again, t0);
      expect(again.state, CardState.learning);
      expect(again.interval, const Duration(minutes: 1));
      expect(again.stability, closeTo(0.40255, 1e-12));
      expect(again.difficulty, closeTo(7.1949, 1e-9));

      final hard = fsrs.review(FsrsCard.newCard(t0), Rating.hard, t0);
      expect(hard.interval, const Duration(seconds: 330));
      expect(hard.difficulty, closeTo(6.488305, 1e-6));

      final good = fsrs.review(FsrsCard.newCard(t0), Rating.good, t0);
      expect(good.interval, const Duration(minutes: 10));

      final easy = fsrs.review(FsrsCard.newCard(t0), Rating.easy, t0);
      expect(easy.state, CardState.review);
      expect(easy.interval, const Duration(days: 16));
      expect(easy.scheduledDays, 16);
      expect(easy.difficulty, closeTo(3.224502, 1e-6));
    });

    test('hard keeps the learning step', () {
      final cards = runAtDue(fsrs, 'hhhhh');
      for (final c in cards) {
        expect(c.state, CardState.learning);
        expect(c.interval, const Duration(seconds: 330));
      }
      expect(cards.last.stability, closeTo(0.58896, 1e-5));
      expect(cards.last.difficulty, closeTo(8.205127, 1e-6));
    });

    test('easy x4 grows fast and difficulty bottoms out at 1', () {
      final cards = runAtDue(fsrs, 'eeee');
      expect([for (final c in cards) c.scheduledDays], [16, 150, 1252, 9305]);
      expect(cards.last.difficulty, 1.0);
    });

    for (final (i, ref) in referenceCases.indexed) {
      test('random sequence #$i (${ref.ratings}) with early/late reviews', () {
        var card = FsrsCard.newCard(t0);
        var now = t0;
        for (var j = 0; j < ref.ratings.length; j++) {
          card = fsrs.review(card, rating(ref.ratings[j]), now);
          final (state, s, d, ivl) = ref.expected[j];
          final where = 'review ${j + 1}';
          expect(card.state.value, state, reason: where);
          expect(
            card.stability,
            closeTo(s, 1e-9 * math.max(1, s)),
            reason: where,
          );
          expect(card.difficulty, closeTo(d, 1e-9), reason: where);
          expect(card.interval!.inSeconds, ivl, reason: where);
          final gap = ref.gaps[j];
          now = gap == null ? card.due : now.add(Duration(minutes: gap));
        }
      });
    }
  });

  group('invariants', () {
    test('intervals are monotonic in the rating for every state', () {
      final starts = <String, FsrsCard>{
        'new': FsrsCard.newCard(t0),
        'learning': runAtDue(fsrs, 'g').last,
        'review': runAtDue(fsrs, 'ggg').last,
        'mature review': runAtDue(fsrs, 'gggggg').last,
        'relearning': runAtDue(fsrs, 'ggga').last,
      };
      for (final MapEntry(key: name, value: card) in starts.entries) {
        for (final delay in [Duration.zero, const Duration(days: 3)]) {
          final now = card.due.add(delay);
          final preview = fsrs.preview(card, now);
          final ivls = [for (final r in Rating.values) preview[r]!.interval!];
          for (var i = 1; i < ivls.length; i++) {
            expect(
              ivls[i] >= ivls[i - 1],
              isTrue,
              reason: '$name +$delay: ${Rating.values[i]} >= previous ($ivls)',
            );
          }
          final stabilities = [
            for (final r in Rating.values) preview[r]!.stability,
          ];
          for (var i = 1; i < stabilities.length; i++) {
            expect(stabilities[i], greaterThanOrEqualTo(stabilities[i - 1]));
          }
        }
      }
    });

    test('difficulty decreases with better ratings and stays in 1..10', () {
      final card = runAtDue(fsrs, 'ggg').last;
      final p = fsrs.preview(card, card.due);
      expect(
        p[Rating.again]!.difficulty,
        greaterThan(p[Rating.good]!.difficulty),
      );
      expect(p[Rating.easy]!.difficulty, lessThan(p[Rating.good]!.difficulty));
      for (final seq in ['aaaaaaaaaa', 'eeeeeeeeee']) {
        for (final c in runAtDue(fsrs, seq)) {
          expect(c.difficulty, inInclusiveRange(1, 10));
        }
      }
    });

    test('lapse: review -> again goes to relearning, counts a lapse and '
        'lowers stability', () {
      final review = runAtDue(fsrs, 'gggg').last;
      expect(review.state, CardState.review);
      final lapsed = fsrs.review(review, Rating.again, review.due);
      expect(lapsed.state, CardState.relearning);
      expect(lapsed.lapses, review.lapses + 1);
      expect(lapsed.stability, lessThan(review.stability));
      expect(lapsed.interval, const Duration(minutes: 10));
      expect(lapsed.scheduledDays, 0);

      // Again while relearning is not another lapse.
      final again = fsrs.review(lapsed, Rating.again, lapsed.due);
      expect(again.state, CardState.relearning);
      expect(again.lapses, lapsed.lapses);
      // Good graduates back to review (single relearning step).
      final back = fsrs.review(again, Rating.good, again.due);
      expect(back.state, CardState.review);
      expect(back.scheduledDays, greaterThanOrEqualTo(1));
    });

    test('learning steps are derived from the last interval', () {
      final steps = Fsrs(
        learningSteps: const [
          Duration(minutes: 1),
          Duration(minutes: 10),
          Duration(hours: 1),
        ],
      );
      final a = steps.review(FsrsCard.newCard(t0), Rating.good, t0);
      expect(steps.currentStep(a), 1);
      expect(a.interval, const Duration(minutes: 10));
      final b = steps.review(a, Rating.hard, a.due);
      expect(steps.currentStep(b), 1, reason: 'hard repeats the step');
      expect(b.interval, const Duration(minutes: 10));
      final c = steps.review(b, Rating.good, b.due);
      expect(steps.currentStep(c), 2);
      expect(c.interval, const Duration(hours: 1));
      final d = steps.review(c, Rating.again, c.due);
      expect(steps.currentStep(d), 0);
      final e = steps.review(c, Rating.good, c.due);
      expect(e.state, CardState.review);
    });

    test('no learning/relearning steps', () {
      final noSteps = Fsrs(learningSteps: const [], relearningSteps: const []);
      final first = noSteps.review(FsrsCard.newCard(t0), Rating.again, t0);
      expect(first.state, CardState.review);
      expect(first.scheduledDays, 1);
      final lapse = noSteps.review(first, Rating.again, first.due);
      expect(lapse.state, CardState.review);
      expect(lapse.lapses, 1);
    });

    test('rejects bad configuration', () {
      expect(() => Fsrs(weights: const [1, 2, 3]), throwsArgumentError);
      expect(() => Fsrs(desiredRetention: 1), throwsArgumentError);
      expect(
        () => Fsrs(
          learningSteps: const [Duration(minutes: 10), Duration(minutes: 1)],
        ),
        throwsArgumentError,
      );
    });

    test('desired retention: higher retention -> shorter intervals', () {
      final strict = Fsrs(desiredRetention: 0.95);
      final lax = Fsrs(desiredRetention: 0.8);
      expect(strict.nextIntervalDays(30), lessThan(fsrs.nextIntervalDays(30)));
      expect(lax.nextIntervalDays(30), greaterThan(fsrs.nextIntervalDays(30)));
      expect(fsrs.nextIntervalDays(30), 30, reason: 'R=0.9 -> I = S');
      expect(fsrs.nextIntervalDays(0.01), 1);
      expect(Fsrs(maximumInterval: 100).nextIntervalDays(1e6), 100);
    });

    test('retrievability is 90 % after `stability` days and 0 when new', () {
      final card = runAtDue(fsrs, 'gggg').last;
      final atS = card.lastReview!.add(Duration(days: card.stability.round()));
      final r = fsrs.retrievability(card, atS);
      expect(r, closeTo(0.9, 0.01));
      expect(fsrs.retrievability(card, card.lastReview!), 1.0);
      expect(fsrs.retrievability(FsrsCard.newCard(t0), t0), 0);
    });

    test('elapsed days and reps are tracked', () {
      final first = fsrs.review(FsrsCard.newCard(t0), Rating.easy, t0);
      expect(first.elapsedDays, 0);
      final late = first.due.add(const Duration(days: 2, hours: 3));
      final second = fsrs.review(first, Rating.good, late);
      expect(second.elapsedDays, 18);
      expect(second.reps, 2);
      expect(second.lastReview, late);
    });
  });

  group('fuzz', () {
    test('off: deterministic; on: within the fuzz range, seeded', () {
      final card = runAtDue(fsrs, 'ggggg').last;
      final plain = fsrs.review(card, Rating.good, card.due).scheduledDays;
      final seen = <int>{};
      for (var seed = 0; seed < 50; seed++) {
        final fuzzed = Fsrs(
          enableFuzz: true,
          random: math.Random(seed),
        ).review(card, Rating.good, card.due).scheduledDays;
        seen.add(fuzzed);
        // delta = 1 + 0.15*4.5 + 0.1*13 + 0.05*(I-20)
        final delta = 1 + 0.675 + 1.3 + 0.05 * (plain - 20);
        expect(fuzzed, inInclusiveRange(plain - delta - 1, plain + delta + 1));
      }
      expect(seen.length, greaterThan(1));
      final a = Fsrs(enableFuzz: true, random: math.Random(7));
      final b = Fsrs(enableFuzz: true, random: math.Random(7));
      expect(
        a.review(card, Rating.good, card.due),
        b.review(card, Rating.good, card.due),
      );
    });

    test('short intervals and learning steps are never fuzzed', () {
      final f = Fsrs(enableFuzz: true, random: math.Random(1));
      final again = f.review(FsrsCard.newCard(t0), Rating.again, t0);
      final learning = f.review(again, Rating.good, again.due);
      expect(learning.interval, const Duration(minutes: 10));
      final graduated = f.review(learning, Rating.good, learning.due);
      expect(graduated.state, CardState.review);
      expect(graduated.scheduledDays, 1, reason: '< 2.5 days is not fuzzed');
    });
  });

  test('roundHalfEven matches Python round()', () {
    expect(roundHalfEven(0.5), 0);
    expect(roundHalfEven(1.5), 2);
    expect(roundHalfEven(2.5), 2);
    expect(roundHalfEven(2.51), 3);
    expect(roundHalfEven(-0.5), 0);
    expect(roundHalfEven(-1.5), -2);
  });

  test('CardState values match the card_reviews.state column', () {
    expect([for (final s in CardState.values) s.value], [0, 1, 2, 3]);
    expect(CardState.fromValue(2), CardState.review);
    expect(CardState.fromValue(9), CardState.newCard);
  });
}
