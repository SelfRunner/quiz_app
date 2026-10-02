import 'llm_provider.dart';

/// Local-only storage for AI settings (flutter_secure_storage). Keys are
/// never sent to Supabase and never logged.
///
/// Every entry is scoped to the signed-in user: a store bound to one user
/// never sees another account's keys on the same device. When signed out,
/// reads return nothing and writes throw `AppAuthException`. Signing out does
/// not delete anything, so the same user gets their keys back on sign-in.
///
/// Implementation: `SecureApiKeyStore` (`secure_api_key_store.dart`).
abstract interface class ApiKeyStore {
  Future<String?> getApiKey(LlmProviderId provider);

  /// Stores [apiKey] (trimmed). An empty key deletes the entry.
  Future<void> setApiKey(LlmProviderId provider, String apiKey);
  Future<void> deleteApiKey(LlmProviderId provider);

  /// Base URL for [LlmProviderId.openaiCompatible] (or an override).
  /// Returns the stored value only; callers fall back to
  /// `LlmProviderId.defaultBaseUrl`.
  Future<String?> getBaseUrl(LlmProviderId provider);

  /// Null or empty clears the override. Throws `ValidationException` for a
  /// malformed URL or a non-https URL to a non-local host (see
  /// `base_url_policy.dart`).
  Future<void> setBaseUrl(LlmProviderId provider, String? baseUrl);

  Future<LlmProviderId?> getSelectedProvider();
  Future<void> setSelectedProvider(LlmProviderId provider);

  /// Selected model per provider.
  Future<String?> getSelectedModel(LlmProviderId provider);
  Future<void> setSelectedModel(LlmProviderId provider, String model);

  /// Extra request headers (OpenAI-compatible endpoints), e.g. OpenRouter's
  /// `HTTP-Referer` and `X-Title`. Empty map when none.
  Future<Map<String, String>> getExtraHeaders(LlmProviderId provider);

  /// Empty map clears them.
  Future<void> setExtraHeaders(
    LlmProviderId provider,
    Map<String, String> headers,
  );

  /// Providers that currently have a key stored.
  Future<Set<LlmProviderId>> configuredProviders();

  /// Deletes every AI setting (keys, selection, models, base URLs, headers)
  /// stored on this device for [userId].
  Future<void> clearForUser(String userId);

  /// Deletes every AI setting stored on this device, for all users.
  Future<void> clearAll();
}
