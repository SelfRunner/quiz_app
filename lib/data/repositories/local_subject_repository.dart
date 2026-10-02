import '../../core/errors/app_exception.dart';
import '../models/subject.dart';
import 'repository_support.dart';
import 'subject_repository.dart';

/// Hive-backed [SubjectRepository] (writes go through the outbox).
class LocalSubjectRepository implements SubjectRepository {
  LocalSubjectRepository(this._ctx) : _cascade = CascadeDeleter(_ctx);

  final DataContext _ctx;
  final CascadeDeleter _cascade;

  @override
  Stream<List<Subject>> watchAll() {
    final userId = _ctx.currentUserId;
    if (userId == null) return Stream.value(const []);
    return _ctx.db.subjects.watchWhere(
      (s) => s.ownerId == userId,
      compare: _byTitle,
    );
  }

  static int _byTitle(Subject a, Subject b) {
    final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  @override
  Stream<Subject?> watchById(String id) => _ctx.db.subjects.watchById(id);

  @override
  Future<Subject?> getById(String id) async => _ctx.db.subjects.getLive(id);

  @override
  Future<Subject> create({
    required String title,
    String? description,
    int? color,
  }) async {
    final userId = _ctx.requireUserId();
    final now = _ctx.clock();
    final subject = Subject(
      id: _ctx.newId(),
      ownerId: userId,
      title: _validTitle(title),
      description: description,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _ctx.save(_ctx.db.subjects, subject);
    return subject;
  }

  @override
  Future<Subject> update(Subject subject) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.requireLive(_ctx.db.subjects, subject.id, 'subject');
    _ctx.ensureOwned(existing, userId, 'subject');
    final next = subject.copyWith(
      title: _validTitle(subject.title),
      ownerId: existing.ownerId,
      createdAt: existing.createdAt,
      updatedAt: _ctx.clock(),
      deletedAt: null,
    );
    await _ctx.save(_ctx.db.subjects, next);
    return next;
  }

  @override
  Future<void> delete(String id) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.db.subjects.getLive(id);
    if (existing == null) return; // Already gone: idempotent.
    _ctx.ensureOwned(existing, userId, 'subject');
    await _cascade.deleteSubject(existing, userId);
  }

  static String _validTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Please enter a subject name.');
    }
    return trimmed;
  }
}
