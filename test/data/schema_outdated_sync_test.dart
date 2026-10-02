import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/remote/remote_data_source.dart';
import 'package:quiz_app/data/remote/supabase_remote_data_source.dart';
import 'package:quiz_app/data/repositories/local_attempt_repository.dart';
import 'package:quiz_app/data/repositories/local_deck_repository.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_quiz_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/sync/default_sync_engine.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'support/fake_remote.dart';
import 'support/test_db.dart';

/// The live project's database is one migration behind the app.
void main() {
  final h = TestHive();
  late FakeRemote remote;
  late LocalSubjectRepository subjects;
  late LocalNoteRepository notes;
  late LocalQuizRepository quizzes;
  late LocalAttemptRepository attempts;
  late LocalDeckRepository decks;
  final engines = <DefaultSyncEngine>[];

  DefaultSyncEngine makeEngine() {
    final e = DefaultSyncEngine(
      db: h.db,
      remote: remote,
      imageRemote: remote,
      currentUserId: () => h.userId,
      connectivity: FakeConnectivity(),
      clock: h.clockFn,
      maxAttempts: 3,
    );
    engines.add(e);
    return e;
  }

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    remote = FakeRemote(userId: 'user-a');
    final ctx = h.context();
    subjects = LocalSubjectRepository(ctx);
    notes = LocalNoteRepository(ctx);
    quizzes = LocalQuizRepository(ctx);
    attempts = LocalAttemptRepository(ctx);
    decks = LocalDeckRepository(ctx);
  });

  tearDown(() async {
    for (final e in engines) {
      await e.dispose();
    }
    engines.clear();
    await h.tearDown();
  });

  group('error classification', () {
    test('schema-cache errors are schemaOutdated, never permanent', () {
      for (final code in [
        'PGRST200',
        'PGRST202',
        'PGRST204',
        'PGRST205',
        '42703',
        '42P01',
        '42883',
      ]) {
        expect(
          classifyErrorCode(code),
          RemoteErrorKind.schemaOutdated,
          reason: code,
        );
      }
      expect(classifyErrorCode('23514'), RemoteErrorKind.permanent);
      expect(classifyErrorCode('42501'), RemoteErrorKind.permanent);
      expect(classifyErrorCode('400'), RemoteErrorKind.permanent);
    });

    test('PostgrestException mapping (parsed and raw bodies)', () {
      final parsed = mapRemoteError(
        const sb.PostgrestException(
          message:
              "Could not find the 'duration_seconds' column of "
              "'quiz_attempts' in the schema cache",
          code: 'PGRST204',
        ),
      );
      expect(parsed.kind, RemoteErrorKind.schemaOutdated);
      expect(parsed.code, 'PGRST204');
      // Body not parsed (e.g. proxy): code is the bare HTTP status.
      final raw = mapRemoteError(
        const sb.PostgrestException(
          message:
              '{"code":"PGRST205","message":"Could not find the table '
              '\'public.decks\' in the schema cache"}',
          code: '404',
        ),
      );
      expect(raw.kind, RemoteErrorKind.schemaOutdated);
      final bucket = mapRemoteError(
        const sb.StorageException('Bucket not found', statusCode: '400'),
      );
      expect(bucket.kind, RemoteErrorKind.schemaOutdated);
    });
  });

  test('PGRST204 (missing column): the quiz attempt is kept, other tables '
      'still sync, status says server outdated; recovers after the '
      'migration', () async {
    remote.missingColumns['quiz_attempts'] = {'duration_seconds'};
    final s = await subjects.create(title: 'Bio');
    final q = await quizzes.create(subjectId: s.id, title: 'Cells');
    final started = await attempts.start(quizId: q.id, total: 3);
    final finished = await attempts.save(
      started.copyWith(score: 2, completedAt: h.clock.now, durationSeconds: 42),
    );
    final second = await attempts.start(quizId: q.id, total: 3);
    // Queued after the attempts: must not be blocked by them.
    final n = await notes.create(subjectId: s.id, title: 'After');
    final engine = makeEngine();

    // More cycles than maxAttempts: still never dropped nor "stuck".
    for (var i = 0; i < 5; i++) {
      await engine.sync();
    }

    expect(remote.tables['subjects']!.keys, [s.id]);
    expect(remote.tables['quizzes']!.keys, [q.id]);
    expect(remote.tables['notes']!.keys, [n.id]);
    expect(remote.tables['quiz_attempts'], isEmpty);
    final pending = h.db.outbox.pending();
    expect(pending.map((op) => op.rowId).toSet(), {finished.id, second.id});
    expect(pending.every((op) => op.attempts == 0), isTrue);
    expect(pending.first.lastError, contains('duration_seconds'));
    // One failing request per cycle; the table's other ops wait.
    expect(remote.schemaErrors, List.filled(5, 'upsert:quiz_attempts'));
    expect(h.db.attempts.get(finished.id)!.durationSeconds, 42);

    final status = engine.currentStatus;
    expect(status.state, SyncState.error);
    expect(status.serverOutdated, isTrue);
    expect(status.unavailableTables, ['quiz_attempts']);
    expect(status.error, contains(serverOutdatedMessage));
    expect(status.pendingOps, 2);
    expect(status.stuckOps, 0);
    expect(status.rejectedChanges, 0);
    expect(engine.rejectedChanges, isEmpty);

    // The migration is applied.
    remote.missingColumns.clear();
    await engine.sync();

    expect(h.db.outbox.length, 0);
    expect(remote.tables['quiz_attempts']!.keys.toSet(), {
      finished.id,
      second.id,
    });
    expect(
      remote.tables['quiz_attempts']![finished.id]!['duration_seconds'],
      42,
    );
    final after = engine.currentStatus;
    expect(after.state, SyncState.idle);
    expect(after.serverOutdated, isFalse);
    expect(after.unavailableTables, isEmpty);
    expect(after.error, isNull);
  });

  test(
    'PGRST205 (missing table): other tables are pulled and pushed, the '
    'table is retried each sync and catches up after the migration',
    () async {
      remote.missingTables.addAll({'decks', 'card_reviews'});
      remote.serverWrite('subjects', subjectRow('s1', 'user-a', title: 'Srv'));
      remote.serverWrite('notes', noteRow('n1', 'user-a', 's1'));
      final s = await subjects.create(title: 'Local');
      final d = await decks.create(
        subjectId: s.id,
        title: 'Deck',
        cards: const [Flashcard(id: 'c1', front: 'F', back: 'B')],
      );
      final engine = makeEngine();

      await engine.sync();

      // Other tables synced in both directions.
      expect(h.db.subjects.get('s1')!.title, 'Srv');
      expect(h.db.notes.get('n1'), isNotNull);
      expect(remote.tables['subjects']!.keys, contains(s.id));
      expect(h.db.meta.cursor('subjects'), isNotNull);
      expect(h.db.meta.cursor('decks'), isNull);
      // The deck is kept locally and queued.
      expect(h.db.decks.get(d.id), isNotNull);
      expect(h.db.outbox.pendingFor('decks', d.id)!.attempts, 0);
      final status = engine.currentStatus;
      expect(status.state, SyncState.error);
      expect(status.serverOutdated, isTrue);
      expect(status.unavailableTables, ['card_reviews', 'decks']);
      expect(status.error, startsWith(serverOutdatedMessage));
      expect(status.rejectedChanges, 0);
      // Reconciliation could not check decks: retried next sync.
      expect(h.db.meta.lastReconciledAt, isNull);

      // Still outdated: retried (pull attempted again), nothing lost.
      remote.schemaErrors.clear();
      await engine.sync();
      expect(remote.schemaErrors, containsAll(['pull:decks', 'upsert:decks']));
      expect(h.db.outbox.length, 1);

      // Migration applied; another device already created a deck.
      remote.missingTables.clear();
      remote.serverWrite('decks', deckRow('d-srv', 'user-a', 's1'));
      await engine.sync();

      expect(h.db.outbox.length, 0);
      expect(remote.tables['decks']!.keys.toSet(), {d.id, 'd-srv'});
      expect(h.db.decks.get('d-srv'), isNotNull);
      expect(h.db.meta.cursor('decks'), isNotNull);
      expect(h.db.meta.lastReconciledAt, isNotNull);
      final after = engine.currentStatus;
      expect(after.state, SyncState.idle);
      expect(after.serverOutdated, isFalse);
      expect(after.unavailableTables, isEmpty);
    },
  );

  test('a new share whose backfill hits a missing table is backfilled again '
      'after the migration', () async {
    remote.missingTables.add('decks');
    final engine = makeEngine();
    await engine.sync(); // initial pull, share list recorded (empty)

    remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
    remote.serverWrite('notes', noteRow('bn', 'user-b', 'bs'));
    remote.serverWrite('decks', deckRow('bd', 'user-b', 'bs'));
    remote.shares.add({
      'id': 'sh',
      'owner_id': 'user-b',
      'recipient_id': 'user-a',
      'resource_type': 'subject',
      'resource_id': 'bs',
    });
    await engine.sync();
    expect(h.db.subjects.get('bs'), isNotNull);
    expect(h.db.notes.get('bn'), isNotNull);
    expect(h.db.decks.get('bd'), isNull);
    expect(engine.currentStatus.serverOutdated, isTrue);
    // Not remembered as seen: the backfill runs again next time.
    expect(h.db.meta.incomingShareKeys, isEmpty);

    remote.missingTables.clear();
    await engine.sync();
    expect(h.db.decks.get('bd'), isNotNull);
    expect(h.db.meta.incomingShareKeys, {'subject:bs'});
    expect(engine.currentStatus.state, SyncState.idle);
  });

  test('every dropped op is recorded in rejectedChanges and counted, '
      'including file ops', () async {
    const path = 'user-a/n1/img.png';
    await h.db.images.write(path, Uint8List.fromList([1, 2, 3]));
    await h.db.outbox.enqueue(
      table: SyncTables.noteImagesBucket,
      op: OutboxOpType.uploadImage,
      rowId: path,
      payload: {'content_type': 'image/png'},
    );
    remote.uploadHook = (bucket, p) => const RemoteException(
      RemoteErrorKind.permanent,
      'Unauthorized',
      code: '403',
    );
    final engine = makeEngine();
    final rejections = <SyncRejection>[];
    engine.rejections.listen(rejections.add);

    await engine.sync();

    expect(h.db.outbox.length, 0);
    final kept = engine.rejectedChanges.single;
    expect(kept.op, 'upload_image');
    expect(kept.table, SyncTables.noteImagesBucket);
    expect(kept.rowId, path);
    expect(kept.payload, {'content_type': 'image/png'});
    expect(engine.currentStatus.rejectedChanges, 1);
    expect(engine.currentStatus.state, SyncState.error);
    expect(engine.currentStatus.serverOutdated, isFalse);
    expect(rejections, hasLength(1));
  });
}
