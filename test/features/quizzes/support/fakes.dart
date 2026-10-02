import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/core/providers.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/attempt_repository.dart';
import 'package:quiz_app/data/repositories/note_repository.dart';
import 'package:quiz_app/data/repositories/quiz_repository.dart';
import 'package:quiz_app/data/repositories/subject_repository.dart';
import 'package:quiz_app/features/ai_generate/presentation/ai_generate_screen.dart';
import 'package:quiz_app/features/quizzes/presentation/quiz_detail_screen.dart';
import 'package:quiz_app/features/quizzes/presentation/quiz_edit_screen.dart';
import 'package:quiz_app/features/quizzes/presentation/quiz_play_screen.dart';

const userId = 'u1';
final fixedNow = DateTime.utc(2026, 1, 1, 12);

int _seq = 0;
String nextId() => 'id-${_seq++}';

/// Minimal in-memory table with change notifications.
class _Table<T> {
  final Map<String, T> rows = {};
  final _changes = StreamController<void>.broadcast();

  Stream<R> watch<R>(R Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  void put(String id, T value) {
    rows[id] = value;
    _changes.add(null);
  }
}

class FakeQuizRepository implements QuizRepository {
  final _t = _Table<Quiz>();
  final List<Quiz> updates = [];

  List<Quiz> get all => _t.rows.values.where((q) => !q.isDeleted).toList();

  Quiz add(Quiz quiz) {
    _t.put(quiz.id, quiz);
    return quiz;
  }

  @override
  Stream<List<Quiz>> watchBySubject(String subjectId) =>
      _t.watch(() => all.where((q) => q.subjectId == subjectId).toList());

  @override
  Stream<List<Quiz>> watchByNote(String noteId) =>
      _t.watch(() => all.where((q) => q.noteId == noteId).toList());

  @override
  Stream<Quiz?> watchById(String id) => _t.watch(() {
    final q = _t.rows[id];
    return q == null || q.isDeleted ? null : q;
  });

  @override
  Future<Quiz?> getById(String id) async => _t.rows[id];

  @override
  Future<Quiz> create({
    required String subjectId,
    String? noteId,
    required String title,
    String? description,
    List<Question> questions = const [],
    QuizSource? source,
  }) async => add(
    Quiz(
      id: nextId(),
      subjectId: subjectId,
      noteId: noteId,
      ownerId: userId,
      title: title,
      description: description,
      questions: questions,
      source: source,
      createdAt: fixedNow,
      updatedAt: fixedNow,
    ),
  );

  @override
  Future<Quiz> update(Quiz quiz) async {
    if (quiz.ownerId != userId) {
      throw const PermissionDeniedException('Read-only');
    }
    updates.add(quiz);
    return add(quiz);
  }

  @override
  Future<void> delete(String id) async {
    final q = _t.rows[id];
    if (q != null) add(q.copyWith(deletedAt: fixedNow));
  }
}

class FakeAttemptRepository implements AttemptRepository {
  final _t = _Table<QuizAttempt>();
  final List<QuizAttempt> saved = [];

  @override
  Stream<List<QuizAttempt>> watchByQuiz(String quizId) => _t.watch(
    () => _t.rows.values
        .where((a) => a.quizId == quizId)
        .toList()
        .reversed
        .toList(),
  );

  @override
  Stream<QuizAttempt?> watchById(String id) => _t.watch(() => _t.rows[id]);

  @override
  Future<QuizAttempt?> getById(String id) async => _t.rows[id];

  @override
  Future<QuizAttempt> start({
    required String quizId,
    required int total,
  }) async {
    final a = QuizAttempt(
      id: nextId(),
      quizId: quizId,
      ownerId: userId,
      total: total,
      startedAt: fixedNow,
      createdAt: fixedNow,
      updatedAt: fixedNow,
    );
    _t.put(a.id, a);
    return a;
  }

  @override
  Future<QuizAttempt> save(QuizAttempt attempt) async {
    saved.add(attempt);
    _t.put(attempt.id, attempt);
    return attempt;
  }

  @override
  Future<void> delete(String id) async {}
}

class FakeNoteRepository implements NoteRepository {
  final _t = _Table<Note>();
  final List<Note> created = [];

  Note add(Note n) {
    _t.put(n.id, n);
    return n;
  }

  @override
  Stream<List<Note>> watchBySubject(String subjectId) => _t.watch(
    () => _t.rows.values.where((n) => n.subjectId == subjectId).toList(),
  );

  @override
  Stream<List<Note>> watchAllAccessible() =>
      _t.watch(() => _t.rows.values.toList());

  @override
  Stream<Note?> watchById(String id) => _t.watch(() => _t.rows[id]);

  @override
  Future<Note?> getById(String id) async => _t.rows[id];

  @override
  Future<Note> create({
    required String subjectId,
    required String title,
    String contentMd = '',
  }) async {
    final n = add(
      Note(
        id: nextId(),
        subjectId: subjectId,
        ownerId: userId,
        title: title,
        contentMd: contentMd,
        createdAt: fixedNow,
        updatedAt: fixedNow,
      ),
    );
    created.add(n);
    return n;
  }

  @override
  Future<Note> update(Note note) async => add(note);

  @override
  Future<void> delete(String id) async {}
}

class FakeSubjectRepository implements SubjectRepository {
  final _t = _Table<Subject>();

