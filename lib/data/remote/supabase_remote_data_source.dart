import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../local/sync_meta_store.dart';
import '../models/attachment.dart';
import '../models/outbox_op.dart';
import '../models/share.dart';
import 'remote_data_source.dart';
import 'supabase_api.dart';

/// Supabase implementation of every remote data source.
class SupabaseRemoteDataSource
    implements
        SyncRemoteDataSource,
        ImageRemoteDataSource,
        ShareRemoteDataSource {
  SupabaseRemoteDataSource(this._client, {this.timeout = _defaultTimeout});

  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const int _fetchPageSize = 1000;
  static const String _noteImageCopies = 'note_image_copies';

  /// Profile embeds documented by the backend (FK constraint names).
  static const String _recipientEmbed =
      'recipient:profiles!shares_recipient_id_fkey(id,email,display_name)';
  static const String _ownerEmbed =
      'owner:profiles!shares_owner_id_fkey(id,email,display_name)';

  final sb.SupabaseClient _client;
  final Duration timeout;

  sb.StorageFileApi _storage(String bucket) => _client.storage.from(bucket);

  final math.Random _random = math.Random.secure();

  /// Unique value for the download `cacheNonce` query parameter.
  String cacheNonce() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      List.generate(16, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
    );
  }

  /// Large blobs get more time than the default request timeout (assumes
  /// at least ~100 KB/s).
  Duration _transferTimeout(int bytes) =>
      Duration(seconds: timeout.inSeconds + bytes ~/ (100 * 1024));

  // -------------------------------------------------------------------------
  // Sync
  // -------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>?> upsert(
    String table,
    Map<String, dynamic> row,
  ) => _guard(
    () => _client
        .from(table)
        .upsert(row, onConflict: 'id')
        .select()
        .maybeSingle(),
  );

  @override
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    PullCursor? after,
    required int limit,
  }) => _guard(() {
    var query = _client.from(table).select();
    if (after != null) {
      final t = _quote(after.updatedAt);
      query = query.or(
        'updated_at.gt.$t,and(updated_at.eq.$t,id.gt.${after.id})',
      );
    }
    return query
        .order('updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
  });

  @override
  Future<Map<String, dynamic>?> fetchById(String table, String id) =>
      _guard(() => _client.from(table).select().eq('id', id).maybeSingle());

  @override
  Future<List<Map<String, dynamic>>> fetchWhere(
    String table,
    String column,
    String value,
  ) async {
    final result = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final page = await _guard(
        () => _client
            .from(table)
            .select()
            .eq(column, value)
            .order('id', ascending: true)
            .range(from, from + _fetchPageSize - 1),
      );
      result.addAll(page);
      if (page.length < _fetchPageSize) return result;
      from += _fetchPageSize;
    }
  }

  @override
  Future<Set<String>> fetchVisibleIds(String table, List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _guard(
      () => _client.from(table).select('id').inFilter('id', ids),
    );
    return {for (final r in rows) r['id'] as String};
  }

  @override
  Future<List<({ShareResourceType type, String resourceId})>> incomingShares(
    String userId,
  ) async {
    final rows = await _guard(
      () => _client
          .from(SyncTables.shares)
          .select('resource_type, resource_id')
          .eq('recipient_id', userId),
    );
    final result = <({ShareResourceType type, String resourceId})>[];
    for (final r in rows) {
      final type = _parseType(r['resource_type']);
      if (type != null) {
        result.add((type: type, resourceId: r['resource_id'] as String));
      }
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------

  @override
  Future<void> uploadImage(
    String path,
    Uint8List bytes, {
    String? contentType,
    String bucket = SyncTables.noteImagesBucket,
  }) => _guard(
    () => _storage(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: sb.FileOptions(upsert: true, contentType: contentType),
    ),
    timeout: _transferTimeout(bytes.length),
  );

  /// Downloads with a unique `cacheNonce` query parameter: the Storage CDN
  /// caches authenticated GETs keyed by URL + Authorization and does not
  /// invalidate them when RLS access changes (e.g. a revoked share), so a
  /// fresh URL forces an origin (RLS-evaluated) read every time.
  @override
  Future<Uint8List> downloadImage(
    String path, {
    String bucket = SyncTables.noteImagesBucket,
  }) => _guard(
    () => _storage(bucket).download(path, cacheNonce: cacheNonce()),
    timeout: bucket == SyncTables.attachmentsBucket
        ? _transferTimeout(Attachment.maxSizeBytes)
        : null,
  );

  @override
  Future<String> createSignedUrl(
    String path,
    Duration expiresIn, {
    String bucket = SyncTables.noteImagesBucket,
  }) =>
      _guard(() => _storage(bucket).createSignedUrl(path, expiresIn.inSeconds));

  @override
  Future<void> removeImages(
    List<String> paths, {
    String bucket = SyncTables.noteImagesBucket,
  }) => _guard(() => _storage(bucket).remove(paths));

  @override
  Future<void> copyImage(
    String fromPath,
    String toPath, {
    String bucket = SyncTables.noteImagesBucket,
  }) => _guard(() => _storage(bucket).copy(fromPath, toPath));

  @override
  Future<List<NoteImageCopy>> pendingImageCopies() async {
    final rows = await _guard(
      () => _client
          .from(_noteImageCopies)
          .select('id, bucket, from_path, to_path')
          .order('created_at', ascending: true),
    );
    return [
      for (final r in rows)
        (
          id: r['id'] as String,
          bucket: (r['bucket'] as String?) ?? SyncTables.noteImagesBucket,
          fromPath: r['from_path'] as String,
          toPath: r['to_path'] as String,
        ),
    ];
  }

  @override
  Future<void> deleteImageCopy(String id) =>
      _guard(() => _client.from(_noteImageCopies).delete().eq('id', id));

  // -------------------------------------------------------------------------
  // Shares / RPC
  // -------------------------------------------------------------------------

  @override
  Future<({String id, String? displayName, String? email})?> findUserByEmail(
    String email,
  ) async {
    final result = await _guard<Object?>(
      () => _client.rpc<Object?>(
        SupabaseRpc.findUserByEmail,
        params: {'p_email': email},
      ),
    );
    final row = switch (result) {
      final List<Object?> list when list.isNotEmpty => list.first,
      final Map<String, dynamic> map => map,
      _ => null,
    };
    if (row is! Map<String, dynamic> || row['id'] == null) return null;
    return (
      id: row['id'] as String,
      displayName: row['display_name'] as String?,
      email: row['email'] as String?,
    );
  }

  @override
  Future<Map<String, dynamic>> insertShare(Map<String, dynamic> row) => _guard(
    () => _client
        .from(SyncTables.shares)
        .insert(row)
        .select('*,$_recipientEmbed')
        .single(),
  );

  @override
  Future<Map<String, dynamic>?> findShare({
    required ShareResourceType type,
    required String resourceId,
    required String recipientId,
  }) => _guard(
    () => _client
        .from(SyncTables.shares)
        .select('*,$_recipientEmbed')
        .eq('resource_type', type.wireName)
        .eq('resource_id', resourceId)
        .eq('recipient_id', recipientId)
        .maybeSingle(),
  );

  @override
  Future<void> deleteShare(String shareId) async {
    final deleted = await _guard(
      () => _client
          .from(SyncTables.shares)
          .delete()
          .eq('id', shareId)
          .select('id'),
    );
    if (deleted.isEmpty) {
      throw const RemoteException(
        RemoteErrorKind.permanent,
        'Share not found or not owned by you.',
        code: '404',
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> sharesForResource({
    required String ownerId,
    required ShareResourceType type,
    required String resourceId,
  }) => _guard(
    () => _client
        .from(SyncTables.shares)
        .select('*,$_recipientEmbed')
        .eq('owner_id', ownerId)
        .eq('resource_type', type.wireName)
        .eq('resource_id', resourceId)
        .order('created_at', ascending: true),
  );

  @override
  Future<List<Map<String, dynamic>>> sharesForRecipient(String recipientId) =>
      _guard(
        () => _client
            .from(SyncTables.shares)
            .select('*,$_ownerEmbed')
            .eq('recipient_id', recipientId)
            .order('created_at', ascending: false),
      );

  @override
  Future<List<Map<String, dynamic>>> fetchProfiles(List<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      return await _guard(
        () => _client.from(SyncTables.profiles).select().inFilter('id', ids),
      );
    } on RemoteException catch (e) {
      if (e.kind == RemoteErrorKind.network) rethrow;
      // Column privileges may hide `email`; retry with public columns.
      return _guard(
        () => _client
            .from(SyncTables.profiles)
            .select('id, display_name')
            .inFilter('id', ids),
      );
    }
  }

  @override
  Future<String?> fetchTitle(String table, String id) async {
    final row = await _guard(
      () => _client.from(table).select('title').eq('id', id).maybeSingle(),
    );
    return row?['title'] as String?;
  }

  @override
  Future<String> copyResource({
    required ShareResourceType type,
    required String resourceId,
    String? targetSubjectId,
    String? targetNoteId,
  }) async {
    final (name, params) = switch (type) {
      ShareResourceType.subject => (
        SupabaseRpc.copySubject,
        <String, dynamic>{'p_subject_id': resourceId},
      ),
      ShareResourceType.note => (
        SupabaseRpc.copyNote,
        <String, dynamic>{
          'p_note_id': resourceId,
          'p_target_subject_id': targetSubjectId,
        },
      ),
      ShareResourceType.quiz => (
        SupabaseRpc.copyQuiz,
        <String, dynamic>{
          'p_quiz_id': resourceId,
          'p_target_subject_id': targetSubjectId,
          'p_target_note_id': targetNoteId,
        },
      ),
      ShareResourceType.deck => (
        SupabaseRpc.copyDeck,
        <String, dynamic>{
          'p_deck_id': resourceId,
          'p_target_subject_id': targetSubjectId,
          'p_target_note_id': targetNoteId,
        },
      ),
    };
    final result = await _guard<Object?>(
      () => _client.rpc<Object?>(name, params: params),
    );
    final id = _extractId(result);
    if (id == null) {
      throw RemoteException(
        RemoteErrorKind.permanent,
        'Unexpected response from $name.',
        cause: result,
      );
    }
    return id;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Accepts a bare uuid, `{id: ..}`, `{copy_x: ..}` or a one-row list.
  static String? _extractId(Object? result) => switch (result) {
    final String s when s.isNotEmpty => s,
    final List<Object?> list when list.isNotEmpty => _extractId(list.first),
    final Map<String, dynamic> map when map.length == 1 => _extractId(
      map.values.first,
    ),
    final Map<String, dynamic> map => _extractId(map['id']),
    _ => null,
  };

  static ShareResourceType? _parseType(Object? raw) {
    for (final t in ShareResourceType.values) {
      if (t.wireName == raw) return t;
    }
    return null;
  }

  static String _quote(String value) => '"$value"';

  Future<T> _guard<T>(Future<T> Function() body, {Duration? timeout}) async {
    try {
      return await body().timeout(timeout ?? this.timeout);
    } catch (e) {
      throw mapRemoteError(e);
    }
  }
}

/// Classifies Supabase / HTTP errors into [RemoteException]s.
RemoteException mapRemoteError(Object error) {
  if (error is RemoteException) return error;
  if (error is TimeoutException || error is http.ClientException) {
    return RemoteException(
      RemoteErrorKind.network,
      'Could not reach the server.',
      cause: error,
    );
  }
  if (error is sb.AuthRetryableFetchException) {
    return RemoteException(
      RemoteErrorKind.network,
      'Could not reach the server.',
      cause: error,
    );
  }
  if (error is sb.AuthException) {
    return RemoteException(
      RemoteErrorKind.auth,
      error.message,
      code: error.statusCode,
      cause: error,
    );
  }
  if (error is sb.PostgrestException) {
    return RemoteException(
      isSchemaCacheError(error.message)
          ? RemoteErrorKind.schemaOutdated
          : classifyErrorCode(error.code),
      error.message,
      code: error.code,
      cause: error,
    );
  }
  if (error is sb.StorageException) {
    return RemoteException(
      error.message.toLowerCase().contains('bucket not found')
          ? RemoteErrorKind.schemaOutdated
          : classifyErrorCode(error.statusCode),
      error.message,
      code: error.statusCode,
      cause: error,
    );
  }
  // Socket errors on some platforms surface with these type names; avoid
  // importing dart:io so this file stays web-compatible.
  final typeName = error.runtimeType.toString();
  if (typeName.contains('SocketException') ||
      typeName.contains('HandshakeException') ||
      typeName.contains('ClientException')) {
    return RemoteException(
      RemoteErrorKind.network,
      'Could not reach the server.',
      cause: error,
    );
  }
  return RemoteException(
    RemoteErrorKind.transient,
    error.toString(),
    cause: error,
  );
}

/// PostgREST / Postgres codes meaning "the server schema is older than the
/// app" (see [RemoteErrorKind.schemaOutdated]).
const Set<String> schemaOutdatedCodes = {
  'PGRST200', // relationship not found in the schema cache
  'PGRST202', // function not found in the schema cache
  'PGRST204', // column not found in the schema cache
  'PGRST205', // table not found in the schema cache
  '42703', // undefined_column
  '42P01', // undefined_table
  '42883', // undefined_function
};

/// Whether a PostgREST error message (or raw body, when it was not parsed)
/// is a schema-cache miss, e.g. "Could not find the 'x' column of 'y' in
/// the schema cache".
bool isSchemaCacheError(String? message) {
  if (message == null) return false;
  final text = message.toLowerCase();
  return text.contains('in the schema cache') ||
      schemaOutdatedCodes.any(
        (c) => c.startsWith('PGRST') && message.contains('"$c"'),
      );
}

/// Maps a Postgres SQLSTATE, PostgREST `PGRSTxxx` code or HTTP status to a
/// [RemoteErrorKind].
RemoteErrorKind classifyErrorCode(String? code) {
  if (code == null || code.isEmpty) return RemoteErrorKind.transient;
  if (schemaOutdatedCodes.contains(code)) {
    return RemoteErrorKind.schemaOutdated;
  }
  if (code == '23503') return RemoteErrorKind.dependency;
  if (code == '23505') return RemoteErrorKind.conflict;
  if (code == '42501') return RemoteErrorKind.permanent; // RLS / privilege
  if (code.startsWith('23') || code.startsWith('22')) {
    return RemoteErrorKind.permanent; // constraint / data errors
  }
  // raise_exception / no_data_found (RPC not found)
  if (code == 'P0001' || code == 'P0002') return RemoteErrorKind.permanent;
  if (code.startsWith('PGRST3')) return RemoteErrorKind.auth; // JWT
  if (code.startsWith('PGRST1')) return RemoteErrorKind.permanent; // request
  final status = int.tryParse(code);
  if (status != null && status >= 100 && status < 600) {
    if (status == 401) return RemoteErrorKind.auth;
    if (status == 409) return RemoteErrorKind.conflict;
    if (status == 408 || status == 429) return RemoteErrorKind.transient;
    if (status >= 400 && status < 500) return RemoteErrorKind.permanent;
    return RemoteErrorKind.transient;
  }
  return RemoteErrorKind.transient;
}
