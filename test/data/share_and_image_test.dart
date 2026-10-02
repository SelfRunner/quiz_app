import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/local_image_store.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/repositories/supabase_share_repository.dart';
import 'package:quiz_app/data/sync/default_sync_engine.dart';
import 'package:quiz_app/data/sync/note_image_copy_processor.dart';

import 'support/fake_remote.dart';
import 'support/test_db.dart';

void main() {
  final h = TestHive();
  late FakeRemote remote;
  late FakeConnectivity connectivity;
  late DefaultSyncEngine engine;
  late SupabaseShareRepository shares;
  late LocalSubjectRepository subjects;
  late LocalNoteRepository notes;
  late LocalImageStore images;
  var syncCalls = 0;

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    remote = FakeRemote(userId: 'user-a')
      ..profiles['user-a'] = {
        'id': 'user-a',
        'email': 'a@x.test',
        'display_name': 'Ann',
      }
      ..profiles['user-b'] = {
        'id': 'user-b',
        'email': 'b@x.test',
        'display_name': 'Bob',
      };
    connectivity = FakeConnectivity();
    engine = DefaultSyncEngine(
      db: h.db,
      remote: remote,
      imageRemote: remote,
      currentUserId: () => h.userId,
      connectivity: connectivity,
      clock: h.clockFn,
    );
    syncCalls = 0;
    shares = SupabaseShareRepository(
      ctx: h.context(),
      remote: remote,
      imageCopies: NoteImageCopyProcessor(remote, h.db.images),
      connectivity: connectivity,
      sync: () {
        syncCalls++;
        return engine.syncFresh();
      },
    );
    subjects = LocalSubjectRepository(h.context());
    notes = LocalNoteRepository(h.context());
    images = LocalImageStore(h.context(), remote);
  });

  tearDown(() async {
    await engine.dispose();
    await h.tearDown();
  });

  group('ShareRepository', () {
    test('is online-only with a clear error', () async {
      connectivity.online = false;
      await expectLater(
        shares.findUserByEmail('b@x.test'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('offline'),
          ),
        ),
      );
      await expectLater(
        shares.sharedWithMe(),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
      'find user, share (pushing the resource first), list, revoke',
      () async {
        final s = await subjects.create(title: 'Bio');
        final bob = await shares.findUserByEmail(' B@x.test ');
        expect(bob?.id, 'user-b');
        expect(bob?.email, 'b@x.test');

        final share = await shares.share(
          resourceType: ShareResourceType.subject,
          resourceId: s.id,
          recipientId: bob!.id,
        );
        expect(syncCalls, 1); // pending subject pushed before sharing
        expect(remote.tables['subjects']!.containsKey(s.id), isTrue);
        expect(share.recipient?.displayName, 'Bob');

        // Idempotent.
        final again = await shares.share(
          resourceType: ShareResourceType.subject,
          resourceId: s.id,
          recipientId: 'user-b',
        );
        expect(again.id, share.id);

        final listed = await shares.listSharesFor(
          ShareResourceType.subject,
          s.id,
        );
        expect(listed.single.recipient?.displayName, 'Bob');

        await shares.revoke(share.id);
        expect(remote.shares, isEmpty);
      },
    );

    test('validation and ownership errors', () async {
      final s = await subjects.create(title: 'Bio');
      expect(
        () => shares.share(
          resourceType: ShareResourceType.subject,
          resourceId: s.id,
          recipientId: 'user-a',
        ),
        throwsA(isA<ValidationException>()),
      );
      await h.db.subjects.put(Subject.fromJson(subjectRow('theirs', 'user-b')));
      expect(
        () => shares.share(
          resourceType: ShareResourceType.subject,
          resourceId: 'theirs',
          recipientId: 'user-c',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(
        () => shares.copyToMyAccount(
          resourceType: ShareResourceType.note,
          resourceId: 'x',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('sharedWithMe joins owner profile and resource title', () async {
      remote.serverWrite('notes', noteRow('bn', 'user-b', 'bs', title: 'T'));
      remote.shares.add({
        'id': 'sh',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'note',
        'resource_id': 'bn',
        'created_at': '2026-01-01T00:00:00Z',
      });
      final list = await shares.sharedWithMe();
      expect(list.single.owner?.displayName, 'Bob');
      expect(list.single.resourceTitle, 'T');
    });

    test('copyToMyAccount copies via RPC, copies images, then syncs', () async {
      // user-b's shared note with an image.
      remote.serverWrite('subjects', subjectRow('bs', 'user-b'));
      remote.serverWrite(
        'notes',
        noteRow(
          'bn',
          'user-b',
          'bs',
          content: 'See ![](note-image://user-b/bn/pic.png)',
        ),
      );
      remote.objects['user-b/bn/pic.png'] = Uint8List.fromList([1, 2]);
      remote.shares.add({
        'id': 'sh',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'note',
        'resource_id': 'bn',
        'created_at': '2026-01-01T00:00:00Z',
      });
      final target = await subjects.create(title: 'Mine');

      final newId = await shares.copyToMyAccount(
        resourceType: ShareResourceType.note,
        resourceId: 'bn',
        targetSubjectId: target.id,
      );

      expect(remote.rpcCalls, ['copy_note']);
      final copy = h.db.notes.get(newId)!; // pulled by the sync
      expect(copy.ownerId, 'user-a');
      expect(copy.subjectId, target.id);
      expect(copy.contentMd, contains('note-image://user-a/$newId/pic.png'));
      expect(remote.objects['user-a/$newId/pic.png'], [1, 2]);
      expect(remote.imageCopies, isEmpty);

      // The copied image resolves through the image store.
      final ref = NoteImageRef.tryParse('note-image://user-a/$newId/pic.png')!;
      expect(await images.load(ref), [1, 2]);
    });
  });

  group('ImageStore', () {
    test('saves locally, queues upload, loads offline from cache', () async {
      final s = await subjects.create(title: 'S');
      final n = await notes.create(subjectId: s.id, title: 'N');
      final ref = await images.saveNoteImage(
        noteId: n.id,
        bytes: Uint8List.fromList([1, 2, 3]),
        extension: 'jpg',
      );
      expect(ref.ownerId, 'user-a');
      expect(ref.noteId, n.id);
      expect(ref.markdownUrl, startsWith('note-image://user-a/${n.id}/'));
      final op = h.db.outbox.pending().last;
      expect(op.op, OutboxOpType.uploadImage);
      expect(op.rowId, ref.storagePath);
      expect(op.payload!['content_type'], 'image/jpeg');

      remote.offline = true;
      final fresh = LocalImageStore(h.context(), remote);
      expect(await fresh.load(ref), [1, 2, 3]);
    });

    test(
      'downloads and caches missing images; null when unavailable',
      () async {
        remote.objects['user-b/bn/x.png'] = Uint8List.fromList([5]);
        final ref = NoteImageRef.tryParse('note-image://user-b/bn/x.png')!;
        expect(await images.load(ref), [5]);
        expect(await h.db.images.read(ref.storagePath), [5]);

        final missing = NoteImageRef.tryParse('user-b/bn/none.png')!;
        expect(await images.load(missing), isNull);
        expect(await images.signedUrl(ref), contains('user-b/bn/x.png'));
      },
    );

    test(
      'delete drops pending upload, queues delete; foreign is denied',
      () async {
        final s = await subjects.create(title: 'S');
        final n = await notes.create(subjectId: s.id, title: 'N');
        final ref = await images.saveNoteImage(
          noteId: n.id,
          bytes: Uint8List.fromList([1]),
          extension: 'png',
        );
        await images.delete(ref);
        final imageOps = h.db.outbox.pending().where(
          (o) => o.table == SyncTables.noteImagesBucket,
        );
        expect(imageOps.single.op, OutboxOpType.deleteImage);
        expect(await h.db.images.read(ref.storagePath), isNull);

        expect(
          () => images.delete(NoteImageRef.tryParse('user-b/n/f.png')!),
          throwsA(isA<PermissionDeniedException>()),
        );
        await h.db.notes.put(Note.fromJson(noteRow('fn', 'user-b', 'x')));
        expect(
          () => images.saveNoteImage(
            noteId: 'fn',
            bytes: Uint8List.fromList([1]),
            extension: 'png',
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );
  });
}
