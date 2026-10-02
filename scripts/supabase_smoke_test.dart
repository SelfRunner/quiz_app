// Live smoke test for the Supabase backend (schema, RLS, RPCs, Storage).
//
// Pure Dart (no Flutter). Talks to the Supabase Auth / PostgREST / Storage
// HTTP APIs directly, exactly like the app does, using three throwaway users.
//
//   flutter pub get                                  # once, for package:http
//   dart run scripts/supabase_smoke_test.dart        # reads ./env.json
//   dart run scripts/supabase_smoke_test.dart path/to/env.json
//   dart run scripts/supabase_smoke_test.dart --email-domain=mydomain.dev
//
// Requirements on the project:
//   * migrations in supabase/migrations applied;
//   * Authentication -> Providers -> Email enabled with "Confirm email" OFF
//     (sign-up must return a session; the test cannot click email links).
//
// Prints one PASS/FAIL line per check and a summary; exits 1 on any failure.
// Keys, passwords and JWTs are never printed. The three users are not deleted
// (the anon key cannot do that); their emails are printed at the end so you
// can remove them in the dashboard (Authentication -> Users).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _bucket = 'note-images';
const _timeout = Duration(seconds: 30);

// 1x1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

final Random _rand = Random.secure();

String _uuid() {
  final b = List<int>.generate(16, (_) => _rand.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

String _randomString(
  int n, [
  String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789',
]) => List.generate(n, (_) => alphabet[_rand.nextInt(alphabet.length)]).join();

String _now() => DateTime.now().toUtc().toIso8601String();

// -----------------------------------------------------------------------------
// Output / bookkeeping
// -----------------------------------------------------------------------------

/// Thrown when a prerequisite failed and the remaining steps cannot run.
class _Abort implements Exception {
  _Abort(this.reason);
  final String reason;
}

class Report {
  final Set<String> _secrets = {};
  int passed = 0;
  final List<String> failures = [];

  void addSecret(String? s) {
    if (s != null && s.length >= 6) _secrets.add(s);
  }

  String scrub(String s) {
    var out = s;
    for (final secret in _secrets) {
      out = out.replaceAll(secret, '***');
    }
    return out;
  }

  void line(String s) => stdout.writeln(scrub(s));

  void section(String title) => line('\n== $title');

  void pass(String name, [String? detail]) {
    passed++;
    line('PASS  $name${detail == null ? '' : '  ($detail)'}');
  }

  void fail(String name, String reason) {
    failures.add(name);
    line('FAIL  $name  -- $reason');
  }

  bool check(String name, bool ok, String Function() reason, [String? detail]) {
    if (ok) {
      pass(name, detail);
    } else {
      fail(name, reason());
    }
    return ok;
  }
}

// -----------------------------------------------------------------------------
// HTTP
// -----------------------------------------------------------------------------

class Res {
  Res(this.status, this.bytes);
  Res.error(String message)
    : status = -1,
      bytes = Uint8List.fromList(utf8.encode(message));

  final int status;
  final Uint8List bytes;

  bool get ok => status >= 200 && status < 300;
  String get body => utf8.decode(bytes, allowMalformed: true);

  Object? get json {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> get map {
    final j = json;
    return j is Map<String, Object?> ? j : const {};
  }

  List<Map<String, Object?>> get rows {
    final j = json;
    return j is List ? j.whereType<Map<String, Object?>>().toList() : const [];
  }

  /// PostgREST / Postgres error code (e.g. 42501, 23505), if any.
  String? get code {
    final c = map['code'];
    return c is String ? c : null;
  }

  String get snippet {
    var s = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 200) s = '${s.substring(0, 200)}...';
    return status < 0 ? 'request error: $s' : 'HTTP $status: $s';
  }
}

String? _str(Map<String, Object?> m, String key) {
  final v = m[key];
  return v is String ? v : null;
}

class Api {
  Api(String url, this.anonKey) : base = url.replaceAll(RegExp(r'/+$'), '');

  final String base;
  final String anonKey;
  final http.Client _client = http.Client();

  void close() => _client.close();

  Future<Res> send(
    String method,
    String path, {
    String? jwt,
    Object? json,
    Uint8List? bytes,
    String? contentType,
    Map<String, String> headers = const {},
  }) async {
    try {
      final req = http.Request(method, Uri.parse('$base$path'));
      req.headers['apikey'] = anonKey;
      if (jwt != null) req.headers['Authorization'] = 'Bearer $jwt';
      req.headers.addAll(headers);
      if (json != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(json);
      } else if (bytes != null) {
        req.headers['Content-Type'] = contentType ?? 'application/octet-stream';
        req.bodyBytes = bytes;
      }
      final streamed = await _client.send(req).timeout(_timeout);
      final resp = await http.Response.fromStream(streamed).timeout(_timeout);
      return Res(resp.statusCode, resp.bodyBytes);
    } on TimeoutException {
      return Res.error('timeout after ${_timeout.inSeconds}s');
    } on Exception catch (e) {
      return Res.error(e.runtimeType.toString());
    }
  }

  static const _repr = {'Prefer': 'return=representation'};

  Future<Res> select(String table, String query, String? jwt) =>
      send('GET', '/rest/v1/$table?$query', jwt: jwt);

  Future<Res> insert(String table, Map<String, Object?> row, String? jwt) =>
      send('POST', '/rest/v1/$table', jwt: jwt, json: row, headers: _repr);

  Future<Res> update(
    String table,
    String filter,
    Map<String, Object?> patch,
    String? jwt,
  ) => send(
    'PATCH',
    '/rest/v1/$table?$filter',
    jwt: jwt,
    json: patch,
    headers: _repr,
  );

  Future<Res> delete(String table, String filter, String? jwt) =>
      send('DELETE', '/rest/v1/$table?$filter', jwt: jwt, headers: _repr);

  Future<Res> rpc(String fn, Map<String, Object?> args, String? jwt) =>
      send('POST', '/rest/v1/rpc/$fn', jwt: jwt, json: args);

  Future<Res> upload(
    String objectPath,
    Uint8List data,
    String jwt, {
    bool upsert = false,
  }) => send(
    'POST',
    '/storage/v1/object/$_bucket/$objectPath',
    jwt: jwt,
    bytes: data,
    contentType: 'image/png',
    headers: {'x-upsert': upsert ? 'true' : 'false'},
  );

  /// The Storage CDN caches authenticated GETs keyed by URL + Authorization
  /// header and does not invalidate them when RLS access changes (e.g. a share
  /// is revoked). A unique query string forces an origin (RLS-evaluated) read.
  Future<Res> download(String objectPath, String? jwt) => send(
    'GET',
    '/storage/v1/object/$_bucket/$objectPath?nocache=${_randomString(12)}',
    jwt: jwt,
  );

  Future<Res> copyObject(String from, String to, String jwt) => send(
    'POST',
    '/storage/v1/object/copy',
    jwt: jwt,
    json: {'bucketId': _bucket, 'sourceKey': from, 'destinationKey': to},
  );

  Future<Res> removeObjects(List<String> paths, String jwt) => send(
    'DELETE',
    '/storage/v1/object/$_bucket',
    jwt: jwt,
    json: {'prefixes': paths},
  );
}

// -----------------------------------------------------------------------------
// Test context
// -----------------------------------------------------------------------------

class User {
  User(this.label, this.email, this.password);
  final String label;
  final String email;
  final String password;
  late final String id;
  late final String jwt;
}

class Ctx {
  Ctx(this.api, this.r);
  final Api api;
  final Report r;
  final List<User> users = [];

  late User a;
  late User b;
  late User c;

  String? subjectId;
  String? note1Id;
  String? note2Id;
  String? quizSubjectId; // subject-level quiz
  String? quizNoteId; // note-attached quiz
  String? imagePath;
  String? shareBId;
  String? shareCId;
  String? attemptId;
  String? copySubjectId;
  final List<String> bImagePaths = [];
}

// -----------------------------------------------------------------------------
// Expectation helpers
// -----------------------------------------------------------------------------

extension on Ctx {
  bool expectOk(String name, Res res, [String? detail]) =>
      r.check(name, res.ok, () => res.snippet, detail);

  bool expectRows(String name, Res res, int n) => r.check(
    name,
    res.ok && res.rows.length == n,
    () => res.ok ? 'expected $n row(s), got ${res.rows.length}' : res.snippet,
  );

  /// Readable set is empty: 2xx with no rows (or, when [allowDenied], a 401/403).
  bool expectNothing(String name, Res res, {bool allowDenied = false}) {
    final denied = allowDenied && (res.status == 401 || res.status == 403);
    return r.check(
      name,
      denied || (res.ok && res.rows.isEmpty),
      () => res.ok ? 'expected no rows, got ${res.rows.length}' : res.snippet,
      denied ? 'HTTP ${res.status}' : null,
    );
  }

  /// A write must be rejected (non-2xx).
  bool expectRejected(String name, Res res, {String? wantCode}) {
    final codeOk = wantCode == null || res.code == wantCode;
    return r.check(
      name,
      res.status > 0 && !res.ok && codeOk,
      () => res.ok
          ? 'expected an error, got ${res.snippet}'
          : 'expected code ${wantCode ?? 'any'}, got ${res.snippet}',
      'HTTP ${res.status}${res.code == null ? '' : ' ${res.code}'}',
    );
  }

  /// UPDATE/DELETE of a row the caller cannot write: PostgREST either errors
  /// or silently affects 0 rows.
  bool expectNoEffect(String name, Res res) => r.check(
    name,
    (res.status > 0 && !res.ok) || (res.ok && res.rows.isEmpty),
    () => res.ok ? 'affected ${res.rows.length} row(s)' : res.snippet,
    res.ok ? '0 rows affected' : 'HTTP ${res.status}',
  );

  bool expectDownload(String name, Res res) => r.check(
    name,
    res.ok && _sameBytes(res.bytes, _png),
    () => res.ok
        ? 'downloaded ${res.bytes.length} bytes, content differs'
        : res.snippet,
  );

  bool expectNoDownload(String name, Res res) => r.check(
    name,
    res.status > 0 && !res.ok,
    () => res.ok ? 'object was downloadable' : res.snippet,
    'HTTP ${res.status}',
  );

  void require(bool ok, String what) {
    if (!ok) throw _Abort(what);
  }
}

bool _sameBytes(List<int> x, List<int> y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

// -----------------------------------------------------------------------------
// Steps
// -----------------------------------------------------------------------------

Future<User> _signUp(Ctx ctx, String label, String domain) async {
  final email = 'smoke+${_randomString(10)}@$domain';
  final password =
      '${_randomString(20, 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789')}aA9!';
  ctx.r.addSecret(password);
  final u = User(label, email, password);
  final res = await ctx.api.send(
    'POST',
    '/auth/v1/signup',
    json: {
      'email': email,
      'password': password,
      'data': {'display_name': 'Smoke $label'},
    },
  );
  if (!res.ok) {
    ctx.r.fail('sign up user $label ($email)', res.snippet);
    if (res.status == 429) {
      ctx.r.line(
        '      Hint: rate limited. If "Confirm email" is on, turn it OFF '
        '(Authentication -> Sign In / Providers -> Email); otherwise wait and retry.',
      );
    } else if (res.body.toLowerCase().contains('invalid')) {
      ctx.r.line(
        '      Hint: the project rejected the email address. Re-run with '
        '--email-domain=<a domain with MX records you control>.',
      );
    }
    throw _Abort('sign-up failed');
  }
  final body = res.map;
  final session = body['session'] is Map<String, Object?>
      ? body['session']! as Map<String, Object?>
      : body;
  final token = _str(session, 'access_token');
  final userMap = session['user'] is Map<String, Object?>
      ? session['user']! as Map<String, Object?>
      : (body['user'] is Map<String, Object?>
            ? body['user']! as Map<String, Object?>
            : body);
  final id = _str(userMap, 'id');
  if (token == null || id == null) {
    ctx.r.fail(
      'sign up user $label ($email)',
      'HTTP ${res.status} but no session was returned',
    );
    ctx.r.line(
      '\n  Sign-up did not return a session. This test needs email confirmation\n'
      '  disabled: Dashboard -> Authentication -> Sign In / Providers -> Email ->\n'
      '  turn OFF "Confirm email", save, and run the test again.\n'
      '  (A user may have been created: $email - delete it in Authentication -> Users.)',
    );
    throw _Abort('no session from sign-up ("Confirm email" is on)');
  }
  ctx.r.addSecret(token);
  u
    ..id = id
    ..jwt = token;
  ctx.r.pass('sign up user $label', email);
  return u;
}

List<Map<String, Object?>> _questions() => [
  {
    'id': _uuid(),
    'type': 'mcq_single',
    'prompt': 'Smoke: 2 + 2 = ?',
    'options': ['3', '4', '5'],
    'correct_indices': [1],
    'answer_text': null,
    'explanation': 'Basic arithmetic.',
  },
  {
    'id': _uuid(),
    'type': 'mcq_multi',
    'prompt': 'Smoke: pick the primes',
    'options': ['2', '3', '4', '5'],
    'correct_indices': [0, 1, 3],
    'answer_text': null,
    'explanation': null,
  },
  {
    'id': _uuid(),
    'type': 'true_false',
    'prompt': 'Smoke: the sky is blue',
    'options': ['True', 'False'],
    'correct_indices': [0],
    'answer_text': null,
    'explanation': null,
  },
  {
    'id': _uuid(),
    'type': 'short_answer',
    'prompt': 'Smoke: capital of France?',
    'options': <String>[],
    'correct_indices': <int>[],
    'answer_text': 'Paris',
    'explanation': null,
  },
];

Future<void> _step1SignUp(Ctx ctx, String domain) async {
  ctx.r.section('1. Sign up three users');
  for (final label in ['A', 'B', 'C']) {
    ctx.users.add(await _signUp(ctx, label, domain));
  }
  ctx
    ..a = ctx.users[0]
    ..b = ctx.users[1]
    ..c = ctx.users[2];
}

Future<void> _step2Profiles(Ctx ctx) async {
  ctx.r.section('2. Profiles auto-created');
  for (final u in ctx.users) {
    final res = await ctx.api.select(
      'profiles',
      'id=eq.${u.id}&select=id,email,display_name',
      u.jwt,
    );
    final rows = res.rows;
    ctx.r.check(
      'profile row exists for ${u.label}',
      res.ok && rows.length == 1 && _str(rows.first, 'email') == u.email,
      () => res.ok ? 'got ${rows.length} row(s): ${res.snippet}' : res.snippet,
      rows.isEmpty ? null : 'display_name=${_str(rows.first, 'display_name')}',
    );
  }
  ctx.expectNothing(
    'B cannot read A\'s profile before any share',
    await ctx.api.select('profiles', 'id=eq.${ctx.a.id}', ctx.b.jwt),
  );
}

Future<void> _step3Create(Ctx ctx) async {
  ctx.r.section('3. User A creates content');
  final api = ctx.api;
  final a = ctx.a;

  final subjectId = _uuid();
  var res = await api.insert('subjects', {
    'id': subjectId,
    'title': 'Smoke subject',
    'description': 'Created by supabase_smoke_test.dart',
    'color': 4282339765,
    'created_at': _now(),
  }, a.jwt);
  final subjectOk = ctx.r.check(
    'A creates subject',
    res.ok && res.rows.length == 1 && _str(res.rows.first, 'owner_id') == a.id,
    () => res.ok ? 'unexpected body: ${res.snippet}' : res.snippet,
  );
  ctx.require(subjectOk, 'subject creation failed');
  ctx.subjectId = subjectId;

  final note1Id = _uuid();
  final imagePath = '${a.id}/$note1Id/x.png';
  res = await api.insert('notes', {
    'id': note1Id,
    'subject_id': subjectId,
    'title': 'Smoke note 1',
    'content_md': '# Smoke\n\nImage: ![x](note-image://$imagePath)\n',
  }, a.jwt);
  ctx.require(
    ctx.expectRows('A creates note in subject', res, 1),
    'note creation failed',
  );
  ctx.note1Id = note1Id;

  final quizS = _uuid();
  res = await api.insert('quizzes', {
    'id': quizS,
    'subject_id': subjectId,
    'title': 'Smoke subject quiz',
    'source': {'provider': 'smoke', 'model': 'none'},
    'questions': _questions(),
  }, a.jwt);
  final quizSOk = ctx.r.check(
    'A creates subject-level quiz (one question of each type)',
    res.ok &&
        res.rows.length == 1 &&
        (res.rows.first['questions'] as List?)?.length == 4,
    () => res.ok ? 'unexpected body: ${res.snippet}' : res.snippet,
  );
  ctx.require(quizSOk, 'quiz creation failed');
  ctx.quizSubjectId = quizS;

  final quizN = _uuid();
  res = await api.insert('quizzes', {
    'id': quizN,
    'subject_id': subjectId,
    'note_id': note1Id,
    'title': 'Smoke note quiz',
    'questions': _questions().sublist(0, 2),
  }, a.jwt);
  ctx.require(
    ctx.expectRows('A creates note-attached quiz', res, 1),
    'note quiz creation failed',
  );
  ctx.quizNoteId = quizN;

  res = await api.upload(imagePath, _png, a.jwt);
  ctx.require(
    ctx.expectOk('A uploads image to $_bucket/{A}/{note}/x.png', res),
    'upload failed',
  );
  ctx.imagePath = imagePath;
  ctx.expectDownload(
    'A downloads own image',
    await api.download(imagePath, a.jwt),
  );
}

Future<void> _expectSeesNothingOfA(Ctx ctx, User u, {bool image = true}) async {
  final api = ctx.api;
  ctx.expectNothing(
    '${u.label} cannot see A\'s subject',
    await api.select('subjects', 'id=eq.${ctx.subjectId}', u.jwt),
  );
  ctx.expectNothing(
    '${u.label} cannot see A\'s notes',
    await api.select('notes', 'subject_id=eq.${ctx.subjectId}', u.jwt),
  );
  ctx.expectNothing(
    '${u.label} cannot see A\'s quizzes',
    await api.select(
      'quizzes',
      'id=in.(${ctx.quizSubjectId},${ctx.quizNoteId})',
      u.jwt,
    ),
  );
  if (image) {
    ctx.expectNoDownload(
      '${u.label} cannot download A\'s image',
      await api.download(ctx.imagePath!, u.jwt),
    );
  }
}

Future<void> _step4RlsNegative(Ctx ctx) async {
  ctx.r.section('4. RLS negative checks');
  final api = ctx.api;
  final a = ctx.a;
  final b = ctx.b;

  await _expectSeesNothingOfA(ctx, b);
  await _expectSeesNothingOfA(ctx, ctx.c);

  final rogueNote = _uuid();
  ctx.expectRejected(
    'B cannot insert a note into A\'s subject',
    await api.insert('notes', {
      'id': rogueNote,
      'subject_id': ctx.subjectId,
      'title': 'rogue',
    }, b.jwt),
  );
  ctx.expectNothing(
    '  ...and no such note exists for A',
    await api.select('notes', 'id=eq.$rogueNote', a.jwt),
  );

  ctx.expectRejected(
    'B cannot insert a quiz into A\'s subject',
    await api.insert('quizzes', {
      'id': _uuid(),
      'subject_id': ctx.subjectId,
      'title': 'rogue',
    }, b.jwt),
  );

  ctx.expectRejected(
    'B cannot insert a note with owner_id = A',
    await api.insert('notes', {
      'id': _uuid(),
      'subject_id': ctx.subjectId,
      'owner_id': a.id,
      'title': 'rogue',
    }, b.jwt),
  );

  ctx.expectRejected(
    'B cannot share A\'s subject',
    await api.insert('shares', {
      'recipient_id': ctx.c.id,
      'resource_type': 'subject',
      'resource_id': ctx.subjectId,
    }, b.jwt),
  );

  ctx.expectRejected(
    'B cannot upload into A\'s storage folder',
    await api.upload('${a.id}/${ctx.note1Id}/rogue.png', _png, b.jwt),
  );

  ctx.expectRejected(
    'A cannot change owner_id of own subject',
    await api.update('subjects', 'id=eq.${ctx.subjectId}', {
      'owner_id': b.id,
    }, a.jwt),
  );
  final res = await api.select(
    'subjects',
    'id=eq.${ctx.subjectId}&select=owner_id',
    a.jwt,
  );
  ctx.r.check(
    '  ...subject still owned by A',
    res.ok && res.rows.length == 1 && _str(res.rows.first, 'owner_id') == a.id,
    () => res.snippet,
  );

  // anon: only the apikey header, no user JWT.
  for (final table in [
    'subjects',
    'notes',
    'quizzes',
    'quiz_attempts',
    'shares',
    'profiles',
  ]) {
    ctx.expectNothing(
      'anon sees nothing in $table',
      await api.select(table, 'select=*&limit=5', null),
      allowDenied: true,
    );
  }
  ctx.expectRejected(
    'anon cannot call find_user_by_email',
    await api.rpc('find_user_by_email', {'p_email': a.email}, null),
  );
  ctx.expectRejected(
    'anon cannot insert a subject',
    await api.insert('subjects', {'id': _uuid(), 'title': 'anon'}, null),
  );
  ctx.expectNoDownload(
    'anon cannot download A\'s image',
    await api.download(ctx.imagePath!, null),
  );
}

Future<String?> _findUser(Ctx ctx, User asker, User target) async {
  // Upper-case + padding: the lookup is case-insensitive and trimmed.
  final res = await ctx.api.rpc('find_user_by_email', {
    'p_email': '  ${target.email.toUpperCase()} ',
  }, asker.jwt);
  final rows = res.rows;
  final ok = res.ok && rows.length == 1 && _str(rows.first, 'id') == target.id;
  ctx.r.check(
    '${asker.label} finds ${target.label} via find_user_by_email',
    ok,
    () => res.ok ? 'got ${rows.length} row(s)' : res.snippet,
  );
  return ok ? target.id : null;
}

Future<void> _step5Share(Ctx ctx) async {
  ctx.r.section('5. A shares the subject with B');
  final api = ctx.api;
  final a = ctx.a;
  final b = ctx.b;

  ctx.expectNothing(
    'find_user_by_email returns nothing for unknown email',
    await api.rpc('find_user_by_email', {
      'p_email': 'nobody-${_randomString(12)}@example.com',
    }, a.jwt),
  );
  ctx.expectNothing(
    'find_user_by_email does not do wildcard matches',
    await api.rpc('find_user_by_email', {'p_email': 'smoke+%'}, a.jwt),
  );

  final bId = await _findUser(ctx, a, b);
  ctx.require(bId != null, 'could not resolve B');

  var res = await api.insert('shares', {
    'recipient_id': bId,
    'resource_type': 'subject',
    'resource_id': ctx.subjectId,
  }, a.jwt);
  final shareOk = ctx.r.check(
    'A shares subject with B',
    res.ok && res.rows.length == 1 && _str(res.rows.first, 'owner_id') == a.id,
    () => res.snippet,
  );
  ctx.require(shareOk, 'share insert failed');
  ctx.shareBId = _str(res.rows.first, 'id');

  ctx.expectRows(
    'B sees A\'s subject',
    await api.select('subjects', 'id=eq.${ctx.subjectId}', b.jwt),
    1,
  );
  ctx.expectRows(
    'B sees A\'s note',
    await api.select('notes', 'id=eq.${ctx.note1Id}', b.jwt),
    1,
  );
  ctx.expectRows(
    'B sees both of A\'s quizzes',
    await api.select(
      'quizzes',
      'id=in.(${ctx.quizSubjectId},${ctx.quizNoteId})',
      b.jwt,
    ),
    2,
  );
  ctx.expectDownload(
    'B downloads A\'s image',
    await api.download(ctx.imagePath!, b.jwt),
  );
  ctx.expectRows(
    'B sees the share row',
    await api.select('shares', 'id=eq.${ctx.shareBId}', b.jwt),
    1,
  );
  ctx.expectRows(
    'B can now read A\'s profile',
    await api.select('profiles', 'id=eq.${a.id}', b.jwt),
    1,
  );
  ctx.expectRows(
    'share_details gives B the resource title',
    await api.select(
      'share_details',
      'id=eq.${ctx.shareBId}&resource_title=eq.Smoke%20subject',
      b.jwt,
    ),
    1,
  );

  // B cannot modify A's rows.
  ctx.expectNoEffect(
    'B cannot update A\'s subject',
    await api.update('subjects', 'id=eq.${ctx.subjectId}', {
      'title': 'hacked',
    }, b.jwt),
  );
  ctx.expectNoEffect(
    'B cannot update A\'s note',
    await api.update('notes', 'id=eq.${ctx.note1Id}', {
      'content_md': 'hacked',
    }, b.jwt),
  );
  ctx.expectNoEffect(
    'B cannot update A\'s quiz',
    await api.update('quizzes', 'id=eq.${ctx.quizSubjectId}', {
      'title': 'hacked',
    }, b.jwt),
  );
  ctx.expectNoEffect(
    'B cannot soft-delete A\'s note',
    await api.update('notes', 'id=eq.${ctx.note1Id}', {
      'deleted_at': _now(),
    }, b.jwt),
  );
  ctx.expectNoEffect(
    'B cannot delete A\'s quiz',
    await api.delete('quizzes', 'id=eq.${ctx.quizNoteId}', b.jwt),
  );
  ctx.expectNoEffect(
    'B cannot delete A\'s note',
    await api.delete('notes', 'id=eq.${ctx.note1Id}', b.jwt),
  );
  ctx.expectNoEffect(
    'B cannot delete A\'s subject',
    await api.delete('subjects', 'id=eq.${ctx.subjectId}', b.jwt),
  );
  ctx.expectNoEffect(
    'B cannot delete A\'s share',
    await api.delete('shares', 'id=eq.${ctx.shareBId}', b.jwt),
  );
  ctx.expectRejected(
    'B cannot overwrite A\'s image',
    await api.upload(ctx.imagePath!, _png, b.jwt, upsert: true),
  );

  res = await api.select(
    'subjects',
    'id=eq.${ctx.subjectId}&select=title',
    a.jwt,
  );
  ctx.r.check(
    '  ...A\'s subject unchanged',
    res.ok &&
        res.rows.length == 1 &&
        _str(res.rows.first, 'title') == 'Smoke subject',
    () => res.snippet,
  );
  res = await api.select(
    'notes',
    'id=eq.${ctx.note1Id}&select=content_md,deleted_at',
    a.jwt,
  );
  ctx.r.check(
    '  ...A\'s note unchanged',
    res.ok &&
        res.rows.length == 1 &&
        _str(res.rows.first, 'content_md') != 'hacked' &&
        res.rows.first['deleted_at'] == null,
    () => res.snippet,
  );
  ctx.expectRows(
    '  ...A\'s quizzes still exist',
    await api.select(
      'quizzes',
      'id=in.(${ctx.quizSubjectId},${ctx.quizNoteId})&title=neq.hacked',
      a.jwt,
    ),
    2,
  );
  ctx.expectRows(
    '  ...A\'s share still exists',
    await api.select('shares', 'id=eq.${ctx.shareBId}', a.jwt),
    1,
  );

  await _expectSeesNothingOfA(ctx, ctx.c);

  // Live share: content created after sharing is visible too.
  final note2Id = _uuid();
  res = await api.insert('notes', {
    'id': note2Id,
    'subject_id': ctx.subjectId,
    'title': 'Smoke note 2 (after share)',
    'content_md': 'second note',
  }, a.jwt);
  if (ctx.expectRows('A creates a second note after sharing', res, 1)) {
    ctx.note2Id = note2Id;
    ctx.expectRows(
      'B sees the new note (live share)',
      await api.select('notes', 'id=eq.$note2Id', b.jwt),
      1,
    );
  }
}

Future<void> _step6NoteShare(Ctx ctx) async {
  ctx.r.section('6. Duplicate share, note-only share with C');
  final api = ctx.api;
  final a = ctx.a;
  final c = ctx.c;

  final dup = await api.insert('shares', {
    'recipient_id': ctx.b.id,
    'resource_type': 'subject',
    'resource_id': ctx.subjectId,
  }, a.jwt);
  ctx.expectRejected(
    'duplicate share is rejected (unique violation)',
    dup,
    wantCode: '23505',
  );

  ctx.expectRejected(
    'A cannot share with self',
    await api.insert('shares', {
      'recipient_id': a.id,
      'resource_type': 'subject',
      'resource_id': ctx.subjectId,
    }, a.jwt),
  );

  final cId = await _findUser(ctx, a, c);
  ctx.require(cId != null, 'could not resolve C');
  final res = await api.insert('shares', {
    'recipient_id': cId,
    'resource_type': 'note',
    'resource_id': ctx.note1Id,
  }, a.jwt);
  ctx.require(
    ctx.expectRows('A shares note 1 (only) with C', res, 1),
    'note share failed',
  );
  ctx.shareCId = _str(res.rows.first, 'id');

  ctx.expectRows(
    'C sees the shared note',
    await api.select('notes', 'id=eq.${ctx.note1Id}', c.jwt),
    1,
  );
  ctx.expectRows(
    'C sees the note-attached quiz',
    await api.select('quizzes', 'id=eq.${ctx.quizNoteId}', c.jwt),
    1,
  );
  ctx.expectDownload(
    'C downloads the shared note\'s image',
    await api.download(ctx.imagePath!, c.jwt),
  );
  ctx.expectNothing(
    'C cannot see the subject',
    await api.select('subjects', 'id=eq.${ctx.subjectId}', c.jwt),
  );
  if (ctx.note2Id != null) {
    ctx.expectNothing(
      'C cannot see the sibling note',
      await api.select('notes', 'id=eq.${ctx.note2Id}', c.jwt),
    );
  }
  ctx.expectNothing(
    'C cannot see the subject-level quiz',
    await api.select('quizzes', 'id=eq.${ctx.quizSubjectId}', c.jwt),
  );
}

Future<void> _step7Attempt(Ctx ctx) async {
  ctx.r.section('7. B records a quiz attempt on A\'s quiz');
  final api = ctx.api;
  final b = ctx.b;
  final attemptId = _uuid();
  final started = DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 2))
      .toIso8601String();
  var res = await api.insert('quiz_attempts', {
    'id': attemptId,
    'quiz_id': ctx.quizSubjectId,
    'answers': [
      {
        'question_id': _uuid(),
        'selected_indices': [1],
        'text_answer': null,
        'is_correct': true,
      },
      {
        'question_id': _uuid(),
        'selected_indices': <int>[],
        'text_answer': 'Paris',
        'is_correct': null,
      },
    ],
    'score': 1.0,
    'total': 2,
    'started_at': started,
    'completed_at': _now(),
  }, b.jwt);
  final ok = ctx.r.check(
    'B records an attempt on A\'s subject quiz',
    res.ok && res.rows.length == 1 && _str(res.rows.first, 'owner_id') == b.id,
    () => res.snippet,
  );
  if (!ok) return;
  ctx.attemptId = attemptId;

  ctx.expectRows(
    'B sees own attempt',
    await api.select('quiz_attempts', 'id=eq.$attemptId', b.jwt),
    1,
  );
  ctx.expectNothing(
    'A cannot see B\'s attempt',
    await api.select('quiz_attempts', 'id=eq.$attemptId', ctx.a.jwt),
  );
  ctx.expectNothing(
    'C cannot see B\'s attempt',
    await api.select('quiz_attempts', 'id=eq.$attemptId', ctx.c.jwt),
  );
  ctx.expectNoEffect(
    'A cannot modify B\'s attempt',
    await api.update('quiz_attempts', 'id=eq.$attemptId', {
      'score': 0,
    }, ctx.a.jwt),
  );
  ctx.expectRejected(
    'C cannot record an attempt on a quiz it cannot read',
    await api.insert('quiz_attempts', {
      'id': _uuid(),
      'quiz_id': ctx.quizSubjectId,
    }, ctx.c.jwt),
  );
  res = await api.update('quiz_attempts', 'id=eq.$attemptId', {
    'quiz_id': ctx.quizNoteId,
  }, b.jwt);
  ctx.expectRejected('B cannot change quiz_id of the attempt', res);
}

