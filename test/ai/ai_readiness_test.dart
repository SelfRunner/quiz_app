import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_capabilities.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_readiness.dart';
import 'package:quiz_app/ai/ai_source.dart';
import 'package:quiz_app/ai/api_key_store.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/secure_api_key_store.dart';
import 'package:quiz_app/data/data_providers.dart';

import 'test_helpers.dart';

final _userId = NotifierProvider<_UserId, String?>(_UserId.new);

class _UserId extends Notifier<String?> {
  @override
  String? build() => 'alice';

  void set(String? id) => state = id;
}

void main() {
  late ProviderContainer container;
  late RecordingClient http;

  setUp(() {
    http = RecordingClient([
      (_) => jsonResponse({
        'data': [
          {
            'id': 'openai/gpt-5.4-mini',
            'architecture': {
              'input_modalities': ['text', 'image', 'file'],
            },
          },
        ],
      }),
    ]);
    container = ProviderContainer(
      overrides: [
        aiSecureStorageProvider.overrideWithValue(InMemoryKeyValueStore()),
        currentUserIdProvider.overrideWith((ref) => ref.watch(_userId)),
        aiHttpClientProvider.overrideWithValue(http.client),
      ],
    );
    addTearDown(container.dispose);
    // Keep it alive like a widget would.
    container.listen(aiReadinessProvider, (_, _) {});
  });

  ApiKeyStore store() => container.read(apiKeyStoreProvider);
  Future<AiReadiness> readiness() => container.read(aiReadinessProvider.future);

  test('transitions with settings writes (store notifies)', () async {
    var r = await readiness();
    expect(r.isConfigured, isFalse);
    expect(r.issue, AiReadinessIssue.noProvider);
    expect(r.reason, contains('API key'));

    // Key for Anthropic -> ready with the default model.
    await store().setApiKey(LlmProviderId.anthropic, 'sk-ant');
    r = await readiness();
    expect(r.isConfigured, isTrue);
    expect(r.providerId, LlmProviderId.anthropic);
    expect(r.model, LlmProviderId.anthropic.defaultModel);
    expect(r.capabilities.pdf && r.capabilities.image, isTrue);
    expect(r.reason, isNull);

    // Selecting a provider without a key -> not ready, names it.
    await store().setSelectedProvider(LlmProviderId.gemini);
    r = await readiness();
    expect(r.isConfigured, isFalse);
    expect(r.issue, AiReadinessIssue.missingApiKey);
    expect(r.providerId, LlmProviderId.gemini);
    expect(r.reason, contains('Google Gemini'));

    await store().setApiKey(LlmProviderId.gemini, 'g');
    await store().setSelectedModel(LlmProviderId.gemini, 'gemini-3-pro');
    r = await readiness();
    expect(r.isConfigured, isTrue);
    expect(r.model, 'gemini-3-pro');
    expect(r.capabilities.youtubeNative, isTrue);
    expect(r.capabilities.video, isTrue);

    // Deleting the key locks AI again.
    await store().deleteApiKey(LlmProviderId.gemini);
    expect((await readiness()).issue, AiReadinessIssue.missingApiKey);
    expect(http.requests, isEmpty);
  });

  test('OpenRouter capabilities come from /models metadata', () async {
    await store().setApiKey(LlmProviderId.openaiCompatible, 'sk-or');
    await store().setSelectedProvider(LlmProviderId.openaiCompatible);
    await store().setSelectedModel(
      LlmProviderId.openaiCompatible,
      'openai/gpt-5.4-mini',
    );
    final r = await readiness();
    expect(r.isConfigured, isTrue);
    expect(r.capabilities.image && r.capabilities.pdf, isTrue);
    expect(r.capabilities.audio, isFalse);
    expect(
      http.requests.single.url.toString(),
      'https://openrouter.ai/api/v1/models',
    );
  });

  test('key-less local endpoint needs base URL + model', () async {
    final s = store();
    await s.setSelectedProvider(LlmProviderId.openaiCompatible);
    var r = await readiness();
    expect(r.issue, AiReadinessIssue.missingApiKey, reason: 'OpenRouter');

    await s.setBaseUrl(
      LlmProviderId.openaiCompatible,
      'http://localhost:11434/v1',
    );
    r = await readiness();
    expect(r.isConfigured, isFalse);
    expect(r.issue, AiReadinessIssue.missingModel);

    await s.setSelectedModel(LlmProviderId.openaiCompatible, 'llava');
    r = await readiness();
    expect(r.isConfigured, isTrue);
    expect(r.model, 'llava');
    expect(r.capabilities.image, isFalse);

    // Manual override "supports images/PDF" is stored and applied.
    await s.setInputOverride(
      LlmProviderId.openaiCompatible,
      'llava',
      {AiInputKind.image},
    );
    r = await readiness();
    expect(r.capabilities.image, isTrue);
    expect(r.capabilities.pdf, isFalse);
    expect(http.requests, isEmpty, reason: 'no lookup for self-hosted');
  });

  test('key-less endpoint is picked without an explicit selection', () async {
    final s = store();
    await s.setBaseUrl(LlmProviderId.openaiCompatible, 'http://10.0.0.5/v1');
    await s.setSelectedModel(LlmProviderId.openaiCompatible, 'qwen');
    final r = await readiness();
    expect(r.isConfigured, isTrue);
    expect(r.providerId, LlmProviderId.openaiCompatible);
  });

  test('user switch recomputes; signed out is not ready', () async {
    await store().setApiKey(LlmProviderId.openai, 'sk-alice');
    expect((await readiness()).isConfigured, isTrue);

    container.read(_userId.notifier).set('bob');
    expect((await readiness()).isConfigured, isFalse);

    container.read(_userId.notifier).set(null);
    final r = await readiness();
    expect(r.isConfigured, isFalse);
    expect(r.issue, AiReadinessIssue.noProvider);

    container.read(_userId.notifier).set('alice');
    expect((await readiness()).providerId, LlmProviderId.openai);
  });

  test('revision bumps on every write', () async {
    final before = container.read(aiSettingsRevisionProvider);
    await store().setExtraHeaders(LlmProviderId.openaiCompatible, {'a': 'b'});
    await store().clearAll();
    expect(container.read(aiSettingsRevisionProvider), before + 2);
  });

  test('resolveAiReadiness without a resolver uses the static table', () async {
    final s = SecureApiKeyStore(userId: 'u', backend: InMemoryKeyValueStore());
    await s.setApiKey(LlmProviderId.openai, 'sk');
    await s.setSelectedModel(LlmProviderId.openai, 'gpt-3.5-turbo');
    final r = await resolveAiReadiness(s, isWeb: true);
    expect(r.isConfigured, isTrue);
    expect(r.capabilities, AiCapabilities.textOnly);
  });
}
