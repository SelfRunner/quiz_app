import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'ai_source.dart';
import 'llm_provider.dart';
import 'providers/openai_provider.dart';

/// Which input kinds a provider + model accepts. Attachment options in the
/// UI should only be offered for supported kinds.
///
/// [text] is always true. [youtube] is true when a YouTube URL can be used
/// at all: natively ([youtubeNative], Gemini) or via a client-side
/// transcript (other providers, not on web where YouTube blocks the
/// request).
@immutable
class AiCapabilities {
  const AiCapabilities({
    this.pdf = false,
    this.image = false,
    this.audio = false,
    this.video = false,
    this.youtube = false,
    this.youtubeNative = false,
  });

  /// Text only, no YouTube.
  static const textOnly = AiCapabilities();

  bool get text => true;
  final bool pdf;
  final bool image;
  final bool audio;
  final bool video;
  final bool youtube;

  /// The video itself is sent to the model (Gemini), not a transcript.
  final bool youtubeNative;

  bool supports(AiInputKind kind) => switch (kind) {
    AiInputKind.text => true,
    AiInputKind.pdf => pdf,
    AiInputKind.image => image,
    AiInputKind.audio => audio,
    AiInputKind.video => video,
    AiInputKind.youtube => youtube,
  };

  Set<AiInputKind> get kinds => {
    for (final k in AiInputKind.values)
      if (supports(k)) k,
  };

  /// Adds [extra] kinds (manual override). Only pdf/image/audio/video are
  /// considered.
  AiCapabilities including(Set<AiInputKind> extra) => AiCapabilities(
    pdf: pdf || extra.contains(AiInputKind.pdf),
    image: image || extra.contains(AiInputKind.image),
    audio: audio || extra.contains(AiInputKind.audio),
    video: video || extra.contains(AiInputKind.video),
    youtube: youtube,
    youtubeNative: youtubeNative,
  );

  /// Capabilities known without network access.
  ///
  /// * Gemini (`gemini-*`): everything, YouTube natively. Gemma: text +
  ///   images. Other models on that API: text.
  /// * OpenAI: PDF + images for vision models (gpt-4o*, gpt-4.1*, gpt-4.5*,
  ///   gpt-4-turbo, gpt-5*, chatgpt-4o*, o1, o3, o4*; not o1-mini/o3-mini),
  ///   otherwise text. No audio/video.
  /// * Anthropic: PDF + images for Claude 3 and later (any `claude-*` except
  ///   claude-1/2/instant), otherwise text.
  /// * OpenAI-compatible: text only (OpenRouter metadata and the manual
  ///   override are applied by [AiCapabilityResolver]).
  ///
  /// YouTube via transcript is available everywhere except on web.
  static AiCapabilities forModel(
    LlmProviderId provider,
    String model, {
    bool isWeb = kIsWeb,
  }) {
    final m = _bareModel(model);
    final transcriptYoutube = !isWeb;
    switch (provider) {
      case LlmProviderId.gemini:
        if (m.startsWith('gemini')) {
          return const AiCapabilities(
            pdf: true,
            image: true,
            audio: true,
            video: true,
            youtube: true,
            youtubeNative: true,
          );
        }
        return AiCapabilities(
          image: m.startsWith('gemma-3') || m.startsWith('gemma-4'),
          youtube: transcriptYoutube,
        );
      case LlmProviderId.openai:
        final vision = isOpenAiVisionModel(m);
        return AiCapabilities(
          pdf: vision,
          image: vision,
          youtube: transcriptYoutube,
        );
      case LlmProviderId.anthropic:
        final vision = isClaudeVisionModel(m);
        return AiCapabilities(
          pdf: vision,
          image: vision,
          youtube: transcriptYoutube,
        );
      case LlmProviderId.openaiCompatible:
        return AiCapabilities(youtube: transcriptYoutube);
    }
  }

  static final _openAiVision = RegExp(
    r'^(gpt-4o|gpt-4\.1|gpt-4\.5|gpt-4-turbo|gpt-5|chatgpt-4o|o1|o3|o4)',
  );
  static final _openAiNoVision = RegExp(r'^(o1-mini|o1-preview|o3-mini)');

  /// OpenAI models that accept images and PDF input.
  static bool isOpenAiVisionModel(String model) {
    final m = model.toLowerCase();
    return OpenAiProvider.isTextModel(m) &&
        _openAiVision.hasMatch(m) &&
        !_openAiNoVision.hasMatch(m);
  }

  static final _claudeLegacy = RegExp(r'^claude-(1|2|instant)');

  /// Claude models that accept images and PDF input (Claude 3+).
  static bool isClaudeVisionModel(String model) {
    final m = model.toLowerCase();
    return m.startsWith('claude-') && !_claudeLegacy.hasMatch(m);
  }

