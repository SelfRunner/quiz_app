import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/data_providers.dart';
import 'ai_capabilities.dart';
import 'ai_chat_service.dart';
import 'ai_readiness.dart';
import 'ai_service.dart';
import 'ai_tools_service.dart';
import 'api_key_store.dart';
import 'default_ai_chat_service.dart';
import 'default_ai_service.dart';
import 'default_ai_tools_service.dart';
import 'llm_provider.dart';
import 'llm_resolver.dart';
import 'notifying_api_key_store.dart';
import 'providers/default_llm_provider_factory.dart';
import 'secure_api_key_store.dart';
import 'transcript_service.dart';
import 'youtube_transcript_service.dart';

/// HTTP client used by all LLM providers. Override with `MockClient` in
/// tests.
final aiHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Device storage backing [apiKeyStoreProvider]. Override with
/// `InMemoryKeyValueStore` in tests.
final aiSecureStorageProvider = Provider<SecureKeyValueStore>(
  (ref) => FlutterSecureKeyValueStore(),
);

/// Bumped after every write through [apiKeyStoreProvider]; watch it to
/// recompute anything derived from AI settings.
final aiSettingsRevisionProvider = NotifierProvider<AiSettingsRevision, int>(
  AiSettingsRevision.new,
);

class AiSettingsRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// Marks AI settings as changed (called by the store; call it yourself
  /// after writing through a store obtained elsewhere).
  void bump() => state++;
}

/// Device-local AI settings (API keys, selected provider/model, base URL,
/// capability overrides), scoped to the signed-in user. Rebuilt when the
/// user changes; signed out it returns nothing. Every write bumps
/// [aiSettingsRevisionProvider]. Capability overrides:
/// `store.getInputOverride` / `setInputOverride`.
final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) {
  final revision = ref.read(aiSettingsRevisionProvider.notifier);
  return NotifyingApiKeyStore(
    SecureApiKeyStore(
      userId: ref.watch(currentUserIdProvider),
      backend: ref.watch(aiSecureStorageProvider),
    ),
    onChanged: revision.bump,
  );
});

/// Model capability lookup (OpenRouter metadata cached for the app's
/// lifetime, 6 h TTL).
final aiCapabilityResolverProvider = Provider<AiCapabilityResolver>(
  (ref) => AiCapabilityResolver(client: ref.watch(aiHttpClientProvider)),
);

/// Whether AI features can be used right now, with which provider/model and
/// which input kinds. Recomputed when the user or any AI setting changes.
/// Never errors: problems are reported as `isConfigured: false` + `reason`.
final aiReadinessProvider = FutureProvider<AiReadiness>((ref) {
  ref.watch(aiSettingsRevisionProvider);
  return resolveAiReadiness(
    ref.watch(apiKeyStoreProvider),
    capabilities: ref.watch(aiCapabilityResolverProvider),
  );
});

final llmProviderFactoryProvider = Provider<LlmProviderFactory>(
  (ref) => DefaultLlmProviderFactory(ref.watch(aiHttpClientProvider)),
);

final transcriptServiceProvider = Provider<TranscriptService>(
  (ref) => YoutubeTranscriptService(),
);

/// Provider/key/model resolution shared by the Wave 3 services.
final llmResolverProvider = Provider<LlmResolver>(
  (ref) => LlmResolver(
    keyStore: ref.watch(apiKeyStoreProvider),
    providerFactory: ref.watch(llmProviderFactoryProvider),
    capabilities: ref.watch(aiCapabilityResolverProvider),
  ),
);

/// Chat with sources (streaming, citations). Override with a fake in UI
/// tests.
final aiChatServiceProvider = Provider<AiChatService>(
  (ref) => DefaultAiChatService(
    resolver: ref.watch(llmResolverProvider),
    transcriptService: ref.watch(transcriptServiceProvider),
  ),
);

/// Note tools, "Explain this" and short-answer grading.
final aiToolsServiceProvider = Provider<AiToolsService>(
  (ref) => DefaultAiToolsService(
    resolver: ref.watch(llmResolverProvider),
    transcriptService: ref.watch(transcriptServiceProvider),
  ),
);

final aiServiceProvider = Provider<AiService>(
  (ref) => DefaultAiService(
    keyStore: ref.watch(apiKeyStoreProvider),
    providerFactory: ref.watch(llmProviderFactoryProvider),
    transcriptService: ref.watch(transcriptServiceProvider),
    capabilities: ref.watch(aiCapabilityResolverProvider),
  ),
);
