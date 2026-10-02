import 'dart:async';
import 'dart:typed_data';

import 'package:quiz_app/data/local/sync_meta_store.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/remote/remote_data_source.dart';
import 'package:quiz_app/data/sync/connectivity_monitor.dart';

/// In-memory Supabase imitation with RLS-like visibility for [userId].
class FakeRemote
    implements
        SyncRemoteDataSource,
        ImageRemoteDataSource,
        ShareRemoteDataSource {
  FakeRemote({required this.userId});

  /// The caller (auth.uid()).
  String userId;

  final Map<String, Map<String, Map<String, dynamic>>> tables = {
    for (final t in SyncTables.synced) t: {},
  };
  final List<Map<String, dynamic>> shares = [];

  /// Objects of bucket `note-images`.
  final Map<String, Uint8List> objects = {};

  /// Objects of bucket `attachments`.
  final Map<String, Uint8List> attachmentObjects = {};

  /// Ordered log of remote writes: `upsert:{table}:{id}`,
  /// `upload:{bucket}:{path}`, `remove:{bucket}:{path}`,
  /// `copy:{bucket}:{from}->{to}`, `download:{bucket}:{path}`.
  final List<String> log = [];

  /// Return an exception to fail a Storage upload of (bucket, path).
  RemoteException? Function(String bucket, String path)? uploadHook;

  Map<String, Uint8List> bucket(String name) => switch (name) {
    SyncTables.noteImagesBucket => objects,
    SyncTables.attachmentsBucket => attachmentObjects,
    _ => throw ArgumentError.value(name, 'bucket'),
  };
  final List<Map<String, dynamic>> imageCopies = [];
  final Map<String, Map<String, dynamic>> profiles = {};

  DateTime _serverNow = DateTime.utc(2026, 3, 1);
  bool offline = false;

  /// Return an exception to fail an upsert of (table, row).
  RemoteException? Function(String table, Map<String, dynamic> row)? upsertHook;

  /// Delay inside upsert (to test concurrency).
  Future<void> Function()? upsertDelay;

  int upsertCalls = 0;
  int pullCalls = 0;
  final List<PullCursor?> pullAfters = [];
  final List<String> rpcCalls = [];

  /// Server timestamp; [sameTimestamp] keeps the previous one (rows written
  /// in the same transaction).
  String nextTimestamp({bool sameTimestamp = false}) {
    if (!sameTimestamp) {
      _serverNow = _serverNow.add(const Duration(seconds: 10, microseconds: 1));
    }
    return _serverNow.toIso8601String().replaceFirst('Z', '+00:00');
  }

  /// Simulates a write by another device/user (bypasses RLS).
  Map<String, dynamic> serverWrite(
    String table,
    Map<String, dynamic> row, {
    bool sameTimestamp = false,
  }) {
    final stored = Map<String, dynamic>.from(row)
      ..['updated_at'] = nextTimestamp(sameTimestamp: sameTimestamp);
    tables[table]![row['id'] as String] = stored;
    return stored;
  }

  void _checkOnline() {
    if (offline) {
      throw const RemoteException(RemoteErrorKind.network, 'offline');
    }
  }

  bool _shared(ShareResourceType type, String? id) =>
      id != null &&
      shares.any(
        (s) =>
            s['recipient_id'] == userId &&
            s['resource_type'] == type.wireName &&
            s['resource_id'] == id,
      );

  bool visible(String table, Map<String, dynamic> row) {
    if (row['owner_id'] == userId) return true;
    return switch (table) {
      SyncTables.subjects => _shared(
        ShareResourceType.subject,
        row['id'] as String,
      ),
      SyncTables.notes =>
        _shared(ShareResourceType.note, row['id'] as String) ||
            _shared(ShareResourceType.subject, row['subject_id'] as String?),
      SyncTables.quizzes =>
        _shared(ShareResourceType.quiz, row['id'] as String) ||
            _shared(ShareResourceType.subject, row['subject_id'] as String?) ||
            _shared(ShareResourceType.note, row['note_id'] as String?),
      SyncTables.decks =>
        _shared(ShareResourceType.deck, row['id'] as String) ||
            _shared(ShareResourceType.subject, row['subject_id'] as String?) ||
            _shared(ShareResourceType.note, row['note_id'] as String?),
      // Only through a subject share, while row and subject are live.
      SyncTables.attachments =>
        row['deleted_at'] == null &&
            tables[SyncTables.subjects]![row['subject_id']]?['deleted_at'] ==
                null &&
            _shared(ShareResourceType.subject, row['subject_id'] as String?),
      _ => false,
    };
  }

  Map<String, dynamic> _copy(Map<String, dynamic> row) =>
      Map<String, dynamic>.from(row);

  // ---------------------------------------------------------------- sync

  @override
  Future<Map<String, dynamic>?> upsert(
    String table,
    Map<String, dynamic> row,
  ) async {
    upsertCalls++;
    await upsertDelay?.call();
    _checkOnline();
    final hooked = upsertHook?.call(table, row);
    if (hooked != null) throw hooked;
    final id = row['id'] as String;
    final existing = tables[table]![id];
    if ((existing != null && existing['owner_id'] != userId) ||
        row['owner_id'] != userId) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'new row violates row-level security policy',
        code: '42501',
      );
    }
    String? parentTable;
    String? parentId;
    if (table == SyncTables.notes ||
        table == SyncTables.quizzes ||
        table == SyncTables.attachments ||
        table == SyncTables.decks) {
      parentTable = SyncTables.subjects;
      parentId = row['subject_id'] as String?;
    } else if (table == SyncTables.quizAttempts ||
        table == SyncTables.mistakes) {
      parentTable = SyncTables.quizzes;
      parentId = row['quiz_id'] as String?;
    } else if (table == SyncTables.cardReviews) {
      parentTable = SyncTables.decks;
      parentId = row['deck_id'] as String?;
    }
    if (parentTable != null && !tables[parentTable]!.containsKey(parentId)) {
      throw const RemoteException(
        RemoteErrorKind.dependency,
        'violates foreign key constraint',
        code: '23503',
      );
    }
    if (SyncTables.privateStudy.contains(table)) _checkStudyRow(table, row);
    log.add('upsert:$table:$id');
    return _copy(serverWrite(table, row));
  }

  /// `card_reviews` / `mistakes`: INSERT needs read access to the parent
  /// (`can_read_deck` / `can_read_quiz`, 42501) and the natural key
  /// `(owner, parent, child)` is unique (23505).
  void _checkStudyRow(String table, Map<String, dynamic> row) {
    final (
      parentTable,
      parentColumn,
      keyColumn,
    ) = table == SyncTables.cardReviews
        ? (SyncTables.decks, 'deck_id', 'card_id')
        : (SyncTables.quizzes, 'quiz_id', 'question_id');
    final id = row['id'] as String;
    if (tables[table]![id] == null) {
      final parent = tables[parentTable]![row[parentColumn]]!;
      if (parent['deleted_at'] != null && parent['owner_id'] != userId ||
          !visible(parentTable, parent)) {
        throw const RemoteException(
          RemoteErrorKind.permanent,
          'new row violates row-level security policy',
          code: '42501',
        );
      }
    }
    final duplicate = tables[table]!.values.any(
      (r) =>
          r['id'] != id &&
          r['owner_id'] == row['owner_id'] &&
          r[parentColumn] == row[parentColumn] &&
          r[keyColumn] == row[keyColumn],
    );
    if (duplicate) {
      throw const RemoteException(
        RemoteErrorKind.conflict,
        'duplicate key value violates unique constraint',
        code: '23505',
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    PullCursor? after,
    required int limit,
  }) async {
    pullCalls++;
    pullAfters.add(after);
    _checkOnline();
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      final c = DateTime.parse(a['updated_at'] as String)
          .compareTo(DateTime.parse(b['updated_at'] as String));
      return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
    }

    final rows = tables[table]!.values.where((r) => visible(table, r)).where((
      r,
    ) {
      if (after == null) return true;
      final t = DateTime.parse(r['updated_at'] as String);
      final c = t.compareTo(after.updatedAtTime);
      return c > 0 || (c == 0 && (r['id'] as String).compareTo(after.id) > 0);
    }).toList()..sort(cmp);
    return rows.take(limit).map(_copy).toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String table, String id) async {
    _checkOnline();
    final row = tables[table]![id];
    return row != null && visible(table, row) ? _copy(row) : null;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWhere(
    String table,
    String column,
    String value,
  ) async {
    _checkOnline();
    return tables[table]!.values
        .where((r) => r[column] == value && visible(table, r))
        .map(_copy)
        .toList();
  }

  @override
  Future<Set<String>> fetchVisibleIds(String table, List<String> ids) async {
    _checkOnline();
    return {
      for (final id in ids)
        if (tables[table]![id] != null && visible(table, tables[table]![id]!))
          id,
    };
  }

  @override
  Future<List<({ShareResourceType type, String resourceId})>> incomingShares(
    String userId,
  ) async {
    _checkOnline();
    return [
      for (final s in shares)
        if (s['recipient_id'] == userId)
          (
            type: ShareResourceType.values.byName(s['resource_type'] as String),
            resourceId: s['resource_id'] as String,
          ),
    ];
  }

  // ------------------------------------------------------------- storage

  @override
  Future<void> uploadImage(
    String path,
    Uint8List bytes, {
    String? contentType,
    String bucket = SyncTables.noteImagesBucket,
  }) async {
    _checkOnline();
    final hooked = uploadHook?.call(bucket, path);
    if (hooked != null) throw hooked;
    if (!path.startsWith('$userId/')) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'Unauthorized',
        code: '403',
      );
    }
    log.add('upload:$bucket:$path');
    this.bucket(bucket)[path] = bytes;
  }

  @override
  Future<Uint8List> downloadImage(
    String path, {
    String bucket = SyncTables.noteImagesBucket,
  }) async {
    _checkOnline();
    log.add('download:$bucket:$path');
    final bytes = this.bucket(bucket)[path];
    if (bytes == null || !_canReadObject(bucket, path)) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'Object not found',
        code: '404',
      );
    }
    return bytes;
  }

  /// Storage read policy (attachments: own folder or a readable row).
  bool _canReadObject(String bucket, String path) {
    if (bucket != SyncTables.attachmentsBucket) return true;
    if (path.startsWith('$userId/')) return true;
    return tables[SyncTables.attachments]!.values.any(
      (r) => r['storage_path'] == path && visible(SyncTables.attachments, r),
    );
  }

  @override
  Future<String> createSignedUrl(
    String path,
    Duration expiresIn, {
    String bucket = SyncTables.noteImagesBucket,
  }) async {
    _checkOnline();
    return 'https://example.test/$bucket/$path?token=${expiresIn.inSeconds}';
  }

  @override
  Future<void> removeImages(
    List<String> paths, {
    String bucket = SyncTables.noteImagesBucket,
  }) async {
    _checkOnline();
    for (final path in paths) {
      log.add('remove:$bucket:$path');
      this.bucket(bucket).remove(path);
    }
  }

  @override
  Future<void> copyImage(
    String fromPath,
    String toPath, {
    String bucket = SyncTables.noteImagesBucket,
  }) async {
    _checkOnline();
    final objects = this.bucket(bucket);
    final bytes = objects[fromPath];
    if (bytes == null) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'Object not found',
        code: '404',
      );
    }
    log.add('copy:$bucket:$fromPath->$toPath');
    objects[toPath] = bytes;
  }

  @override
  Future<List<NoteImageCopy>> pendingImageCopies() async {
    _checkOnline();
    return [
      for (final c in imageCopies)
        if (c['owner_id'] == userId)
          (
            id: c['id'] as String,
            bucket: (c['bucket'] as String?) ?? SyncTables.noteImagesBucket,
            fromPath: c['from_path'] as String,
            toPath: c['to_path'] as String,
          ),
    ];
  }

  @override
  Future<void> deleteImageCopy(String id) async {
    _checkOnline();
    imageCopies.removeWhere((c) => c['id'] == id);
  }

  // -------------------------------------------------------------- shares

  @override
  Future<({String id, String? displayName, String? email})?> findUserByEmail(
    String email,
  ) async {
    _checkOnline();
    for (final p in profiles.values) {
      if ((p['email'] as String?)?.toLowerCase() == email.toLowerCase()) {
        return (
          id: p['id'] as String,
          displayName: p['display_name'] as String?,
          email: p['email'] as String?,
        );
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> insertShare(Map<String, dynamic> row) async {
    _checkOnline();
    // RLS: the caller must own the (server-side) resource.
    final table = switch (row['resource_type']) {
      'subject' => SyncTables.subjects,
      'note' => SyncTables.notes,
      'deck' => SyncTables.decks,
      _ => SyncTables.quizzes,
    };
    final resource = tables[table]![row['resource_id']];
    if (resource == null || resource['owner_id'] != userId) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'new row violates row-level security policy for table "shares"',
        code: '42501',
      );
    }
    final dup = shares.any(
      (s) =>
          s['resource_type'] == row['resource_type'] &&
          s['resource_id'] == row['resource_id'] &&
          s['recipient_id'] == row['recipient_id'],
    );
    if (dup) {
      throw const RemoteException(
        RemoteErrorKind.conflict,
        'duplicate key',
        code: '23505',
      );
    }
    final stored = _copy(row);
    shares.add(stored);
    return {...stored, 'recipient': profiles[row['recipient_id']]};
  }

  @override
  Future<Map<String, dynamic>?> findShare({
    required ShareResourceType type,
    required String resourceId,
    required String recipientId,
  }) async {
    _checkOnline();
    for (final s in shares) {
      if (s['resource_type'] == type.wireName &&
          s['resource_id'] == resourceId &&
          s['recipient_id'] == recipientId) {
        return _copy(s);
      }
    }
    return null;
  }

  @override
  Future<void> deleteShare(String shareId) async {
    _checkOnline();
    shares.removeWhere((s) => s['id'] == shareId);
  }

  @override
  Future<List<Map<String, dynamic>>> sharesForResource({
    required String ownerId,
    required ShareResourceType type,
    required String resourceId,
  }) async {
    _checkOnline();
    return [
      for (final s in shares)
        if (s['owner_id'] == ownerId &&
            s['resource_type'] == type.wireName &&
            s['resource_id'] == resourceId)
          {...s, 'recipient': profiles[s['recipient_id']]},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> sharesForRecipient(
    String recipientId,
  ) async {
    _checkOnline();
    return [
      for (final s in shares)
        if (s['recipient_id'] == recipientId)
          {...s, 'owner': profiles[s['owner_id']]},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchProfiles(List<String> ids) async {
    _checkOnline();
    return [
      for (final id in ids)
        if (profiles[id] != null) profiles[id]!,
    ];
  }

  @override
  Future<String?> fetchTitle(String table, String id) async {
    _checkOnline();
    final row = tables[table]![id];
    return row != null && visible(table, row) ? row['title'] as String? : null;
  }

  /// Simulated copy RPC: copies a note into [targetSubjectId], rewriting
  /// image paths and queueing `note_image_copies` rows like the SQL does.
  @override
  Future<String> copyResource({
    required ShareResourceType type,
    required String resourceId,
    String? targetSubjectId,
    String? targetNoteId,
  }) async {
    _checkOnline();
    rpcCalls.add('copy_${type.wireName}');
    if (type == ShareResourceType.deck) {
      return _copyDeck(resourceId, targetSubjectId, targetNoteId);
    }
    if (type != ShareResourceType.note) {
      throw UnimplementedError('FakeRemote only copies notes and decks');
    }
    final src = tables[SyncTables.notes]![resourceId];
    if (src == null || !visible(SyncTables.notes, src)) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'note not found',
        code: 'P0002',
      );
    }
    final newId = 'copy-of-$resourceId';
    var content = src['content_md'] as String;
    final srcPrefix = '${src['owner_id']}/$resourceId/';
    final pattern = RegExp(
      'note-image://${RegExp.escape(srcPrefix)}([^)\\s]+)',
    );
    for (final m in pattern.allMatches(content).toList()) {
      final file = m.group(1)!;
      imageCopies.add({
        'id': 'copy-row-${imageCopies.length + 1}',
        'owner_id': userId,
        'from_path': '$srcPrefix$file',
        'to_path': '$userId/$newId/$file',
      });
    }
    content = content.replaceAll(
      'note-image://$srcPrefix',
      'note-image://$userId/$newId/',
    );
    serverWrite(SyncTables.notes, {
      ...src,
      'id': newId,
      'owner_id': userId,
      'subject_id': targetSubjectId,
      'content_md': content,
    });
    return newId;
  }
}

extension on FakeRemote {
  /// Simulated `copy_deck`: same rules as `copy_quiz`, card ids kept.
  String _copyDeck(String deckId, String? subjectId, String? noteId) {
    final src = tables[SyncTables.decks]![deckId];
    if (src == null ||
        src['deleted_at'] != null ||
        !visible(SyncTables.decks, src)) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'deck not found',
        code: 'P0002',
      );
    }
    final subject = tables[SyncTables.subjects]![subjectId];
    final note = noteId == null ? null : tables[SyncTables.notes]![noteId];
    if (subject == null ||
        subject['owner_id'] != userId ||
        (noteId != null &&
            (note == null ||
                note['owner_id'] != userId ||
                note['subject_id'] != subjectId))) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'target not owned',
        code: '42501',
      );
    }
    final newId = 'copy-of-$deckId';
    serverWrite(SyncTables.decks, {
      ...src,
      'id': newId,
      'owner_id': userId,
      'subject_id': subjectId,
      'note_id': noteId,
    });
    return newId;
  }
}