Future<void> _step8Copy(Ctx ctx) async {
  ctx.r.section('8. B copies the shared subject (copy_subject + image copies)');
  final api = ctx.api;
  final b = ctx.b;

  var res = await api.rpc('copy_subject', {
    'p_subject_id': ctx.subjectId,
  }, b.jwt);
  final newId = res.json is String ? res.json! as String : null;
  ctx.require(
    ctx.r.check(
      'B calls copy_subject',
      res.ok && newId != null,
      () => res.snippet,
    ),
    'copy_subject failed',
  );
  ctx.copySubjectId = newId;

  res = await api.select('subjects', 'id=eq.$newId', b.jwt);
  ctx.r.check(
    'copied subject is owned by B',
    res.ok && res.rows.length == 1 && _str(res.rows.first, 'owner_id') == b.id,
    () => res.snippet,
  );
  final expectedNotes = ctx.note2Id == null ? 1 : 2;
  res = await api.select(
    'notes',
    'subject_id=eq.$newId&select=id,owner_id,content_md',
    b.jwt,
  );
  final notes = res.rows;
  ctx.r.check(
    'copied notes ($expectedNotes) are owned by B',
    res.ok &&
        notes.length == expectedNotes &&
        notes.every((n) => _str(n, 'owner_id') == b.id),
    () => res.ok ? 'got ${notes.length} note(s)' : res.snippet,
  );
  final rewritten = notes
      .where(
        (n) => (_str(n, 'content_md') ?? '').contains('note-image://${b.id}/'),
      )
      .toList();
  ctx.r.check(
    'copied note content points images at B\'s folder',
    rewritten.length == 1,
    () => 'found ${rewritten.length} note(s) with rewritten image references',
  );
  res = await api.select(
    'quizzes',
    'subject_id=eq.$newId&select=id,owner_id,note_id,questions',
    b.jwt,
  );
  final quizzes = res.rows;
  ctx.r.check(
    'copied quizzes (subject-level + note-attached) are owned by B',
    res.ok &&
        quizzes.length == 2 &&
        quizzes.every((q) => _str(q, 'owner_id') == b.id) &&
        quizzes.where((q) => q['note_id'] != null).length == 1,
    () => res.ok ? 'got ${quizzes.length} quiz(zes)' : res.snippet,
  );
  ctx.expectNothing(
    'A cannot see B\'s copy',
    await api.select('subjects', 'id=eq.$newId', ctx.a.jwt),
  );

  res = await api.select(
    'note_image_copies',
    'select=id,from_path,to_path',
    b.jwt,
  );
  final copies = res.rows;
  ctx.r.check(
    'note_image_copies has a row for the image',
    res.ok &&
        copies.length == 1 &&
        _str(copies.first, 'from_path') == ctx.imagePath,
    () => res.ok ? 'got ${copies.length} row(s): ${res.snippet}' : res.snippet,
  );
  for (final row in copies) {
    final from = _str(row, 'from_path')!;
    final to = _str(row, 'to_path')!;
    final copyRes = await api.copyObject(from, to, b.jwt);
    if (ctx.expectOk(
      'B copies image via Storage API',
      copyRes,
      to.split('/').skip(1).join('/'),
    )) {
      ctx.bImagePaths.add(to);
      ctx.expectRows(
        'B deletes processed note_image_copies row',
        await api.delete(
          'note_image_copies',
          'id=eq.${_str(row, 'id')}',
          b.jwt,
        ),
        1,
      );
      ctx.expectDownload(
        'B downloads the copied image',
        await api.download(to, b.jwt),
      );
      ctx.expectNoDownload(
        'A cannot download B\'s copied image',
        await api.download(to, ctx.a.jwt),
      );
    }
  }
  ctx.expectNothing(
    'note_image_copies queue is empty',
    await api.select('note_image_copies', 'select=id', b.jwt),
  );
}

