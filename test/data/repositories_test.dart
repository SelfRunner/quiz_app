import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/local_attempt_repository.dart';
import 'package:quiz_app/data/repositories/local_image_store.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_quiz_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';

import 'support/fake_remote.dart';
import 'support/test_db.dart';

void main() {
  final h = TestHive();
  late LocalSubjectRepository subjects;
  late LocalNoteRepository notes;
  late LocalQuizRepository quizzes;
  late LocalAttemptRepository attempts;

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    final ctx = h.context();
    subjects = LocalSubjectRepository(ctx);
    notes = LocalNoteRepository(ctx);
    quizzes = LocalQuizRepository(ctx);
    attempts = LocalAttemptRepository(ctx);
  });
  tearDown(h.tearDown);

  /// A subject owned by someone else, as pulled by sync.
  Future<Subject> putForeignSubject() async {
    final s = Subject.fromJson(subjectRow('foreign-s', 'user-b'));
    await h.db.subjects.put(s);
    return s;
  }

  test('create sets owner, ids, timestamps and enqueues an upsert', () async {
    final s = await subjects.create(title: '  Biology ');
    expect(s.ownerId, 'user-a');
    expect(s.title, 'Biology');
    expect(s.createdAt, s.updatedAt);
    expect(h.db.subjects.get(s.id), s);
    final op = h.db.outbox.pending().single;
    expect(op.table, SyncTables.subjects);
    expect(op.op, OutboxOpType.upsert);
    expect(op.payload!['owner_id'], 'user-a');
  });

  test('update bumps updatedAt, keeps owner/createdAt, coalesces', () async {
    final s = await subjects.create(title: 'A');
    final updated = await subjects.update(
      s.copyWith(title: 'B', ownerId: 'evil', createdAt: DateTime.utc(2000)),
    );
    expect(updated.title, 'B');
    expect(updated.ownerId, 'user-a');
    expect(updated.createdAt, s.createdAt);
    expect(updated.updatedAt.isAfter(s.updatedAt), isTrue);
    final op = h.db.outbox.pending().single; // coalesced
    expect(op.payload!['title'], 'B');
  });

  test('validation and signed-out errors', () async {
    expect(
      () => subjects.create(title: '  '),
      throwsA(isA<ValidationException>()),
    );
    h.userId = null;
    expect(() => subjects.create(title: 'X'), throwsA(isA<AppAuthException>()));
  });

  group('read-only enforcement for shared items', () {
    test('updating or deleting a shared subject is denied', () async {
      final s = await putForeignSubject();
      expect(
        () => subjects.update(s.copyWith(title: 'hacked')),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(
        () => subjects.delete(s.id),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(h.db.outbox.length, 0);
    });

    test('creating notes/quizzes inside a shared subject is denied', () async {
      final s = await putForeignSubject();
      expect(
        () => notes.create(subjectId: s.id, title: 'x'),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(
        () => quizzes.create(subjectId: s.id, title: 'x'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('editing a shared note is denied but attempts are allowed', () async {
      await putForeignSubject();
      final note = Note.fromJson(noteRow('fn', 'user-b', 'foreign-s'));
      await h.db.notes.put(note);
      final quiz = Quiz.fromJson(quizRow('fq', 'user-b', 'foreign-s'));
      await h.db.quizzes.put(quiz);
      expect(
        () => notes.update(note.copyWith(title: 'x')),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(
        () => quizzes.delete(quiz.id),
        throwsA(isA<PermissionDeniedException>()),
      );
      final attempt = await attempts.start(quizId: quiz.id, total: 3);
      expect(attempt.ownerId, 'user-a');
      final saved = await attempts.save(attempt.copyWith(score: 2));
      expect(saved.score, 2);
    });

    test('shared rows are readable through watch streams', () async {
      await putForeignSubject();
      await h.db.notes.put(Note.fromJson(noteRow('fn', 'user-b', 'foreign-s')));
      expect((await notes.watchBySubject('foreign-s').first).single.id, 'fn');
      // watchAll only lists own subjects.
      expect(await subjects.watchAll().first, isEmpty);
      expect((await subjects.watchById('foreign-s').first)?.id, 'foreign-s');
    });
  });

  test('watchAll is sorted by title and hides deleted subjects', () async {
    await subjects.create(title: 'beta');
    final alpha = await subjects.create(title: 'Alpha');
    await subjects.create(title: 'gamma');
    await subjects.delete((await subjects.watchAll().first).last.id);
    final list = await subjects.watchAll().first;
    expect(list.map((s) => s.title), ['Alpha', 'beta']);
    expect(list.first, alpha);
  });

  test('deleting a subject cascades to notes, quizzes and images', () async {
    final s = await subjects.create(title: 'S');
    final n = await notes.create(subjectId: s.id, title: 'N');
    final noteQuiz = await quizzes.create(
      subjectId: s.id,
      noteId: n.id,
      title: 'NQ',
    );
    final subjectQuiz = await quizzes.create(subjectId: s.id, title: 'SQ');
    final images = LocalImageStore(h.context(), FakeRemote(userId: 'user-a'));
    final ref = await images.saveNoteImage(
      noteId: n.id,
      bytes: Uint8List.fromList([1, 2, 3]),
      extension: 'png',
    );
    await notes.update(n.copyWith(contentMd: '![](${ref.markdownUrl})'));

    await subjects.delete(s.id);

    for (final id in [n.id]) {
      expect(h.db.notes.get(id)!.isDeleted, isTrue);
    }
    expect(h.db.quizzes.get(noteQuiz.id)!.isDeleted, isTrue);
    expect(h.db.quizzes.get(subjectQuiz.id)!.isDeleted, isTrue);
    expect(h.db.subjects.get(s.id)!.isDeleted, isTrue);
    expect(await notes.watchBySubject(s.id).first, isEmpty);
    expect(await quizzes.watchBySubject(s.id).first, isEmpty);

    final ops = h.db.outbox.pending();
    // Tombstones are queued as upserts with deleted_at set.
    final upserts = ops.where((o) => o.op == OutboxOpType.upsert);
    expect(upserts.every((o) => o.payload!['deleted_at'] != null), isTrue);
    expect(upserts.map((o) => o.rowId).toSet(), {
      s.id,
      n.id,
      noteQuiz.id,
      subjectQuiz.id,
    });
    // Pending upload replaced by a delete of the image.
    expect(ops.where((o) => o.op == OutboxOpType.uploadImage), isEmpty);
    expect(
      ops.singleWhere((o) => o.op == OutboxOpType.deleteImage).rowId,
      ref.storagePath,
    );
    expect(await h.db.images.read(ref.storagePath), isNull);
  });

  test('deleting a note cascades to its quizzes only', () async {
    final s = await subjects.create(title: 'S');
    final n = await notes.create(subjectId: s.id, title: 'N');
    final q1 = await quizzes.create(subjectId: s.id, noteId: n.id, title: 'a');
    final q2 = await quizzes.create(subjectId: s.id, title: 'b');
    await notes.delete(n.id);
    expect(h.db.quizzes.get(q1.id)!.isDeleted, isTrue);
    expect(h.db.quizzes.get(q2.id)!.isDeleted, isFalse);
    expect(h.db.subjects.get(s.id)!.isDeleted, isFalse);
  });

  test(
    'quiz must use its note subject; moving a note moves its quizzes',
    () async {
      final s1 = await subjects.create(title: 'S1');
      final s2 = await subjects.create(title: 'S2');
      final n = await notes.create(subjectId: s1.id, title: 'N');
      expect(
        () => quizzes.create(subjectId: s2.id, noteId: n.id, title: 'x'),
        throwsA(isA<ValidationException>()),
      );
      final q = await quizzes.create(
        subjectId: s1.id,
        noteId: n.id,
        title: 'q',
      );
      await notes.update(n.copyWith(subjectId: s2.id));
      expect(h.db.quizzes.get(q.id)!.subjectId, s2.id);
      expect((await quizzes.watchByNote(n.id).first).single.id, q.id);
    },
  );

  test('attempts: newest first, own only', () async {
    final first = await attempts.start(quizId: 'q', total: 2);
    final second = await attempts.start(quizId: 'q', total: 2);
    await h.db.attempts.put(first.copyWith(id: 'other', ownerId: 'user-b'));
    final list = await attempts.watchByQuiz('q').first;
    expect(list.map((a) => a.id), [second.id, first.id]);
    expect(
      () => attempts.save(first.copyWith(id: 'other', ownerId: 'user-b')),
      throwsA(isA<PermissionDeniedException>()),
    );
    await attempts.delete(first.id);
    expect((await attempts.watchByQuiz('q').first).single.id, second.id);
  });
}