/// Controllable connectivity.
class FakeConnectivity implements ConnectivityMonitor {
  bool online = true;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  /// Delay inside [isOnline] after the value is read (a slow platform check
  /// whose result can be stale by the time it returns).
  Future<void> Function()? checkDelay;

  void set(bool value) {
    online = value;
    _changes.add(value);
  }

  @override
  Future<bool> isOnline() async {
    final value = online;
    await checkDelay?.call();
    return value;
  }

  @override
  Stream<bool> get onChanged => _changes.stream;
}

/// Row JSON helpers for server-side fixtures.
Map<String, dynamic> subjectRow(
  String id,
  String owner, {
  String title = 'S',
  String? deletedAt,
}) => {
  'id': id,
  'owner_id': owner,
  'title': title,
  'description': null,
  'color': null,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'deleted_at': deletedAt,
};

Map<String, dynamic> noteRow(
  String id,
  String owner,
  String subjectId, {
  String title = 'N',
  String content = '',
  String? deletedAt,
}) => {
  'id': id,
  'subject_id': subjectId,
  'owner_id': owner,
  'title': title,
  'content_md': content,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'deleted_at': deletedAt,
};

Map<String, dynamic> quizRow(
  String id,
  String owner,
  String subjectId, {
  String? noteId,
  String title = 'Q',
}) => {
  'id': id,
  'subject_id': subjectId,
  'note_id': noteId,
  'owner_id': owner,
  'title': title,
  'description': null,
  'source': null,
  'questions': <Object?>[],
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'deleted_at': null,
};

