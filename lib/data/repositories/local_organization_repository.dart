import '../../core/errors/app_exception.dart';
import '../local/local_table.dart';
import '../models/models.dart';
import 'organization_repository.dart';
import 'repository_support.dart';

/// Hive-backed [OrganizationRepository].
class LocalOrganizationRepository implements OrganizationRepository {
  LocalOrganizationRepository(this._ctx);

  final DataContext _ctx;

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  @override
  Future<void> setTags(TaggableKind kind, String id, Iterable<String> tags) =>
      _edit(kind, id, (current) => checkedTags(tags), null);

  @override
  Future<void> addTag(TaggableKind kind, String id, String tag) =>
      _edit(kind, id, (current) => checkedTags([...current, tag]), null);

  @override
  Future<void> removeTag(TaggableKind kind, String id, String tag) {
    final normalized = normalizeTag(tag);
    return _edit(
      kind,
      id,
      (current) => [
        for (final t in current)
          if (t != normalized) t,
      ],
      null,
    );
  }

  @override
  Future<void> setPinned(TaggableKind kind, String id, bool pinned) =>
      _edit(kind, id, null, pinned);

  @override
  Future<int> renameTag(String from, String to) {
    final source = normalizeTag(from);
    final target = normalizeTag(to);
    if (target == null) {
      throw const ValidationException('Please enter a tag name.');
    }
    if (source == null || source == target) return Future.value(0);
    return _rewriteOwnTags(
      (tags) => tags.contains(source)
          ? checkedTags([for (final t in tags) t == source ? target : t])
          : null,
    );
  }

  @override
  Future<int> deleteTag(String tag) {
    final normalized = normalizeTag(tag);
    if (normalized == null) return Future.value(0);
    return _rewriteOwnTags(
      (tags) => tags.contains(normalized)
          ? [
              for (final t in tags)
                if (t != normalized) t,
            ]
          : null,
    );
  }

  @override
  Future<Subject> setSubjectPinned(String subjectId, bool pinned) =>
      _editSubject(
        subjectId,
        (s) => s.pinned == pinned ? null : s.copyWith(pinned: pinned),
      );

  @override
  Future<Subject> archiveSubject(String subjectId) => _editSubject(
    subjectId,
    (s) => s.archivedAt != null ? null : s.copyWith(archivedAt: _ctx.clock()),
  );

  @override
  Future<Subject> unarchiveSubject(String subjectId) => _editSubject(
    subjectId,
    (s) => s.archivedAt == null ? null : s.copyWith(archivedAt: null),
  );

  /// Normalized tags, or [ValidationException] when there are too many.
  static List<String> checkedTags(Iterable<String> tags) {
    final normalized = normalizeTags(tags);
    if (normalized.length > TagRules.maxTags) {
      throw const ValidationException(
        'An item can have at most ${TagRules.maxTags} tags.',
      );
    }
    return normalized;
  }

  Future<Subject> _editSubject(
    String id,
    Subject? Function(Subject current) change,
  ) async {
    final userId = _ctx.requireUserId();
    final subject = _ctx.requireLive(_ctx.db.subjects, id, 'subject');
    _ctx.ensureOwned(subject, userId, 'subject');
    final next = change(subject);
    if (next == null) return subject;
    final saved = next.copyWith(updatedAt: _ctx.clock());
    await _ctx.save(_ctx.db.subjects, saved);
    return saved;
  }

  /// Applies new tags and/or pin to one item (no write when unchanged).
  Future<void> _edit(
    TaggableKind kind,
    String id,
    List<String> Function(List<String> current)? tags,
    bool? pinned,
  ) async {
    final userId = _ctx.requireUserId();
    final db = _ctx.db;
    switch (kind) {
      case TaggableKind.note:
        final note = _ctx.requireLive(db.notes, id, 'note');
        _ctx.ensureOwned(note, userId, 'note');
        final t = tags?.call(note.tags) ?? note.tags;
        final p = pinned ?? note.pinned;
        if (_same(t, note.tags) && p == note.pinned) return;
        await _ctx.save(
          db.notes,
          note.copyWith(tags: t, pinned: p, updatedAt: _ctx.clock()),
        );
      case TaggableKind.quiz:
        final quiz = _ctx.requireLive(db.quizzes, id, 'quiz');
        _ctx.ensureOwned(quiz, userId, 'quiz');
        final t = tags?.call(quiz.tags) ?? quiz.tags;
        final p = pinned ?? quiz.pinned;
        if (_same(t, quiz.tags) && p == quiz.pinned) return;
        await _ctx.save(
          db.quizzes,
          quiz.copyWith(tags: t, pinned: p, updatedAt: _ctx.clock()),
        );
      case TaggableKind.deck:
        final deck = _ctx.requireLive(db.decks, id, 'deck');
        _ctx.ensureOwned(deck, userId, 'deck');
        final t = tags?.call(deck.tags) ?? deck.tags;
        final p = pinned ?? deck.pinned;
        if (_same(t, deck.tags) && p == deck.pinned) return;
        await _ctx.save(
          db.decks,
          deck.copyWith(tags: t, pinned: p, updatedAt: _ctx.clock()),
        );
    }
  }

