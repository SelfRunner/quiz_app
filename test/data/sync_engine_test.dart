import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/local/sync_meta_store.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/remote/remote_data_source.dart';
import 'package:quiz_app/data/repositories/local_image_store.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/sync/default_sync_engine.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';

import 'support/fake_remote.dart';
import 'support/test_db.dart';

void main() {
  final h = TestHive();
  late FakeRemote remote;
  late FakeConnectivity connectivity;
  late LocalSubjectRepository subjects;
  late LocalNoteRepository notes;
  final engines = <DefaultSyncEngine>[];

  DefaultSyncEngine makeEngine({
    int pageSize = 500,
    int maxAttempts = 8,
    Stream<String?>? users,
    Duration debounce = const Duration(seconds: 2),
  }) {
    final e = DefaultSyncEngine(
      db: h.db,
      remote: remote,
      imageRemote: remote,
      currentUserId: () => h.userId,
      userChanges: users,
      connectivity: connectivity,
      clock: h.clockFn,
      pageSize: pageSize,
      maxAttempts: maxAttempts,
      localWriteDebounce: debounce,
    );
    engines.add(e);
    return e;
  }

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    remote = FakeRemote(userId: 'user-a');
    connectivity = FakeConnectivity();
    subjects = LocalSubjectRepository(h.context());
    notes = LocalNoteRepository(h.context());
  });

  tearDown(() async {
    for (final e in engines) {
      await e.dispose();
    }
    engines.clear();
    await h.tearDown();
  });

  test(
    'pushes the outbox, then pulls; cursor = max server updated_at',
    () async {
      final s = await subjects.create(title: 'Bio');
      final n = await notes.create(subjectId: s.id, title: 'Cells');
      final engine = makeEngine();

      await engine.sync();

      expect(h.db.outbox.length, 0);
      expect(remote.tables['subjects']!.keys, [s.id]);
      expect(remote.tables['notes']!.keys, [n.id]);
      // Local rows now carry the server timestamp.
      final serverUpdated = DateTime.parse(
        remote.tables['subjects']![s.id]!['updated_at'] as String,
      );
      expect(h.db.subjects.get(s.id)!.updatedAt, serverUpdated);
      expect(
        h.db.meta.cursor('subjects'),
        PullCursor(
          updatedAt: remote.tables['subjects']![s.id]!['updated_at'] as String,
          id: s.id,
        ),
      );
      expect(engine.currentStatus.state, SyncState.idle);
      expect(engine.currentStatus.lastSyncedAt, isNotNull);
      expect(engine.currentStatus.pendingOps, 0);
    },
  );

  test('incremental pull starts from cursor minus lookback', () async {
    final engine = makeEngine();
    remote.serverWrite('subjects', subjectRow('s1', 'user-a', title: 'one'));
    await engine.sync();
    final cursor = h.db.meta.cursor('subjects')!;

    remote.pullAfters.clear();
    remote.serverWrite('subjects', subjectRow('s2', 'user-a', title: 'two'));
    await engine.sync();

    final after = remote.pullAfters.first!;
    expect(
      after.updatedAtTime,
      cursor.updatedAtTime.subtract(const Duration(seconds: 5)),
    );
    expect(h.db.subjects.get('s2')!.title, 'two');
    expect(
      h.db.meta.cursor('subjects')!.updatedAt,
      remote.tables['subjects']!['s2']!['updated_at'],
    );
  });

  test('pages through rows sharing one timestamp (keyset paging)', () async {
    remote.serverWrite('subjects', subjectRow('s', 'user-a'));
    for (var i = 0; i < 5; i++) {
      remote.serverWrite(
        'notes',
        noteRow('n$i', 'user-a', 's'),
        sameTimestamp: i > 0,
      );
    }
    final engine = makeEngine(pageSize: 2);
    await engine.sync();
    expect(h.db.notes.all().map((n) => n.id).toSet(), {
      'n0',
      'n1',
      'n2',
      'n3',
      'n4',
    });
    expect(h.db.meta.cursor('notes')!.id, 'n4');
  });

  test('LWW: a pulled row never overwrites a row with a pending op', () async {
    final engine = makeEngine();
    final s = await subjects.create(title: 'v1');
    await engine.sync();

    // Local edit is pending, but its push fails transiently this time.
    await subjects.update(h.db.subjects.get(s.id)!.copyWith(title: 'local'));
    remote.upsertHook = (_, _) =>
        const RemoteException(RemoteErrorKind.transient, '503', code: '503');
    // Meanwhile another device changed the row on the server.
    remote.serverWrite('subjects', {
      ...remote.tables['subjects']![s.id]!,
      'title': 'other device',
    });

    await engine.sync();
    expect(h.db.subjects.get(s.id)!.title, 'local');
    expect(h.db.outbox.pending().single.attempts, 1);

    // Once the push succeeds, the local (latest) write wins on the server.
    remote.upsertHook = null;
    await engine.sync();
    expect(remote.tables['subjects']![s.id]!['title'], 'local');
    expect(h.db.subjects.get(s.id)!.title, 'local');
    expect(h.db.outbox.length, 0);
  });

  test('without a pending op the server version wins', () async {
    final engine = makeEngine();
    final s = await subjects.create(title: 'v1');
    await engine.sync();
    remote.serverWrite('subjects', {
      ...remote.tables['subjects']![s.id]!,
      'title': 'v2',
    });
    await engine.sync();
    expect(h.db.subjects.get(s.id)!.title, 'v2');
  });

  test('tombstones: foreign purged, own kept, unknown skipped', () async {
    final engine = makeEngine();
    remote.serverWrite('subjects', subjectRow('own', 'user-a'));
    remote.serverWrite('subjects', subjectRow('theirs', 'user-b'));
    remote.shares.add({
      'id': 'sh',
      'owner_id': 'user-b',
      'recipient_id': 'user-a',
      'resource_type': 'subject',
      'resource_id': 'theirs',
      'created_at': '2026-01-01T00:00:00Z',
    });
    await engine.sync();
    expect(h.db.subjects.get('theirs'), isNotNull);

    const deleted = '2026-02-01T00:00:00Z';
    remote.serverWrite(
      'subjects',
      subjectRow('own', 'user-a', deletedAt: deleted),
    );
    remote.serverWrite(
      'subjects',
      subjectRow('theirs', 'user-b', deletedAt: deleted),
    );
    remote.serverWrite(
      'subjects',
      subjectRow('never-seen', 'user-a', deletedAt: deleted),
    );
    await engine.sync();

    expect(h.db.subjects.get('own')!.isDeleted, isTrue); // kept for sync
    expect(h.db.subjects.get('theirs'), isNull); // purged
    expect(h.db.subjects.get('never-seen'), isNull);
    expect(await subjects.watchAll().first, isEmpty);
  });

  test('permanent rejection (RLS 42501) drops the op and reports it; '
      'the queue keeps going', () async {
    final engine = makeEngine();
    final good = await subjects.create(title: 'good');
    final bad = await subjects.create(title: 'bad');
    remote.upsertHook = (_, row) => row['id'] == bad.id
        ? const RemoteException(
            RemoteErrorKind.permanent,
            'new row violates row-level security policy',
            code: '42501',
          )
        : null;
    final rejections = <SyncRejection>[];
    final sub = engine.rejections.listen(rejections.add);

    await engine.sync();
    await pumpEventQueue();
    await sub.cancel();

    expect(h.db.outbox.length, 0);
    expect(remote.tables['subjects']!.keys, [good.id]);
    expect(engine.currentStatus.state, SyncState.error);
    expect(engine.currentStatus.error, contains('rejected'));
    expect(rejections.single.op.rowId, bad.id);

    // The user's version is kept (the server has none to restore here).
    final kept = engine.rejectedChanges.single;
    expect(kept.rowId, bad.id);
    expect(kept.table, SyncTables.subjects);
    expect(kept.payload!['title'], 'bad');
    expect(engine.currentStatus.rejectedChanges, 1);

    await engine.dismissRejectedChange(kept.id);
    expect(engine.rejectedChanges, isEmpty);
    expect(engine.currentStatus.rejectedChanges, 0);
  });

  test('rejected edit: server version restored, user content kept', () async {
    final engine = makeEngine();
    final s = await subjects.create(title: 'S');
    final n = await notes.create(subjectId: s.id, title: 'N');
    await engine.sync();
    await notes.update(
      h.db.notes.get(n.id)!.copyWith(contentMd: 'my precious edit'),
    );
    remote.upsertHook = (_, _) => const RemoteException(
      RemoteErrorKind.permanent,
      'check constraint',
      code: '23514',
    );

    await engine.sync();

    expect(h.db.notes.get(n.id)!.contentMd, ''); // server version restored
    final kept = engine.rejectedChanges.single;
    expect(kept.payload!['content_md'], 'my precious edit');
    // Survives a restart (persisted in sync_meta).
    final restarted = makeEngine();
    expect(restarted.rejectedChanges.single.id, kept.id);
    expect(restarted.currentStatus.rejectedChanges, 1);
  });

  test(
    'FK violations are deferred within the cycle (child before parent)',
    () async {
      final engine = makeEngine();
      final s = Subject.fromJson(subjectRow('s', 'user-a'));
      final n = Note.fromJson(noteRow('n', 'user-a', 's'));
      // Enqueue the child first to simulate an out-of-order queue.
      await h.db.saveAndEnqueue(h.db.notes, n);
      await h.db.saveAndEnqueue(h.db.subjects, s);

      await engine.sync();

      expect(h.db.outbox.length, 0);
      expect(remote.tables['notes']!.containsKey('n'), isTrue);
      expect(engine.currentStatus.state, SyncState.idle);
    },
  );

  test('transient failures are never dropped; flagged as stuck', () async {
    final engine = makeEngine(maxAttempts: 2);
    final s = await subjects.create(title: 'x');
    remote.upsertHook = (_, _) =>
        const RemoteException(RemoteErrorKind.transient, 'boom', code: '503');

    await engine.sync();
    expect(h.db.outbox.pending().single.attempts, 1);
    expect(h.db.outbox.pending().single.lastError, 'boom');
    expect(engine.currentStatus.stuckOps, 0);

    // A long outage: many more failures than the threshold.
    for (var i = 0; i < 5; i++) {
      await engine.sync();
    }
    expect(h.db.outbox.pending().single.attempts, 6);
    expect(engine.currentStatus.stuckOps, 1);
    expect(engine.currentStatus.state, SyncState.error);
    expect(engine.currentStatus.error, contains('Retrying automatically'));
    expect(h.db.subjects.get(s.id)!.title, 'x'); // local row untouched
    expect(engine.rejectedChanges, isEmpty);

    // Server recovers: the op is pushed and the flag clears.
    remote.upsertHook = null;
    await engine.sync();
    expect(h.db.outbox.length, 0);
    expect(remote.tables['subjects']!.containsKey(s.id), isTrue);
    expect(engine.currentStatus.stuckOps, 0);
    expect(engine.currentStatus.state, SyncState.idle);
  });

  test('FK-blocked ops are not counted while their parent fails '
      'transiently', () async {
    final engine = makeEngine(maxAttempts: 1);
    final s = await subjects.create(title: 'parent');
    final n = await notes.create(subjectId: s.id, title: 'child');
    remote.upsertHook = (table, _) => table == SyncTables.subjects
        ? const RemoteException(RemoteErrorKind.transient, 'boom', code: '500')
        : null;

    for (var i = 0; i < 3; i++) {
      await engine.sync();
    }
    expect(h.db.outbox.length, 2); // nothing dropped
    expect(engine.rejectedChanges, isEmpty);

    remote.upsertHook = null;
    await engine.sync();
    expect(h.db.outbox.length, 0);
    expect(remote.tables['notes']!.containsKey(n.id), isTrue);
  });

  test('network failure: offline status, nothing dropped', () async {
    final engine = makeEngine();
    await subjects.create(title: 'x');
    remote.offline = true;
    await engine.sync();
    expect(engine.currentStatus.state, SyncState.offline);
    expect(h.db.outbox.pending().single.attempts, 0);
    expect(engine.currentStatus.pendingOps, 1);

    // Connectivity monitor says offline: no request is made at all.
    connectivity.online = false;
    final calls = remote.upsertCalls;
    await engine.sync();
    expect(remote.upsertCalls, calls);
    expect(engine.currentStatus.state, SyncState.offline);

    connectivity.online = true;
    remote.offline = false;
    await engine.sync();
    expect(h.db.outbox.length, 0);
    expect(engine.currentStatus.state, SyncState.idle);
  });

  test('single-flight: concurrent sync() calls join one cycle', () async {
    final engine = makeEngine();
    await subjects.create(title: 'x');
    final gate = Completer<void>();
    remote.upsertDelay = () => gate.future;

    final a = engine.sync();
    final b = engine.sync();
    expect(identical(a, b), isTrue);
    await pumpEventQueue();
    expect(engine.currentStatus.state, SyncState.syncing);
    gate.complete();
    await Future.wait([a, b]);

    expect(remote.upsertCalls, 1);
    // One pull per table for a single cycle.
    expect(remote.pullCalls, SyncTables.synced.length);
  });

  test('revoked share: reconciliation purges rows no longer visible', () async {
    final engine = makeEngine();
    remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
    remote.serverWrite('notes', noteRow('bn', 'user-b', 'bs'));
    remote.serverWrite('quizzes', quizRow('bq', 'user-b', 'bs'));
    remote.shares.add({
      'id': 'sh1',
      'owner_id': 'user-b',
      'recipient_id': 'user-a',
      'resource_type': 'subject',
      'resource_id': 'bs',
      'created_at': '2026-01-01T00:00:00Z',
    });
    final own = await subjects.create(title: 'mine');
    await engine.sync();
    expect(h.db.notes.get('bn'), isNotNull);
    expect(h.db.quizzes.get('bq'), isNotNull);

    remote.shares.clear(); // owner revokes
    await engine.sync();

    expect(h.db.subjects.get('bs'), isNull);
    expect(h.db.notes.get('bn'), isNull);
    expect(h.db.quizzes.get('bq'), isNull);
    expect(h.db.subjects.get(own.id), isNotNull); // own rows untouched
  });

  test('new share: backfills rows older than the cursor', () async {
    final engine = makeEngine();
    // Owner's rows are written long before the share exists.
    remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
    remote.serverWrite('notes', noteRow('bn', 'user-b', 'bs'));
    await subjects.create(title: 'mine');
    await engine.sync(); // recipient's cursor is now past bs/bn
    expect(h.db.subjects.get('bs'), isNull);

    remote.shares.add({
      'id': 'sh1',
      'owner_id': 'user-b',
      'recipient_id': 'user-a',
      'resource_type': 'subject',
      'resource_id': 'bs',
      'created_at': '2026-01-01T00:00:00Z',
    });
    await engine.sync();
    expect(h.db.subjects.get('bs'), isNotNull);
    expect(h.db.notes.get('bn'), isNotNull);
  });

  test('explicit sign-out clears user data; account switch starts '
      'clean', () async {
    final users = StreamController<String?>.broadcast();
    final engine = makeEngine(users: users.stream)..start();
    await subjects.create(title: 'x');
    await engine.sync();
    expect(h.db.subjects.all(), isNotEmpty);

    // Account switch: user-b signs in on this device.
    h.userId = 'user-b';
    remote.userId = 'user-b';
    users.add('user-b');
    await pumpEventQueue();
    await engine.authSettled;
    await engine.sync();
    expect(h.db.subjects.all(), isEmpty);
    expect(h.db.meta.userId, 'user-b');

    await LocalSubjectRepository(h.context()).create(title: 'b');
    await engine.sync();
    expect(h.db.subjects.all(), hasLength(1));

    h.userId = null;
    users.add(null);
    await pumpEventQueue();
    await engine.authSettled;
    // The auth stream alone never wipes (could be an expired session).
    expect(h.db.subjects.all(), hasLength(1));

    await engine.clearAfterSignOut();
    expect(h.db.subjects.all(), isEmpty);
    expect(h.db.outbox.length, 0);
    expect(h.db.meta.cursor('subjects'), isNull);
    expect(engine.currentStatus.state, SyncState.idle);
    await users.close();
  });

  test('involuntary sign-out keeps the outbox; the same user signing back '
      'in pushes it', () async {
    final users = StreamController<String?>.broadcast();
    final engine = makeEngine(users: users.stream)..start();
    await engine.authSettled;
    await engine.sync();
    remote.offline = true;
    final s = await subjects.create(title: 'unsynced');
    await engine.sync();
    expect(h.db.outbox.length, 1);

    // Refresh token revoked: the session ends without the user asking.
    h.userId = null;
    users.add(null);
    await pumpEventQueue();
    await engine.authSettled;
    expect(h.db.subjects.get(s.id), isNotNull);
    expect(h.db.outbox.length, 1);
    final calls = remote.upsertCalls;
    await engine.sync(); // signed out: nothing is attempted
    expect(remote.upsertCalls, calls);

    remote.offline = false;
    h.userId = 'user-a';
    users.add('user-a');
    await pumpEventQueue();
    await engine.authSettled;
    await engine.sync();
    expect(h.db.outbox.length, 0);
    expect(remote.tables['subjects']!.containsKey(s.id), isTrue);

    // A *different* user signing in after an involuntary sign-out starts
    // clean.
    h.userId = null;
    users.add(null);
    await pumpEventQueue();
    h.userId = 'user-b';
    remote.userId = 'user-b';
    users.add('user-b');
    await pumpEventQueue();
    await engine.authSettled;
    expect(h.db.subjects.all(), isEmpty);
    await users.close();
  });

  test('clearAfterSignOut is a no-op when a user is signed in', () async {
    final engine = makeEngine();
    await subjects.create(title: 'x');
    await engine.clearAfterSignOut();
    expect(h.db.subjects.all(), hasLength(1));
  });

  test('local writes trigger a debounced sync after start()', () async {
    final engine = makeEngine(debounce: const Duration(milliseconds: 20))
      ..start();
    await pumpEventQueue();
    final s = await subjects.create(title: 'auto');
    await eventually(() => remote.tables['subjects']!.containsKey(s.id));
    await eventually(() => engine.currentStatus.state == SyncState.idle);
    expect(engine.currentStatus.pendingOps, 0);
  });

  test('connectivity regained triggers a sync', () async {
    final engine = makeEngine()..start();
    await engine.sync(); // joins the cycle start() kicked off
    connectivity.set(false);
    await subjects.create(title: 'offline edit');
    await engine.sync();
    expect(engine.currentStatus.state, SyncState.offline);

    connectivity.set(true);
    await eventually(() => remote.tables['subjects']!.length == 1);
    await eventually(() => engine.currentStatus.state == SyncState.idle);
  });

  test('connectivity lost during a running cycle ends offline', () async {
    final engine = makeEngine()..start();
    await engine.sync();
    await subjects.create(title: 'x');
    final gate = Completer<void>();
    remote.upsertDelay = () => gate.future;

    final running = engine.sync();
    await pumpEventQueue();
    expect(engine.currentStatus.state, SyncState.syncing);
    // The interface goes down, but the request in flight still succeeds.
    connectivity.set(false);
    await pumpEventQueue();
    gate.complete();
    // sync() callers wait for the follow-up cycle, which sees the change
    // (before the fix the cycle ended `idle` while offline).
    await running;
    expect(h.db.outbox.length, 0);
    expect(engine.currentStatus.state, SyncState.offline);
  });

  test('connectivity regained while a cycle checks connectivity is not '
      'missed (stale isOnline result)', () async {
    final engine = makeEngine()..start();
    await engine.sync();
    await subjects.create(title: 'x');
    // The connection drops without an event (or the event is late), and the
    // platform check is slow: the cycle reads "offline" ...
    connectivity.online = false;
    final gate = Completer<void>();
    connectivity.checkDelay = () => gate.future;
    final running = engine.sync();
    await pumpEventQueue();
    // ... but before it returns, connectivity comes back.
    connectivity.checkDelay = null;
    connectivity.set(true);
    await pumpEventQueue();
    gate.complete();
    await running;

    expect(remote.tables['subjects'], hasLength(1));
    expect(engine.currentStatus.state, SyncState.idle);
  });

  test('status stream emits current value first, then changes', () async {
    final engine = makeEngine();
    await subjects.create(title: 'x');
    final states = <SyncState>[];
    final sub = engine.status.listen((s) => states.add(s.state));
    await engine.sync();
    await pumpEventQueue();
    await sub.cancel();
    expect(states.first, SyncState.idle);
    expect(states, contains(SyncState.syncing));
    expect(states.last, SyncState.idle);
  });

  test('image ops upload saved bytes and process note_image_copies', () async {
    final engine = makeEngine();
    final s = await subjects.create(title: 'S');
    final n = await notes.create(subjectId: s.id, title: 'N');
    final store = LocalImageStore(h.context(), remote);
    final ref = await store.saveNoteImage(
      noteId: n.id,
      bytes: Uint8List.fromList([9, 9]),
      extension: '.PNG',
    );
    expect(ref.fileName, endsWith('.png'));
    remote.objects['user-b/src/pic.png'] = Uint8List.fromList([7]);
    remote.imageCopies.add({
      'id': 'c1',
      'owner_id': 'user-a',
      'from_path': 'user-b/src/pic.png',
      'to_path': 'user-a/${n.id}/pic.png',
    });
    remote.imageCopies.add({
      'id': 'c2',
      'owner_id': 'user-a',
      'from_path': 'user-b/src/missing.png',
      'to_path': 'user-a/${n.id}/missing.png',
    });

    await engine.sync();

    expect(remote.objects[ref.storagePath], [9, 9]);
    expect(remote.objects['user-a/${n.id}/pic.png'], [7]);
    expect(remote.imageCopies, isEmpty); // copied or source gone: removed
    expect(h.db.outbox.length, 0);
  });
}
