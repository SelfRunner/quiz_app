import 'ai_source.dart';
import 'api_key_store.dart';
import 'llm_provider.dart';

/// [ApiKeyStore] decorator that calls [onChanged] after every successful
/// write, so readers such as `aiReadinessProvider` can refresh. Used by
/// `apiKeyStoreProvider`; tests overriding that provider with a plain store
/// get no notifications.
class NotifyingApiKeyStore implements ApiKeyStore {
  NotifyingApiKeyStore(this.inner, {required this.onChanged});

  final ApiKeyStore inner;
  final void Function() onChanged;

  Future<void> _notify(Future<void> write) async {
    await write;
    onChanged();
  }

  @override
  Future<String?> getApiKey(LlmProviderId provider) =>
      inner.getApiKey(provider);

  @override
  Future<void> setApiKey(LlmProviderId provider, String apiKey) =>
      _notify(inner.setApiKey(provider, apiKey));

  @override
  Future<void> deleteApiKey(LlmProviderId provider) =>
      _notify(inner.deleteApiKey(provider));

  @override
  Future<String?> getBaseUrl(LlmProviderId provider) =>
      inner.getBaseUrl(provider);

  @override
  Future<void> setBaseUrl(LlmProviderId provider, String? baseUrl) =>
      _notify(inner.setBaseUrl(provider, baseUrl));

  @override
  Future<LlmProviderId?> getSelectedProvider() => inner.getSelectedProvider();

  @override
  Future<void> setSelectedProvider(LlmProviderId provider) =>
      _notify(inner.setSelectedProvider(provider));

  @override
  Future<String?> getSelectedModel(LlmProviderId provider) =>
      inner.getSelectedModel(provider);

  @override
  Future<void> setSelectedModel(LlmProviderId provider, String model) =>
      _notify(inner.setSelectedModel(provider, model));

  @override
  Future<Map<String, String>> getExtraHeaders(LlmProviderId provider) =>
      inner.getExtraHeaders(provider);

  @override
  Future<void> setExtraHeaders(
    LlmProviderId provider,
    Map<String, String> headers,
  ) => _notify(inner.setExtraHeaders(provider, headers));

  @override
  Future<Set<LlmProviderId>> configuredProviders() =>
      inner.configuredProviders();

  @override
  Future<void> clearForUser(String userId) =>
      _notify(inner.clearForUser(userId));

  @override
  Future<void> clearAll() => _notify(inner.clearAll());

  @override
  Future<Set<AiInputKind>> getInputOverride(
    LlmProviderId provider,
    String model,
  ) => inner.getInputOverride(provider, model);

  @override
  Future<void> setInputOverride(
    LlmProviderId provider,
    String model,
    Set<AiInputKind> kinds,
  ) => _notify(inner.setInputOverride(provider, model, kinds));
}