Future<void> _step9Revoke(Ctx ctx) async {
  ctx.r.section('9. A revokes B\'s share');
  final api = ctx.api;
  final b = ctx.b;
  final res = await api.delete('shares', 'id=eq.${ctx.shareBId}', ctx.a.jwt);
  ctx.require(ctx.expectRows('A deletes the share', res, 1), 'revoke failed');
  ctx.shareBId = null;

  await _expectSeesNothingOfA(ctx, b);
  if (ctx.copySubjectId != null) {
    ctx.expectRows(
      'B still has its own copy',
      await api.select('subjects', 'id=eq.${ctx.copySubjectId}', b.jwt),
      1,
    );
  }
  ctx.expectRows(
    'C\'s note share is unaffected',
    await api.select('notes', 'id=eq.${ctx.note1Id}', ctx.c.jwt),
    1,
  );
  ctx.expectRejected(
    'B cannot record a new attempt after revocation',
    await api.insert('quiz_attempts', {
      'id': _uuid(),
      'quiz_id': ctx.quizSubjectId,
    }, b.jwt),
  );
}

/// Best effort: problems are reported as WARN and do not fail the run.
Future<void> _cleanup(Ctx ctx) async {
  ctx.r.section('10. Cleanup (best effort)');
  final api = ctx.api;
  if (ctx.users.length < 3) {
    ctx.r.line('INFO  nothing to clean up');
    return;
  }

  Future<void> step(String name, Future<Res> f) async {
    final res = await f;
    ctx.r.line(res.ok ? 'OK    $name' : 'WARN  $name  -- ${res.snippet}');
  }

  final a = ctx.a;
  final b = ctx.b;
  final c = ctx.c;
  if (ctx.bImagePaths.isNotEmpty) {
    await step(
      'B deletes copied images',
      api.removeObjects(ctx.bImagePaths, b.jwt),
    );
  }
  await step(
    'B deletes leftover note_image_copies',
    api.delete('note_image_copies', 'owner_id=eq.${b.id}', b.jwt),
  );
  await step(
    'B deletes own quiz attempts',
    api.delete('quiz_attempts', 'owner_id=eq.${b.id}', b.jwt),
  );
  await step(
    'B deletes own subjects (cascade)',
    api.delete('subjects', 'owner_id=eq.${b.id}', b.jwt),
  );
  await step(
    'C deletes own quiz attempts',
    api.delete('quiz_attempts', 'owner_id=eq.${c.id}', c.jwt),
  );
  await step(
    'C deletes own subjects (cascade)',
    api.delete('subjects', 'owner_id=eq.${c.id}', c.jwt),
  );
  if (ctx.imagePath != null) {
    await step('A deletes image', api.removeObjects([ctx.imagePath!], a.jwt));
  }
  await step(
    'A deletes own shares',
    api.delete('shares', 'owner_id=eq.${a.id}', a.jwt),
  );
  await step(
    'A deletes own subjects (cascade)',
    api.delete('subjects', 'owner_id=eq.${a.id}', a.jwt),
  );

  final left = await api.select(
    'subjects',
    'owner_id=eq.${a.id}&select=id',
    a.jwt,
  );
  ctx.r.line(
    left.ok && left.rows.isEmpty
        ? 'OK    A has no subjects left'
        : 'WARN  A still has data: ${left.snippet}',
  );
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

File _findEnv(String? explicit) {
  if (explicit != null) return File(explicit);
  final cwd = File('env.json');
  if (cwd.existsSync()) return cwd;
  try {
    final repoRoot = File.fromUri(Platform.script).parent.parent;
    final f = File('${repoRoot.path}${Platform.pathSeparator}env.json');
    if (f.existsSync()) return f;
  } on Object {
    // Platform.script is not a file (e.g. snapshot); fall through.
  }
  return cwd;
}

Future<void> main(List<String> args) async {
  String? envPath;
  var domain = 'example.com';
  for (final arg in args) {
    if (arg == '-h' || arg == '--help') {
      stdout.writeln(
        'Usage: dart run scripts/supabase_smoke_test.dart [path/to/env.json] [--email-domain=example.com]',
      );
      return;
    } else if (arg.startsWith('--email-domain=')) {
      domain = arg.substring('--email-domain='.length);
    } else if (!arg.startsWith('-')) {
      envPath = arg;
    } else {
      stderr.writeln('Unknown option: $arg');
      exit(2);
    }
  }

  final envFile = _findEnv(envPath);
  if (!envFile.existsSync()) {
    stderr.writeln(
      'env file not found: ${envFile.path} (copy env.example.json to env.json)',
    );
    exit(2);
  }
  final Object? env;
  try {
    env = jsonDecode(envFile.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('${envFile.path} is not valid JSON: ${e.message}');
    exit(2);
  }
  final envMap = env is Map<String, Object?> ? env : const <String, Object?>{};
  final url = _str(envMap, 'SUPABASE_URL');
  final key = _str(envMap, 'SUPABASE_ANON_KEY');
  if (url == null ||
      key == null ||
      url.isEmpty ||
      key.isEmpty ||
      url.contains('YOUR-PROJECT-REF') ||
      key.startsWith('YOUR-')) {
    stderr.writeln(
      '${envFile.path} must set SUPABASE_URL and SUPABASE_ANON_KEY (not the placeholders).',
    );
    exit(2);
  }

  final report = Report()..addSecret(key);
  final api = Api(url, key);
  final ctx = Ctx(api, report);
  report.line(
    'Supabase smoke test against ${api.base}  (env: ${envFile.path})',
  );

  try {
    await _step1SignUp(ctx, domain);
    await _step2Profiles(ctx);
    await _step3Create(ctx);
    await _step4RlsNegative(ctx);
    await _step5Share(ctx);
    await _step6NoteShare(ctx);
    await _step7Attempt(ctx);
    await _step8Copy(ctx);
    await _step9Revoke(ctx);
  } on _Abort catch (e) {
    report.fail('ABORTED', '${e.reason}; remaining checks skipped');
  } on Object catch (e) {
    report.fail(
      'ABORTED',
      'unexpected ${e.runtimeType}: ${report.scrub(e.toString())}',
    );
  }

  try {
    await _cleanup(ctx);
  } on Object catch (e) {
    report.line('WARN  cleanup stopped: ${e.runtimeType}');
  }
  api.close();

  if (ctx.users.isNotEmpty) {
    report.line(
      '\nTest users (delete them in Dashboard -> Authentication -> Users):',
    );
    for (final u in ctx.users) {
      report.line('  ${u.label}: ${u.email}');
    }
  }
  final failed = report.failures.length;
  report.line('\n== Summary: ${report.passed} passed, $failed failed');
  if (failed > 0) {
    for (final f in report.failures) {
      report.line('  - $f');
    }
  }
  await stdout.flush();
  exit(failed > 0 ? 1 : 0);
}
