import 'llm_provider.dart';

/// Local-only storage for AI settings (flutter_secure_storage). Keys are
/// never sent to Supabase.
abstract interface class ApiKeyStore {
  Future<String?> getApiKey(LlmProviderId provider);
  Future<void> setApiKey(LlmProviderId provider, String apiKey);
  Future<void> deleteApiKey(LlmProviderId provider);

  /// Base URL for [LlmProviderId.openaiCompatible] (or an override).
  Future<String?> getBaseUrl(LlmProviderId provider);
  Future<void> setBaseUrl(LlmProviderId provider, String? baseUrl);

  Future<LlmProviderId?> getSelectedProvider();
  Future<void> setSelectedProvider(LlmProviderId provider);

  /// Selected model per provider.
  Future<String?> getSelectedModel(LlmProviderId provider);
  Future<void> setSelectedModel(LlmProviderId provider, String model);

  /// Providers that currently have a key stored.
  Future<Set<LlmProviderId>> configuredProviders();
}
