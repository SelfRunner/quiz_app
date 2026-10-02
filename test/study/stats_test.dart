import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/study/local_day.dart';
import 'package:quiz_app/study/stats.dart';

final utc = fixedOffset(Duration.zero);

Question q(String id) => Question(
  id: id,
  type: QuestionType.mcqSingle,
  prompt: 'P$id',
  options: const ['a', 'b'],
  correctIndices: const [0],
);

Quiz quiz(String id, String subjectId, List<String> questions) => Quiz(
  id: id,
  subjectId: subjectId,
  ownerId: 'u',
  title: 'Quiz $id',
  questions: [for (final x in questions) q(x)],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Subject subject(String id, String title) => Subject(
  id: id,
  ownerId: 'u',
  title: title,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

int _n = 0;

/// A completed attempt; [results] maps question id -> correct (null =
/// ungraded).
QuizAttempt attempt(
  String quizId,
  Map<String, bool?> results, {
  required DateTime at,
  AttemptMode mode = AttemptMode.practice,
  bool completed = true,
}) => QuizAttempt(
  id: 'a${_n++}',
  quizId: quizId,
  ownerId: 'u',
  answers: [
    for (final e in results.entries)
      QuestionAnswer(questionId: e.key, isCorrect: e.value),
  ],
  score: results.values.where((v) => v == true).length.toDouble(),
  total: results.length,
  mode: mode,
  startedAt: at.subtract(const Duration(minutes: 5)),
  completedAt: completed ? at : null,
  createdAt: at,
  updatedAt: at,
);

Deck deck(String id) => Deck(
  id: id,
  subjectId: 's1',
  ownerId: 'u',
  title: 'Deck $id',
  cards: const [
    Flashcard(id: 'c1', front: 'f', back: 'b'),
    Flashcard(id: 'c2', front: 'f', back: 'b'),
  ],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

CardReview review(String deckId, String cardId, DateTime last) => CardReview(
  id: '$deckId/$cardId',
  ownerId: 'u',
  deckId: deckId,
  cardId: cardId,
  state: CardState.review,
  dueAt: last.add(const Duration(days: 30)),
  stability: 30,
  difficulty: 5,
  scheduledDays: 30,
  reps: 3,
  lastReviewAt: last,
  createdAt: last.subtract(const Duration(days: 10)),
  updatedAt: last,
);

void main() {
  final now = DateTime.utc(2026, 3, 10, 12);
  DateTime day(int d, [int h = 12]) => DateTime.utc(2026, 3, d, h);

  group('streak', () {
    test('counts consecutive local days ending today or yesterday', () {
      final today = localDay(now, utc);
      Set<DateTime> days(List<int> ds) => {
        for (final d in ds) localDay(day(d), utc),
      };
      expect(
        computeStreak(days([10, 9, 8, 5, 4]), today),
        const StreakInfo(current: 3, longest: 3, activeToday: true),
      );
      expect(
        computeStreak(days([9, 8]), today),
        const StreakInfo(current: 2, longest: 2),
        reason: 'not studied yet today: still alive',
      );
      expect(computeStreak(days([8, 7, 6, 5]), today).current, 0);
      expect(computeStreak(days([8, 7, 6, 5]), today).longest, 4);
      expect(computeStreak({}, today), const StreakInfo());
    });

    test('crosses month boundaries', () {
      final days = {
        for (final d in [
          DateTime.utc(2026, 2, 27),
          DateTime.utc(2026, 2, 28),
          DateTime.utc(2026, 3, 1),
        ])
          d,
      };
      expect(computeStreak(days, DateTime.utc(2026, 3, 1)).current, 3);
    });

    test('activity days use the local time zone; attempts and reviews', () {
      final lateEvening = DateTime.utc(2026, 3, 9, 23, 30);
      final a = attempt('q', {'x': true}, at: lateEvening);
      expect(activityDays(attempts: [a], toLocal: utc), {
        DateTime.utc(2026, 3, 9),
      });
      expect(
        activityDays(
          attempts: [a],
          toLocal: fixedOffset(const Duration(hours: 1)),
        ),
        {DateTime.utc(2026, 3, 10)},
      );
      final inProgress = attempt(
        'q',
        {'x': false},
        at: day(8),
        completed: false,
      );
      final empty = attempt('q', {}, at: day(7), completed: false);
      final r = review('d', 'c1', day(6));
      expect(
        activityDays(attempts: [inProgress, empty], reviews: [r], toLocal: utc),
        {
          DateTime.utc(2026, 3, 8),
          DateTime.utc(2026, 3, 6),
          DateTime.utc(2026, 2, 24), // first review (row created)
        },
      );
    });
  });

  group('quizzes', () {
    final quizzes = [
      quiz('qa', 's1', ['1', '2', '3']),
      quiz('qb', 's2', ['1', '2']),
    ];
    final subjects = [subject('s1', 'Zoology'), subject('s2', 'Algebra')];
    final attempts = [
      attempt('qa', {'1': true, '2': false, '3': false}, at: day(1)),
      attempt('qa', {'1': true, '2': false, '3': true}, at: day(2)),
      attempt('qb', {'1': true, '2': true}, at: day(3)),
      attempt('qb', {'1': true, '2': null}, at: day(4)),
      attempt('qa', {'1': false}, at: day(5), completed: false),
      attempt('gone', {'1': false}, at: day(5)),
    ];

    test('quizzes taken and overall accuracy', () {
      expect(quizzesTaken(attempts), 5);
      expect(
        overallAccuracy(attempts),
        const Accuracy(correct: 6, answered: 10),
      );
      expect(const Accuracy().ratio, isNull);
    });

    test('accuracy per subject (sorted by title)', () {
      final result = accuracyBySubject(
        attempts: attempts,
        quizzes: quizzes,
        subjects: subjects,
      );
      expect(result.map((s) => s.title), ['Algebra', 'Zoology']);
      expect(result[0].accuracy, const Accuracy(correct: 3, answered: 3));
      expect(result[0].attempts, 2);
      expect(result[1].accuracy, const Accuracy(correct: 3, answered: 6));
    });

    test('weakest questions need a minimum sample', () {
      final weak = weakestQuestions(attempts: attempts, quizzes: quizzes);
      expect(weak.map((w) => (w.quizId, w.questionId)), [
        ('qa', '2'),
        ('qa', '3'),
      ]);
      expect(weak.first.accuracy, const Accuracy(correct: 0, answered: 2));
      expect(weak.first.prompt, 'P2');
      expect(
        weakestQuestions(attempts: attempts, quizzes: quizzes, minAnswers: 3),
        isEmpty,
      );
      expect(
        weakestQuestions(attempts: attempts, quizzes: quizzes, limit: 1),
        hasLength(1),
      );
    });

    test('weakest quizzes', () {
      final weak = weakestQuizzes(attempts: attempts, quizzes: quizzes);
      expect(weak.single.quizId, 'qa');
      expect(weak.single.attempts, 2);
    });
  });

  test('recent activity merges attempts and review sessions', () {
    final quizzes = [
      quiz('qa', 's1', ['1']),
    ];
    final a1 = attempt(
      'qa',
      {'1': true},
      at: day(9, 8),
      mode: AttemptMode.exam,
    );
    final a2 = attempt('qa', {'1': false}, at: day(10, 9));
    final feed = recentActivity(
      attempts: [a1, a2],
      quizzes: quizzes,
      reviews: [
        review('d1', 'c1', day(10, 10)),
        review('d1', 'c2', day(10, 11)),
        review('d1', 'c3', day(9, 7)),
        review('unknown', 'c1', day(10, 12)),
      ],
      decks: [deck('d1')],
      toLocal: utc,
    );
    expect(feed, hasLength(4));
    final first = feed[0] as ReviewActivity;
    expect(first.cards, 2);
    expect(first.at, day(10, 11));
    expect(first.deckTitle, 'Deck d1');
    expect((feed[1] as QuizActivity).attempt, a2);
    expect((feed[2] as QuizActivity).mode, AttemptMode.exam);
    expect((feed[3] as ReviewActivity).day, DateTime.utc(2026, 3, 9));
    expect(
      recentActivity(attempts: [a1, a2], quizzes: quizzes, limit: 1),
      hasLength(1),
    );
  });

  test('computeDashboard puts it together', () {
    final qa = quiz('qa', 's1', ['1', '2']);
    final snapshot = StudySnapshot(
      subjects: [subject('s1', 'Bio')],
      quizzes: [qa],
      decks: [deck('d1')],
      attempts: [
        attempt('qa', {'1': true, '2': false}, at: day(9)),
        attempt('qa', {'1': true, '2': false}, at: day(10, 9)),
      ],
      reviews: [review('d1', 'c1', day(10, 8))],
      mistakes: [
        Mistake(
          id: 'm1',
          ownerId: 'u',
          quizId: 'qa',
          questionId: '2',
          wrongCount: 2,
          createdAt: day(9),
          updatedAt: day(10),
        ),
        Mistake(
          id: 'm2',
          ownerId: 'u',
          quizId: 'qa',
          questionId: 'removed',
          createdAt: day(9),
          updatedAt: day(10),
        ),
        Mistake(
          id: 'm3',
          ownerId: 'u',
          quizId: 'qa',
          questionId: '1',
          resolvedAt: day(10),
          createdAt: day(9),
          updatedAt: day(10),
        ),
      ],
    );
    final stats = computeDashboard(
      snapshot,
      now: now,
      newCardsPerDay: 5,
      toLocal: utc,
    );
    expect(stats.streak.current, 2);
    expect(stats.streak.activeToday, isTrue);
    expect(stats.quizzesTaken, 2);
    expect(stats.overallAccuracy.ratio, 0.5);
    expect(stats.accuracyBySubject.single.title, 'Bio');
    expect(stats.weakestQuestions.single.questionId, '2');
    expect(stats.dueCards, 1, reason: 'c2 is new, c1 not due');
    expect(stats.reviewsToday, 1);
    expect(stats.openMistakes, 1);
    expect(stats.recentActivity, hasLength(3));
  });
}
