import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/deck_repository.dart';
import 'package:quiz_app/data/repositories/review_repository.dart';
import 'package:quiz_app/features/ai_generate/presentation/ai_generate_screen.dart';
import 'package:quiz_app/features/decks/presentation/deck_detail_screen.dart';
import 'package:quiz_app/features/decks/presentation/deck_edit_screen.dart';
import 'package:quiz_app/features/decks/presentation/deck_study_screen.dart';
import 'package:quiz_app/features/study/presentation/study_queue_screen.dart';
import 'package:quiz_app/study/due_queue.dart';
import 'package:quiz_app/study/fsrs.dart';

import '../../ai_generate/support/ai_fakes.dart';
import '../../quizzes/support/fakes.dart';

/// UTC = local in these tests.
DateTime _utc(DateTime t) => t.toUtc();

class FakeDeckRepository implements DeckRepository {
  final Map<String, Deck> rows = {};
  final List<Deck> updates = [];
  final List<Deck> created = [];
  final _changes = StreamController<void>.broadcast();

  List<Deck> get live => rows.values.where((d) => d.deletedAt == null).toList();

  Deck put(Deck d) {
    rows[d.id] = d;
    _changes.add(null);
    return d;
  }

  Stream<R> _watch<R>(R Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  Stream<void> get changes => _changes.stream;

  @override
  Stream<List<Deck>> watchBySubject(String subjectId) =>
      _watch(() => live.where((d) => d.subjectId == subjectId).toList());

  @override
  Stream<List<Deck>> watchByNote(String noteId) =>
      _watch(() => live.where((d) => d.noteId == noteId).toList());

  @override
  Stream<List<Deck>> watchAllAccessible() => _watch(() => live);

  @override
  Stream<Deck?> watchById(String id) => _watch(() {
    final d = rows[id];
    return d == null || d.deletedAt != null ? null : d;
  });

  @override
  Future<Deck?> getById(String id) async => rows[id];

  @override
  Future<Deck> create({
    required String subjectId,
    String? noteId,
    required String title,
    String? description,
    List<Flashcard> cards = const [],
    QuizSource? source,
  }) async {
    final d = put(
      Deck(
        id: nextId(),
        subjectId: subjectId,
        noteId: noteId,
        ownerId: userId,
        title: title,
        description: description,
        cards: cards,
        source: source,
        createdAt: fixedNow,
        updatedAt: fixedNow,
      ),
    );
    created.add(d);
    return d;
  }

  @override
  Future<Deck> update(Deck deck) async {
    if (deck.ownerId != userId) {
      throw const PermissionDeniedException('Read-only');
    }
    updates.add(deck);
    return put(deck);
  }

  @override
  Future<void> delete(String id) async {
    final d = rows[id];
    if (d != null) put(d.copyWith(deletedAt: fixedNow));
  }
}

/// One recorded rating.
typedef ReviewCall = ({String deckId, String cardId, Rating rating});

/// In-memory review state scheduled with real FSRS (no fuzz) at [now].
class FakeReviewRepository implements ReviewRepository {
  FakeReviewRepository(this.decks);

  final FakeDeckRepository decks;
  final Map<String, CardReview> rows = {};
  final List<ReviewCall> calls = [];
  final _changes = StreamController<void>.broadcast();
  DateTime now = fixedNow;
  int newCardsPerDay = 20;
  final _fsrs = Fsrs();

  void put(CardReview r) {
    rows['${r.deckId}/${r.cardId}'] = r;
    _changes.add(null);
  }

  Stream<R> _watch<R>(R Function() read) async* {
    yield read();
    yield* StreamGroup.merge(_changes.stream, decks.changes).map((_) => read());
  }

  void _requireCard(String deckId, String cardId) {
    final d = decks.rows[deckId];
    if (d == null ||
        d.deletedAt != null ||
        !d.cards.any((c) => c.id == cardId)) {
      throw const NotFoundException('This card no longer exists.');
    }
  }

  @override
  Future<CardReview> recordReview({
    required String deckId,
    required String cardId,
    required Rating rating,
  }) async {
    _requireCard(deckId, cardId);
    calls.add((deckId: deckId, cardId: cardId, rating: rating));
    final existing = rows['$deckId/$cardId'];
    final next = _fsrs.review(
      existing?.toFsrs() ?? FsrsCard.newCard(now),
      rating,
      now,
    );
    final row =
        (existing ??
                CardReview(
                  id: CardReview.idFor(
                    ownerId: userId,
                    deckId: deckId,
                    cardId: cardId,
                  ),
                  ownerId: userId,
                  deckId: deckId,
                  cardId: cardId,
                  dueAt: now,
                  createdAt: now,
                  updatedAt: now,
                ))
            .withFsrs(next);
    put(row);
    return row;
  }

  @override
  Future<Map<Rating, DateTime>> previewDue({
    required String deckId,
    required String cardId,
  }) async {
    _requireCard(deckId, cardId);
    final base = rows['$deckId/$cardId']?.toFsrs() ?? FsrsCard.newCard(now);
    return {
      for (final e in _fsrs.preview(base, now).entries) e.key: e.value.due,
    };
  }

