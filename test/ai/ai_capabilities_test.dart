import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_capabilities.dart';
import 'package:quiz_app/ai/ai_source.dart';
import 'package:quiz_app/ai/llm_provider.dart';

import 'test_helpers.dart';

AiCapabilities caps(LlmProviderId p, String model, {bool isWeb = false}) =>
    AiCapabilities.forModel(p, model, isWeb: isWeb);

Map<String, dynamic> _openRouterModels() => {
  'data': [
    {
      'id': 'openai/gpt-5.4-mini',
      'architecture': {
        'input_modalities': ['text', 'image', 'file'],
        'output_modalities': ['text'],
      },
    },
    {
      'id': 'qwen/qwen3-vl',
      'architecture': {
        'input_modalities': ['image', 'text'],
      },
    },
    {
      'id': 'meta/llama-3-8b',
      'architecture': {
        'input_modalities': ['text'],
      },
    },
    {'id': 'weird/no-arch'},
  ],
};

void main() {
  group('static table', () {
    test('Gemini: everything, YouTube native', () {
      final c = caps(LlmProviderId.gemini, 'models/gemini-2.5-flash');
      expect(c.kinds, AiInputKind.values.toSet());
      expect(c.youtubeNative, isTrue);
      expect(
        caps(LlmProviderId.gemini, 'gemini-flash-latest', isWeb: true).youtube,
        isTrue,
        reason: 'native YouTube works on web',
      );
      final gemma = caps(LlmProviderId.gemini, 'gemma-3-27b-it');
      expect(gemma.image, isTrue);
      expect(gemma.pdf || gemma.audio || gemma.youtubeNative, isFalse);
    });

    test('OpenAI: vision families get PDF + images, others text', () {
      for (final m in [
        'gpt-4o',
        'gpt-4o-mini',
        'gpt-4.1-nano',
        'gpt-5.4-mini',
        'gpt-5',
        'o1',
        'o3',
        'o3-pro',
        'o4-mini',
        'chatgpt-4o-latest',
      ]) {
        final c = caps(LlmProviderId.openai, m);
        expect(c.pdf && c.image, isTrue, reason: m);
        expect(c.audio || c.video || c.youtubeNative, isFalse, reason: m);
      }
      for (final m in [
        'gpt-3.5-turbo',
        'o1-mini',
        'o3-mini',
        'gpt-4o-audio-preview',
        'my-finetune',
      ]) {
        expect(caps(LlmProviderId.openai, m).kinds, {
          AiInputKind.text,
          AiInputKind.youtube,
        }, reason: m);
      }
    });

    test('Anthropic: Claude 3+ get PDF + images', () {
      for (final m in [
        'claude-sonnet-5-5',
        'claude-3-haiku-20240307',
        'claude-3-5-sonnet-latest',
        'claude-opus-4-1',
        'claude-haiku-4-5',
      ]) {
        final c = caps(LlmProviderId.anthropic, m);
        expect(c.pdf && c.image, isTrue, reason: m);
        expect(c.audio || c.video, isFalse);
      }
      expect(caps(LlmProviderId.anthropic, 'claude-2.1').image, isFalse);
      expect(caps(LlmProviderId.anthropic, 'claude-instant-1').pdf, isFalse);
    });

    test('OpenAI-compatible: text only; YouTube transcript except web', () {
      final c = caps(LlmProviderId.openaiCompatible, 'llava');
      expect(c.kinds, {AiInputKind.text, AiInputKind.youtube});
      expect(c.youtubeNative, isFalse);
      expect(caps(LlmProviderId.openaiCompatible, 'llava', isWeb: true).kinds, {
        AiInputKind.text,
      });
      expect(caps(LlmProviderId.openai, 'gpt-5', isWeb: true).youtube, isFalse);
    });

    test('including() adds manual kinds', () {
      final c = AiCapabilities.textOnly.including({
        AiInputKind.image,
        AiInputKind.pdf,
      });
      expect(c.kinds, {AiInputKind.text, AiInputKind.image, AiInputKind.pdf});
    });
  });

  group('AiCapabilityResolver', () {
    test('OpenRouter metadata is fetched once and cached', () async {
      final rc = RecordingClient([(_) => jsonResponse(_openRouterModels())]);
      final r = AiCapabilityResolver(client: rc.client, isWeb: false);
      final gpt = await r.resolve(
        provider: LlmProviderId.openaiCompatible,
        model: 'openai/gpt-5.4-mini',
        baseUrl: 'https://openrouter.ai/api/v1',
      );
      expect(gpt.image && gpt.pdf, isTrue);
      final qwen = await r.resolve(
        provider: LlmProviderId.openaiCompatible,
        model: 'qwen/qwen3-vl',
        baseUrl: 'https://openrouter.ai/api/v1/',
      );
      expect(qwen.image, isTrue);
      expect(qwen.pdf, isFalse);
      final llama = await r.resolve(
        provider: LlmProviderId.openaiCompatible,
        model: 'meta/llama-3-8b',
      ); // default base URL = OpenRouter
      expect(llama.image || llama.pdf, isFalse);
      final unknown = await r.resolve(
        provider: LlmProviderId.openaiCompatible,
        model: 'not/listed',
        baseUrl: 'https://openrouter.ai/api/v1',
      );
      expect(unknown.kinds, {AiInputKind.text, AiInputKind.youtube});

      expect(rc.requests, hasLength(1));
      expect(
        rc.requests.single.url.toString(),
        'https://openrouter.ai/api/v1/models',
      );
      expect(rc.requests.single.headers.containsKey('authorization'), isFalse);
    });

    test('cache expires after the TTL', () async {
      var now = DateTime(2026);
      final rc = RecordingClient([(_) => jsonResponse(_openRouterModels())]);
      final r = AiCapabilityResolver(
        client: rc.client,
        isWeb: false,
        cacheTtl: const Duration(hours: 1),
        clock: () => now,
      );
      await r.openRouterModalities('https://openrouter.ai/api/v1');
      now = now.add(const Duration(minutes: 59));
      await r.openRouterModalities('https://openrouter.ai/api/v1');
      expect(rc.requests, hasLength(1));
      now = now.add(const Duration(minutes: 2));
      await r.openRouterModalities('https://openrouter.ai/api/v1');
      expect(rc.requests, hasLength(2));
    });

    test('lookup failure -> text only, not cached', () async {
      final rc = RecordingClient([
        (_) => jsonResponse({'error': 'down'}, 503),
        (_) => jsonResponse(_openRouterModels()),
      ]);
      final r = AiCapabilityResolver(client: rc.client, isWeb: false);
      Future<AiCapabilities> gpt() => r.resolve(
        provider: LlmProviderId.openaiCompatible,
        model: 'openai/gpt-5.4-mini',
      );
      expect((await gpt()).image, isFalse);
      expect((await gpt()).image, isTrue);
    });

    test('self-hosted: no lookup, manual override applies', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      final r = AiCapabilityResolver(client: rc.client, isWeb: false);
      final plain = await r.resolve(
        provider: LlmProviderId.openaiCompatible,
        model: 'llava',
        baseUrl: 'http://localhost:11434/v1',
      );
      expect(plain.image, isFalse);
      final overridden = await r.resolve(
        provider: LlmProviderId.openaiCompatible,
        model: 'llava',
        baseUrl: 'http://localhost:11434/v1',
        manualOverride: {AiInputKind.image},
      );
      expect(overridden.image, isTrue);
      expect(overridden.pdf, isFalse);
      expect(rc.requests, isEmpty);
    });

    test('first-party providers ignore the manual override', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      final r = AiCapabilityResolver(client: rc.client, isWeb: false);
      final c = await r.resolve(
        provider: LlmProviderId.openai,
        model: 'gpt-3.5-turbo',
        manualOverride: {AiInputKind.image},
      );
      expect(c.image, isFalse);
      expect(rc.requests, isEmpty);
    });
  });
}
