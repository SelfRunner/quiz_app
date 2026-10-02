import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/providers.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/local_attachment_repository.dart';
import 'package:quiz_app/data/repositories/local_chat_repository.dart';
import 'package:quiz_app/data/repositories/local_deck_repository.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_organization_repository.dart';
import 'package:quiz_app/data/repositories/local_quiz_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';
import 'package:quiz_app/data/repositories/repository_support.dart';
import 'package:quiz_app/search/live_search_index.dart';
import 'package:quiz_app/search/search_documents.dart';
import 'package:quiz_app/search/search_models.dart';
import 'package:quiz_app/search/search_providers.dart';

import '../data/support/fake_remote.dart';
import '../data/support/test_db.dart';

void main() {
  group('LiveSearchIndex', () {
    test('diffs source lists and emits revisions once ready', () async {
      final notes = StreamController<List<Note>>();
      final subjects = StreamController<List<Subject>>();
      final live = LiveSearchIndex()
        ..attach<Note>(
          type: SearchItemType.note,
          source: notes.stream,
          id: (n) => n.id,
          toDocument: noteDocument,
        )
        ..attach<Subject>(
          type: SearchItemType.subject,
          source: subjects.stream,
          id: (s) => s.id,
          toDocument: subjectDocument,
        );
      final revisions = <int>[];
      final sub = live.revisions.listen(revisions.add);
      final t = DateTime.utc(2026);
      Note note(String id, String title) => Note(
        id: id,
        subjectId: 's',
        ownerId: 'u',
        title: title,
        createdAt: t,
        updatedAt: t,
      );

      final a = note('a', 'Alpha');
      notes.add([a, note('b', 'Beta')]);
      await pumpEvents();
      expect(live.isReady, isFalse);
      expect(revisions, isEmpty);
      subjects.add(const []);
      await pumpEvents();
      expect(live.isReady, isTrue);
      expect(revisions, hasLength(1));
      expect(live.index.length, 2);

      // Same (or equal) items: no change, no revision.
      notes.add([a, note('b', 'Beta')]);
      await pumpEvents();
      expect(revisions, hasLength(1));

      notes.add([a.copyWith(title: 'Alpha prime')]);
      await pumpEvents();
      expect(revisions, hasLength(2));
      expect(live.index.length, 1);
      expect(live.search('prime').single.id, 'a');

      await sub.cancel();
      await live.dispose();
      await notes.close();
      await subjects.close();
    });
  });

  group('searchProvider', () {
    final h = TestHive();
    late ProviderContainer container;
    late DataContext ctx;

    setUp(() async {
      await h.setUp();
      ctx = h.context();
      final remote = FakeRemote(userId: 'user-a');
      container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(h.clockFn),
          currentUserIdProvider.overrideWithValue('user-a'),
          subjectRepositoryProvider.overrideWithValue(
            LocalSubjectRepository(ctx),
          ),
          noteRepositoryProvider.overrideWithValue(LocalNoteRepository(ctx)),
          quizRepositoryProvider.overrideWithValue(LocalQuizRepository(ctx)),
          deckRepositoryProvider.overrideWithValue(LocalDeckRepository(ctx)),
          attachmentRepositoryProvider.overrideWithValue(
            LocalAttachmentRepository(ctx, remote),
          ),
          chatRepositoryProvider.overrideWithValue(LocalChatRepository(ctx)),
          organizationRepositoryProvider.overrideWithValue(
            LocalOrganizationRepository(ctx),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await h.tearDown();
    });

    Future<List<SearchResult>> results(
      String query, [
      SearchFilters filters = const SearchFilters(),
    ]) async {
      final request = (query: query, filters: filters);
      final sub = container.listen(searchProvider(request), (_, _) {});
      try {
        await eventually(
          () => container.read(searchProvider(request)).hasValue,
        );
        return container.read(searchProvider(request)).requireValue;
      } finally {
        sub.close();
      }
    }

    test('indexes every source and follows repository changes', () async {
      final s = await LocalSubjectRepository(ctx).create(title: 'Biology');
      final n = await LocalNoteRepository(ctx).create(
        subjectId: s.id,
        title: 'Cells',
        contentMd: '# Organelles\nThe **mitochondria** makes energy.',
      );
      await LocalQuizRepository(ctx).create(
        subjectId: s.id,
        title: 'Quiz 1',
        questions: const [
          Question(
            id: 'q1',
            type: QuestionType.mcqSingle,
            prompt: 'Which organelle makes ATP?',
            options: ['Ribosome', 'Mitochondria'],
            correctIndices: [1],
          ),
        ],
      );
      await LocalDeckRepository(ctx).create(
        subjectId: s.id,
        title: 'Deck',
        cards: const [Flashcard(id: 'c', front: 'Mitochondria', back: 'ATP')],
      );
      await LocalAttachmentRepository(ctx, FakeRemote(userId: 'user-a')).add(
        subjectId: s.id,
        name: 'lecture.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
        extractedText: 'Mitochondria have their own DNA',
      );
      final chat = await LocalChatRepository(ctx).create(
        scopeType: ChatScopeType.note,
        scopeId: n.id,
        title: 'Mitochondria Q&A',
      );

      final hits = await results('mitochondria');
      expect(hits.map((r) => r.type).toSet(), {
        SearchItemType.note,
        SearchItemType.quiz,
        SearchItemType.deck,
        SearchItemType.attachment,
        SearchItemType.chat,
      });
      final chatHit = hits.firstWhere((r) => r.type == SearchItemType.chat);
      expect(chatHit.id, chat.id);
      expect(chatHit.document.subjectId, s.id);
      expect(hits.first.subjectTitle, 'Biology');
      expect((await results('biology')).single.type, SearchItemType.subject);
      expect(
        (await results(
          'mitochondria',
          const SearchFilters(types: {SearchItemType.quiz}),
        )).single.type,
        SearchItemType.quiz,
      );

      // Incremental: edits, tags and archive are reflected.
      await LocalNoteRepository(ctx)
          .update(n.copyWith(contentMd: 'Now about chloroplasts'));
      await LocalOrganizationRepository(ctx)
          .addTag(TaggableKind.note, n.id, 'exam');
      await eventually(
        () => container
            .read(searchIndexProvider)
            .search('chloroplasts')
            .isNotEmpty,
      );
      expect(
        (await results('', const SearchFilters(tags: {'exam'}))).single.id,
        n.id,
      );
      await LocalOrganizationRepository(ctx).archiveSubject(s.id);
      await eventually(
        () => container
            .read(searchIndexProvider)
            .index
            .archivedSubjectIds
            .contains(s.id),
      );
      expect(
        await results(
          'chloroplasts',
          const SearchFilters(includeArchived: false),
        ),
        isEmpty,
      );
      expect((await results('chloroplasts')).single.archived, isTrue);

      await LocalNoteRepository(ctx).delete(n.id);
      await eventually(
        () =>
            container.read(searchIndexProvider).search('chloroplasts').isEmpty,
      );
    });
  });
}

/// Lets stream events propagate.
Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);
