import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/local_deck_repository.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_organization_repository.dart';
import 'package:quiz_app/data/repositories/local_quiz_repository.dart';
import 'package:quiz_app/data/repositories/local_review_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';
import 'package:quiz_app/data/repositories/repository_support.dart';
import 'package:quiz_app/data/repositories/study_activity_repository.dart';

import 'support/test_db.dart';

void main() {
  final h = TestHive();
  late DataContext ctx;
  late LocalOrganizationRepository org;
  late LocalSubjectRepository subjects;
  late LocalNoteRepository notes;
  late LocalQuizRepository quizzes;
  late LocalDeckRepository decks;

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    ctx = h.context();
    org = LocalOrganizationRepository(ctx);
    subjects = LocalSubjectRepository(ctx);
    notes = LocalNoteRepository(ctx);
    quizzes = LocalQuizRepository(ctx);
    decks = LocalDeckRepository(ctx);
  });

  tearDown(h.tearDown);

  group('tags', () {
    test('normalizeTags trims, lowercases, dedupes, strips #', () {
      expect(normalizeTags([' Math ', 'math', '#Exam  Prep', '', '  ', '##']), [
        'math',
        'exam prep',
      ]);
      expect(normalizeTag('x' * 100)!.length, TagRules.maxTagLength);
    });

    test('old JSON without the new keys decodes with defaults', () {
      final json = {
        'id': 'n',
        'subject_id': 's',
        'owner_id': 'u',
        'title': 'T',
        'content_md': '',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'deleted_at': null,
      };
      final note = Note.fromJson(json);
      expect(note.tags, isEmpty);
      expect(note.pinned, isFalse);
      expect(note.toJson()['tags'], isEmpty);
      expect(note.toJson()['pinned'], isFalse);
      final subject = Subject.fromJson({
        'id': 's',
        'owner_id': 'u',
        'title': 'S',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(subject.pinned, isFalse);
      expect(subject.archivedAt, isNull);
      expect(subject.isArchived, isFalse);
      expect(subject.toJson().containsKey('archived_at'), isTrue);
      for (final decoded in [
        Quiz.fromJson({...json, 'tags': null}),
        Deck.fromJson({...json, 'tags': null}),
      ]) {
        expect(decoded.toJson()['tags'], isEmpty);
      }
    });

    test('set / add / remove tags on notes, quizzes and decks', () async {
      final s = await subjects.create(title: 'S');
      final n = await notes.create(subjectId: s.id, title: 'N');
      final q = await quizzes.create(subjectId: s.id, title: 'Q');
      final d = await decks.create(subjectId: s.id, title: 'D');

      await org.setTags(TaggableKind.note, n.id, ['B', 'a', 'b']);
      expect(h.db.notes.get(n.id)!.tags, ['b', 'a']);
      await org.addTag(TaggableKind.quiz, q.id, ' Exam ');
      await org.addTag(TaggableKind.quiz, q.id, 'exam');
      expect(h.db.quizzes.get(q.id)!.tags, ['exam']);
      await org.addTag(TaggableKind.deck, d.id, 'a');
      await org.removeTag(TaggableKind.note, n.id, 'B');
      expect(h.db.notes.get(n.id)!.tags, ['a']);

      expect(await org.watchTags().first, const [
        TagCount('a', 2),
        TagCount('exam', 1),
      ]);
      expect(await org.watchTags(kind: TaggableKind.quiz).first, const [
        TagCount('exam', 1),
      ]);

      expect(
        () => org.setTags(TaggableKind.note, n.id, [
          for (var i = 0; i < 51; i++) 't$i',
        ]),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => org.addTag(TaggableKind.note, 'missing', 'x'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('no write when nothing changes', () async {
      final s = await subjects.create(title: 'S');
      final n = await notes.create(subjectId: s.id, title: 'N');
      await h.db.outbox.clear();
      await org.setTags(TaggableKind.note, n.id, const []);
      await org.setPinned(TaggableKind.note, n.id, false);
      await org.removeTag(TaggableKind.note, n.id, 'x');
      expect(h.db.outbox.length, 0);
      await org.setPinned(TaggableKind.note, n.id, true);
      expect(h.db.outbox.pending().single.payload!['pinned'], isTrue);
    });

    test('shared items are read-only', () async {
      final now = DateTime.utc(2026);
      await h.db.notes.put(
        Note(
          id: 'shared',
          subjectId: 's',
          ownerId: 'user-b',
          title: 'N',
          tags: const ['x'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(
        () => org.setPinned(TaggableKind.note, 'shared', true),
        throwsA(isA<PermissionDeniedException>()),
      );
      // ...but their tags are counted.
      expect(await org.watchTags().first, const [TagCount('x', 1)]);
      // renameTag only touches own items.
      expect(await org.renameTag('x', 'y'), 0);
    });

    test('renameTag merges, deleteTag removes', () async {
      final s = await subjects.create(title: 'S');
      final n = await notes.create(subjectId: s.id, title: 'N');
      final q = await quizzes.create(subjectId: s.id, title: 'Q');
      await org.setTags(TaggableKind.note, n.id, ['old', 'new']);
      await org.setTags(TaggableKind.quiz, q.id, ['old']);
      expect(await org.renameTag('OLD', 'New'), 2);
      expect(h.db.notes.get(n.id)!.tags, ['new']);
      expect(h.db.quizzes.get(q.id)!.tags, ['new']);
      expect(await org.deleteTag('new'), 2);
      expect(await org.watchTags().first, isEmpty);
      expect(
        () => org.renameTag('a', '  '),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('lists', () {
    test('filter by tags / pinned / subject / note; sort modes', () async {
      final s1 = await subjects.create(title: 'S1');
      final s2 = await subjects.create(title: 'S2');
      final a = await notes.create(subjectId: s1.id, title: 'banana');
      final b = await notes.create(subjectId: s1.id, title: 'Apple');
      final c = await notes.create(subjectId: s2.id, title: 'cherry');
      await org.setTags(TaggableKind.note, a.id, ['fruit', 'yellow']);
      await org.setTags(TaggableKind.note, b.id, ['fruit']);
      await org.setPinned(TaggableKind.note, c.id, true);

      Future<List<String>> titles(ItemListQuery q) async =>
          (await org.watchNotes(q).first).map((n) => n.title).toList();

      // recent: c (pinned) first, then by updatedAt desc.
      expect(await titles(const ItemListQuery()), [
        'cherry',
        'Apple',
        'banana',
      ]);
      expect(await titles(const ItemListQuery(sort: ItemSort.name)), [
        'cherry',
        'Apple',
        'banana',
      ]);
      expect(
        await titles(
          const ItemListQuery(sort: ItemSort.name, pinnedFirst: false),
        ),
        ['Apple', 'banana', 'cherry'],
      );
      expect(
        await titles(
          const ItemListQuery(sort: ItemSort.created, pinnedFirst: false),
        ),
        ['cherry', 'Apple', 'banana'],
      );
      expect(await titles(const ItemListQuery(tags: {'Fruit'})), [
        'Apple',
        'banana',
      ]);
      expect(await titles(const ItemListQuery(tags: {'fruit', 'yellow'})), [
        'banana',
      ]);
      expect(await titles(const ItemListQuery(pinnedOnly: true)), ['cherry']);
      expect(await titles(ItemListQuery(subjectId: s1.id)), [
        'Apple',
        'banana',
      ]);

      final q = await quizzes.create(
        subjectId: s1.id,
        noteId: a.id,
        title: 'Q',
      );
      await quizzes.create(subjectId: s1.id, title: 'Other');
      expect(
        (await org.watchQuizzes(ItemListQuery(noteId: a.id)).first).single.id,
        q.id,
      );
      expect(await org.watchDecks().first, isEmpty);
    });

    test('streams update on change', () async {
      final s = await subjects.create(title: 'S');
      final n = await notes.create(subjectId: s.id, title: 'N');
      final stream = org.watchNotes(const ItemListQuery(pinnedOnly: true));
      final seen = <int>[];
      final sub = stream.listen((l) => seen.add(l.length));
      await eventually(() => seen.isNotEmpty);
      await org.setPinned(TaggableKind.note, n.id, true);
      await eventually(() => seen.length >= 2);
      await sub.cancel();
      expect(seen, [0, 1]);
    });

    test('query equality (provider family keys)', () {
      expect(
        const ItemListQuery(tags: {'a', 'b'}),
        const ItemListQuery(tags: {'b', 'a'}),
      );
      expect(
        const ItemListQuery(tags: {'a', 'b'}).hashCode,
        const ItemListQuery(tags: {'b', 'a'}).hashCode,
      );
      expect(
        const ItemListQuery(),
        isNot(const ItemListQuery(sort: ItemSort.name)),
      );
      expect(
        const ItemListQuery().copyWith(subjectId: () => 's'),
        const ItemListQuery(subjectId: 's'),
      );
      expect(const SubjectListQuery(), const SubjectListQuery());
    });
  });

  group('subjects: pin and archive', () {
    test('archived subjects are hidden by default but accessible', () async {
      final a = await subjects.create(title: 'Alpha');
      final b = await subjects.create(title: 'Beta');
      final c = await subjects.create(title: 'Gamma');
      await org.setSubjectPinned(c.id, true);
      expect((await subjects.watchAll().first).map((s) => s.title), [
        'Gamma',
        'Alpha',
        'Beta',
      ]);

      final archived = await org.archiveSubject(b.id);
      expect(archived.archivedAt, isNotNull);
      expect(await org.archiveSubject(b.id), archived); // no-op
      expect((await subjects.watchAll().first).map((s) => s.title), [
        'Gamma',
        'Alpha',
      ]);
      expect(
        (await org
                .watchSubjects(
                  const SubjectListQuery(archive: ArchiveFilter.archived),
                )
                .first)
            .single
            .id,
        b.id,
      );
      expect(
        await org
            .watchSubjects(const SubjectListQuery(archive: ArchiveFilter.all))
            .first,
        hasLength(3),
      );
      expect(await subjects.getById(b.id), isNotNull);

      // Items of an archived subject: hidden from cross-subject lists and
      // tag counts, shown inside the subject.
      final n = await notes.create(subjectId: b.id, title: 'Hidden');
      await org.addTag(TaggableKind.note, n.id, 't');
      await notes.create(subjectId: a.id, title: 'Shown');
      expect((await org.watchNotes().first).map((x) => x.title), ['Shown']);
      expect(
        await org.watchNotes(const ItemListQuery(includeArchived: true)).first,
        hasLength(2),
      );
      expect(
        (await org.watchNotes(ItemListQuery(subjectId: b.id)).first).single.id,
        n.id,
      );
      expect(await org.watchTags().first, isEmpty);
      expect(await org.watchTags(subjectId: b.id).first, const [
        TagCount('t', 1),
      ]);

      final restored = await org.unarchiveSubject(b.id);
      expect(restored.archivedAt, isNull);
      expect(await subjects.watchAll().first, hasLength(3));
      // A later edit keeps pin / archive state.
      final edited = await subjects.update(
        (await subjects.getById(c.id))!.copyWith(title: 'Gamma 2'),
      );
      expect(edited.pinned, isTrue);
    });

    test('archived subjects leave the study queue and dashboard', () async {
      final s = await subjects.create(title: 'S');
      final other = await subjects.create(title: 'Other');
      final deck = await decks.create(
        subjectId: s.id,
        title: 'D',
        cards: const [Flashcard(id: 'c1', front: 'f', back: 'b')],
      );
      await decks.create(
        subjectId: other.id,
        title: 'D2',
        cards: const [Flashcard(id: 'c2', front: 'f', back: 'b')],
      );
      final reviews = LocalReviewRepository(ctx);
      expect((await reviews.watchDue().first).count, 2);
      await org.archiveSubject(s.id);
      expect((await reviews.watchDue().first).count, 1);
      // The deck itself can still be studied.
      expect((await reviews.watchDue(deckId: deck.id).first).count, 1);

      final snapshot = await LocalStudyActivityRepository(ctx)
          .watchSnapshot()
          .first;
      expect(snapshot.subjects.map((x) => x.id), [other.id]);
      expect(snapshot.decks.map((d) => d.title), ['D2']);
    });

    test('shared subjects cannot be archived', () async {
      final now = DateTime.utc(2026);
      await h.db.subjects.put(
        Subject(
          id: 'sh',
          ownerId: 'user-b',
          title: 'S',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(
        () => org.archiveSubject('sh'),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(
        (await org
                .watchSubjects(const SubjectListQuery(includeShared: true))
                .first)
            .single
            .id,
        'sh',
      );
      expect(await org.watchSubjects().first, isEmpty);
    });
  });
}
