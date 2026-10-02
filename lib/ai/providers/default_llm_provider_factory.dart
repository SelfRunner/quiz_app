import 'package:http/http.dart' as http;

import '../llm_provider.dart';
import 'anthropic_provider.dart';
import 'gemini_provider.dart';
import 'openai_compatible_provider.dart';
import 'openai_provider.dart';

/// Creates the HTTP-backed provider for a config. The [http.Client] is
/// injectable so tests can use `MockClient`.
class DefaultLlmProviderFactory implements LlmProviderFactory {
  DefaultLlmProviderFactory(this.client, {this.isWeb});

  final http.Client client;

  /// Overrides platform detection (tests); null = `kIsWeb`.
  final bool? isWeb;

  @override
  LlmProvider create(LlmConfig config) => switch (config.providerId) {
    LlmProviderId.gemini => GeminiProvider(config, client, isWeb: isWeb),
    LlmProviderId.openai => OpenAiProvider(config, client, isWeb: isWeb),
    LlmProviderId.anthropic => AnthropicProvider(config, client, isWeb: isWeb),
    LlmProviderId.openaiCompatible => OpenAiCompatibleProvider(
      config,
      client,
      isWeb: isWeb,
    ),
  };
}