  static String _bareModel(String model) {
    final m = model.trim().toLowerCase();
    return m.startsWith('models/') ? m.substring(7) : m;
  }

  @override
  bool operator ==(Object other) =>
      other is AiCapabilities &&
      other.pdf == pdf &&
      other.image == image &&
      other.audio == audio &&
      other.video == video &&
      other.youtube == youtube &&
      other.youtubeNative == youtubeNative;

  @override
  int get hashCode =>
      Object.hash(pdf, image, audio, video, youtube, youtubeNative);

  @override
  String toString() =>
      'AiCapabilities(${kinds.map((k) => k.name).join(', ')}'
      '${youtubeNative ? ', youtubeNative' : ''})';
}

/// The per-model manual override "this model supports images / PDF" for
/// OpenAI-compatible endpoints whose capabilities cannot be detected. Every
/// `ApiKeyStore` implements it (the methods are part of that interface), so
/// call them on the store directly.
abstract interface class AiCapabilityOverrideStore {
  /// Extra input kinds the user enabled for [model] (empty when none).
  Future<Set<AiInputKind>> getInputOverride(
    LlmProviderId provider,
    String model,
  );

  /// Replaces the override for [model]; an empty set clears it. Only
  /// [AiInputKind.image] and [AiInputKind.pdf] are meaningful.
  Future<void> setInputOverride(
    LlmProviderId provider,
    String model,
    Set<AiInputKind> kinds,
  );
}

/// Resolves [AiCapabilities] for a provider + model, using OpenRouter's
/// `/models` metadata (`architecture.input_modalities`) when the
/// OpenAI-compatible base URL is OpenRouter. The model list is cached per
/// base URL for [cacheTtl]; lookup failures fall back to text-only.
class AiCapabilityResolver {
  AiCapabilityResolver({
    required this.client,
    bool? isWeb,
    this.cacheTtl = const Duration(hours: 6),
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : isWeb = isWeb ?? kIsWeb,
       _clock = clock ?? DateTime.now;

  final http.Client client;
  final bool isWeb;
  final Duration cacheTtl;
  final Duration timeout;
  final DateTime Function() _clock;

  final _cache = <String, _CachedModalities>{};
  final _inFlight = <String, Future<Map<String, Set<AiInputKind>>>>{};

  static bool isOpenRouterUrl(String? baseUrl) =>
      baseUrl != null &&
      (Uri.tryParse(baseUrl)?.host ?? '').toLowerCase().endsWith(
        'openrouter.ai',
      );

  /// [manualOverride] adds kinds for OpenAI-compatible endpoints (ignored for
  /// the first-party providers, whose capabilities are known).
  Future<AiCapabilities> resolve({
    required LlmProviderId provider,
    required String model,
    String? baseUrl,
    Set<AiInputKind> manualOverride = const {},
  }) async {
    final base = AiCapabilities.forModel(provider, model, isWeb: isWeb);
    if (provider != LlmProviderId.openaiCompatible) return base;
    var caps = base;
    final url = baseUrl ?? provider.defaultBaseUrl;
    if (isOpenRouterUrl(url)) {
      try {
        final modalities = await openRouterModalities(url!);
        caps = caps.including(modalities[model.trim()] ?? const {});
      } catch (_) {
        // Unknown -> conservative (text only).
      }
    }
    return caps.including(manualOverride);
  }

  /// Model id -> supported attachment kinds (image / pdf) from OpenRouter's
  /// public `/models` list. Cached; concurrent calls share one request.
  Future<Map<String, Set<AiInputKind>>> openRouterModalities(String baseUrl) {
    final key = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cached = _cache[key];
    if (cached != null && _clock().difference(cached.at) < cacheTtl) {
      return Future.value(cached.models);
    }
    // Block body: returning the removed (pending) future from whenComplete
    // would make it wait for itself.
    return _inFlight[key] ??= _fetch(key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<Map<String, Set<AiInputKind>>> _fetch(String base) async {
    final response = await client
        .get(Uri.parse('$base/models'))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final data = body is Map ? body['data'] : null;
    final models = <String, Set<AiInputKind>>{};
    for (final m in (data is List ? data : const <Object?>[])) {
      if (m is! Map || m['id'] is! String) continue;
      final arch = m['architecture'];
      final inputs = arch is Map ? arch['input_modalities'] : null;
      models[m['id'] as String] = {
        if (inputs is List) ...[
          if (inputs.contains('image')) AiInputKind.image,
          if (inputs.contains('file')) AiInputKind.pdf,
        ],
      };
    }
    _cache[base] = _CachedModalities(_clock(), models);
    return models;
  }

  /// Drops cached OpenRouter metadata.
  void clearCache() => _cache.clear();
}

class _CachedModalities {
  const _CachedModalities(this.at, this.models);
  final DateTime at;
  final Map<String, Set<AiInputKind>> models;
}
