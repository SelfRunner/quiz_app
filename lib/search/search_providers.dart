import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/data_providers.dart';
import '../data/models/models.dart';
import '../data/repositories/organization_repository.dart';
import 'live_search_index.dart';
import 'search_documents.dart';
import 'search_models.dart';

/// Search query + filters (family key of [searchProvider]).
typedef SearchRequest = ({String query, SearchFilters filters});

/// The live local search index over everything the user can read:
/// subjects (incl. archived and shared), notes, quizzes, decks,
/// attachments and chats. Kept alive for 5 minutes after the last
/// listener so reopening search is instant; rebuilt on account switch.
final searchIndexProvider = Provider.autoDispose<LiveSearchIndex>((ref) {
  ref.watch(currentUserIdProvider);
  final org = ref.watch(organizationRepositoryProvider);
  final notes = ref.watch(noteRepositoryProvider);
  final decks = ref.watch(deckRepositoryProvider);
  final attachments = ref.watch(attachmentRepositoryProvider);
  final chats = ref.watch(chatRepositoryProvider);

  final live = LiveSearchIndex();
  final index = live.index;
  live
    ..attach<Subject>(
      type: SearchItemType.subject,
      source: org.watchSubjects(
        const SubjectListQuery(
          archive: ArchiveFilter.all,
          includeShared: true,
          pinnedFirst: false,
        ),
      ),
      id: (s) => s.id,
      toDocument: subjectDocument,
      onList: (subjects) {
        final archived = {
          for (final s in subjects)
            if (s.archivedAt != null) s.id,
        };
        final changed =
            archived.length != index.archivedSubjectIds.length ||
            !archived.containsAll(index.archivedSubjectIds);
        index
          ..archivedSubjectIds = archived
          ..subjectTitles = {for (final s in subjects) s.id: s.title};
        return changed;
      },
    )
    ..attach<Note>(
      type: SearchItemType.note,
      source: notes.watchAllAccessible(),
      id: (n) => n.id,
      toDocument: noteDocument,
    )
    ..attach<Quiz>(
      type: SearchItemType.quiz,
      source: org.watchQuizzes(
        const ItemListQuery(includeArchived: true, pinnedFirst: false),
      ),
      id: (q) => q.id,
      toDocument: quizDocument,
    )
    ..attach<Deck>(
      type: SearchItemType.deck,
      source: decks.watchAllAccessible(),
      id: (d) => d.id,
      toDocument: deckDocument,
    )
    ..attach<Attachment>(
      type: SearchItemType.attachment,
      source: attachments.watchAllAccessible(),
      id: (a) => a.id,
      toDocument: attachmentDocument,
    )
    ..attach<Chat>(
      type: SearchItemType.chat,
      source: chats.watchAll(),
      id: (c) => c.id,
      toDocument: (c) => chatDocument(
        c,
        subjectId: switch (c.scopeType) {
          ChatScopeType.note =>
            index.document(SearchItemType.note, c.scopeId!)?.subjectId,
          ChatScopeType.attachment =>
            index.document(SearchItemType.attachment, c.scopeId!)?.subjectId,
          _ => null,
        },
      ),
    );

  final link = ref.keepAlive();
  Timer? timer;
  ref
    ..onCancel(() => timer = Timer(const Duration(minutes: 5), link.close))
    ..onResume(() => timer?.cancel())
    ..onDispose(() {
      timer?.cancel();
      unawaited(live.dispose());
    });
  return live;
});

/// Index revision: loading until every source has been indexed once, then
/// a new value after every change.
final searchRevisionProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(searchIndexProvider).revisions,
);

/// Ranked results (max 50) for `(query: ..., filters: ...)`; recomputed
/// when the index changes. Empty query + no filters -> no results; empty
/// query + filters -> most recent matching items.
final searchProvider = Provider.autoDispose
    .family<AsyncValue<List<SearchResult>>, SearchRequest>((ref, request) {
      final revision = ref.watch(searchRevisionProvider);
      final index = ref.watch(searchIndexProvider);
      final now = ref.watch(clockProvider)();
      return revision.whenData(
        (_) => index.search(request.query, filters: request.filters, now: now),
      );
    });
