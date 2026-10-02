import '../models/note.dart';
import '../models/syncable.dart';
import 'note_repository.dart';
import 'repository_support.dart';

/// Hive-backed [NoteRepository] (writes go through the outbox).
class LocalNoteRepository implements NoteRepository {
  LocalNoteRepository(this._ctx) : _cascade = CascadeDeleter(_ctx);

  final DataContext _ctx;
  final CascadeDeleter _cascade;

  @override
  Stream<List<Note>> watchBySubject(String subjectId) => _ctx.db.notes
      .watchWhere((n) => n.subjectId == subjectId, compare: _byUpdatedDesc);

  static int _byUpdatedDesc(Note a, Note b) {
    final c = b.updatedAt.compareTo(a.updatedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  @override
  Stream<List<Note>> watchAllAccessible() =>
      _ctx.db.notes.watchWhere((_) => true, compare: _byUpdatedDesc);

  @override
  Stream<Note?> watchById(String id) => _ctx.db.notes.watchById(id);

  @override
  Future<Note?> getById(String id) async => _ctx.db.notes.getLive(id);

  @override
  Future<Note> create({
    required String subjectId,
    required String title,
    String contentMd = '',
  }) async {
    final userId = _ctx.requireUserId();
    final subject = _ctx.requireLive(_ctx.db.subjects, subjectId, 'subject');
    _ctx.ensureOwned(subject, userId, 'subject');
    final now = _ctx.clock();
    final note = Note(
      id: _ctx.newId(),
      subjectId: subjectId,
      ownerId: userId,
      title: title.trim(),
      contentMd: contentMd,
      createdAt: now,
      updatedAt: now,
    );
    await _ctx.save(_ctx.db.notes, note);
    return note;
  }

  @override
  Future<Note> update(Note note) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.requireLive(_ctx.db.notes, note.id, 'note');
    _ctx.ensureOwned(existing, userId, 'note');
    final now = _ctx.clock();
    final moved = note.subjectId != existing.subjectId;
    if (moved) {
      final target = _ctx.requireLive(
        _ctx.db.subjects,
        note.subjectId,
        'subject',
      );
      _ctx.ensureOwned(target, userId, 'subject');
    }
    final next = note.copyWith(
      title: note.title.trim(),
      ownerId: existing.ownerId,
      createdAt: existing.createdAt,
      updatedAt: now,
      deletedAt: null,
    );
    await _ctx.save(_ctx.db.notes, next);
    if (moved) {
      // Quizzes attached to the note follow it to the new subject.
      for (final quiz in _ctx.db.quizzes.where((q) => q.noteId == note.id)) {
        if (!quiz.isOwnedBy(userId)) continue;
        await _ctx.save(
          _ctx.db.quizzes,
          quiz.copyWith(subjectId: note.subjectId, updatedAt: now),
        );
      }
    }
    return next;
  }

  @override
  Future<void> delete(String id) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.db.notes.getLive(id);
    if (existing == null) return;
    _ctx.ensureOwned(existing, userId, 'note');
    await _cascade.deleteNote(existing, userId);
  }
}
