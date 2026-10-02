import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/remote/remote_data_source.dart';
import 'package:quiz_app/data/remote/supabase_remote_data_source.dart';
import 'package:quiz_app/data/repositories/attachment_repository.dart';
import 'package:quiz_app/data/repositories/local_attachment_repository.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/repositories/note_search.dart';
import 'package:quiz_app/data/sync/default_sync_engine.dart';
import 'package:quiz_app/data/sync/note_image_copy_processor.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'support/fake_remote.dart';
import 'support/test_db.dart';

Uint8List bytesOf(List<int> values) => Uint8List.fromList(values);

void main() {
  group('Attachment helpers', () {
    test('kind detection: extension first, then MIME type', () {
      AttachmentKind k(String name, [String? mime]) =>
          AttachmentKind.detect(fileName: name, mimeType: mime);
      expect(k('Lecture.PDF'), AttachmentKind.pdf);
      expect(k('photo.jpeg'), AttachmentKind.image);
      expect(k('scan.HEIC'), AttachmentKind.image);
      expect(k('notes.md'), AttachmentKind.text);
      expect(k('notes.txt'), AttachmentKind.text);
      expect(k('essay.docx'), AttachmentKind.docx);
      expect(k('talk.m4a'), AttachmentKind.audio);
      expect(k('clip.webm'), AttachmentKind.video);
      expect(k('archive.zip'), AttachmentKind.other);
      expect(k('noext'), AttachmentKind.other);
      // MIME fallback when the extension is unknown / missing.
      expect(k('blob', 'application/pdf'), AttachmentKind.pdf);
      expect(k('blob', 'image/png'), AttachmentKind.image);
      expect(k('blob', 'audio/mpeg; codecs=x'), AttachmentKind.audio);
      expect(k('blob', 'video/mp4'), AttachmentKind.video);
      expect(k('blob', 'text/plain'), AttachmentKind.text);
      expect(k('icon.svg', 'image/svg+xml'), AttachmentKind.other);
      expect(mimeTypeForFileName('a.docx'), contains('wordprocessingml'));
      expect(mimeTypeForFileName('a.unknown'), isNull);
    });

    test('file name sanitizing and storage path', () {
      expect(
        Attachment.sanitizeFileName('My notes (v2).pdf'),
        'My_notes__v2_.pdf',
      );
      expect(Attachment.sanitizeFileName('Résumé.docx'), 'R_sum_.docx');
      expect(Attachment.sanitizeFileName('dir/sub/x.txt'), 'x.txt');
      expect(Attachment.sanitizeFileName(''), 'file');
      expect(Attachment.sanitizeFileName('..'), 'file');
      final long = Attachment.sanitizeFileName('${'a' * 300}.pdf');
      expect(long.length, 100);
      expect(long, endsWith('.pdf'));
      expect(
        Attachment.buildStoragePath(
          ownerId: 'o',
          subjectId: 's',
          id: 'i',
          fileName: 'a b.pdf',
        ),
        'o/s/i/a_b.pdf',
      );
    });

    test('JSON round trip uses column names; unknown kind -> other', () {
      final json = attachmentRow('a1', 'u', 's', name: 'x.pdf');
      final a = Attachment.fromJson(json);
      expect(a.kind, AttachmentKind.pdf);
      expect(a.sizeBytes, 3);
      expect(a.toJson(), {
        ...json,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      final odd = Attachment.fromJson({
        ...attachmentRow('a2', 'u', 's'),
        'kind': 'hologram',
      });
      expect(odd.kind, AttachmentKind.other);
    });
  });

  group('AttachmentRepository + sync', () {
    final h = TestHive();
    late FakeRemote remote;
    late FakeConnectivity connectivity;
    late LocalSubjectRepository subjects;
    late LocalAttachmentRepository files;
    final engines = <DefaultSyncEngine>[];

    DefaultSyncEngine makeEngine() {
      final e = DefaultSyncEngine(
        db: h.db,
        remote: remote,
        imageRemote: remote,
        currentUserId: () => h.userId,
        connectivity: connectivity,
        clock: h.clockFn,
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
      files = LocalAttachmentRepository(h.context(), remote);
    });

    tearDown(() async {
      for (final e in engines) {
        await e.dispose();
      }
      engines.clear();
      await h.tearDown();
    });

    test('add stores bytes locally and queues upload before the row', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'Cell notes.md',
        bytes: bytesOf([1, 2, 3]),
        extractedText: 'x' * (Attachment.maxExtractedTextLength + 10),
      );

      expect(a.ownerId, 'user-a');
      expect(a.kind, AttachmentKind.text);
      expect(a.mimeType, 'text/markdown');
      expect(a.sizeBytes, 3);
      expect(a.storagePath, 'user-a/${s.id}/${a.id}/Cell_notes.md');
      expect(a.extractedText!.length, Attachment.maxExtractedTextLength);
      expect(await h.db.attachmentFiles.read(a.storagePath), [1, 2, 3]);
      expect(await files.isCached(a), isTrue);
      expect(await files.getBytes(a), [1, 2, 3]);

      final ops = h.db.outbox.pending();
      final uploadIndex = ops.indexWhere(
        (o) => o.op == OutboxOpType.uploadAttachment,
      );
      final rowIndex = ops.indexWhere(
        (o) => o.table == SyncTables.attachments && o.rowId == a.id,
      );
      expect(uploadIndex, greaterThanOrEqualTo(0));
      expect(rowIndex, greaterThan(uploadIndex));
      expect(ops[uploadIndex].rowId, a.storagePath);
      expect(ops[uploadIndex].payload, {
        'attachment_id': a.id,
        'content_type': 'text/markdown',
      });

      expect(await files.watchBySubject(s.id).first, [a]);
      expect(await files.watchAllAccessible().first, [a]);
    });

    test(
      'validation: size limit, empty file, shared subject, missing',
      () async {
        final s = await subjects.create(title: 'Bio');
        await expectLater(
          files.add(
            subjectId: s.id,
            name: 'huge.mp4',
            bytes: Uint8List(AttachmentRepository.maxSizeBytes + 1),
          ),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              allOf(contains('huge.mp4'), contains('at most 50 MB')),
            ),
          ),
        );
        await expectLater(
          files.add(subjectId: s.id, name: 'e.txt', bytes: Uint8List(0)),
          throwsA(isA<ValidationException>()),
        );
        await expectLater(
          files.add(subjectId: 'nope', name: 'a.pdf', bytes: bytesOf([1])),
          throwsA(isA<NotFoundException>()),
        );
        expect(h.db.outbox.length, 1); // Only the subject.

        // Shared subject (owned by user-b): read-only.
        await h.db.subjects.put(Subject.fromJson(subjectRow('sb', 'user-b')));
        await expectLater(
          files.add(subjectId: 'sb', name: 'a.pdf', bytes: bytesOf([1])),
          throwsA(isA<PermissionDeniedException>()),
        );
        final foreign = Attachment.fromJson(
          attachmentRow('fa', 'user-b', 'sb'),
        );
        await h.db.attachments.put(foreign);
        await expectLater(
          files.rename('fa', 'mine.pdf'),
          throwsA(isA<PermissionDeniedException>()),
        );
        await expectLater(
          files.delete('fa'),
          throwsA(isA<PermissionDeniedException>()),
        );
        // Readable though.
        expect(await files.watchBySubject('sb').first, [foreign]);
      },
    );

    test('sync uploads the blob before pushing the row', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'paper.pdf',
        bytes: bytesOf([7, 7]),
      );
      final engine = makeEngine();

      await engine.sync();

      expect(remote.log, [
        'upsert:subjects:${s.id}',
        'upload:attachments:${a.storagePath}',
        'upsert:attachments:${a.id}',
      ]);
      expect(remote.attachmentObjects[a.storagePath], [7, 7]);
      expect(remote.objects, isEmpty); // Not the note-images bucket.
      expect(h.db.outbox.length, 0);
      expect(
        remote.tables[SyncTables.attachments]![a.id]!['storage_path'],
        a.storagePath,
      );
      expect(engine.currentStatus.state, SyncState.idle);
      expect(await files.watchUpload(a).first, AttachmentUploadState.done);
    });

    test('offline add, then sync when back online', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.png',
        bytes: bytesOf([1]),
      );
      final engine = makeEngine();
      connectivity.online = false;

      await engine.sync();
      expect(engine.currentStatus.state, SyncState.offline);
      expect(remote.log, isEmpty);
      expect(
        (await files.watchUpload(a).first).phase,
        AttachmentUploadPhase.queued,
      );

      connectivity.online = true;
      await engine.sync();
      expect(remote.log, [
        'upsert:subjects:${s.id}',
        'upload:attachments:${a.storagePath}',
        'upsert:attachments:${a.id}',
      ]);
      expect(await files.watchUpload(a).first, AttachmentUploadState.done);
    });

    test(
      'a failing upload holds back its row (never a row without blob)',
      () async {
        final s = await subjects.create(title: 'Bio');
        final a = await files.add(
          subjectId: s.id,
          name: 'a.pdf',
          bytes: bytesOf([1]),
        );
        final engine = makeEngine();
        remote.uploadHook = (bucket, path) => const RemoteException(
          RemoteErrorKind.transient,
          'storage 503',
          code: '503',
        );

        await engine.sync();
        expect(remote.tables[SyncTables.attachments], isEmpty);
        expect(h.db.outbox.length, 2);
        final state = await files.watchUpload(a).first;
        expect(state.phase, AttachmentUploadPhase.retrying);
        expect(state.attempts, 1);

        remote.uploadHook = null;
        await engine.sync();
        expect(remote.log.sublist(1), [
          'upload:attachments:${a.storagePath}',
          'upsert:attachments:${a.id}',
        ]);
        expect(h.db.outbox.length, 0);
      },
    );

    test('watchUpload reports uploading while the engine uploads', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.pdf',
        bytes: bytesOf([1]),
      );
      final engine = makeEngine();
      final gate = Completer<void>();
      final states = <AttachmentUploadPhase>[];
      final sub = files.watchUpload(a).listen((s) => states.add(s.phase));
      // Simulate a running upload through the engine's transfer tracker.
      final running = h.db.transfers.track(a.storagePath, () => gate.future);
      await eventually(() => states.contains(AttachmentUploadPhase.uploading));
      gate.complete();
      await running;
      await engine.sync();
      await eventually(() => states.last == AttachmentUploadPhase.done);
      expect(states.first, AttachmentUploadPhase.queued);
      await sub.cancel();
    });

    test('delete: tombstone pushed before the blob is removed', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.pdf',
        bytes: bytesOf([1, 2]),
      );
      final engine = makeEngine();
      await engine.sync();
      remote.log.clear();

      await files.delete(a.id);
      expect(await files.watchBySubject(s.id).first, isEmpty);
      expect(await h.db.attachmentFiles.read(a.storagePath), isNull);
      expect(h.db.attachments.get(a.id)!.isDeleted, isTrue);
      await files.delete(a.id); // Idempotent.

      await engine.sync();
      expect(remote.log, [
        'upsert:attachments:${a.id}',
        'remove:attachments:${a.storagePath}',
      ]);
      expect(
        remote.tables[SyncTables.attachments]![a.id]!['deleted_at'],
        isNotNull,
      );
      expect(remote.attachmentObjects, isEmpty);
    });

    test('blob removal waits for its tombstone (FK-deferred)', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.pdf',
        bytes: bytesOf([1]),
      );
      final engine = makeEngine();
      await engine.sync();
      remote.log.clear();
      await files.delete(a.id);
      var failTombstone = true;
      remote.upsertHook = (table, row) => failTombstone
          ? const RemoteException(RemoteErrorKind.transient, '503', code: '503')
          : null;

      await engine.sync();
      expect(remote.log, isEmpty); // Blob still there.
      expect(remote.attachmentObjects, hasLength(1));

      failTombstone = false;
      await engine.sync();
      expect(remote.log, [
        'upsert:attachments:${a.id}',
        'remove:attachments:${a.storagePath}',
      ]);
    });

    test('offline add then delete never uploads the blob', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.pdf',
        bytes: bytesOf([1]),
      );
      await files.delete(a.id);
      expect(
        h.db.outbox.pending().where(
          (o) => o.op == OutboxOpType.uploadAttachment,
        ),
        isEmpty,
      );
      await makeEngine().sync();
      expect(remote.log.where((l) => l.startsWith('upload:')), isEmpty);
      expect(h.db.outbox.length, 0);
    });

    test('deleting a subject cascades to its attachments and blobs', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.pdf',
        bytes: bytesOf([1]),
      );
      final engine = makeEngine();
      await engine.sync();
      remote.log.clear();

      await subjects.delete(s.id);
      expect(h.db.attachments.get(a.id)!.isDeleted, isTrue);
      expect(await h.db.attachmentFiles.read(a.storagePath), isNull);
      await engine.sync();
      expect(remote.log, [
        'upsert:attachments:${a.id}',
        'remove:attachments:${a.storagePath}',
        'upsert:subjects:${s.id}',
      ]);
    });

    test('rename/update only changes mutable fields', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.txt',
        bytes: bytesOf([1]),
      );
      final renamed = await files.rename(a.id, '  Lecture 1.txt ');
      expect(renamed.name, 'Lecture 1.txt');
      expect(renamed.storagePath, a.storagePath);
      final updated = await files.update(
        renamed.copyWith(
          extractedText: 'hello',
          subjectId: 'other',
          storagePath: 'evil/path',
          sizeBytes: 999,
        ),
      );
      expect(updated.extractedText, 'hello');
      expect(updated.subjectId, s.id);
      expect(updated.storagePath, a.storagePath);
      expect(updated.sizeBytes, 1);
      await expectLater(
        files.rename(a.id, '   '),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      'pull: own rows from other devices; own tombstone purges bytes',
      () async {
        remote.serverWrite(SyncTables.subjects, subjectRow('s1', 'user-a'));
        final row = remote.serverWrite(
          SyncTables.attachments,
          attachmentRow('a1', 'user-a', 's1'),
        );
        remote.attachmentObjects[row['storage_path'] as String] = bytesOf([4]);
        final engine = makeEngine();
        await engine.sync();

        final a = h.db.attachments.get('a1')!;
        expect(a.name, 'file.pdf');
        expect(h.db.meta.cursor(SyncTables.attachments), isNotNull);
        // Downloaded on demand and cached.
        expect(await files.getBytes(a), [4]);
        expect(await files.isCached(a), isTrue);

        remote.serverWrite(SyncTables.attachments, {
          ...row,
          'deleted_at': '2026-03-02T00:00:00Z',
        });
        await engine.sync();
        expect(h.db.attachments.get('a1')!.isDeleted, isTrue);
        expect(await files.watchBySubject('s1').first, isEmpty);
        expect(await h.db.attachmentFiles.read(a.storagePath), isNull);
      },
    );

    test(
      'new subject share backfills attachments; revoke purges them',
      () async {
        final engine = makeEngine();
        await engine.sync(); // Cursors exist (not an initial pull any more).

        remote.serverWrite(SyncTables.subjects, subjectRow('sb', 'user-b'));
        final row = Map<String, dynamic>.from(
          attachmentRow('fb', 'user-b', 'sb'),
        )..['updated_at'] = '2025-01-01T00:00:00+00:00'; // Older than cursor.
        remote.tables[SyncTables.attachments]!['fb'] = row;
        remote.attachmentObjects[row['storage_path'] as String] = bytesOf([9]);
        remote.shares.add({
          'id': 'sh1',
          'owner_id': 'user-b',
          'recipient_id': 'user-a',
          'resource_type': 'subject',
          'resource_id': 'sb',
        });

        await engine.sync();
        final shared = h.db.attachments.get('fb');
        expect(shared, isNotNull);
        expect(await files.watchAllAccessible().first, [shared]);
        expect(await files.getBytes(shared!), [9]);
        expect(await files.isCached(shared), isTrue);
        // Read-only.
        await expectLater(
          files.delete('fb'),
          throwsA(isA<PermissionDeniedException>()),
        );

        remote.shares.clear();
        await engine.sync();
        expect(h.db.attachments.get('fb'), isNull);
        expect(await h.db.attachmentFiles.read(shared.storagePath), isNull);
        // Storage refuses the revoked user too.
        await expectLater(
          files.getBytes(shared),
          throwsA(isA<NotFoundException>()),
        );
      },
    );

    test('note shares never expose attachments', () async {
      remote.serverWrite(SyncTables.subjects, subjectRow('sb', 'user-b'));
      remote.serverWrite(SyncTables.notes, noteRow('nb', 'user-b', 'sb'));
      remote.serverWrite(
        SyncTables.attachments,
        attachmentRow('fb', 'user-b', 'sb'),
      );
      remote.shares.add({
        'id': 'sh1',
        'owner_id': 'user-b',
        'recipient_id': 'user-a',
        'resource_type': 'note',
        'resource_id': 'nb',
      });
      await makeEngine().sync();
      expect(h.db.notes.get('nb'), isNotNull);
      expect(h.db.attachments.all(), isEmpty);
    });

    test('getBytes errors: offline, unavailable', () async {
      remote.serverWrite(SyncTables.subjects, subjectRow('s1', 'user-a'));
      remote.serverWrite(
        SyncTables.attachments,
        attachmentRow('a1', 'user-a', 's1'),
      );
      await makeEngine().sync();
      final a = h.db.attachments.get('a1')!;
      // Blob never uploaded / copied.
      await expectLater(files.getBytes(a), throwsA(isA<NotFoundException>()));
      remote.offline = true;
      await expectLater(files.getBytes(a), throwsA(isA<NetworkException>()));
    });

    test('copy queue: rows use their bucket; local bytes follow', () async {
      remote.attachmentObjects['user-b/sb/fb/x.pdf'] = bytesOf([1]);
      remote.objects['user-b/nb/pic.png'] = bytesOf([2]);
      await h.db.attachmentFiles.write('user-b/sb/fb/x.pdf', bytesOf([1]));
      remote.imageCopies
        ..add({
          'id': 'c1',
          'owner_id': 'user-a',
          'bucket': 'attachments',
          'from_path': 'user-b/sb/fb/x.pdf',
          'to_path': 'user-a/s2/f2/x.pdf',
        })
        ..add({
          // Legacy row without bucket = note-images.
          'id': 'c2',
          'owner_id': 'user-a',
          'from_path': 'user-b/nb/pic.png',
          'to_path': 'user-a/n2/pic.png',
        })
        ..add({
          'id': 'c3',
          'owner_id': 'user-a',
          'bucket': 'attachments',
          'from_path': 'user-b/sb/gone/y.pdf',
          'to_path': 'user-a/s2/f3/y.pdf',
        });
      final processor = NoteImageCopyProcessor(
        remote,
        h.db.images,
        attachmentCache: h.db.attachmentFiles,
      );

      expect(await processor.run(), 3);
      expect(remote.attachmentObjects['user-a/s2/f2/x.pdf'], [1]);
      expect(remote.objects['user-a/n2/pic.png'], [2]);
      expect(remote.objects.containsKey('user-a/s2/f2/x.pdf'), isFalse);
      expect(remote.imageCopies, isEmpty); // Missing source: dropped.
      expect(await h.db.attachmentFiles.read('user-a/s2/f2/x.pdf'), [1]);
      expect(await h.db.images.read('user-a/s2/f2/x.pdf'), isNull);
    });

    test('the engine runs attachment copies on sync', () async {
      remote.attachmentObjects['user-b/sb/fb/x.pdf'] = bytesOf([3]);
      remote.imageCopies.add({
        'id': 'c1',
        'owner_id': 'user-a',
        'bucket': 'attachments',
        'from_path': 'user-b/sb/fb/x.pdf',
        'to_path': 'user-a/s2/f2/x.pdf',
      });
      await makeEngine().sync();
      expect(remote.attachmentObjects['user-a/s2/f2/x.pdf'], [3]);
      expect(remote.imageCopies, isEmpty);
    });

    test('sign-out wipe clears attachments and their bytes', () async {
      final s = await subjects.create(title: 'Bio');
      final a = await files.add(
        subjectId: s.id,
        name: 'a.pdf',
        bytes: bytesOf([1]),
      );
      await h.db.clearUserData();
      expect(h.db.attachments.all(), isEmpty);
      expect(await h.db.attachmentFiles.read(a.storagePath), isNull);
    });
  });

  group('note picker', () {
    final h = TestHive();
    setUp(h.setUp);
    tearDown(h.tearDown);

    test('watchAllAccessible: own + shared, live, newest first', () async {
      final subjects = LocalSubjectRepository(h.context());
      final notes = LocalNoteRepository(h.context());
      final s = await subjects.create(title: 'Bio');
      final n1 = await notes.create(subjectId: s.id, title: 'Cells');
      final n2 = await notes.create(subjectId: s.id, title: 'DNA');
      final deleted = await notes.create(subjectId: s.id, title: 'Old');
      await notes.delete(deleted.id);
      final shared = Note.fromJson(
        noteRow('nb', 'user-b', 'sb', title: 'Shared genetics'),
      );
      await h.db.notes.put(shared);

      final all = await notes.watchAllAccessible().first;
      expect(all, [n2, n1, shared]);
    });

    test('searchNotes: case-insensitive, all terms, title hits first', () {
      Note n(String id, String title, String content) => Note(
        id: id,
        subjectId: 's',
        ownerId: 'u',
        title: title,
        contentMd: content,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final a = n('a', 'Photosynthesis', 'Light reactions in the CHLOROPLAST');
      final b = n('b', 'Cell organelles', 'The chloroplast and mitochondria');
      final c = n('c', 'Chloroplast structure', 'Thylakoids');
      final list = [a, b, c];

      expect(searchNotes(list, ''), list);
      expect(searchNotes(list, '   '), list);
      expect(searchNotes(list, 'chloroPLAST'), [c, a, b]);
      expect(searchNotes(list, 'chloroplast light'), [a]);
      expect(searchNotes(list, 'xyz'), isEmpty);
      expect(noteMatches(b, 'MITO'), isTrue);

      // A few thousand notes stay fast (memoized lowercase).
      final many = [
        for (var i = 0; i < 5000; i++)
          n('$i', 'Note $i', 'Lorem ipsum dolor sit amet ' * 40),
      ];
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        searchNotes(many, 'ipsum ${i % 10}');
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('SupabaseRemoteDataSource storage', () {
    late List<http.Request> requests;
    late sb.SupabaseClient client;
    late SupabaseRemoteDataSource source;

    setUp(() {
      requests = [];
      client = sb.SupabaseClient(
        'http://localhost:9',
        'anon-key',
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          http.Response json(Object body) => http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
          if (request.url.path.contains('/rest/v1/note_image_copies')) {
            return json([
              {
                'id': 'c1',
                'bucket': 'attachments',
                'from_path': 'a/b/c/d',
                'to_path': 'e/f/g/h',
              },
              {'id': 'c2', 'from_path': 'a/b/c', 'to_path': 'e/f/g'},
            ]);
          }
          if (request.url.path.endsWith('/object/copy')) {
            return json({'Key': 'attachments/b'});
          }
          if (request.method == 'DELETE') return json(<Object>[]);
          return http.Response.bytes([1, 2, 3], 200, request: request);
        }),
      );
      source = SupabaseRemoteDataSource(client);
    });

    tearDown(() => client.dispose());

    test('downloads are cache-busted with a unique query parameter', () async {
      await source.downloadImage('u/n/pic.png');
      await source.downloadImage('u/n/pic.png');
      final bytes = await source.downloadImage(
        'u/s/a/x.pdf',
        bucket: SyncTables.attachmentsBucket,
      );
      expect(bytes, [1, 2, 3]);

      expect(requests, hasLength(3));
      expect(
        requests[0].url.path,
        '/storage/v1/object/note-images/u/n/pic.png',
      );
      expect(
        requests[2].url.path,
        '/storage/v1/object/attachments/u/s/a/x.pdf',
      );
      final nonces = [
        for (final r in requests) r.url.queryParameters['cacheNonce'],
      ];
      expect(nonces, everyElement(isNotNull));
      expect(nonces.toSet(), hasLength(3));
    });

    test('pending copies select the bucket (default note-images)', () async {
      final copies = await source.pendingImageCopies();
      expect(requests.single.url.queryParameters['select'], contains('bucket'));
      expect(copies.map((c) => c.bucket), ['attachments', 'note-images']);
    });

    test('copy and remove target the given bucket', () async {
      await source.copyImage('a', 'b', bucket: SyncTables.attachmentsBucket);
      await source.removeImages(['x'], bucket: SyncTables.attachmentsBucket);
      final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(body['bucketId'], 'attachments');
      expect(requests.last.url.path, '/storage/v1/object/attachments');
    });
  });
}
