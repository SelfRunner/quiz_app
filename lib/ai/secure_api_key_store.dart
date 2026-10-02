import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/errors/app_exception.dart';
import 'ai_source.dart';
import 'api_key_store.dart';
import 'base_url_policy.dart';
import 'llm_provider.dart';

/// Minimal key-value backend so [SecureApiKeyStore] can be tested without
/// platform channels.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// All stored keys (values are not returned).
  Future<Set<String>> keys();
}

/// [SecureKeyValueStore] backed by `flutter_secure_storage`.
///
/// Platform guarantees differ:
/// * Android: values are encrypted with a key held in the Android Keystore.
/// * macOS/iOS: Keychain. Linux: libsecret. Windows: DPAPI-encrypted file.
/// * **Web: much weaker.** Values are AES-encrypted with WebCrypto, but the
///   wrapping key lives in the same browser storage, so anything running in
///   the page origin (an XSS payload, a malicious extension) can read the
///   keys. Treat API keys entered on web as "remembered by this browser",
///   not as secrets protected at rest; users can remove them in Settings.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _guard(() => _storage.read(key: key));

  @override
  Future<void> write(String key, String value) =>
      _guard(() => _storage.write(key: key, value: value));

  @override
  Future<void> delete(String key) => _guard(() => _storage.delete(key: key));

  @override
  Future<Set<String>> keys() =>
      _guard(() async => (await _storage.readAll()).keys.toSet());

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e, st) {
      // Never include values in the message; the cause is the plugin error.
      throw StorageException(
        'Could not access secure storage on this device.',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

/// In-memory [SecureKeyValueStore] for tests and previews.
class InMemoryKeyValueStore implements SecureKeyValueStore {
  InMemoryKeyValueStore([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}

/// [ApiKeyStore] on top of a [SecureKeyValueStore] (flutter_secure_storage
/// in the app). Everything here stays on the device; nothing is synced.
///
/// Entries are namespaced by [userId] (`ai.u.<userId>.<entry>`). With a null
/// [userId] (signed out) reads return nothing and writes throw
/// [AppAuthException].
///
/// Migration: entries written before namespacing (`ai.<entry>`) are moved to
/// the first signed-in user that uses a store (existing values of that user
/// win), then deleted, so later users never see them.
class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore({required this.userId, SecureKeyValueStore? backend})
    : _kv = backend ?? FlutterSecureKeyValueStore();

  /// Supabase user id the store is bound to; null when signed out.
  final String? userId;

  final SecureKeyValueStore _kv;

  static const _prefix = 'ai.';

  static String _apiKeyEntry(LlmProviderId p) => 'api_key.${p.wireName}';
  static String _baseUrlEntry(LlmProviderId p) => 'base_url.${p.wireName}';
  static String _modelEntry(LlmProviderId p) => 'model.${p.wireName}';
  static String _headersEntry(LlmProviderId p) => 'headers.${p.wireName}';
  static String _capsEntry(LlmProviderId p) => 'caps.${p.wireName}';
  static const _selectedProviderEntry = 'selected_provider';

  /// Every entry name a user namespace can hold.
  static List<String> get _allEntries => [
    for (final p in LlmProviderId.values) ...[
      _apiKeyEntry(p),
      _baseUrlEntry(p),
      _modelEntry(p),
      _headersEntry(p),
      _capsEntry(p),
    ],
    _selectedProviderEntry,
  ];

  static String _userKey(String userId, String entry) =>
      '${_prefix}u.$userId.$entry';
  static String _legacyKey(String entry) => '$_prefix$entry';

  Future<void>? _migration;

  /// Moves legacy un-namespaced entries to the current user (once).
  Future<void> _ready() async {
    final uid = userId;
    if (uid == null) return;
    final m = _migration ??= _migrateLegacy(uid);
    try {
      await m;
    } catch (_) {
      // Retry on the next call instead of caching the failure.
      if (identical(_migration, m)) _migration = null;
      rethrow;
    }
  }

  Future<void> _migrateLegacy(String uid) async {
    for (final entry in _allEntries) {
      final legacy = _legacyKey(entry);
      final value = await _kv.read(legacy);
      if (value == null) continue;
      final target = _userKey(uid, entry);
      if (await _kv.read(target) == null) await _kv.write(target, value);
      await _kv.delete(legacy);
    }
  }

  Future<String?> _read(String entry) async {
    final uid = userId;
    if (uid == null) return null;
    await _ready();
    return _kv.read(_userKey(uid, entry));
  }

  Future<void> _write(String entry, String value) async {
    final uid = userId;
    if (uid == null) {
      throw const AppAuthException('Sign in to save AI settings.');
    }
    await _ready();
    await _kv.write(_userKey(uid, entry), value);
  }

  Future<void> _delete(String entry) async {
    final uid = userId;
    if (uid == null) return;
    await _ready();
    await _kv.delete(_userKey(uid, entry));
  }

  @override
  Future<String?> getApiKey(LlmProviderId provider) async =>
      _nonEmpty(await _read(_apiKeyEntry(provider)));

  @override
  Future<void> setApiKey(LlmProviderId provider, String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return deleteApiKey(provider);
    await _write(_apiKeyEntry(provider), key);
  }

  @override
  Future<void> deleteApiKey(LlmProviderId provider) =>
      _delete(_apiKeyEntry(provider));

  @override
  Future<String?> getBaseUrl(LlmProviderId provider) async =>
      _nonEmpty(await _read(_baseUrlEntry(provider)));

  @override
  Future<void> setBaseUrl(LlmProviderId provider, String? baseUrl) async {
    final url = baseUrl?.trim() ?? '';
    if (url.isEmpty) return _delete(_baseUrlEntry(provider));
    await _write(_baseUrlEntry(provider), normalizeBaseUrl(url));
  }

  @override
  Future<LlmProviderId?> getSelectedProvider() async =>
      LlmProviderId.fromWireName(await _read(_selectedProviderEntry));

  @override
  Future<void> setSelectedProvider(LlmProviderId provider) =>
      _write(_selectedProviderEntry, provider.wireName);

  @override
  Future<String?> getSelectedModel(LlmProviderId provider) async =>
      _nonEmpty(await _read(_modelEntry(provider)));

  @override
  Future<void> setSelectedModel(LlmProviderId provider, String model) async {
    final m = model.trim();
    if (m.isEmpty) return _delete(_modelEntry(provider));
    await _write(_modelEntry(provider), m);
  }

  @override
  Future<Map<String, String>> getExtraHeaders(LlmProviderId provider) async {
    final raw = await _read(_headersEntry(provider));
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } on FormatException {
      return const {};
    }
  }

  @override
  Future<void> setExtraHeaders(
    LlmProviderId provider,
    Map<String, String> headers,
  ) async {
    final clean = {
      for (final e in headers.entries)
        if (e.key.trim().isNotEmpty) e.key.trim(): e.value.trim(),
    };
    if (clean.isEmpty) return _delete(_headersEntry(provider));
    await _write(_headersEntry(provider), jsonEncode(clean));
  }

  /// `{model: [kind names]}` for [provider].
  Future<Map<String, List<String>>> _readOverrides(
    LlmProviderId provider,
  ) async {
    final raw = await _read(_capsEntry(provider));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is List)
            e.key.toString(): [
              for (final v in e.value as List)
                if (v is String) v,
            ],
      };
    } on FormatException {
      return {};
    }
  }

  @override
  Future<Set<AiInputKind>> getInputOverride(
    LlmProviderId provider,
    String model,
  ) async {
    final names = (await _readOverrides(provider))[model.trim()] ?? const [];
    return {
      for (final k in AiInputKind.values)
        if (names.contains(k.name)) k,
    };
  }

  @override
  Future<void> setInputOverride(
    LlmProviderId provider,
    String model,
    Set<AiInputKind> kinds,
  ) async {
    final m = model.trim();
    if (m.isEmpty) return;
    final all = await _readOverrides(provider);
    final names = [
      for (final k in AiInputKind.values)
        if (kinds.contains(k) && k != AiInputKind.text) k.name,
    ];
    if (names.isEmpty) {
      all.remove(m);
    } else {
      all[m] = names;
    }
    if (all.isEmpty) return _delete(_capsEntry(provider));
    await _write(_capsEntry(provider), jsonEncode(all));
  }

  @override
  Future<Set<LlmProviderId>> configuredProviders() async {
    final result = <LlmProviderId>{};
    for (final p in LlmProviderId.values) {
      if (await getApiKey(p) != null) result.add(p);
    }
    return result;
  }

  @override
  Future<void> clearForUser(String userId) async {
    // Run the pending migration first so legacy entries that would move to
    // this user are removed too.
    if (userId == this.userId) await _ready();
    for (final entry in _allEntries) {
      await _kv.delete(_userKey(userId, entry));
    }
  }

  @override
  Future<void> clearAll() async {
    for (final key in await _kv.keys()) {
      if (key.startsWith(_prefix)) await _kv.delete(key);
    }
  }

  static String? _nonEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v;
}
