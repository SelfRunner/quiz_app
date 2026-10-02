import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/api_key_store.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/secure_api_key_store.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/data_providers.dart';

final _userId = NotifierProvider<_UserId, String?>(_UserId.new);

class _UserId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

void main() {
  late InMemoryKeyValueStore kv;
  late SecureApiKeyStore store;

  setUp(() {
    kv = InMemoryKeyValueStore();
    store = SecureApiKeyStore(userId: 'u1', backend: kv);
  });

  test('base URL rejects http:// to remote hosts, allows local', () async {
    const p = LlmProviderId.openaiCompatible;
    await expectLater(
      store.setBaseUrl(p, 'http://openrouter.ai/api/v1'),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          contains('https://'),
        ),
      ),
    );
    expect(await store.getBaseUrl(p), isNull);

    await store.setBaseUrl(p, 'http://localhost:11434/v1/');
    expect(await store.getBaseUrl(p), 'http://localhost:11434/v1');
    await store.setBaseUrl(p, 'http://192.168.1.20:1234/v1');
    expect(await store.getBaseUrl(p), 'http://192.168.1.20:1234/v1');
  });

  group('per-user namespacing', () {
    test('users on the same device do not see each other', () async {
      final a = SecureApiKeyStore(userId: 'alice', backend: kv);
      final b = SecureApiKeyStore(userId: 'bob', backend: kv);
      await a.setApiKey(LlmProviderId.openai, 'sk-alice');
      await a.setSelectedProvider(LlmProviderId.openai);
      await a.setSelectedModel(LlmProviderId.openai, 'gpt-a');
      await a.setBaseUrl(
        LlmProviderId.openaiCompatible,
        'https://example.com/v1',
      );
      await a.setExtraHeaders(LlmProviderId.openaiCompatible, {'X': '1'});

      expect(await b.getApiKey(LlmProviderId.openai), isNull);
      expect(await b.configuredProviders(), isEmpty);
      expect(await b.getSelectedProvider(), isNull);
      expect(await b.getSelectedModel(LlmProviderId.openai), isNull);
      expect(await b.getBaseUrl(LlmProviderId.openaiCompatible), isNull);
      expect(await b.getExtraHeaders(LlmProviderId.openaiCompatible), isEmpty);

      await b.setApiKey(LlmProviderId.openai, 'sk-bob');
      expect(await a.getApiKey(LlmProviderId.openai), 'sk-alice');
      expect(await b.getApiKey(LlmProviderId.openai), 'sk-bob');
      expect(kv.values.keys, everyElement(startsWith('ai.u.')));
    });

    test('signed out: reads are empty, writes throw', () async {
      await SecureApiKeyStore(
        userId: 'alice',
        backend: kv,
      ).setApiKey(LlmProviderId.openai, 'sk-alice');
      final out = SecureApiKeyStore(userId: null, backend: kv);
      expect(await out.getApiKey(LlmProviderId.openai), isNull);
      expect(await out.configuredProviders(), isEmpty);
      expect(await out.getSelectedProvider(), isNull);
      await expectLater(
        out.setApiKey(LlmProviderId.openai, 'sk-x'),
        throwsA(isA<AppAuthException>()),
      );
      await out.deleteApiKey(LlmProviderId.openai); // no-op
      expect(
        await SecureApiKeyStore(
          userId: 'alice',
          backend: kv,
        ).getApiKey(LlmProviderId.openai),
        'sk-alice',
      );
    });

    test(
      'legacy entries move to the first user only, then are deleted',
      () async {
        kv.values.addAll({
          'ai.api_key.openai': 'sk-legacy',
          'ai.api_key.gemini': 'g-legacy',
          'ai.selected_provider': 'openai',
          'ai.model.openai': 'gpt-legacy',
          'ai.base_url.openai_compatible': 'http://localhost:11434/v1',
          'ai.headers.openai_compatible': '{"X-Title":"Quiz"}',
        });
        // Existing namespaced values of the first user win.
        kv.values['ai.u.alice.api_key.gemini'] = 'g-alice';

        final alice = SecureApiKeyStore(userId: 'alice', backend: kv);
        expect(await alice.getApiKey(LlmProviderId.openai), 'sk-legacy');
        expect(await alice.getApiKey(LlmProviderId.gemini), 'g-alice');
        expect(await alice.getSelectedProvider(), LlmProviderId.openai);
        expect(
          await alice.getSelectedModel(LlmProviderId.openai),
          'gpt-legacy',
        );
        expect(
          await alice.getBaseUrl(LlmProviderId.openaiCompatible),
          'http://localhost:11434/v1',
        );
        expect(await alice.getExtraHeaders(LlmProviderId.openaiCompatible), {
          'X-Title': 'Quiz',
        });
        expect(
          kv.values.keys.where((k) => !k.startsWith('ai.u.')),
          isEmpty,
          reason: 'legacy entries are deleted',
        );

        final bob = SecureApiKeyStore(userId: 'bob', backend: kv);
        expect(await bob.configuredProviders(), isEmpty);
        expect(await bob.getSelectedProvider(), isNull);
      },
    );

    test('signed-out store leaves legacy entries alone', () async {
      kv.values['ai.api_key.openai'] = 'sk-legacy';
      final out = SecureApiKeyStore(userId: null, backend: kv);
      expect(await out.getApiKey(LlmProviderId.openai), isNull);
      expect(kv.values['ai.api_key.openai'], 'sk-legacy');
    });

    test('clearForUser and clearAll', () async {
      final a = SecureApiKeyStore(userId: 'alice', backend: kv);
      final b = SecureApiKeyStore(userId: 'bob', backend: kv);
      await a.setApiKey(LlmProviderId.openai, 'sk-a');
      await a.setSelectedProvider(LlmProviderId.openai);
      await a.setExtraHeaders(LlmProviderId.openaiCompatible, {'X': '1'});
      await b.setApiKey(LlmProviderId.gemini, 'g-b');
      kv.values['unrelated'] = 'keep';

      await b.clearForUser('alice');
      expect(await a.configuredProviders(), isEmpty);
      expect(await a.getSelectedProvider(), isNull);
      expect(await a.getExtraHeaders(LlmProviderId.openaiCompatible), isEmpty);
      expect(await b.getApiKey(LlmProviderId.gemini), 'g-b');

      await a.setApiKey(LlmProviderId.openai, 'sk-a');
      kv.values['ai.api_key.anthropic'] = 'legacy';
      await a.clearAll();
      expect(kv.values, {'unrelated': 'keep'});
    });

    test('clearForUser(current) also drops pending legacy entries', () async {
      kv.values['ai.api_key.openai'] = 'sk-legacy';
      final a = SecureApiKeyStore(userId: 'alice', backend: kv);
      await a.clearForUser('alice');
      expect(kv.values, isEmpty);
    });

    test('apiKeyStoreProvider follows the signed-in user', () async {
      final container = ProviderContainer(
        overrides: [
          aiSecureStorageProvider.overrideWithValue(kv),
          currentUserIdProvider.overrideWith((ref) => ref.watch(_userId)),
        ],
      );
      addTearDown(container.dispose);
      ApiKeyStore read() => container.read(apiKeyStoreProvider);

      container.read(_userId.notifier).set('alice');
      await read().setApiKey(LlmProviderId.openai, 'sk-alice');

      container.read(_userId.notifier).set(null);
      expect(await read().getApiKey(LlmProviderId.openai), isNull);

      container.read(_userId.notifier).set('bob');
      expect(await read().configuredProviders(), isEmpty);

      container.read(_userId.notifier).set('alice');
      expect(
        await read().getApiKey(LlmProviderId.openai),
        'sk-alice',
        reason: 'signing out does not delete keys',
      );
    });
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
