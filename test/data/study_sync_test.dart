import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/local/local_database.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/local_deck_repository.dart';
import 'package:quiz_app/data/repositories/local_mistake_repository.dart';
import 'package:quiz_app/data/repositories/local_quiz_repository.dart';
import 'package:quiz_app/data/repositories/local_review_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/repositories/repository_support.dart';
import 'package:quiz_app/data/repositories/supabase_share_repository.dart';
import 'package:quiz_app/data/sync/default_sync_engine.dart';
import 'package:quiz_app/data/sync/note_image_copy_processor.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';
import 'package:quiz_app/study/study_settings.dart';

import 'support/fake_remote.dart';
import 'support/test_db.dart';

void main() {
  final h = TestHive();
  late FakeRemote remote;
  late FakeConnectivity connectivity;
  final engines = <DefaultSyncEngine>[];

  DefaultSyncEngine makeEngine([LocalDatabase? db]) {
    final e = DefaultSyncEngine(
      db: db ?? h.db,
      remote: remote,
      imageRemote: remote,
      currentUserId: () => h.userId,
      connectivity: connectivity,
      clock: h.clockFn,
    );
    engines.add(e);
    return e;
  }

  DataContext ctxFor(LocalDatabase db) => DataContext(
    db: db,
    clock: h.clockFn,
    newId: h.ids.call,
    currentUserId: () => h.userId,
  );

  LocalReviewRepository reviewsFor(LocalDatabase db) => LocalReviewRepository(
    ctxFor(db),
    settings: () => const StudySettings(fuzz: false),
  );

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    remote = FakeRemote(userId: 'user-a');
    connectivity = FakeConnectivity();
  });

  tearDown(() async {
    for (final e in engines) {
      await e.dispose();
    }
    engines.clear();
    await h.tearDown();
  });

  test('uuid v5 ids match the contract (RFC 4122, URL namespace)', () {
    // Python: uuid.uuid5(uuid.NAMESPACE_URL, 'quizapp:card_review:...')
    expect(
      CardReview.idFor(ownerId: 'user-a', deckId: 'deck-1', cardId: 'card-1'),
      '91df680c-e1fa-567a-9a55-0ce1d49aee9a',
    );
    expect(
      Mistake.idFor(ownerId: 'user-a', quizId: 'quiz-1', questionId: 'q1'),
      'ca967adc-ceb9-55dc-a1f5-782714f25ff9',
    );
    expect(
      CardReview.idFor(ownerId: 'user-b', deckId: 'deck-1', cardId: 'card-1'),
      isNot(
        CardReview.idFor(ownerId: 'user-a', deckId: 'deck-1', cardId: 'card-1'),
      ),
    );
  });

  test('pushes and pulls decks, card reviews and mistakes', () async {
    final ctx = h.context();
    final s = await LocalSubjectRepository(ctx).create(title: 'S');
    final q = await LocalQuizRepository(ctx).create(
      subjectId: s.id,
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
    final d = await LocalDeckRepository(ctx).create(
      subjectId: s.id,
      title: 'D',
      cards: const [Flashcard(id: 'c1', front: 'f', back: 'b', hint: 'h')],
    );
    final r = await reviewsFor(h.db)
        .recordReview(deckId: d.id, cardId: 'c1', rating: Rating.good);
    final m = await LocalMistakeRepository(ctx)
        .recordAnswer(quizId: q.id, questionId: 'q1', correct: false);

    final engine = makeEngine();
    await engine.sync();
    expect(engine.currentStatus.state, SyncState.idle);
    expect(h.db.outbox.length, 0);
    expect(remote.tables['decks']![d.id]!['cards'], [
      {'id': 'c1', 'front': 'f', 'back': 'b', 'hint': 'h'},
    ]);
    expect(remote.tables['card_reviews']![r.id]!['state'], 1);
    expect(remote.tables['mistakes']![m!.id]!['wrong_count'], 1);
    for (final t in ['decks', 'card_reviews', 'mistakes']) {
      expect(h.db.meta.cursor(t), isNotNull, reason: t);
    }

    // Another device updates the review; the pull applies it (LWW).
    remote.serverWrite('card_reviews', {
      ...remote.tables['card_reviews']![r.id]!,
      'reps': 7,
    });
    await engine.sync();
    expect(h.db.reviews.get(r.id)!.reps, 7);
  });

  test('two devices reviewing the same card offline converge on one row '
      '(deterministic id, last write wins)', () async {
    remote.serverWrite('subjects', subjectRow('s', 'user-a'));
    remote.serverWrite('decks', deckRow('d', 'user-a', 's'));
    final dbB = await h.openDb(suffix: '_b');
    final engineA = makeEngine();
    final engineB = makeEngine(dbB);
    await engineA.sync();
    await engineB.sync();

    // Both offline: each reviews card c1.
    final a = await reviewsFor(h.db)
        .recordReview(deckId: 'd', cardId: 'c1', rating: Rating.again);
    final b = await reviewsFor(dbB)
        .recordReview(deckId: 'd', cardId: 'c1', rating: Rating.easy);
    expect(a.id, b.id);

    await engineA.sync();
    await engineB.sync(); // same id: an update, not a 23505
    await engineA.sync();
    expect(engineB.currentStatus.error, isNull);
    expect(remote.tables['card_reviews']!.keys, [a.id]);
    expect(remote.tables['card_reviews']![a.id]!['state'], 2, reason: 'B won');
    expect(h.db.reviews.get(a.id)!.state, CardState.review);
    expect(dbB.reviews.get(a.id)!.state, CardState.review);
    expect(h.db.reviews.all(), hasLength(1));
  });

  test('23505 on a review: adopts the existing row id and re-applies the '
      'local change', () async {
    remote.serverWrite('subjects', subjectRow('s', 'user-a'));
    remote.serverWrite('decks', deckRow('d', 'user-a', 's'));
    // A row for (user-a, d, c1) created by a client without derived ids.
    remote.serverWrite(
      'card_reviews',
      reviewRow('legacy-id', 'user-a', 'd', 'c1', reps: 3),
    );
    final engine = makeEngine();
    // Only pull decks (simulate the legacy row not being pulled yet).
    await h.db.decks.put(Deck.fromJson(deckRow('d', 'user-a', 's')));
    await h.db.subjects.put(Subject.fromJson(subjectRow('s', 'user-a')));
    final local = await reviewsFor(h.db)
        .recordReview(deckId: 'd', cardId: 'c1', rating: Rating.easy);
    expect(local.id, isNot('legacy-id'));

    await engine.sync();
    expect(engine.currentStatus.error, isNull);
    expect(engine.rejectedChanges, isEmpty);
    expect(remote.tables['card_reviews']!.keys, ['legacy-id']);
    final server = remote.tables['card_reviews']!['legacy-id']!;
    expect(server['reps'], 1, reason: 'the local review was re-applied');
    expect(
      DateTime.parse(server['created_at'] as String),
      DateTime.utc(2026, 1, 2),
    );
    expect(h.db.reviews.get(local.id), isNull);
    expect(h.db.reviews.get('legacy-id')!.state, CardState.review);

    // Later reviews of that card keep using the adopted row.
    final next = await reviewsFor(h.db)
        .recordReview(deckId: 'd', cardId: 'c1', rating: Rating.good);
    expect(next.id, 'legacy-id');
  });

  test(
    '42501 on a review of a deck no longer readable: dropped quietly',
    () async {
      remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
      remote.serverWrite('decks', deckRow('bd', 'user-b', 'bs'));
      remote.shares.add({
        'id': 'sh',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'deck',
        'resource_id': 'bd',
      });
      final engine = makeEngine();
      await engine.sync();
      expect(h.db.decks.get('bd'), isNotNull);

      final r = await reviewsFor(h.db)
          .recordReview(deckId: 'bd', cardId: 'c1', rating: Rating.good);
      remote.shares.clear(); // revoked before the review was pushed
      await engine.sync();
      expect(h.db.outbox.length, 0);
      expect(engine.currentStatus.state, SyncState.idle);
      expect(engine.rejectedChanges, isEmpty);
      expect(remote.tables['card_reviews'], isEmpty);
      expect(h.db.decks.get('bd'), isNull, reason: 'reconciled');
      expect(await reviewsFor(h.db).watchAll().first, isEmpty);
      // Never saved on the server and its deck is gone: purged locally too.
      expect(h.db.reviews.get(r.id), isNull);
    },
  );

  group('shared decks', () {
    test('a new deck share backfills the deck; revoking purges it', () async {
      remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
      remote.serverWrite('decks', deckRow('bd', 'user-b', 'bs'));
      final engine = makeEngine();
      await engine.sync();
      expect(h.db.decks.get('bd'), isNull);

      remote.shares.add({
        'id': 'sh',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'deck',
        'resource_id': 'bd',
      });
      remote.pullAfters.clear();
      await engine.sync();
      expect(h.db.decks.get('bd')!.cards.map((c) => c.id), ['c1', 'c2']);

      remote.shares.clear();
      await engine.sync();
      expect(h.db.decks.get('bd'), isNull);
    });

    test('subject and note shares backfill their decks', () async {
      remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
      remote.serverWrite('subjects', subjectRow('bs2', 'user-b'));
      remote.serverWrite('notes', noteRow('bn', 'user-b', 'bs2'));
      remote.serverWrite('decks', deckRow('d-subject', 'user-b', 'bs'));
      remote.serverWrite(
        'decks',
        deckRow('d-note', 'user-b', 'bs2', noteId: 'bn'),
      );
      remote.serverWrite('decks', deckRow('d-other', 'user-b', 'bs2'));
      final engine = makeEngine();
      await engine.sync();
      remote.shares
        ..add({
          'id': 'sh1',
          'owner_id': 'user-b',
          'recipient_id': 'user-a',
          'resource_type': 'subject',
          'resource_id': 'bs',
        })
        ..add({
          'id': 'sh2',
          'owner_id': 'user-b',
          'recipient_id': 'user-a',
          'resource_type': 'note',
          'resource_id': 'bn',
        });
      await engine.sync();
      expect(h.db.decks.all().map((d) => d.id).toSet(), {
        'd-subject',
        'd-note',
      });
    });

    test('tombstones: other users\' are purged, own are kept hidden', () async {
      remote.serverWrite('subjects', subjectRow('s', 'user-a'));
      remote.serverWrite('decks', deckRow('mine', 'user-a', 's'));
      remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
      remote.serverWrite('decks', deckRow('theirs', 'user-b', 'bs'));
      remote.shares.add({
        'id': 'sh',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'subject',
        'resource_id': 'bs',
      });
      final engine = makeEngine();
      await engine.sync();
      expect(h.db.decks.all(), hasLength(2));

      remote.serverWrite(
        'decks',
        deckRow('mine', 'user-a', 's', deletedAt: '2026-02-01T00:00:00Z'),
      );
      remote.serverWrite(
        'decks',
        deckRow('theirs', 'user-b', 'bs', deletedAt: '2026-02-01T00:00:00Z'),
      );
      await engine.sync();
      expect(h.db.decks.get('mine')!.isDeleted, isTrue);
      expect(h.db.decks.get('theirs'), isNull);
    });
  });

  test('reconciliation purges reviews/mistakes whose parent was '
      'hard-deleted, keeps those of revoked parents', () async {
    remote.serverWrite('subjects', subjectRow('s', 'user-a'));
    remote.serverWrite('decks', deckRow('gone', 'user-a', 's'));
    remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
    remote.serverWrite('decks', deckRow('revoked', 'user-b', 'bs'));
    remote.serverWrite('quizzes', quizRow('gq', 'user-a', 's'));
    remote.serverWrite(
      'card_reviews',
      reviewRow('r-gone', 'user-a', 'gone', 'c1'),
    );
    remote.serverWrite(
      'card_reviews',
      reviewRow('r-revoked', 'user-a', 'revoked', 'c1'),
    );
    remote.serverWrite('mistakes', {
      'id': 'm-gone',
      'owner_id': 'user-a',
      'quiz_id': 'gq',
      'question_id': 'q1',
      'wrong_count': 1,
      'correct_streak': 0,
      'last_wrong_at': null,
      'resolved_at': null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'deleted_at': null,
    });
    final engine = makeEngine();
    await engine.sync();
    expect(h.db.reviews.all(), hasLength(2));
    expect(h.db.mistakes.all(), hasLength(1));

    // Hard deletes cascade on the server without tombstones.
    remote.tables['decks']!.remove('gone');
    remote.tables['card_reviews']!.remove('r-gone');
    remote.tables['quizzes']!.remove('gq');
    remote.tables['mistakes']!.remove('m-gone');
    await h.db.decks.remove('gone');
    await h.db.quizzes.remove('gq');
    await engine.reconcileForeignRows(userId: 'user-a');
    expect(h.db.reviews.get('r-gone'), isNull);
    expect(h.db.mistakes.get('m-gone'), isNull);
    expect(h.db.reviews.get('r-revoked'), isNotNull);
  });

  test(
    'copyToMyAccount copies a shared deck into an owned subject/note',
    () async {
      remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
      remote.serverWrite('decks', deckRow('bd', 'user-b', 'bs'));
      remote.shares.add({
        'id': 'sh',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'deck',
        'resource_id': 'bd',
        'created_at': '2026-01-01T00:00:00Z',
      });
      final engine = makeEngine();
      final ctx = h.context();
      final mine = await LocalSubjectRepository(ctx).create(title: 'Mine');
      await engine.sync();
      final shares = SupabaseShareRepository(
        ctx: ctx,
        remote: remote,
        imageCopies: NoteImageCopyProcessor(remote, h.db.images),
        connectivity: connectivity,
        sync: engine.syncFresh,
      );
      final id = await shares.copyToMyAccount(
        resourceType: ShareResourceType.deck,
        resourceId: 'bd',
        targetSubjectId: mine.id,
      );
      expect(remote.rpcCalls, ['copy_deck']);
      final copy = h.db.decks.get(id)!;
      expect(copy.ownerId, 'user-a');
      expect(copy.subjectId, mine.id);
      expect(copy.cards.map((c) => c.id), ['c1', 'c2'], reason: 'ids kept');

      final shared = await shares.sharedWithMe();
      expect(shared.single.resourceType, ShareResourceType.deck);
      expect(shared.single.resourceTitle, 'D');
    },
  );

  test('sharedWithMe ignores share rows of unknown resource types', () async {
    remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
    remote.shares
      ..add({
        'id': 'sh1',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'subject',
        'resource_id': 'bs',
        'created_at': '2026-01-01T00:00:00Z',
      })
      ..add({
        'id': 'sh2',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'mind_map', // from a future version
        'resource_id': 'x',
        'created_at': '2026-01-01T00:00:00Z',
      });
    final shares = SupabaseShareRepository(
      ctx: h.context(),
      remote: remote,
      imageCopies: NoteImageCopyProcessor(remote, h.db.images),
      connectivity: connectivity,
      sync: () async {},
    );
    final list = await shares.sharedWithMe();
    expect(list.single.resourceId, 'bs');
  });
}
