import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/providers.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/auth_repository.dart';
import 'package:quiz_app/data/sync/connectivity_monitor.dart';
import 'package:quiz_app/study/study_providers.dart';
import 'package:quiz_app/study/study_settings.dart';

import '../data/support/fake_remote.dart';
import '../data/support/test_db.dart';

class _Auth implements AuthRepository {
  @override
  AppUser? get currentUser => const AppUser(id: 'user-a');

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<void> resetPassword(String email) async {}

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();
}

/// Waits for the first data value of [provider].
Future<T> firstData<T>(
  ProviderContainer c,
  ProviderListenable<AsyncValue<T>> provider, {
  bool Function(T value)? where,
}) {
  final done = Completer<T>();
  final sub = c.listen<AsyncValue<T>>(provider, (_, next) {
    final value = next.value;
    if (next.hasValue &&
        !done.isCompleted &&
        (where?.call(value as T) ?? true)) {
      done.complete(value as T);
    }
  }, fireImmediately: true);
  return done.future
      .whenComplete(sub.close)
      .timeout(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final h = TestHive();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test(
    'study providers wire decks, reviews, mistakes and the dashboard',
    () async {
      final remote = FakeRemote(userId: 'user-a');
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth()),
          localDatabaseProvider.overrideWithValue(h.db),
          syncRemoteDataSourceProvider.overrideWithValue(remote),
          imageRemoteDataSourceProvider.overrideWithValue(remote),
          shareRemoteDataSourceProvider.overrideWithValue(remote),
          connectivityMonitorProvider.overrideWithValue(
            const AlwaysOnlineMonitor(),
          ),
          clockProvider.overrideWithValue(h.clockFn),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(studySettingsProvider.notifier)
          .set(const StudySettings(newCardsPerDay: 1, fuzz: false));
      expect(container.read(studySettingsProvider).newCardsPerDay, 1);

      final subject = await container
          .read(subjectRepositoryProvider)
          .create(title: 'S');
      final deck = await container
          .read(deckRepositoryProvider)
          .create(
            subjectId: subject.id,
            title: 'D',
            cards: const [
              Flashcard(id: 'a', front: 'f', back: 'b'),
              Flashcard(id: 'b', front: 'f', back: 'b'),
            ],
          );
      expect(
        (await firstData(
          container,
          decksBySubjectProvider(subject.id),
        )).single.id,
        deck.id,
      );
      expect(await firstData(container, dueCountProvider), 1);

      await container
          .read(reviewRepositoryProvider)
          .recordReview(deckId: deck.id, cardId: 'a', rating: Rating.easy);
      final stats = await firstData(
        container,
        deckStatsProvider(deck.id),
        where: (s) => s.review == 1,
      );
      expect(stats.newCount, 1);

      final quiz = await container
          .read(quizRepositoryProvider)
          .create(
            subjectId: subject.id,
            title: 'Q',
            questions: const [
              Question(
                id: 'q1',
                type: QuestionType.trueFalse,
                prompt: 'p',
                options: ['True', 'False'],
                correctIndices: [0],
              ),
            ],
          );
      await container
          .read(mistakeRepositoryProvider)
          .recordAnswer(quizId: quiz.id, questionId: 'q1', correct: false);
      expect(await firstData(container, openMistakeCountProvider), 1);

      final dashboard = await firstData(
        container,
        dashboardStatsProvider,
        where: (d) => d.openMistakes == 1,
      );
      expect(dashboard.reviewsToday, 1);
      expect(dashboard.streak.current, greaterThanOrEqualTo(1));
      expect(dashboard.due.newIntroducedToday, 1);
      expect(dashboard.dueCards, 0, reason: 'daily new-card limit reached');
    },
  );
}
