import 'package:meta/meta.dart';

import '../models/deck.dart';
import '../models/note.dart';
import '../models/quiz.dart';
import '../models/subject.dart';

/// Items that carry `tags` + `pinned` (Wave 3).
enum TaggableKind { note, quiz, deck }

/// List order. `recent` = `updatedAt` desc, `name` = title A-Z
/// (case-insensitive), `created` = `createdAt` desc. Ties by id.
enum ItemSort { recent, name, created }

/// Which subjects a subject list shows.
enum ArchiveFilter { active, archived, all }

/// Filter + order of a note / quiz / deck list.
///
/// - [subjectId] / [noteId]: restrict to one subject (incl. its note items)
///   / note. When [subjectId] is set, items of an archived subject are shown
///   (the user opened it); otherwise they are hidden unless
///   [includeArchived].
/// - [tags]: the item must carry **every** tag (normalized before matching).
/// - [pinnedOnly], [ownedOnly] (exclude items shared with me).
/// - [pinnedFirst]: pinned items before the others, each group in [sort]
///   order.
@immutable
class ItemListQuery {
  const ItemListQuery({
    this.subjectId,
    this.noteId,
    this.tags = const {},
    this.pinnedOnly = false,
    this.includeArchived = false,
    this.ownedOnly = false,
    this.sort = ItemSort.recent,
    this.pinnedFirst = true,
  });

  final String? subjectId;
  final String? noteId;
  final Set<String> tags;
  final bool pinnedOnly;
  final bool includeArchived;
  final bool ownedOnly;
  final ItemSort sort;
  final bool pinnedFirst;

  ItemListQuery copyWith({
    String? Function()? subjectId,
    String? Function()? noteId,
    Set<String>? tags,
    bool? pinnedOnly,
    bool? includeArchived,
    bool? ownedOnly,
    ItemSort? sort,
    bool? pinnedFirst,
  }) => ItemListQuery(
    subjectId: subjectId != null ? subjectId() : this.subjectId,
    noteId: noteId != null ? noteId() : this.noteId,
    tags: tags ?? this.tags,
    pinnedOnly: pinnedOnly ?? this.pinnedOnly,
    includeArchived: includeArchived ?? this.includeArchived,
    ownedOnly: ownedOnly ?? this.ownedOnly,
    sort: sort ?? this.sort,
    pinnedFirst: pinnedFirst ?? this.pinnedFirst,
  );

  @override
  bool operator ==(Object other) =>
      other is ItemListQuery &&
      other.subjectId == subjectId &&
      other.noteId == noteId &&
      other.tags.length == tags.length &&
      other.tags.containsAll(tags) &&
      other.pinnedOnly == pinnedOnly &&
      other.includeArchived == includeArchived &&
      other.ownedOnly == ownedOnly &&
      other.sort == sort &&
      other.pinnedFirst == pinnedFirst;

  @override
  int get hashCode => Object.hash(
    subjectId,
    noteId,
    Object.hashAllUnordered(tags),
    pinnedOnly,
    includeArchived,
    ownedOnly,
    sort,
    pinnedFirst,
  );

  @override
  String toString() =>
      'ItemListQuery(subject: $subjectId, note: $noteId, tags: $tags, '
      'pinnedOnly: $pinnedOnly, includeArchived: $includeArchived, '
      'ownedOnly: $ownedOnly, sort: ${sort.name}, pinnedFirst: $pinnedFirst)';
}

/// Filter + order of a subject list. Default: the user's own active
/// subjects, pinned first, by name (what `SubjectRepository.watchAll`
/// returns).
@immutable
class SubjectListQuery {
  const SubjectListQuery({
    this.archive = ArchiveFilter.active,
    this.pinnedOnly = false,
    this.includeShared = false,
    this.sort = ItemSort.name,
    this.pinnedFirst = true,
  });

  final ArchiveFilter archive;
  final bool pinnedOnly;

  /// Also subjects shared with me (cached by sync).
  final bool includeShared;
  final ItemSort sort;
  final bool pinnedFirst;

  @override
  bool operator ==(Object other) =>
      other is SubjectListQuery &&
      other.archive == archive &&
      other.pinnedOnly == pinnedOnly &&
      other.includeShared == includeShared &&
      other.sort == sort &&
      other.pinnedFirst == pinnedFirst;

  @override
  int get hashCode =>
      Object.hash(archive, pinnedOnly, includeShared, sort, pinnedFirst);

  @override
  String toString() =>
      'SubjectListQuery(${archive.name}, pinnedOnly: $pinnedOnly, '
      'includeShared: $includeShared, sort: ${sort.name}, '
      'pinnedFirst: $pinnedFirst)';
}

/// A tag in use and how many live items carry it.
@immutable
class TagCount {
  const TagCount(this.tag, this.count);

  final String tag;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is TagCount && other.tag == tag && other.count == count;

  @override
  int get hashCode => Object.hash(tag, count);

  @override
  String toString() => 'TagCount($tag: $count)';
}

/// Tags, pin, archive and the filtered / sorted lists built on them.
///
/// Writes are owner-only (`PermissionDeniedException` for shared items;
/// `NotFoundException` for missing ones), local-first (outbox), and no-ops
/// when nothing changes. Tags are normalized with `normalizeTags`
/// (trim, lowercase, dedupe); more than 50 -> `ValidationException`.
abstract interface class OrganizationRepository {
  Future<void> setTags(TaggableKind kind, String id, Iterable<String> tags);
  Future<void> addTag(TaggableKind kind, String id, String tag);
  Future<void> removeTag(TaggableKind kind, String id, String tag);
  Future<void> setPinned(TaggableKind kind, String id, bool pinned);

  /// Renames [from] to [to] (merging if [to] exists) on every own note,
  /// quiz and deck. Returns the number of items changed.
  Future<int> renameTag(String from, String to);

  /// Removes [tag] from every own note, quiz and deck. Returns the number
  /// of items changed.
  Future<int> deleteTag(String tag);

  Future<Subject> setSubjectPinned(String subjectId, bool pinned);

  /// Hides the subject from default lists, the dashboard and the study
  /// queue (still reachable by id and via [ArchiveFilter.archived]).
  Future<Subject> archiveSubject(String subjectId);
  Future<Subject> unarchiveSubject(String subjectId);

  Stream<List<Subject>> watchSubjects([
    SubjectListQuery query = const SubjectListQuery(),
  ]);
  Stream<List<Note>> watchNotes([ItemListQuery query = const ItemListQuery()]);
  Stream<List<Quiz>> watchQuizzes([
    ItemListQuery query = const ItemListQuery(),
  ]);
  Stream<List<Deck>> watchDecks([ItemListQuery query = const ItemListQuery()]);

  /// Tags in use on live notes / quizzes / decks I can read (all kinds, or
  /// one [kind]; optionally within one subject), by count desc then name.
  /// Items of archived subjects count only when [subjectId] is theirs or
  /// [includeArchived].
  Stream<List<TagCount>> watchTags({
    TaggableKind? kind,
    String? subjectId,
    bool includeArchived = false,
  });
}