  Future<int> _rewriteOwnTags(
    List<String>? Function(List<String> tags) rewrite,
  ) async {
    final userId = _ctx.requireUserId();
    final db = _ctx.db;
    var changed = 0;
    for (final note in db.notes.where((n) => n.isOwnedBy(userId))) {
      final next = rewrite(note.tags);
      if (next == null || _same(next, note.tags)) continue;
      await _ctx.save(
        db.notes,
        note.copyWith(tags: next, updatedAt: _ctx.clock()),
      );
      changed++;
    }
    for (final quiz in db.quizzes.where((q) => q.isOwnedBy(userId))) {
      final next = rewrite(quiz.tags);
      if (next == null || _same(next, quiz.tags)) continue;
      await _ctx.save(
        db.quizzes,
        quiz.copyWith(tags: next, updatedAt: _ctx.clock()),
      );
      changed++;
    }
    for (final deck in db.decks.where((d) => d.isOwnedBy(userId))) {
      final next = rewrite(deck.tags);
      if (next == null || _same(next, deck.tags)) continue;
      await _ctx.save(
        db.decks,
        deck.copyWith(tags: next, updatedAt: _ctx.clock()),
      );
      changed++;
    }
    return changed;
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  @override
  Stream<List<Subject>> watchSubjects([
    SubjectListQuery query = const SubjectListQuery(),
  ]) => watchQuery(
    [_ctx.db.subjects.box],
    () => filterSubjects(
      _ctx.db.subjects.where((_) => true),
      query,
      currentUserId: _ctx.currentUserId,
    ),
    equals: _listEquals,
  );

  @override
  Stream<List<Note>> watchNotes([
    ItemListQuery query = const ItemListQuery(),
  ]) => _watchItems(_ctx.db.notes, query);

  @override
  Stream<List<Quiz>> watchQuizzes([
    ItemListQuery query = const ItemListQuery(),
  ]) => _watchItems(_ctx.db.quizzes, query);

  @override
  Stream<List<Deck>> watchDecks([
    ItemListQuery query = const ItemListQuery(),
  ]) => _watchItems(_ctx.db.decks, query);

  Stream<List<T>> _watchItems<T extends Syncable>(
    LocalTable<T> table,
    ItemListQuery query,
  ) => watchQuery(
    [table.box, _ctx.db.subjects.box],
    () => filterItems(
      table.where((_) => true),
      query,
      archivedSubjectIds: _archivedSubjectIds(),
      currentUserId: _ctx.currentUserId,
    ),
    equals: _listEquals,
  );

  @override
  Stream<List<TagCount>> watchTags({
    TaggableKind? kind,
    String? subjectId,
    bool includeArchived = false,
  }) {
    final db = _ctx.db;
    return watchQuery(
      [db.notes.box, db.quizzes.box, db.decks.box, db.subjects.box],
      () {
        final query = ItemListQuery(
          subjectId: subjectId,
          includeArchived: includeArchived,
          pinnedFirst: false,
        );
        final archived = _archivedSubjectIds();
        final items = <Syncable>[
          if (kind == null || kind == TaggableKind.note)
            ...filterItems(
              db.notes.where((_) => true),
              query,
              archivedSubjectIds: archived,
            ),
          if (kind == null || kind == TaggableKind.quiz)
            ...filterItems(
              db.quizzes.where((_) => true),
              query,
              archivedSubjectIds: archived,
            ),
          if (kind == null || kind == TaggableKind.deck)
            ...filterItems(
              db.decks.where((_) => true),
              query,
              archivedSubjectIds: archived,
            ),
        ];
        return countTags(items.map(itemTags));
      },
      equals: _listEquals,
    );
  }

  Set<String> _archivedSubjectIds() => {
    for (final s in _ctx.db.subjects.where((s) => s.archivedAt != null)) s.id,
  };

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// -----------------------------------------------------------------------------
// Pure helpers (also used by other repositories and tests)
// -----------------------------------------------------------------------------

/// Title / subject / note / tags / pinned of a note, quiz or deck.
({
  String title,
  String subjectId,
  String? noteId,
  List<String> tags,
  bool pinned,
})
itemFields(Syncable item) => switch (item) {
  final Note n => (
    title: n.title,
    subjectId: n.subjectId,
    noteId: null,
    tags: n.tags,
    pinned: n.pinned,
  ),
  final Quiz q => (
    title: q.title,
    subjectId: q.subjectId,
    noteId: q.noteId,
    tags: q.tags,
    pinned: q.pinned,
  ),
  final Deck d => (
    title: d.title,
    subjectId: d.subjectId,
    noteId: d.noteId,
    tags: d.tags,
    pinned: d.pinned,
  ),
  _ => throw ArgumentError.value(item, 'item', 'Not a taggable item'),
};

List<String> itemTags(Syncable item) => itemFields(item).tags;

/// Applies [query] to live notes / quizzes / decks ([items] may contain
/// tombstones; they are dropped).
List<T> filterItems<T extends Syncable>(
  Iterable<T> items,
  ItemListQuery query, {
  Set<String> archivedSubjectIds = const {},
  String? currentUserId,
}) {
  final wanted = normalizeTags(query.tags);
  final result = <(T, String, bool)>[];
  for (final item in items) {
    if (item.isDeleted) continue;
    final f = itemFields(item);
    if (query.subjectId != null && f.subjectId != query.subjectId) continue;
    if (query.noteId != null) {
      final noteId = item is Note ? item.id : f.noteId;
      if (noteId != query.noteId) continue;
    }
    if (query.subjectId == null &&
        !query.includeArchived &&
        archivedSubjectIds.contains(f.subjectId)) {
      continue;
    }
    if (query.pinnedOnly && !f.pinned) continue;
    if (query.ownedOnly && !item.isOwnedBy(currentUserId)) continue;
    if (wanted.isNotEmpty && !wanted.every(f.tags.contains)) continue;
    result.add((item, f.title, f.pinned));
  }
  result.sort(
    (a, b) => _compare(
      a.$1,
      b.$1,
      a.$2,
      b.$2,
      a.$3,
      b.$3,
      query.sort,
      query.pinnedFirst,
    ),
  );
  return [for (final r in result) r.$1];
}

/// Applies [query] to subjects ([subjects] may contain tombstones).
List<Subject> filterSubjects(
  Iterable<Subject> subjects,
  SubjectListQuery query, {
  String? currentUserId,
}) {
  final result = [
    for (final s in subjects)
      if (!s.isDeleted &&
          (query.includeShared || s.isOwnedBy(currentUserId)) &&
          (!query.pinnedOnly || s.pinned) &&
          switch (query.archive) {
            ArchiveFilter.active => s.archivedAt == null,
            ArchiveFilter.archived => s.archivedAt != null,
            ArchiveFilter.all => true,
          })
        s,
  ];
  result.sort(
    (a, b) => _compare(
      a,
      b,
      a.title,
      b.title,
      a.pinned,
      b.pinned,
      query.sort,
      query.pinnedFirst,
    ),
  );
  return result;
}

int _compare(
  Syncable a,
  Syncable b,
  String titleA,
  String titleB,
  bool pinnedA,
  bool pinnedB,
  ItemSort sort,
  bool pinnedFirst,
) {
  if (pinnedFirst && pinnedA != pinnedB) return pinnedA ? -1 : 1;
  final c = switch (sort) {
    ItemSort.recent => b.updatedAt.compareTo(a.updatedAt),
    ItemSort.created => b.createdAt.compareTo(a.createdAt),
    ItemSort.name => titleA.toLowerCase().compareTo(titleB.toLowerCase()),
  };
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Counts tags over [tagLists], by count desc then tag name.
List<TagCount> countTags(Iterable<List<String>> tagLists) {
  final counts = <String, int>{};
  for (final tags in tagLists) {
    for (final t in tags.toSet()) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  final result = [for (final e in counts.entries) TagCount(e.key, e.value)]
    ..sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.tag.compareTo(b.tag);
    });
  return result;
}
