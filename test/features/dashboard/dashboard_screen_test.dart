import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/providers.dart';
import 'package:quiz_app/core/theme/app_theme.dart';
import 'package:quiz_app/core/widgets/app_card.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/dashboard/application/dashboard_providers.dart';
import 'package:quiz_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:quiz_app/study/due_queue.dart';
import 'package:quiz_app/study/stats.dart';
import 'package:quiz_app/study/study_providers.dart';

import '../subjects/support/fakes.dart';

/// 2026-01-01 12:00 UTC (a Thursday).
final DateTime _now = kNow;
final DateTime _today = DateTime.utc(2026, 1, 1);

Deck _deck() => Deck(
  id: 'd1',
  subjectId: 's1',
  ownerId: kUserId,
  title: 'Cell vocab',
  cards: const [
    Flashcard(id: 'c1', front: 'a', back: 'b'),
    Flashcard(id: 'c2', front: 'c', back: 'd'),
    Flashcard(id: 'c3', front: 'e', back: 'f'),
  ],
  createdAt: _now,
  updatedAt: _now,
);

DashboardStats _stats() {
  final deck = _deck();
  final attempt = QuizAttempt(
    id: 'a1',
    quizId: 'q1',
    ownerId: kUserId,
    score: 8,
    total: 10,
    startedAt: _now.subtract(const Duration(hours: 2)),
    completedAt: _now.subtract(const Duration(hours: 1)),
    createdAt: _now,
    updatedAt: _now,
  );
  return DashboardStats(
    streak: const StreakInfo(current: 3, longest: 9, activeToday: true),
    quizzesTaken: 12,
    overallAccuracy: const Accuracy(correct: 40, answered: 50),
    accuracyBySubject: const [
      SubjectAccuracy(
        subjectId: 's1',
        title: 'Biology',
        color: 0xFF4CAF50,
        accuracy: Accuracy(correct: 3, answered: 4),
        attempts: 2,
      ),
      SubjectAccuracy(
        subjectId: 's2',
        title: 'History',
        accuracy: Accuracy(correct: 1, answered: 4),
        attempts: 1,
      ),
    ],
    weakestQuestions: const [
      WeakQuestion(
        quizId: 'q1',
        quizTitle: 'Cells quiz',
        subjectId: 's1',
        questionId: 'x1',
        prompt: 'What does the mitochondria do?',
        accuracy: Accuracy(correct: 1, answered: 4),
      ),
    ],
    due: DueQueue(
      dueNow: [
        DueCard(deck: deck, card: deck.cards[0]),
        DueCard(deck: deck, card: deck.cards[1]),
      ],
      newCards: [DueCard(deck: deck, card: deck.cards[2])],
    ),
    openMistakes: 4,
    recentActivity: [
      QuizActivity(attempt: attempt, quizTitle: 'Cells quiz', subjectId: 's1'),
      ReviewActivity(
        deckId: 'd1',
        deckTitle: 'Cell vocab',
        subjectId: 's1',
        day: _today,
        cards: 6,
        at: _now.subtract(const Duration(hours: 3)),
      ),
    ],
  );
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required DashboardStats stats,
  TestDeps? deps,
  Size size = const Size(1280, 2000),
  Set<DateTime>? days,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  deps ??= TestDeps(
    user: const AppUser(id: kUserId, email: 'ada@x.io', displayName: 'Ada L'),
  );
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const DashboardScreen()),
      GoRoute(path: '/study', builder: (_, _) => const Text('study screen')),
      GoRoute(
        path: '/mistakes',
        builder: (_, _) => const Text('mistakes screen'),
      ),
      GoRoute(
        path: '/quizzes/:id',
        builder: (_, s) => Text('quiz ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/decks/:id',
        builder: (_, s) => Text('deck ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/ai/generate',
        builder: (_, s) => Text('generate ${s.uri.queryParameters['kind']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...deps.overrides,
        clockProvider.overrideWithValue(() => _now),
        dashboardStatsProvider.overrideWith((ref) => Stream.value(stats)),
        activityDaysProvider.overrideWith(
          (ref) => Stream.value(
            days ??
                {
                  _today,
                  _today.subtract(const Duration(days: 1)),
                  _today.subtract(const Duration(days: 2)),
                  _today.subtract(const Duration(days: 20)),
                },
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _text(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  return switch (widget) {
    final Text t => t.data ?? t.textSpan!.toPlainText(),
    _ => throw StateError('not a Text'),
  };
}

void main() {
  testWidgets('renders stats from the dashboard provider', (tester) async {
    await _pump(tester, stats: _stats());

    expect(find.textContaining('Ada'), findsOneWidget);
    expect(_text(tester, const Key('dashboard-streak-current')), '3  days');
    expect(_text(tester, const Key('dashboard-streak-best')), 'Best 9');
    expect(_text(tester, const Key('dashboard-due-count')), '3  cards');
    expect(find.text('2 to review · 1 new'), findsOneWidget);
    expect(find.text('Study now'), findsOneWidget);
    expect(find.text('4 open mistakes'), findsOneWidget);
    expect(_text(tester, const Key('dashboard-quizzes-taken')), '12  taken');
    expect(_text(tester, const Key('dashboard-accuracy')), '80%  accuracy');

    // Accuracy per subject.
    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    // Weakest topics + activity feed.
    expect(find.text('What does the mitochondria do?'), findsOneWidget);
    expect(find.text('Cells quiz · 1/4 correct'), findsOneWidget);
    expect(find.text('Cells quiz'), findsOneWidget); // feed
    expect(find.textContaining('Quiz · 8/10'), findsOneWidget);
    expect(find.textContaining('Reviewed 6 cards'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);

    // Activity strip: 7 days by default, 30 on toggle.
    expect(
      find.bySemanticsLabel('Studied on 3 of the last 7 days'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('dashboard-range-30')));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Studied on 4 of the last 30 days'),
      findsOneWidget,
    );
  });

  testWidgets('links: weakest question, study now, mistakes', (tester) async {
    final router = await _pump(tester, stats: _stats());

    await tester.tap(find.text('What does the mitochondria do?'));
    await tester.pumpAndSettle();
    expect(find.text('quiz q1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dashboard-mistakes')));
    await tester.pumpAndSettle();
    expect(find.text('mistakes screen'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dashboard-study-now')));
    await tester.pumpAndSettle();
    expect(find.text('study screen'), findsOneWidget);
  });

  testWidgets('phone: single column without overflow', (tester) async {
    await _pump(tester, stats: _stats(), size: const Size(390, 3000));
    expect(tester.takeException(), isNull);
    expect(find.text('Study now'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    // Today card above the streak card.
    final due = tester.getTopLeft(find.byKey(const Key('dashboard-due-count')));
    final streak = tester.getTopLeft(
      find.byKey(const Key('dashboard-streak-current')),
    );
    expect(due.dx, streak.dx);
    expect(due.dy, lessThan(streak.dy));
  });

  testWidgets('medium: two-column layout without overflow', (tester) async {
    await _pump(tester, stats: _stats(), size: const Size(760, 2400));
    expect(tester.takeException(), isNull);
    Rect card(String key) => tester.getRect(
      find
          .ancestor(of: find.byKey(Key(key)), matching: find.byType(AppCard))
          .first,
    );
    final streak = card('dashboard-streak-current');
    final quizzes = card('dashboard-quizzes-taken');
    final today = card('dashboard-due-count');
    // Today spans the row; streak and quizzes share the next row.
    expect(streak.top, quizzes.top);
    expect(streak.height, quizzes.height);
    expect(streak.left, lessThan(quizzes.left));
    expect(today.width, greaterThan(streak.width * 1.5));
  });

  testWidgets('new user: getting-started guide', (tester) async {
    final deps = TestDeps();
    await _pump(
      tester,
      stats: const DashboardStats(),
      deps: deps,
      days: const {},
    );
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Create a subject'), findsOneWidget);
    expect(find.byKey(const Key('guide-new-subject')), findsOneWidget);
    expect(find.text('Study now'), findsNothing);
    // AI not configured: the generate step is locked.
    await tester.tap(find.byKey(const Key('guide-generate')));
    await tester.pumpAndSettle();
    expect(find.text('Set up AI'), findsOneWidget);
  });

  testWidgets('guide marks finished steps', (tester) async {
    final deps = TestDeps()..configureAi();
    deps.subjects.seed(id: 's1');
    deps.notes.seed(subjectId: 's1');
    await _pump(
      tester,
      stats: const DashboardStats(),
      deps: deps,
      days: const {},
    );
    expect(find.byKey(const Key('guide-new-subject')), findsNothing);
    expect(find.byKey(const Key('guide-new-note')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Step 1, done')), findsOneWidget);

    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.text('generate quiz'), findsOneWidget);
  });

  test('activity feed merges notes and study activity', () {
    final s = _stats();
    final note = Note(
      id: 'n1',
      subjectId: 's1',
      ownerId: kUserId,
      title: 'Fresh',
      createdAt: _now.subtract(const Duration(minutes: 90)),
      updatedAt: _now,
    );
    final feed = buildActivityFeed(s.recentActivity, [note]);
    expect(feed.map((e) => e.at), [
      _now.subtract(const Duration(hours: 1)),
      _now.subtract(const Duration(minutes: 90)),
      _now.subtract(const Duration(hours: 3)),
    ]);
    expect(feed[1], isA<NoteFeedEntry>());
    expect(isFreshStart(const DashboardStats()), isTrue);
    expect(isFreshStart(s), isFalse);
  });
}
