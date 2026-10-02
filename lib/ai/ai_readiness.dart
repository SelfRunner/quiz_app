import 'package:meta/meta.dart';

import '../core/errors/app_exception.dart';
import 'ai_capabilities.dart';
import 'ai_source.dart';
import 'api_key_store.dart';
import 'base_url_policy.dart';
import 'llm_provider.dart';

/// Why AI is not ready (see [AiReadiness.issue]).
enum AiReadinessIssue {
  /// No provider selected and none has a key (also when signed out).
  noProvider,

  /// The selected provider has no API key.
  missingApiKey,

  /// Key-less OpenAI-compatible endpoint (e.g. Ollama) without a model.
  missingModel,

  /// The stored base URL violates the https policy.
  invalidBaseUrl,

  /// Secure storage could not be read.
  storageError,
}

/// Whether AI generation can run, and with what. Exposed by
/// `aiReadinessProvider`; AI entry points are locked while [isConfigured] is
/// false and show [reason].
@immutable
class AiReadiness {
  const AiReadiness({
    required this.isConfigured,
    this.providerId,
    this.model,
    this.capabilities = AiCapabilities.textOnly,
    this.reason,
    this.issue,
  });

  const AiReadiness.notReady({
    required String this.reason,
    required AiReadinessIssue this.issue,
    this.providerId,
    this.model,
  }) : isConfigured = false,
       capabilities = AiCapabilities.textOnly;

  final bool isConfigured;

  /// Provider that would be used (null when none is usable / selected).
  final LlmProviderId? providerId;

  /// Model that would be used (stored selection or provider default).
  final String? model;

  /// Input kinds of [providerId] + [model] (text-only when not ready).
  final AiCapabilities capabilities;

  /// User-facing explanation when not ready.
  final String? reason;
  final AiReadinessIssue? issue;

  @override
  bool operator ==(Object other) =>
      other is AiReadiness &&
      other.isConfigured == isConfigured &&
      other.providerId == providerId &&
      other.model == model &&
      other.capabilities == capabilities &&
      other.reason == reason &&
      other.issue == issue;

  @override
  int get hashCode =>
      Object.hash(isConfigured, providerId, model, capabilities, reason, issue);

  @override
  String toString() => isConfigured
      ? 'AiReadiness(ready, ${providerId?.wireName}, $model, $capabilities)'
      : 'AiReadiness(not ready: ${issue?.name}, $reason)';
}

/// An OpenAI-compatible base URL that may be used without an API key
/// (self-hosted: Ollama, LM Studio, ...). OpenRouter always needs a key.
bool isKeylessEndpoint(LlmProviderId provider, String? storedBaseUrl) =>
    provider.requiresBaseUrl &&
    storedBaseUrl != null &&
    !AiCapabilityResolver.isOpenRouterUrl(storedBaseUrl);

/// Computes [AiReadiness] from the stored settings.
///
/// Ready = a provider (selected, else the first with a key) that has an API
/// key and a model (stored or `defaultModel`). OpenAI-compatible endpoints
/// other than OpenRouter may have no key; a stored base URL and a stored
/// model suffice then. Capabilities come from [capabilities] (OpenRouter
/// metadata + manual override) or, without it, the static table.
Future<AiReadiness> resolveAiReadiness(
  ApiKeyStore store, {
  AiCapabilityResolver? capabilities,
  bool? isWeb,
}) async {
  try {
    final selected = await store.getSelectedProvider();
    if (selected != null) {
      return await _check(store, selected, capabilities, isWeb);
    }
    for (final p in LlmProviderId.values) {
      final r = await _check(store, p, capabilities, isWeb);
      if (r.isConfigured) return r;
    }
    return const AiReadiness.notReady(
      reason: 'Add an AI provider API key in Settings to use AI features.',
      issue: AiReadinessIssue.noProvider,
    );
  } on AppException catch (e) {
    return AiReadiness.notReady(
      reason: e.message,
      issue: AiReadinessIssue.storageError,
    );
  }
}

Future<AiReadiness> _check(
  ApiKeyStore store,
  LlmProviderId p,
  AiCapabilityResolver? resolver,
  bool? isWeb,
) async {
  final key = await store.getApiKey(p);
  final storedBase = await store.getBaseUrl(p);
  final storedModel = await store.getSelectedModel(p);
  if (key == null) {
    if (!isKeylessEndpoint(p, storedBase)) {
      return AiReadiness.notReady(
        reason: 'Add your ${p.displayName} API key in Settings.',
        issue: AiReadinessIssue.missingApiKey,
        providerId: p,
      );
    }
    if (storedModel == null) {
      return AiReadiness.notReady(
        reason:
            'Choose a model for your ${p.displayName} endpoint in '
            'Settings.',
        issue: AiReadinessIssue.missingModel,
        providerId: p,
      );
    }
  }
  final model = storedModel ?? p.defaultModel;
  final baseUrl = storedBase ?? p.defaultBaseUrl;
  if (baseUrl != null && baseUrlProblem(baseUrl) != null) {
    return AiReadiness.notReady(
      reason:
          'The ${p.displayName} base URL is not allowed: '
          '${baseUrlProblem(baseUrl)}',
      issue: AiReadinessIssue.invalidBaseUrl,
      providerId: p,
      model: model,
    );
  }
  final manual = await store.getInputOverride(p, model);
  final caps = resolver != null
      ? await resolver.resolve(
          provider: p,
          model: model,
          baseUrl: baseUrl,
          manualOverride: manual,
        )
      : staticCapabilities(p, model, manual: manual, isWeb: isWeb);
  return AiReadiness(
    isConfigured: true,
    providerId: p,
    model: model,
    capabilities: caps,
  );
}

/// [AiCapabilities.forModel] plus the manual override (OpenAI-compatible
/// only), without network lookups.
AiCapabilities staticCapabilities(
  LlmProviderId provider,
  String model, {
  Set<AiInputKind> manual = const {},
  bool? isWeb,
}) {
  final base = isWeb == null
      ? AiCapabilities.forModel(provider, model)
      : AiCapabilities.forModel(provider, model, isWeb: isWeb);
  return provider == LlmProviderId.openaiCompatible
      ? base.including(manual)
      : base;
}
