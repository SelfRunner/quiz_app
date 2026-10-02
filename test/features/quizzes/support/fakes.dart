import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/ai/ai_capabilities.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_readiness.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/ai_tools_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/core/providers.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/attempt_repository.dart';
import 'package:quiz_app/data/repositories/mistake_repository.dart';
import 'package:quiz_app/data/repositories/note_repository.dart';
import 'package:quiz_app/data/repositories/quiz_repository.dart';
import 'package:quiz_app/data/repositories/study_activity_repository.dart';
import 'package:quiz_app/data/repositories/subject_repository.dart';
import 'package:quiz_app/features/ai_generate/presentation/ai_generate_screen.dart';
import 'package:quiz_app/features/quizzes/application/ai_grading.dart';
import 'package:quiz_app/features/quizzes/presentation/quiz_detail_screen.dart';
import 'package:quiz_app/features/quizzes/presentation/quiz_edit_screen.dart';
import 'package:quiz_app/features/quizzes/presentation/quiz_play_screen.dart';
import 'package:quiz_app/features/study/presentation/mistakes_screen.dart';
import 'package:quiz_app/study/stats.dart';

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
    AttemptMode mode = AttemptMode.practice,
    int? timeLimitSeconds,
    List<String>? questionIds,
  }) async {
    final a = QuizAttempt(
      id: nextId(),
      quizId: quizId,
      ownerId: userId,
      total: total,
      mode: mode,
      timeLimitSeconds: timeLimitSeconds,
      questionIds: questionIds,
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
  Future<void> delete(String id) async {
    deleted.add(id);
    _t.rows.remove(id);
    _t._changes.add(null);
  }

  final List<String> deleted = [];
}

/// In-memory [MistakeRepository] following the contract's lifecycle.
class FakeMistakeRepository implements MistakeRepository {
  FakeMistakeRepository(this.quizzes, {required this.clock});

  final FakeQuizRepository quizzes;
  final DateTime Function() clock;
  final _t = _Table<Mistake>();

  /// Every recorded answer, in order.
  final List<({String quizId, String questionId, bool correct})> recorded = [];

  Iterable<Mistake> get rows => _t.rows.values;

  Mistake? find(String quizId, String questionId) =>
      _t.rows[_key(quizId, questionId)];

  static String _key(String quizId, String questionId) => '$quizId/$questionId';

  Mistake add(Mistake m) {
    _t.put(_key(m.quizId, m.questionId), m);
    return m;
  }

  @override
  Future<Mistake?> recordAnswer({
    required String quizId,
    required String questionId,
    required bool correct,
  }) async {
    recorded.add((quizId: quizId, questionId: questionId, correct: correct));
    final existing = find(quizId, questionId);
    final now = clock();
    if (!correct) {
      final base =
          existing ??
          Mistake(
            id: Mistake.idFor(
              ownerId: userId,
              quizId: quizId,
              questionId: questionId,
            ),
            ownerId: userId,
            quizId: quizId,
            questionId: questionId,
            createdAt: now,
            updatedAt: now,
          );
      return add(
        base.copyWith(
          wrongCount: base.wrongCount + 1,
          correctStreak: 0,
          lastWrongAt: now,
          resolvedAt: null,
          updatedAt: now,
        ),
      );
    }
    if (existing == null || !existing.isOpen) return existing;
    final streak = existing.correctStreak + 1;
    return add(
      existing.copyWith(
        correctStreak: streak,
        resolvedAt: streak >= Mistake.resolveAfterCorrect ? now : null,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<void> recordAttempt(QuizAttempt attempt) async {
    for (final a in attempt.answers) {
      final correct = a.isCorrect;
      if (correct == null) continue;
      await recordAnswer(
        quizId: attempt.quizId,
        questionId: a.questionId,
        correct: correct,
      );
    }
  }

  List<MistakeGroup> _groups() {
    final byQuiz = <String, List<Mistake>>{};
    for (final m in _t.rows.values.where((m) => m.isOpen)) {
      (byQuiz[m.quizId] ??= []).add(m);
    }
    final groups = <MistakeGroup>[];
    for (final MapEntry(key: quizId, value: list) in byQuiz.entries) {
      final quiz = quizzes._t.rows[quizId];
      if (quiz == null || quiz.isDeleted) continue;
      final byQuestion = {for (final m in list) m.questionId: m};
      final entries = [
        for (final q in quiz.questions)
          if (byQuestion[q.id] case final m?)
            MistakeEntry(mistake: m, question: q),
      ];
      if (entries.isNotEmpty) {
        groups.add(MistakeGroup(quiz: quiz, entries: entries));
      }
    }
    groups.sort(
      (a, b) => (b.lastWrongAt ?? DateTime(0)).compareTo(
        a.lastWrongAt ?? DateTime(0),
      ),
    );
    return groups;
  }

  @override
  Stream<List<MistakeGroup>> watchOpen() => _t.watch(_groups);

  @override
  Stream<int> watchOpenCount() =>
      watchOpen().map((g) => g.fold<int>(0, (n, g) => n + g.entries.length));

  @override
  Future<void> resolve({
    required String quizId,
    required String questionId,
  }) async {
    final m = find(quizId, questionId);
    if (m == null || !m.isOpen) return;
    add(m.copyWith(resolvedAt: clock(), updatedAt: clock()));
  }
}

/// Snapshot of the fakes (subjects, quizzes, attempts, mistakes); emits
/// again whenever a mistake changes.
class FakeStudyActivityRepository implements StudyActivityRepository {
  FakeStudyActivityRepository(
    this.subjects,
    this.quizzes,
    this.attempts,
    this.mistakes,
  );

  final FakeSubjectRepository subjects;
  final FakeQuizRepository quizzes;
  final FakeAttemptRepository attempts;
  final FakeMistakeRepository mistakes;

  @override
  Stream<StudySnapshot> watchSnapshot() => mistakes._t.watch(
    () => StudySnapshot(
      subjects: subjects._t.rows.values.toList(),
      quizzes: quizzes.all,
      attempts: attempts._t.rows.values.toList(),
      mistakes: mistakes.rows.toList(),
    ),
  );
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
  Future<T> generateStructured<T>(
    StructuredGenerationRequest request, {
    required DraftValidation<T> Function(Map<String, dynamic> json) validate,
    String what = 'result',
  }) => throw UnimplementedError();

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

const testSelection = AiSelection(
  providerId: LlmProviderId.openai,
  model: 'gpt-test',
);

/// Fake [AiToolsService] for "Explain this" and AI grading. Defaults: an
/// explanation citing the first source, and a "correct" grade.
class FakeAiToolsService implements AiToolsService {
  final List<
    ({Question question, QuestionAnswer? answer, List<AiSource> sources})
  >
  explainCalls = [];
  final List<({String question, String modelAnswer, String answer})>
  gradeCalls = [];

  Future<AiExplanation> Function(
    Question question,
    QuestionAnswer? answer,
    List<AiSource> sources,
  )?
  onExplain;
  Future<ShortAnswerGrade> Function(String question, String answer)? onGrade;

  static AiExplanation defaultExplanation(List<AiSource> sources) {
    final first = sources.whereType<NoteSource>().firstOrNull;
    return AiExplanation(
      markdown: first == null
          ? 'The answer is **right** because of the facts.'
          : 'The answer is **right** because of the notes [S1].',
      selection: testSelection,
      citations: [
        if (first != null)
          ChatCitation(
            number: 1,
            type: AiSourceType.note,
            id: first.id,
            title: first.title,
          ),
      ],
    );
  }

  @override
  Future<AiExplanation> explainAnswer(
    Question question,
    QuestionAnswer? userAnswer, {
    List<AiSource> sources = const [],
    String? language,
    LlmProviderId? providerId,
    String? model,
  }) {
    explainCalls.add((
      question: question,
      answer: userAnswer,
      sources: sources,
    ));
    return onExplain?.call(question, userAnswer, sources) ??
        Future.value(defaultExplanation(sources));
  }

  @override
  Future<ShortAnswerGrade> gradeShortAnswer(
    String question,
    String modelAnswer,
    String userAnswer, {
    String? language,
    LlmProviderId? providerId,
    String? model,
  }) {
    gradeCalls.add((
      question: question,
      modelAnswer: modelAnswer,
      answer: userAnswer,
    ));
    return onGrade?.call(question, userAnswer) ??
        Future.value(
          const ShortAnswerGrade(
            verdict: GradeVerdict.correct,
            score: 1,
            feedback: 'Well done.',
            selection: testSelection,
          ),
        );
  }

  @override
  Future<NoteToolResult> transformNote(
    String markdown,
    NoteTool tool, {
    String? title,
    String? language,
    String? extraInstructions,
    LlmProviderId? providerId,
    String? model,
  }) => throw UnimplementedError();
}

/// [AiGradeShortAnswersSetting] starting at a fixed value (no Hive).
class PresetAiGradeSetting extends AiGradeShortAnswersSetting {
  PresetAiGradeSetting(this.initial);

  final bool initial;

  @override
  bool build() => initial;
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
  late final mistakes = FakeMistakeRepository(quizzes, clock: () => now);
  late final activity = FakeStudyActivityRepository(
    subjects,
    quizzes,
    attempts,
    mistakes,
  );

  /// The app clock (`clockProvider`); advance it in timer tests.
  DateTime now = fixedNow;
  final ai = FakeAiService(
    selection: const AiSelection(
      providerId: LlmProviderId.openai,
      model: 'gpt-test',
    ),
  );

  /// Input kinds reported by `aiReadinessProvider` (ready while
  /// `ai.selection` is set).
  AiCapabilities capabilities = AiCapabilities.textOnly;

  /// More overrides for feature-specific tests.
  List<Override> get extraOverrides => const [];

  /// Set false to lock AI entry points regardless of [ai.selection].
  bool aiReady = true;

  /// "Explain this" / AI grading service.
  final tools = FakeAiToolsService();

  /// Initial "Grade short answers with AI" setting.
  bool aiGrading = false;

  AiReadiness _readiness() {
    if (!aiReady) {
      return const AiReadiness.notReady(
        reason: 'Add an API key in Settings to use AI.',
        issue: AiReadinessIssue.missingApiKey,
      );
    }
    final sel = ai.selection;
    if (sel == null) {
      return const AiReadiness.notReady(
        reason: 'Add an AI provider API key in Settings to use AI features.',
        issue: AiReadinessIssue.noProvider,
      );
    }
    return AiReadiness(
      isConfigured: true,
      providerId: sel.providerId,
      model: sel.model,
      capabilities: capabilities,
    );
  }

  List<Override> get overrides => [
    ...extraOverrides,
    aiReadinessProvider.overrideWith((ref) async => _readiness()),
    currentUserIdProvider.overrideWithValue(userId),
    quizRepositoryProvider.overrideWithValue(quizzes),
    attemptRepositoryProvider.overrideWithValue(attempts),
    noteRepositoryProvider.overrideWithValue(notes),
    subjectRepositoryProvider.overrideWithValue(subjects),
    mistakeRepositoryProvider.overrideWithValue(mistakes),
    studyActivityRepositoryProvider.overrideWithValue(activity),
    aiServiceProvider.overrideWithValue(ai),
    aiToolsServiceProvider.overrideWithValue(tools),
    aiGradeShortAnswersProvider.overrideWith(
      () => PresetAiGradeSetting(aiGrading),
    ),
    clockProvider.overrideWithValue(() => now),
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
              builder: (_, s) => QuizPlayScreen(
                quizId: s.pathParameters['id']!,
                mode: s.uri.queryParameters['mode'],
              ),
            ),
          ],
        ),
        GoRoute(path: '/mistakes', builder: (_, _) => const MistakesScreen()),
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
