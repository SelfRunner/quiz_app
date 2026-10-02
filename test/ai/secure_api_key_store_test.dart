import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/secure_api_key_store.dart';
import 'package:quiz_app/core/errors/app_exception.dart';

void main() {
  late InMemoryKeyValueStore kv;
  late SecureApiKeyStore store;

  setUp(() {
    kv = InMemoryKeyValueStore();
    store = SecureApiKeyStore(kv);
  });

  test('keys are stored per provider and trimmed', () async {
    await store.setApiKey(LlmProviderId.openai, '  sk-1  ');
    await store.setApiKey(LlmProviderId.gemini, 'g-1');
    expect(await store.getApiKey(LlmProviderId.openai), 'sk-1');
    expect(await store.getApiKey(LlmProviderId.gemini), 'g-1');
    expect(await store.getApiKey(LlmProviderId.anthropic), isNull);
    expect(await store.configuredProviders(), {
      LlmProviderId.openai,
      LlmProviderId.gemini,
    });

    await store.deleteApiKey(LlmProviderId.openai);
    expect(await store.getApiKey(LlmProviderId.openai), isNull);
    await store.setApiKey(LlmProviderId.gemini, '   ');
    expect(await store.getApiKey(LlmProviderId.gemini), isNull);
    expect(kv.values, isEmpty);
  });

  test('selected provider and per-provider model', () async {
    expect(await store.getSelectedProvider(), isNull);
    await store.setSelectedProvider(LlmProviderId.anthropic);
    expect(await store.getSelectedProvider(), LlmProviderId.anthropic);

    await store.setSelectedModel(LlmProviderId.anthropic, 'claude-x');
    await store.setSelectedModel(LlmProviderId.openai, 'gpt-x');
    expect(await store.getSelectedModel(LlmProviderId.anthropic), 'claude-x');
    expect(await store.getSelectedModel(LlmProviderId.openai), 'gpt-x');
  });

  test('base URL is validated and trailing slashes removed', () async {
    await store.setBaseUrl(
      LlmProviderId.openaiCompatible,
      'https://openrouter.ai/api/v1/',
    );
    expect(
      await store.getBaseUrl(LlmProviderId.openaiCompatible),
      'https://openrouter.ai/api/v1',
    );
    await expectLater(
      store.setBaseUrl(LlmProviderId.openaiCompatible, 'openrouter'),
      throwsA(isA<ValidationException>()),
    );
    await store.setBaseUrl(LlmProviderId.openaiCompatible, null);
    expect(await store.getBaseUrl(LlmProviderId.openaiCompatible), isNull);
  });

  test('extra headers round-trip and clear', () async {
    await store.setExtraHeaders(LlmProviderId.openaiCompatible, {
      'HTTP-Referer': 'https://quiz.app',
      'X-Title': ' Quiz ',
      ' ': 'ignored',
    });
    expect(await store.getExtraHeaders(LlmProviderId.openaiCompatible), {
      'HTTP-Referer': 'https://quiz.app',
      'X-Title': 'Quiz',
    });
    await store.setExtraHeaders(LlmProviderId.openaiCompatible, {});
    expect(
      await store.getExtraHeaders(LlmProviderId.openaiCompatible),
      isEmpty,
    );
  });

  test('LlmConfig.toString never contains the key', () {
    const config = LlmConfig(
      providerId: LlmProviderId.openai,
      apiKey: 'sk-very-secret',
      model: 'gpt-x',
    );
    expect(config.toString(), isNot(contains('sk-very-secret')));
  });
}
