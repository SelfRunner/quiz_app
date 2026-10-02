// Fakes for Wave 3 organization / search / export UI tests.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quiz_app/core/utils/file_opener.dart';
import 'package:quiz_app/core/utils/file_saver.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';

/// Records saved files instead of writing them.
class FakeFileSaver implements FileSaver {
  final List<({String name, Uint8List bytes, String? mimeType})> saved = [];

  /// Returned path (null = "download started").
  String? path;

  @override
  Future<String?> save(
    String fileName,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    saved.add((name: fileName, bytes: bytes, mimeType: mimeType));
    return path;
  }
}

/// Returns [next] (null = cancelled) from every pick.
class FakeFileOpener implements FileOpener {
  OpenedFile? next;
  int calls = 0;
  List<String>? lastExtensions;

  void text(String name, String content) =>
      next = OpenedFile(name, Uint8List.fromList(utf8.encode(content)));

  @override
  Future<OpenedFile?> pick({
    List<String> extensions = const [],
    String? dialogTitle,
  }) async {
    calls++;
    lastExtensions = extensions;
    return next;
  }
}

/// In-memory subjects (pin / archive) plus recorded item tag / pin calls.
class FakeOrganizationRepository implements OrganizationRepository {
  FakeOrganizationRepository({DateTime? now})
    : now = now ?? DateTime.utc(2026, 1, 1, 12);

  final DateTime now;
  final Map<String, Subject> subjects = {};
  final List<TagCount> tags = [];
  final List<String> calls = [];
  final _changes = StreamController<void>.broadcast();

  /// Applies item changes (e.g. to a fake deck repository).
  void Function(
    TaggableKind kind,
    String id, {
    List<String>? tags,
    bool? pinned,
  })?
  onItem;

  Subject seed(
    String id,
    String title, {
    bool pinned = false,
    bool archived = false,
    String ownerId = 'user-1',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final s = Subject(
      id: id,
      ownerId: ownerId,
      title: title,
      pinned: pinned,
      archivedAt: archived ? now : null,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
    subjects[id] = s;
    _changes.add(null);
    return s;
  }

  Stream<R> _watch<R>(R Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  Subject _put(Subject s) {
    subjects[s.id] = s;
    _changes.add(null);
    return s;
  }

  @override
  Future<Subject> setSubjectPinned(String subjectId, bool pinned) async {
    calls.add('pinSubject:$subjectId:$pinned');
    return _put(subjects[subjectId]!.copyWith(pinned: pinned));
  }

  @override
  Future<Subject> archiveSubject(String subjectId) async {
    calls.add('archive:$subjectId');
    return _put(subjects[subjectId]!.copyWith(archivedAt: now));
  }

  @override
  Future<Subject> unarchiveSubject(String subjectId) async {
    calls.add('unarchive:$subjectId');
    return _put(subjects[subjectId]!.copyWith(archivedAt: null));
  }

  @override
  Stream<List<Subject>> watchSubjects([
    SubjectListQuery query = const SubjectListQuery(),
  ]) => _watch(() {
    final list = [
      for (final s in subjects.values)
        if (switch (query.archive) {
          ArchiveFilter.active => s.archivedAt == null,
          ArchiveFilter.archived => s.archivedAt != null,
          ArchiveFilter.all => true,
        })
          s,
    ];
    list.sort((a, b) {
      if (query.pinnedFirst && a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.title.compareTo(b.title);
    });
    return list;
  });

  @override
  Future<void> setTags(TaggableKind kind, String id, Iterable<String> t) async {
    final list = normalizeTags(t);
    calls.add('setTags:${kind.name}:$id:${list.join('|')}');
    onItem?.call(kind, id, tags: list);
  }

  @override
  Future<void> addTag(TaggableKind kind, String id, String tag) async =>
      calls.add('addTag:${kind.name}:$id:$tag');

  @override
  Future<void> removeTag(TaggableKind kind, String id, String tag) async =>
      calls.add('removeTag:${kind.name}:$id:$tag');

  @override
  Future<void> setPinned(TaggableKind kind, String id, bool pinned) async {
    calls.add('setPinned:${kind.name}:$id:$pinned');
    onItem?.call(kind, id, pinned: pinned);
  }

  @override
  Future<int> renameTag(String from, String to) async => 0;

  @override
  Future<int> deleteTag(String tag) async => 0;

  @override
  Stream<List<Note>> watchNotes([
    ItemListQuery query = const ItemListQuery(),
  ]) => Stream.value(const []);

  @override
  Stream<List<Quiz>> watchQuizzes([
    ItemListQuery query = const ItemListQuery(),
  ]) => Stream.value(const []);

  @override
  Stream<List<Deck>> watchDecks([
    ItemListQuery query = const ItemListQuery(),
  ]) => Stream.value(const []);

  @override
  Stream<List<TagCount>> watchTags({
    TaggableKind? kind,
    String? subjectId,
    bool includeArchived = false,
  }) => Stream.value(tags);
}
