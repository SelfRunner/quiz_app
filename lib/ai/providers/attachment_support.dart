import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../ai_source.dart';
import '../llm_provider.dart';

const _mb = 1024 * 1024;

/// Per-provider attachment limits, checked before anything is sent.
///
/// | Provider | per file | per request | notes |
/// |---|---|---|---|
/// | Gemini | 2 GB | - | inline (base64) up to 15 MB in total, larger files via the Files API |
/// | OpenAI | 50 MB | 50 MB | PDF + png/jpeg/webp/gif |
/// | Anthropic | PDF 24 MB, image 5 MB | 24 MB | 32 MB request cap incl. base64 overhead; png/jpeg/webp/gif |
/// | OpenAI-compatible | 20 MB | 30 MB | PDF (`file` part) + images (`image_url`) |
class ProviderLimits {
  const ProviderLimits({
    required this.kinds,
    required this.maxFileBytes,
    required this.maxTotalBytes,
    this.imageMimeTypes,
    this.maxImageBytes,
  });

  /// File kinds the API can take at all.
  final Set<AiInputKind> kinds;
  final int maxFileBytes;

  /// Sum of all attachment bytes in one request (null = no limit).
  final int? maxTotalBytes;

  /// Accepted image types (null = any `image/*`).
  final Set<String>? imageMimeTypes;

  /// Stricter per-image limit, if any.
  final int? maxImageBytes;

  static const _commonImages = {
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
  };

  /// Gemini inline (base64) budget; files above it (or once the request
  /// holds this much inline data) go through the Files API.
  static const geminiInlineBytes = 15 * _mb;

  static const gemini = ProviderLimits(
    kinds: {
      AiInputKind.pdf,
      AiInputKind.image,
      AiInputKind.audio,
      AiInputKind.video,
    },
    maxFileBytes: 2048 * _mb,
    maxTotalBytes: null,
    imageMimeTypes: {
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/heic',
      'image/heif',
    },
  );

  static const openai = ProviderLimits(
    kinds: {AiInputKind.pdf, AiInputKind.image},
    maxFileBytes: 50 * _mb,
    maxTotalBytes: 50 * _mb,
    imageMimeTypes: _commonImages,
  );

  static const anthropic = ProviderLimits(
    kinds: {AiInputKind.pdf, AiInputKind.image},
    maxFileBytes: 24 * _mb,
    maxTotalBytes: 24 * _mb,
    imageMimeTypes: _commonImages,
    maxImageBytes: 5 * _mb,
  );

  static const openaiCompatible = ProviderLimits(
    kinds: {AiInputKind.pdf, AiInputKind.image},
    maxFileBytes: 20 * _mb,
    maxTotalBytes: 30 * _mb,
    imageMimeTypes: _commonImages,
  );

  static ProviderLimits forProvider(LlmProviderId id) => switch (id) {
    LlmProviderId.gemini => gemini,
    LlmProviderId.openai => openai,
    LlmProviderId.anthropic => anthropic,
    LlmProviderId.openaiCompatible => openaiCompatible,
  };

  /// Throws `AiException(kind: unsupported)` for a kind / image type the
  /// provider cannot take, `ValidationException` when a file or the request
  /// is too large.
  void check(List<LlmAttachment> attachments, String providerName) {
    var total = 0;
    for (final a in attachments) {
      if (a is! LlmFileAttachment) continue;
      if (!kinds.contains(a.kind)) {
        throw AiException(
          '$providerName can\'t read ${a.kind.plural} ("${a.filename}"). '
          '${a.kind == AiInputKind.audio || a.kind == AiInputKind.video ? 'Use Gemini for audio and video.' : 'Pick a different provider.'}',
          kind: AiErrorKind.unsupported,
        );
      }
      final images = imageMimeTypes;
      if (a.kind == AiInputKind.image &&
          images != null &&
          !images.contains(a.mimeType)) {
        throw AiException(
          '$providerName can\'t read ${a.mimeType} images ("${a.filename}"). '
          'Use ${images.map((m) => m.substring(6).toUpperCase()).join(', ')}.',
          kind: AiErrorKind.unsupported,
        );
      }
      final limit = a.kind == AiInputKind.image && maxImageBytes != null
          ? maxImageBytes!
          : maxFileBytes;
      if (a.bytes.length > limit) {
        throw ValidationException(
          '"${a.filename}" is ${formatBytes(a.bytes.length)}; $providerName '
          'accepts ${a.kind.plural} up to ${formatBytes(limit)}.',
        );
      }
      total += a.bytes.length;
    }
    final max = maxTotalBytes;
    if (max != null && total > max) {
      throw ValidationException(
        'The attached files total ${formatBytes(total)}; $providerName '
        'accepts up to ${formatBytes(max)} per request. Remove some files.',
      );
    }
  }
}

/// `data:<mime>;base64,<data>` URL.
String dataUrl(String mimeType, List<int> bytes) =>
    'data:$mimeType;base64,${base64Encode(bytes)}';

/// Human-readable size (e.g. `14.2 MB`).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < _mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * _mb) {
    final mb = bytes / _mb;
    return '${mb == mb.roundToDouble() ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * _mb)).toStringAsFixed(1)} GB';
}

/// Throws `AiException(unsupported)` if [attachments] contain a YouTube URL
/// (all providers but Gemini).
void rejectYoutube(
  List<LlmAttachment> attachments,
  String? youtubeUrl,
  String providerName,
) {
  if (youtubeUrl != null || attachments.any((a) => a is LlmYoutubeAttachment)) {
    throw AiException(
      '$providerName cannot watch YouTube videos directly; a transcript is '
      'used instead.',
      kind: AiErrorKind.unsupported,
    );
  }
}
