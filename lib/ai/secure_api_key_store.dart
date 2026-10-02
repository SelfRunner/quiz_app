import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/errors/app_exception.dart';
import 'api_key_store.dart';
import 'llm_provider.dart';

/// Minimal key-value backend so [SecureApiKeyStore] can be tested without
/// platform channels.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
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
}

/// [ApiKeyStore] on top of a [SecureKeyValueStore] (flutter_secure_storage
/// in the app). Everything here stays on the device; nothing is synced.
class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore([SecureKeyValueStore? backend])
    : _kv = backend ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _kv;

  static const _prefix = 'ai.';
  static String _apiKeyKey(LlmProviderId p) =>
      '${_prefix}api_key.${p.wireName}';
  static String _baseUrlKey(LlmProviderId p) =>
      '${_prefix}base_url.${p.wireName}';
  static String _modelKey(LlmProviderId p) => '${_prefix}model.${p.wireName}';
  static String _headersKey(LlmProviderId p) =>
      '${_prefix}headers.${p.wireName}';
  static const _selectedProviderKey = '${_prefix}selected_provider';

  @override
  Future<String?> getApiKey(LlmProviderId provider) async =>
      _nonEmpty(await _kv.read(_apiKeyKey(provider)));

  @override
  Future<void> setApiKey(LlmProviderId provider, String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return deleteApiKey(provider);
    await _kv.write(_apiKeyKey(provider), key);
  }

  @override
  Future<void> deleteApiKey(LlmProviderId provider) =>
      _kv.delete(_apiKeyKey(provider));

  @override
  Future<String?> getBaseUrl(LlmProviderId provider) async =>
      _nonEmpty(await _kv.read(_baseUrlKey(provider)));

  @override
  Future<void> setBaseUrl(LlmProviderId provider, String? baseUrl) async {
    final url = baseUrl?.trim() ?? '';
    if (url.isEmpty) return _kv.delete(_baseUrlKey(provider));
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      throw const ValidationException(
        'Enter a full base URL, e.g. https://openrouter.ai/api/v1',
      );
    }
    await _kv.write(_baseUrlKey(provider), url.replaceAll(RegExp(r'/+$'), ''));
  }

  @override
  Future<LlmProviderId?> getSelectedProvider() async =>
      LlmProviderId.fromWireName(await _kv.read(_selectedProviderKey));

  @override
  Future<void> setSelectedProvider(LlmProviderId provider) =>
      _kv.write(_selectedProviderKey, provider.wireName);

  @override
  Future<String?> getSelectedModel(LlmProviderId provider) async =>
      _nonEmpty(await _kv.read(_modelKey(provider)));

  @override
  Future<void> setSelectedModel(LlmProviderId provider, String model) async {
    final m = model.trim();
    if (m.isEmpty) return _kv.delete(_modelKey(provider));
    await _kv.write(_modelKey(provider), m);
  }

  @override
  Future<Map<String, String>> getExtraHeaders(LlmProviderId provider) async {
    final raw = await _kv.read(_headersKey(provider));
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
    if (clean.isEmpty) return _kv.delete(_headersKey(provider));
    await _kv.write(_headersKey(provider), jsonEncode(clean));
  }

  @override
  Future<Set<LlmProviderId>> configuredProviders() async {
    final result = <LlmProviderId>{};
    for (final p in LlmProviderId.values) {
      if (await getApiKey(p) != null) result.add(p);
    }
    return result;
  }

  static String? _nonEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v;
}
