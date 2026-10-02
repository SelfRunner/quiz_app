import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/local_attempt_repository.dart';
import 'package:quiz_app/data/repositories/local_deck_repository.dart';
import 'package:quiz_app/data/repositories/local_mistake_repository.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_quiz_repository.dart';
import 'package:quiz_app/data/repositories/local_review_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/repositories/mistake_repository.dart';
import 'package:quiz_app/data/repositories/study_activity_repository.dart';
import 'package:quiz_app/study/local_day.dart';
import 'package:quiz_app/study/study_settings.dart';

import 'support/fake_remote.dart';
import 'support/test_db.dart';

Flashcard card(String id) => Flashcard(id: id, front: 'F$id', back: 'B$id');

Question mcq(String id) => Question(
  id: id,
  type: QuestionType.mcqSingle,
  prompt: 'P$id',
  options: const ['a', 'b'],
  correctIndices: const [0],
);

void main() {
  final h = TestHive();
  late LocalSubjectRepository subjects;
  late LocalNoteRepository notes;
  late LocalQuizRepository quizzes;
  late LocalDeckRepository decks;
  late LocalReviewRepository reviews;
  late LocalMistakeRepository mistakes;
  late LocalAttemptRepository attempts;
  var settings = const StudySettings(fuzz: false);

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    h.clock
      ..frozen = false
      ..now = DateTime.utc(2026, 1, 1, 12);
    settings = const StudySettings(fuzz: false);
    final ctx = h.context();
    subjects = LocalSubjectRepository(ctx);
    notes = LocalNoteRepository(ctx);
    quizzes = LocalQuizRepository(ctx);
    decks = LocalDeckRepository(ctx);
    reviews = LocalReviewRepository(
      ctx,
      settings: () => settings,
      toLocal: fixedOffset(Duration.zero),
    );
    mistakes = LocalMistakeRepository(ctx);
    attempts = LocalAttemptRepository(ctx);
  });
  tearDown(h.tearDown);

  Future<Deck> foreignDeck({List<String> cards = const ['c1', 'c2']}) async {
    await h.db.subjects.put(Subject.fromJson(subjectRow('fs', 'user-b')));
    final d = Deck.fromJson(deckRow('fd', 'user-b', 'fs', cardIds: cards));
    await h.db.decks.put(d);
    return d;
  }

  group('DeckRepository', () {
    test('CRUD, ordering, watchByNote/Subject/AllAccessible', () async {
      final s = await subjects.create(title: 'Bio');
      final n = await notes.create(subjectId: s.id, title: 'Cells');
      final d1 = await decks.create(
        subjectId: s.id,
        title: ' Terms ',
        cards: [card('a'), card('b')],
      );
      final d2 = await decks.create(subjectId: s.id, noteId: n.id, title: 'N');
      expect(d1.title, 'Terms');
      expect(d1.ownerId, 'user-a');
      expect(h.db.outbox.pending().last.table, SyncTables.decks);
      expect(
        h.db.outbox.pending().last.payload!['cards'],
        isEmpty,
        reason: 'jsonb cards array',
      );

      expect((await decks.watchBySubject(s.id).first).map((d) => d.id), [
        d2.id,
        d1.id,
      ]);
      expect((await decks.watchByNote(n.id).first).single.id, d2.id);
      final other = await foreignDeck();
      expect(
        (await decks.watchAllAccessible().first).map((d) => d.id),
        containsAll([d1.id, d2.id, other.id]),
      );

      final updated = await decks.update(
        d1.copyWith(title: 'T2', cards: [card('a')]),
      );
      expect(updated.cards.single.id, 'a');
      expect(updated.updatedAt.isAfter(d1.updatedAt), isTrue);

      await decks.delete(d1.id);
      expect(await decks.getById(d1.id), isNull);
      expect(h.db.decks.get(d1.id)!.deletedAt, isNotNull);
    });

    test('shared decks are read-only; parents must be owned', () async {
      final shared = await foreignDeck();
      await expectLater(
        decks.update(shared.copyWith(title: 'x')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        decks.delete(shared.id),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        decks.create(subjectId: 'fs', title: 'x'),
        throwsA(isA<PermissionDeniedException>()),
      );
      final s = await subjects.create(title: 'A');
      final other = await subjects.create(title: 'B');
      final n = await notes.create(subjectId: other.id, title: 'n');
      await expectLater(
        decks.create(subjectId: s.id, noteId: n.id, title: 'x'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('card ids must be unique and non-empty', () async {
      final s = await subjects.create(title: 'A');
      await expectLater(
        decks.create(
          subjectId: s.id,
          title: 'x',
          cards: [card('a'), card('a')],
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        decks.create(subjectId: s.id, title: 'x', cards: [card('')]),
        throwsA(isA<ValidationException>()),
      );
    });

    test('cascades: subject/note delete soft-deletes decks; note move '
        'moves its decks', () async {
      final s = await subjects.create(title: 'A');
      final t = await subjects.create(title: 'B');
      final n = await notes.create(subjectId: s.id, title: 'n');
      final noteDeck = await decks.create(
        subjectId: s.id,
        noteId: n.id,
        title: 'nd',
      );
      final subjectDeck = await decks.create(subjectId: s.id, title: 'sd');

      await notes.update(n.copyWith(subjectId: t.id));
      expect(h.db.decks.get(noteDeck.id)!.subjectId, t.id);

      await notes.delete(n.id);
      expect(h.db.decks.get(noteDeck.id)!.isDeleted, isTrue);
      expect(h.db.decks.get(subjectDeck.id)!.isDeleted, isFalse);

      await subjects.delete(s.id);
      expect(h.db.decks.get(subjectDeck.id)!.isDeleted, isTrue);
      expect(
        h.db.outbox.pending().where(
          (op) =>
              op.table == SyncTables.decks && op.payload!['deleted_at'] != null,
        ),
        hasLength(2),
      );
    });
  });

  group('ReviewRepository', () {
    late Deck deck;

    setUp(() async {
      final s = await subjects.create(title: 'S');
      deck = await decks.create(
        subjectId: s.id,
        title: 'D',
        cards: [card('a'), card('b'), card('c')],
      );
      h.clock
        ..now = DateTime.utc(2026, 1, 1, 12)
        ..frozen = true;
    });

    test('recordReview schedules with FSRS under a deterministic id', () async {
      final r = await reviews.recordReview(
        deckId: deck.id,
        cardId: 'a',
        rating: Rating.good,
      );
      expect(
        r.id,
        CardReview.idFor(ownerId: 'user-a', deckId: deck.id, cardId: 'a'),
      );
      expect(r.state, CardState.learning);
      expect(r.dueAt, DateTime.utc(2026, 1, 1, 12, 10));
      expect(r.reps, 1);
      expect(r.stability, closeTo(3.173, 1e-9));
      final op = h.db.outbox.pending().last;
      expect(op.table, SyncTables.cardReviews);
      expect(op.payload!['state'], 1);
      expect(op.payload!['card_id'], 'a');

      h.clock.now = r.dueAt;
      final r2 = await reviews.recordReview(
        deckId: deck.id,
        cardId: 'a',
        rating: Rating.good,
      );
      expect(r2.id, r.id);
      expect(r2.state, CardState.review);
      expect(r2.scheduledDays, 4);
      expect(r2.createdAt, r.createdAt);
      expect(h.db.reviews.all(), hasLength(1));
    });

    test('works on shared decks; missing deck/card -> NotFound', () async {
      final shared = await foreignDeck();
      final r = await reviews.recordReview(
        deckId: shared.id,
        cardId: 'c1',
        rating: Rating.easy,
      );
      expect(r.ownerId, 'user-a');
      await expectLater(
        reviews.recordReview(
          deckId: shared.id,
          cardId: 'zz',
          rating: Rating.good,
        ),
        throwsA(isA<NotFoundException>()),
      );
      await expectLater(
        reviews.recordReview(deckId: 'nope', cardId: 'a', rating: Rating.good),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('previewDue labels every rating', () async {
      final p = await reviews.previewDue(deckId: deck.id, cardId: 'a');
      final now = DateTime.utc(2026, 1, 1, 12);
      expect(p[Rating.again], now.add(const Duration(minutes: 1)));
      expect(p[Rating.good], now.add(const Duration(minutes: 10)));
      expect(p[Rating.easy], now.add(const Duration(days: 16)));
    });

    test('due queue: due reviews, new cards (daily limit), later today; '
        're-emits on changes', () async {
      settings = const StudySettings(newCardsPerDay: 2, fuzz: false);
      final queue = reviews.watchDue();
      final q0 = await queue.first;
      expect(q0.newCards.map((c) => c.card.id), ['a', 'b']);
      expect(q0.unseenTotal, 3);
      expect(q0.count, 2);

      // Learning card: due later today.
      await reviews.recordReview(
        deckId: deck.id,
        cardId: 'a',
        rating: Rating.good,
      );
      final q1 = await reviews.watchDue().first;
      expect(q1.laterToday.single.card.id, 'a');
      expect(q1.newIntroducedToday, 1);
      expect(q1.newCards.map((c) => c.card.id), ['b']);

      // Ten minutes later it is due now; the next day's limit resets.
      h.clock.now = DateTime.utc(2026, 1, 1, 12, 10);
      final q2 = await reviews.watchDue().first;
      expect(q2.dueNow.single.card.id, 'a');
      expect(q2.next!.card.id, 'a');

      h.clock.now = DateTime.utc(2026, 1, 2, 9);
      final q3 = await reviews.watchDue().first;
      expect(q3.newIntroducedToday, 0);
      expect(q3.newCards.map((c) => c.card.id), ['b', 'c']);
      expect(await reviews.watchDueCount().first, 3);

      // Stream re-emits after a review.
      final emitted = <int>[];
      final sub = reviews.watchDueCount().listen(emitted.add);
      await eventually(() => emitted.isNotEmpty);
      await reviews.recordReview(
        deckId: deck.id,
        cardId: 'b',
        rating: Rating.easy,
      );
      await eventually(() => emitted.length >= 2);
      expect(emitted.last, 2);
      await sub.cancel();
    });

    test(
      'ignores reviews of removed cards and deleted decks; resetCard',
      () async {
        await reviews.recordReview(
          deckId: deck.id,
          cardId: 'a',
          rating: Rating.easy,
        );
        await reviews.recordReview(
          deckId: deck.id,
          cardId: 'b',
          rating: Rating.again,
        );
        h.clock.now = DateTime.utc(2026, 1, 20);
        await decks.update(deck.copyWith(cards: [card('b'), card('c')]));
        var q = await reviews.watchDue().first;
        expect(q.all.map((c) => c.card.id), ['b', 'c']);
        expect((await reviews.watchAll().first).length, 2);

        await reviews.resetCard(deckId: deck.id, cardId: 'b');
        q = await reviews.watchDue().first;
        expect(q.newCards.map((c) => c.card.id), ['b', 'c']);

        final stats = await reviews.watchDeckStats(deck.id).first;
        expect(stats.total, 2);
        expect(stats.newCount, 2);

        await decks.delete(deck.id);
        expect((await reviews.watchDue().first).isEmpty, isTrue);
        expect(await reviews.watchAll().first, isEmpty);
        expect(h.db.reviews.where((_) => true), hasLength(1), reason: 'kept');
      },
    );

    test('deck stats', () async {
      await reviews.recordReview(
        deckId: deck.id,
        cardId: 'a',
        rating: Rating.easy,
      );
      await reviews.recordReview(
        deckId: deck.id,
        cardId: 'b',
        rating: Rating.good,
      );
      final stats = await reviews.watchDeckStats(deck.id).first;
      expect(stats.total, 3);
      expect(stats.newCount, 1);
      expect(stats.learning, 1);
      expect(stats.review, 1);
      expect(stats.dueToday, 1, reason: 'b is due in 10 minutes');
    });

    test('signed out: empty streams, writes throw', () async {
      h.userId = null;
      expect((await reviews.watchDue().first).isEmpty, isTrue);
      await expectLater(
        reviews.recordReview(deckId: deck.id, cardId: 'a', rating: Rating.good),
        throwsA(isA<AppAuthException>()),
      );
    });
  });

  group('MistakeRepository', () {
    late Quiz quiz;

    setUp(() async {
      final s = await subjects.create(title: 'S');
      quiz = await quizzes.create(
        subjectId: s.id,
        title: 'Q',
        questions: [mcq('q1'), mcq('q2'), mcq('q3')],
      );
    });

    test('lifecycle: wrong -> open; 2 correct in a row -> resolved; wrong '
        'again reopens', () async {
      expect(
        await mistakes.recordAnswer(
          quizId: quiz.id,
          questionId: 'q1',
          correct: true,
        ),
        isNull,
        reason: 'correct without a mistake writes nothing',
      );
      expect(h.db.mistakes.all(), isEmpty);

      var m = await mistakes.recordAnswer(
        quizId: quiz.id,
        questionId: 'q1',
        correct: false,
      );
      expect(
        m!.id,
        Mistake.idFor(ownerId: 'user-a', quizId: quiz.id, questionId: 'q1'),
      );
      expect(m.wrongCount, 1);
      expect(m.isOpen, isTrue);
      expect(m.lastWrongAt, isNotNull);

      m = await mistakes.recordAnswer(
        quizId: quiz.id,
        questionId: 'q1',
        correct: true,
      );
      expect(m!.correctStreak, 1);
      expect(m.isOpen, isTrue);
      m = await mistakes.recordAnswer(
        quizId: quiz.id,
        questionId: 'q1',
        correct: false,
      );
      expect(m!.wrongCount, 2);
      expect(m.correctStreak, 0);
      m = await mistakes.recordAnswer(
        quizId: quiz.id,
        questionId: 'q1',
        correct: true,
      );
      m = await mistakes.recordAnswer(
        quizId: quiz.id,
        questionId: 'q1',
        correct: true,
      );
      expect(m!.resolvedAt, isNotNull);
      expect(m.isOpen, isFalse);
      // Correct while resolved: no write.
      final pending = h.db.outbox.length;
      await mistakes.recordAnswer(
        quizId: quiz.id,
        questionId: 'q1',
        correct: true,
      );
      expect(h.db.outbox.length, pending);

      m = await mistakes.recordAnswer(
        quizId: quiz.id,
        questionId: 'q1',
        correct: false,
      );
      expect(m!.resolvedAt, isNull);
      expect(m.wrongCount, 3);
      expect(h.db.mistakes.all(), hasLength(1));
      expect(
        h.db.outbox.pending().where((op) => op.table == SyncTables.mistakes),
        hasLength(1),
        reason: 'upserts of one row coalesce',
      );
    });

    test(
      'recordAttempt + watchOpen groups by quiz in question order',
      () async {
        final s2 = await subjects.create(title: 'T');
        final quiz2 = await quizzes.create(
          subjectId: s2.id,
          title: 'Q2',
          questions: [mcq('x')],
        );
        final attempt = QuizAttempt(
          id: 'att',
          quizId: quiz.id,
          ownerId: 'user-a',
          answers: const [
            QuestionAnswer(questionId: 'q3', isCorrect: false),
            QuestionAnswer(questionId: 'q1', isCorrect: false),
            QuestionAnswer(questionId: 'q2', isCorrect: true),
            QuestionAnswer(questionId: 'qx'),
          ],
          startedAt: DateTime.utc(2026),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        await mistakes.recordAttempt(attempt);
        await mistakes.recordAnswer(
          quizId: quiz2.id,
          questionId: 'x',
          correct: false,
        );

        final groups = await mistakes.watchOpen().first;
        expect(groups.map((g) => g.quiz.id), [quiz2.id, quiz.id]);
        expect(groups.last.questions.map((q) => q.id), ['q1', 'q3']);
        expect(await mistakes.watchOpenCount().first, 3);

        // Removed questions and deleted quizzes are hidden (rows kept).
        await quizzes.update(quiz.copyWith(questions: [mcq('q1')]));
        await quizzes.delete(quiz2.id);
        final after = await mistakes.watchOpen().first;
        expect(after.single.entries.single.question.id, 'q1');
        expect(h.db.mistakes.all(), hasLength(3));

        await mistakes.resolve(quizId: quiz.id, questionId: 'q1');
        expect(await mistakes.watchOpen().first, isEmpty);
      },
    );

    test('mistakes on a shared quiz are the user\'s own', () async {
      await h.db.subjects.put(Subject.fromJson(subjectRow('fs', 'user-b')));
      final shared = Quiz.fromJson(quizRow('fq', 'user-b', 'fs'))
          .copyWith(questions: [mcq('q1')]);
      await h.db.quizzes.put(shared);
      final m = await mistakes.recordAnswer(
        quizId: 'fq',
        questionId: 'q1',
        correct: false,
      );
      expect(m!.ownerId, 'user-a');
      expect(
        (await mistakes.watchOpen().first).single,
        isA<MistakeGroup>().having((g) => g.quiz.id, 'quiz', 'fq'),
      );
      await expectLater(
        mistakes.recordAnswer(quizId: 'gone', questionId: 'q1', correct: false),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('AttemptRepository (exam fields)', () {
    test('start stores mode, time limit and question pool', () async {
      final a = await attempts.start(
        quizId: 'q',
        total: 2,
        mode: AttemptMode.exam,
        timeLimitSeconds: 600,
        questionIds: ['q2', 'q1'],
      );
      expect(a.mode, AttemptMode.exam);
      final payload = h.db.outbox.pending().single.payload!;
      expect(payload['mode'], 'exam');
      expect(payload['time_limit_seconds'], 600);
      expect(payload['question_ids'], ['q2', 'q1']);
      expect(payload['duration_seconds'], isNull);
      final saved = await attempts.save(a.copyWith(durationSeconds: 42));
      expect(h.db.attempts.get(saved.id)!.durationSeconds, 42);
      await expectLater(
        attempts.start(quizId: 'q', total: 1, timeLimitSeconds: 0),
        throwsA(isA<ValidationException>()),
      );
      final plain = await attempts.start(quizId: 'q', total: 1);
      expect(plain.mode, AttemptMode.practice);
    });
  });

  test('StudyActivityRepository snapshot: own rows + live content', () async {
    final s = await subjects.create(title: 'S');
    final q = await quizzes.create(subjectId: s.id, title: 'Q');
    await attempts.start(quizId: q.id, total: 0);
    await h.db.attempts.put(
      QuizAttempt(
        id: 'other',
        quizId: q.id,
        ownerId: 'user-b',
        startedAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    final snap = await LocalStudyActivityRepository(h.context())
        .watchSnapshot()
        .first;
    expect(snap.subjects.single.id, s.id);
    expect(snap.quizzes.single.id, q.id);
    expect(snap.attempts.single.ownerId, 'user-a');
  });
}
