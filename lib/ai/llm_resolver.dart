import '../core/errors/app_exception.dart';
import 'ai_capabilities.dart';
import 'ai_readiness.dart';
import 'ai_service.dart';
import 'api_key_store.dart';
import 'base_url_policy.dart';
import 'llm_provider.dart';

/// A provider instance ready to call, plus what it was built from.
class ResolvedLlm {
  const ResolvedLlm({
    required this.provider,
    required this.selection,
    required this.baseUrl,
  });

  final LlmProvider provider;
  final AiSelection selection;

  /// Effective (policy-checked) base URL, null = provider default.
  final String? baseUrl;
}

/// Shared provider/key/model resolution for every AI service
/// (`DefaultAiService`, `DefaultAiChatService`, `DefaultAiToolsService`):
/// selection order, keyless local endpoints, the base-URL policy and
/// capability lookup live here so all features behave the same.
class LlmResolver {
  LlmResolver({
    required ApiKeyStore keyStore,
    required LlmProviderFactory providerFactory,
    this.capabilities,
    this.isWeb,
  }) : _keys = keyStore,
       _factory = providerFactory;

  final ApiKeyStore _keys;
  final LlmProviderFactory _factory;

  /// Resolves model capabilities (OpenRouter metadata); null = static table.
  final AiCapabilityResolver? capabilities;

  /// Platform override for the static capability table (null = `kIsWeb`).
  final bool? isWeb;

  ApiKeyStore get keyStore => _keys;
  LlmProviderFactory get providerFactory => _factory;

  /// See `AiService.resolveSelection`.
  Future<AiSelection> resolveSelection({
    LlmProviderId? providerId,
    String? model,
  }) async {
    var provider = providerId ?? await _keys.getSelectedProvider();
    if (provider == null) {
      final configured = await _keys.configuredProviders();
      for (final p in LlmProviderId.values) {
        if (configured.contains(p) ||
            isKeylessEndpoint(p, await _keys.getBaseUrl(p))) {
          provider = p;
          break;
        }
      }
    }
    if (provider == null) {
      throw const AiException(
        'Add an AI provider API key in Settings to generate content.',
        kind: AiErrorKind.missingApiKey,
      );
    }
    final override = model?.trim();
    final resolvedModel = (override != null && override.isNotEmpty)
        ? override
        : (await _keys.getSelectedModel(provider)) ?? provider.defaultModel;
    return AiSelection(providerId: provider, model: resolvedModel);
  }

  /// Builds the provider for a generation/chat call. Throws
  /// `AiException(missingApiKey)` when the provider has no key (and is not
  /// a keyless local endpoint) and `ValidationException` for a base URL the
  /// policy rejects.
  Future<ResolvedLlm> resolve({
    LlmProviderId? providerId,
    String? model,
  }) async {
    final selection = await resolveSelection(
      providerId: providerId,
      model: model,
    );
    final id = selection.providerId;
    final key = await _keys.getApiKey(id);
    final storedBase = await _keys.getBaseUrl(id);
    if (key == null && !isKeylessEndpoint(id, storedBase)) {
      throw AiException(
        'No API key saved for ${id.displayName}. Add one in Settings.',
        kind: AiErrorKind.missingApiKey,
      );
    }
    final baseUrl = checkedBaseUrl(storedBase ?? id.defaultBaseUrl);
    final provider = _factory.create(
      LlmConfig(
        providerId: id,
        apiKey: key ?? '',
        model: selection.model,
        baseUrl: baseUrl,
        extraHeaders: id == LlmProviderId.openaiCompatible
            ? await _keys.getExtraHeaders(id)
            : const {},
      ),
    );
    return ResolvedLlm(
      provider: provider,
      selection: selection,
      baseUrl: baseUrl,
    );
  }

  /// Input kinds the selected model accepts (manual override included).
  Future<AiCapabilities> capabilitiesFor(
    AiSelection selection,
    String? baseUrl,
  ) async {
    final manual = await _keys.getInputOverride(
      selection.providerId,
      selection.model,
    );
    final resolver = capabilities;
    if (resolver != null) {
      return resolver.resolve(
        provider: selection.providerId,
        model: selection.model,
        baseUrl: baseUrl,
        manualOverride: manual,
      );
    }
    return staticCapabilities(
      selection.providerId,
      selection.model,
      manual: manual,
      isWeb: isWeb,
    );
  }

  /// Never send a key to a non-https remote URL (unsaved Settings input or
  /// a value stored before the https rule existed).
  static String? checkedBaseUrl(String? url) =>
      url == null ? null : normalizeBaseUrl(url);
}
