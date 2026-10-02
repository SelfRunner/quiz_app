import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'ai_service.dart';
import 'api_key_store.dart';
import 'default_ai_service.dart';
import 'llm_provider.dart';
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

/// Device-local AI settings (API keys, selected provider/model, base URL).
final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) => SecureApiKeyStore());

final llmProviderFactoryProvider = Provider<LlmProviderFactory>(
  (ref) => DefaultLlmProviderFactory(ref.watch(aiHttpClientProvider)),
);

final transcriptServiceProvider = Provider<TranscriptService>(
  (ref) => YoutubeTranscriptService(),
);

final aiServiceProvider = Provider<AiService>(
  (ref) => DefaultAiService(
    keyStore: ref.watch(apiKeyStoreProvider),
    providerFactory: ref.watch(llmProviderFactoryProvider),
    transcriptService: ref.watch(transcriptServiceProvider),
  ),
);