  Subject add(Subject s) {
    _t.put(s.id, s);
    return s;
  }

  @override
  Stream<List<Subject>> watchAll() => _t.watch(() => _t.rows.values.toList());

  @override
  Stream<Subject?> watchById(String id) => _t.watch(() => _t.rows[id]);

  @override
  Future<Subject?> getById(String id) async => _t.rows[id];

  @override
  Future<Subject> create({
    required String title,
    String? description,
    int? color,
  }) async => add(
    Subject(
      id: nextId(),
      ownerId: userId,
      title: title,
      createdAt: fixedNow,
      updatedAt: fixedNow,
    ),
  );

  @override
  Future<Subject> update(Subject subject) async => add(subject);

  @override
  Future<void> delete(String id) async {}
}

class FakeAiService implements AiService {
  FakeAiService({this.selection, this.selectionError});

  AiSelection? selection;
  Object? selectionError;
  final List<QuizGenerationRequest> quizRequests = [];
  final List<NoteGenerationRequest> noteRequests = [];

  /// Responses; defaults return a fixed draft.
  Future<QuizDraft> Function(QuizGenerationRequest r)? onQuiz;
  Future<NoteDraft> Function(NoteGenerationRequest r)? onNote;

  @override
  Future<AiSelection> resolveSelection({
    LlmProviderId? providerId,
    String? model,
  }) async {
    if (selectionError != null) throw selectionError!;
    return selection ??
        (throw const AiException(
          'No API key',
          kind: AiErrorKind.missingApiKey,
        ));
  }

  @override
  Future<QuizDraft> generateQuiz(QuizGenerationRequest request) {
    quizRequests.add(request);
    return onQuiz?.call(request) ?? Future.value(sampleDraft);
  }

  @override
  Future<NoteDraft> generateNote(NoteGenerationRequest request) {
    noteRequests.add(request);
    return onNote?.call(request) ??
        Future.value(
          const NoteDraft(title: 'AI note', contentMarkdown: '# Heading'),
        );
  }

  @override
  Future<List<String>> listModels(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  }) async => const [];

  @override
  Future<void> testConnection(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  }) async {}
}

const sampleDraft = QuizDraft(
  title: 'Planets',
  description: 'Solar system basics',
  questions: [
    QuestionDraft(
      type: QuestionType.mcqSingle,
      prompt: 'Largest planet?',
      options: ['Mars', 'Jupiter', 'Venus'],
      correctIndices: [1],
    ),
    QuestionDraft(
      type: QuestionType.trueFalse,
      prompt: 'Pluto is a planet.',
      options: ['True', 'False'],
      correctIndices: [1],
    ),
  ],
);

Subject subject(String id, String title) => Subject(
  id: id,
  ownerId: userId,
  title: title,
  createdAt: fixedNow,
  updatedAt: fixedNow,
);

Quiz quiz(
  String id,
  List<Question> questions, {
  String owner = userId,
  String title = 'Sample quiz',
  String subjectId = 's1',
  String? noteId,
}) => Quiz(
  id: id,
  subjectId: subjectId,
  noteId: noteId,
  ownerId: owner,
  title: title,
  questions: questions,
  createdAt: fixedNow,
  updatedAt: fixedNow,
);

/// Everything a screen test needs.
class TestEnv {
  final quizzes = FakeQuizRepository();
  final attempts = FakeAttemptRepository();
  final notes = FakeNoteRepository();
  final subjects = FakeSubjectRepository();
  final ai = FakeAiService(
    selection: const AiSelection(
      providerId: LlmProviderId.openai,
      model: 'gpt-test',
    ),
  );

  List<Override> get overrides => [
    currentUserIdProvider.overrideWithValue(userId),
    quizRepositoryProvider.overrideWithValue(quizzes),
    attemptRepositoryProvider.overrideWithValue(attempts),
    noteRepositoryProvider.overrideWithValue(notes),
    subjectRepositoryProvider.overrideWithValue(subjects),
    aiServiceProvider.overrideWithValue(ai),
    clockProvider.overrideWithValue(() => fixedNow),
    idGeneratorProvider.overrideWithValue(nextId),
  ];

  /// App with the quizzes / AI routes and simple placeholders elsewhere.
  Widget app(String initialLocation, {Widget? home}) {
    Widget label(String text) => Scaffold(body: Center(child: Text(text)));
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (_, _) => home ?? label('Home')),
        GoRoute(path: '/settings', builder: (_, _) => label('Settings page')),
        GoRoute(
          path: '/subjects/:id',
          builder: (_, s) => label('Subject ${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/notes/:id',
          builder: (_, s) => label('Note ${s.pathParameters['id']}'),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, s) => label('Note editor ${s.pathParameters['id']}'),
            ),
          ],
        ),
        GoRoute(
          path: '/quizzes/:id',
          builder: (_, s) => QuizDetailScreen(quizId: s.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, s) =>
                  QuizEditScreen(quizId: s.pathParameters['id']!),
            ),
            GoRoute(
              path: 'play',
              builder: (_, s) =>
                  QuizPlayScreen(quizId: s.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/ai/generate',
          builder: (_, s) {
            final q = s.uri.queryParameters;
            return AiGenerateScreen(
              kind: q['kind'] == 'note'
                  ? AiGenerateKind.note
                  : AiGenerateKind.quiz,
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
      child: MaterialApp.router(routerConfig: router),
    );
  }
}