Map<String, dynamic> attachmentRow(
  String id,
  String owner,
  String subjectId, {
  String name = 'file.pdf',
  String kind = 'pdf',
  String? deletedAt,
}) => {
  'id': id,
  'subject_id': subjectId,
  'owner_id': owner,
  'name': name,
  'mime_type': 'application/pdf',
  'size_bytes': 3,
  'kind': kind,
  'storage_path': '$owner/$subjectId/$id/$name',
  'extracted_text': null,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'deleted_at': deletedAt,
};

Map<String, dynamic> deckRow(
  String id,
  String owner,
  String subjectId, {
  String? noteId,
  String title = 'D',
  List<String> cardIds = const ['c1', 'c2'],
  String? deletedAt,
}) => {
  'id': id,
  'subject_id': subjectId,
  'note_id': noteId,
  'owner_id': owner,
  'title': title,
  'description': null,
  'source': null,
  'cards': [
    for (final c in cardIds) {'id': c, 'front': 'F $c', 'back': 'B $c'},
  ],
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'deleted_at': deletedAt,
};

Map<String, dynamic> reviewRow(
  String id,
  String owner,
  String deckId,
  String cardId, {
  int state = 2,
  String dueAt = '2026-01-05T00:00:00Z',
  int reps = 1,
}) => {
  'id': id,
  'owner_id': owner,
  'deck_id': deckId,
  'card_id': cardId,
  'state': state,
  'due_at': dueAt,
  'stability': 3.0,
  'difficulty': 5.0,
  'elapsed_days': 0,
  'scheduled_days': 3,
  'reps': reps,
  'lapses': 0,
  'last_review_at': '2026-01-02T00:00:00Z',
  'created_at': '2026-01-02T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
  'deleted_at': null,
};