  DueQueue queue({String? deckId}) => buildDueQueue(
    decks: decks.live,
    reviews: rows.values,
    now: now,
    newCardsPerDay: newCardsPerDay,
    deckId: deckId,
    toLocal: _utc,
  );

  @override
  Stream<DueQueue> watchDue({DateTime? now, String? deckId}) =>
      _watch(() => queue(deckId: deckId));

  @override
  Stream<int> watchDueCount({DateTime? now}) => _watch(() => queue().count);

  @override
  Stream<DeckStats> watchDeckStats(String deckId, {DateTime? now}) =>
      _watch(() {
        final d = decks.rows[deckId];
        return d == null
            ? const DeckStats()
            : deckStats(d, rows.values, now: this.now, toLocal: _utc);
      });

  @override
  Stream<List<CardReview>> watchAll() => _watch(() => rows.values.toList());

  @override
  Future<void> resetCard({
    required String deckId,
    required String cardId,
  }) async {
    rows.remove('$deckId/$cardId');
    _changes.add(null);
  }
}

/// Minimal merge of broadcast streams (avoids a package:async dependency).
abstract final class StreamGroup {
  static Stream<T> merge<T>(Stream<T> a, Stream<T> b) {
    late StreamController<T> c;
    StreamSubscription<T>? sa, sb;
    c = StreamController<T>(
      onListen: () {
        sa = a.listen(c.add);
        sb = b.listen(c.add);
      },
      onCancel: () async {
        await sa?.cancel();
        await sb?.cancel();
      },
    );
    return c.stream;
  }
}

/// AI service whose structured generation returns [deckJson].
class FakeDeckAiService extends FakeAiService {
  FakeDeckAiService({super.selection});

  final List<StructuredGenerationRequest> structuredRequests = [];
  Map<String, dynamic> deckJson = {
    'title': 'Cells',
    'description': 'Cell biology basics',
    'cards': [
      {
        'front': 'Powerhouse of the cell?',
        'back': 'Mitochondria',
        'hint': null,
      },
      {'front': 'Control center of the cell?', 'back': 'Nucleus', 'hint': 'N…'},
    ],
  };

  @override
  Future<T> generateStructured<T>(
    StructuredGenerationRequest request, {
    required DraftValidation<T> Function(Map<String, dynamic> json) validate,
    String what = 'result',
  }) async {
    structuredRequests.add(request);
    final result = validate(deckJson);
    if (!result.isValid) {
      throw AiException(
        result.errors.join(' '),
        kind: AiErrorKind.invalidOutput,
      );
    }
    return result.value as T;
  }
}

Deck deck(
  String id,
  List<Flashcard> cards, {
  String owner = userId,
  String title = 'Biology',
  String subjectId = 's1',
  String? noteId,
  DateTime? createdAt,
}) => Deck(
  id: id,
  subjectId: subjectId,
  noteId: noteId,
  ownerId: owner,
  title: title,
  cards: cards,
  createdAt: createdAt ?? fixedNow,
  updatedAt: fixedNow,
);

Flashcard card(String id, String front, String back, {String? hint}) =>
    Flashcard(id: id, front: front, back: back, hint: hint);

/// [AiTestEnv] plus decks, reviews and the deck/study routes.
class DeckTestEnv extends AiTestEnv {
  DeckTestEnv() {
    deckAi.selection = ai.selection;
  }

  final decks = FakeDeckRepository();
  late final reviews = FakeReviewRepository(decks);
  final deckAi = FakeDeckAiService();

  @override
  List<Override> get extraOverrides => [
    ...super.extraOverrides,
    deckRepositoryProvider.overrideWithValue(decks),
    reviewRepositoryProvider.overrideWithValue(reviews),
  ];

  Widget deckApp(String initialLocation, {Widget? home}) {
    Widget label(String text) => Scaffold(body: Center(child: Text(text)));
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (_, _) => home ?? label('Home')),
        GoRoute(path: '/settings', builder: (_, _) => label('Settings page')),
        GoRoute(path: '/study', builder: (_, _) => const StudyQueueScreen()),
        GoRoute(
          path: '/subjects/:id',
          builder: (_, s) => label('Subject ${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/notes/:id',
          builder: (_, s) => label('Note ${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/decks/:id',
          builder: (_, s) => DeckDetailScreen(deckId: s.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, s) =>
                  DeckEditScreen(deckId: s.pathParameters['id']!),
            ),
            GoRoute(
              path: 'study',
              builder: (_, s) =>
                  DeckStudyScreen(deckId: s.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/ai/generate',
          builder: (_, s) {
            final q = s.uri.queryParameters;
            return AiGenerateScreen(
              kind: AiGenerateKind.values.byName(q['kind'] ?? 'quiz'),
              subjectId: q['subjectId'],
              noteId: q['noteId'],
            );
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      // Nested scope: the deck-aware AI fake replaces `ai` for the screens.
      child: ProviderScope(
        overrides: [aiServiceProvider.overrideWithValue(deckAi)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }
}
