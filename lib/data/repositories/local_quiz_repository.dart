import '../../core/errors/app_exception.dart';
import '../models/question.dart';
import '../models/quiz.dart';
import '../models/quiz_source.dart';
import 'quiz_repository.dart';
import 'repository_support.dart';

/// Hive-backed [QuizRepository] (writes go through the outbox).
class LocalQuizRepository implements QuizRepository {
  LocalQuizRepository(this._ctx) : _cascade = CascadeDeleter(_ctx);

  final DataContext _ctx;
  final CascadeDeleter _cascade;

  @override
  Stream<List<Quiz>> watchBySubject(String subjectId) => _ctx.db.quizzes
      .watchWhere((q) => q.subjectId == subjectId, compare: _byUpdatedDesc);

  @override
  Stream<List<Quiz>> watchByNote(String noteId) => _ctx.db.quizzes.watchWhere(
    (q) => q.noteId == noteId,
    compare: _byUpdatedDesc,
  );

  static int _byUpdatedDesc(Quiz a, Quiz b) {
    final c = b.updatedAt.compareTo(a.updatedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  @override
  Stream<Quiz?> watchById(String id) => _ctx.db.quizzes.watchById(id);

  @override
  Future<Quiz?> getById(String id) async => _ctx.db.quizzes.getLive(id);

  @override
  Future<Quiz> create({
    required String subjectId,
    String? noteId,
    required String title,
    String? description,
    List<Question> questions = const [],
    QuizSource? source,
  }) async {
    final userId = _ctx.requireUserId();
    _checkParents(userId, subjectId, noteId);
    final now = _ctx.clock();
    final quiz = Quiz(
      id: _ctx.newId(),
      subjectId: subjectId,
      noteId: noteId,
      ownerId: userId,
      title: title.trim(),
      description: description,
      source: source,
      questions: questions,
      createdAt: now,
      updatedAt: now,
    );
    await _ctx.save(_ctx.db.quizzes, quiz);
    return quiz;
  }

  @override
  Future<Quiz> update(Quiz quiz) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.requireLive(_ctx.db.quizzes, quiz.id, 'quiz');
    _ctx.ensureOwned(existing, userId, 'quiz');
    if (quiz.subjectId != existing.subjectId ||
        quiz.noteId != existing.noteId) {
      _checkParents(userId, quiz.subjectId, quiz.noteId);
    }
    final next = quiz.copyWith(
      title: quiz.title.trim(),
      ownerId: existing.ownerId,
      createdAt: existing.createdAt,
      updatedAt: _ctx.clock(),
      deletedAt: null,
    );
    await _ctx.save(_ctx.db.quizzes, next);
    return next;
  }

  @override
  Future<void> delete(String id) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.db.quizzes.getLive(id);
    if (existing == null) return;
    _ctx.ensureOwned(existing, userId, 'quiz');
    await _cascade.deleteQuiz(existing);
  }

  void _checkParents(String userId, String subjectId, String? noteId) {
    final subject = _ctx.requireLive(_ctx.db.subjects, subjectId, 'subject');
    _ctx.ensureOwned(subject, userId, 'subject');
    if (noteId == null) return;
    final note = _ctx.requireLive(_ctx.db.notes, noteId, 'note');
    _ctx.ensureOwned(note, userId, 'note');
    if (note.subjectId != subjectId) {
      throw const ValidationException(
        'The note belongs to a different subject.',
      );
    }
  }
}
