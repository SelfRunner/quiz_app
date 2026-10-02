import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import '../../core/errors/app_exception.dart';
import '../llm_chat.dart';
import '../llm_provider.dart';
import 'sse.dart';

/// Carried in `AiException.cause` when a model returned text that is not a
/// JSON object, so `AiService` can send it back in the repair prompt.
class RawModelOutput {
  const RawModelOutput(this.text, {this.truncated = false});
  final String text;

  /// The model hit its output-token limit; retrying the same request is
  /// unlikely to help.
  final bool truncated;

  @override
  String toString() => 'RawModelOutput(${text.length} chars)';
}

/// Shared HTTP plumbing for [LlmProvider] implementations: timeouts,
/// transport-error mapping, status-code mapping to typed [AiException]s and
/// lenient JSON extraction.
abstract class HttpLlmProvider implements LlmProvider {
  HttpLlmProvider(
    this.config,
    this.client, {
    this.generateTimeout = const Duration(minutes: 5),
    this.listTimeout = const Duration(seconds: 30),
    bool? isWeb,
  }) : isWeb = isWeb ?? kIsWeb;

  final LlmConfig config;
  final http.Client client;
  final Duration generateTimeout;
  final Duration listTimeout;

  /// Whether requests come from a browser (adds CORS-related headers and
  /// error hints).
  final bool isWeb;

  @override
  LlmProviderId get id => config.providerId;

  /// Name used in user-facing messages.
  String get displayName => config.providerId.displayName;

  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration? timeout,
  }) => _send(
    () => client.post(
      uri,
      headers: {'content-type': 'application/json', ...headers},
      body: jsonEncode(body),
    ),
    timeout ?? generateTimeout,
  );

  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) => _send(() => client.get(uri, headers: headers), timeout ?? listTimeout);

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    final response = await sendRaw(request, timeout: timeout);
    final body = _decodeBody(response);
    if (body == null) {
      throw AiException(
        '$displayName returned an unexpected response.',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  /// Sends [request] with transport-error mapping; non-2xx responses throw
  /// the mapped [AiException]. Returns the raw 2xx response (for endpoints
  /// whose result is in headers, e.g. resumable uploads).
  Future<http.Response> sendRaw(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout ?? generateTimeout);
    } on TimeoutException catch (e, st) {
      throw transportError(e, st);
    } on http.ClientException catch (e, st) {
      throw transportError(e, st);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw mapHttpError(
      providerName: displayName,
      statusCode: response.statusCode,
      body: _decodeBody(response),
      rawBody: response.body,
      apiKey: config.apiKey,
    );
  }

  /// Maps a transport failure (timeout, connection error) to a
  /// [NetworkException]; [AppException]s pass through unchanged.
  AppException transportError(Object e, StackTrace st) {
    if (e is AppException) return e;
    if (e is TimeoutException) {
      return NetworkException(
        '$displayName took too long to respond. Try again, use a faster '
        'model, or shorten the input.',
        cause: e,
        stackTrace: st,
      );
    }
    if (e is http.ClientException) {
      return NetworkException(
        isWeb
            ? "Couldn't reach $displayName. Check your connection. In the "
                  'browser this can also mean the endpoint blocks web '
                  'requests (CORS).'
            : "Couldn't reach $displayName. Check your internet connection.",
        cause: e,
        stackTrace: st,
      );
    }
    return AiException(
      '$displayName returned an unexpected response.',
      cause: e,
      stackTrace: st,
    );
  }

  /// Maximum silence between two stream chunks before the stream fails with
  /// a [NetworkException].
  Duration get streamIdleTimeout => const Duration(minutes: 3);

  /// Endpoints (provider + base URL + model) that rejected `stream: true`
  /// during this app session.
  static final _noStreaming = <String>{};

  String get _streamKey =>
      '${config.providerId.wireName}|${config.baseUrl}|${config.model}';

  /// True once this endpoint + model rejected `stream: true` (remembered
  /// for the app session, across provider instances); chat calls then go
  /// straight to the non-streaming request.
  bool get streamingUnsupported => _noStreaming.contains(_streamKey);
  set streamingUnsupported(bool value) =>
      value ? _noStreaming.add(_streamKey) : _noStreaming.remove(_streamKey);

  /// Forgets every remembered streaming rejection (tests).
  @visibleForTesting
  static void resetStreamingSupport() => _noStreaming.clear();

  /// Shared driver for SSE chat streams.
  ///
  /// POSTs the result of [body] (built inside the stream, so its errors are
  /// stream errors too) to [uri] as an abortable request (cancelling the
  /// returned stream completes the abort trigger and cancels the byte
  /// stream, which closes the connection) and feeds every SSE event to a
  /// fresh parser from [parser]. Emits exactly one [LlmChatDone] last.
  ///
  /// * Non-2xx: mapped with [mapHttpError]; a 400/422 whose message matches
  ///   [streamRejection] switches this instance to [fallback] (non-streaming)
  ///   and answers with it.
  /// * A JSON (non-SSE) 2xx answer is parsed with [parseJson].
  Stream<LlmChatEvent> streamSse({
    required Uri uri,
    required Map<String, String> headers,
    required Future<Map<String, Object?>> Function() body,
    required SseChatParser Function() parser,
    required LlmChatCompletion Function(Map<String, dynamic> json) parseJson,
    required Future<LlmChatCompletion> Function() fallback,
    RegExp? streamRejection,
  }) {
    late final StreamController<LlmChatEvent> controller;
    final abort = Completer<void>();
    StreamSubscription<SseEvent>? sub;
    var closed = false;

    void finish() {
      if (closed) return;
      closed = true;
      final s = sub;
      if (s != null) unawaited(s.cancel());
      unawaited(controller.close());
    }

    void fail(Object e, StackTrace st) {
      if (closed) return;
      controller.addError(transportError(e, st), st);
      finish();
    }

    void emit(LlmChatEvent event) {
      if (closed) return;
      controller.add(event);
      if (event is LlmChatDone) finish();
    }

    void emitCompletion(LlmChatCompletion c) {
      if (c.text.isNotEmpty) emit(LlmTextDelta(c.text));
      emit(LlmChatDone(c.reason, detail: c.detail, streamed: false));
    }

    Future<void> start() async {
      try {
        if (streamingUnsupported) {
          emitCompletion(await fallback());
          return;
        }
        final payload = await body();
        if (closed) return;
        final request =
            http.AbortableRequest('POST', uri, abortTrigger: abort.future)
              ..headers.addAll({
                'content-type': 'application/json',
                'accept': 'text/event-stream',
                ...headers,
              })
              ..body = jsonEncode(payload);
        final response = await client.send(request).timeout(generateTimeout);
        if (closed) return;
        final status = response.statusCode;
        if (status < 200 || status >= 300) {
          final raw = await response.stream.bytesToString().timeout(
            listTimeout,
            onTimeout: () => '',
          );
          final error = mapHttpError(
            providerName: displayName,
            statusCode: status,
            body: _decodeString(raw),
            rawBody: raw,
            apiKey: config.apiKey,
          );
          if (error is AiException &&
              streamRejection != null &&
              HttpLlmProvider.isRejection(error, streamRejection)) {
            streamingUnsupported = true;
            if (closed) return;
            emitCompletion(await fallback());
            return;
          }
          throw error;
        }
        final type = (response.headers['content-type'] ?? '').toLowerCase();
        if (type.contains('json') && !type.contains('event-stream')) {
          final raw = await response.stream.bytesToString().timeout(
            generateTimeout,
          );
          final json = _decodeString(raw);
          if (json == null) {
            throw AiException('$displayName returned an unexpected response.');
          }
          emitCompletion(parseJson(json));
          return;
        }
        final p = parser();
        sub = parseSse(response.stream)
            .timeout(
              streamIdleTimeout,
              onTimeout: (sink) => sink.addError(
                TimeoutException('No data for $streamIdleTimeout'),
              ),
            )
            .listen(
              (event) {
                try {
                  p.onEvent(event).forEach(emit);
                } catch (e, st) {
                  fail(e, st);
                }
              },
              onError: fail,
              onDone: () {
                if (closed) return;
                try {
                  emit(p.onEnd());
                } catch (e, st) {
                  fail(e, st);
                }
              },
              cancelOnError: true,
            );
      } catch (e, st) {
        fail(e, st);
      }
    }

    controller = StreamController<LlmChatEvent>(
      onListen: () => unawaited(start()),
      onCancel: () {
        closed = true;
        if (!abort.isCompleted) abort.complete();
        return sub?.cancel();
      },
    );
    return controller.stream;
  }

  static Map<String, dynamic>? _decodeString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// True if [e] is a 400/422-style rejection whose provider message matches
  /// [pattern] (used to fall back to an older request shape).
  static bool isRejection(AiException e, RegExp pattern) {
    final code = e.statusCode;
    if (code != 400 && code != 422) return false;
    if (e.kind == AiErrorKind.invalidApiKey) return false;
    final cause = e.cause;
    final detail = cause is ProviderErrorDetail ? cause.message : e.message;
    return pattern.hasMatch(detail);
  }
}

/// Stateful per-request parser used by [HttpLlmProvider.streamSse].
abstract class SseChatParser {
  /// Events produced by one SSE event (may throw a typed error).
  Iterable<LlmChatEvent> onEvent(SseEvent event);

  /// Called when the stream ends without an [LlmChatDone] having been
  /// emitted: return the final event or throw (e.g. connection lost).
  LlmChatDone onEnd();
}

/// Decodes an SSE `data` payload as a JSON object (null for `[DONE]`,
/// empty or non-object data).
Map<String, dynamic>? sseJson(SseEvent event) {
  final data = event.data.trim();
  if (data.isEmpty || data == '[DONE]') return null;
  try {
    final decoded = jsonDecode(data);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Error for a stream that ended before the provider's final event.
NetworkException streamInterrupted(String providerName) => NetworkException(
  'The connection to $providerName was lost before the answer was '
  'complete. Try again.',
);

/// Provider error text (key-redacted), attached as `AiException.cause`.
class ProviderErrorDetail {
  const ProviderErrorDetail(this.message);
  final String message;

  @override
  String toString() => 'ProviderErrorDetail($message)';
}

/// Extracts a human-readable error message from common provider bodies:
/// OpenAI/OpenRouter `{error: {message}}`, Anthropic
/// `{type: error, error: {type, message}}`, Gemini
/// `{error: {code, message, status}}`.
String extractErrorMessage(Map<String, dynamic>? body, String rawBody) {
  final error = body?['error'];
  if (error is Map) {
    final message = error['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  if (error is String && error.isNotEmpty) return error;
  final message = body?['message'];
  if (message is String && message.isNotEmpty) return message;
  final trimmed = rawBody.trim();
  if (trimmed.isEmpty || trimmed.startsWith('<')) return '';
  return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
}

/// Maps a non-2xx response to an [AppException] with a user-safe message.
/// The API key is redacted from anything echoed back.
AppException mapHttpError({
  required String providerName,
  required int statusCode,
  required Map<String, dynamic>? body,
  required String rawBody,
  required String apiKey,
}) {
  var detail = extractErrorMessage(body, rawBody);
  if (apiKey.isNotEmpty) detail = detail.replaceAll(apiKey, '[redacted]');
  final lower = '$detail ${body == null ? '' : jsonEncode(body)}'.toLowerCase();
  final cause = ProviderErrorDetail(detail);
  final suffix = detail.isEmpty ? '' : ' ($detail)';

  final keyInvalid =
      lower.contains('api_key_invalid') ||
      lower.contains('api key not valid') ||
      lower.contains('invalid api key') ||
      lower.contains('invalid_api_key') ||
      lower.contains('incorrect api key') ||
      lower.contains('authentication_error');

  if (statusCode == 401 || (statusCode == 400 && keyInvalid)) {
    return AiException(
      'Your $providerName API key was rejected. Check it in Settings.',
      kind: AiErrorKind.invalidApiKey,
      statusCode: statusCode,
      cause: cause,
    );
  }
  if (statusCode == 403) {
    return AiException(
      'Your $providerName API key was rejected or has no access to this '
      'model.$suffix',
      kind: AiErrorKind.invalidApiKey,
      statusCode: statusCode,
      cause: cause,
    );
  }
  if (statusCode == 402 ||
      (statusCode == 429 &&
          (lower.contains('quota') ||
              lower.contains('billing') ||
              lower.contains('credit')))) {
    return AiException(
      'Your $providerName quota or credits are used up. Check your plan and '
      'billing with the provider.$suffix',
      kind: AiErrorKind.rateLimited,
      statusCode: statusCode,
      cause: cause,
    );
  }
  if (statusCode == 429) {
    return AiException(
      '$providerName rate limit reached. Wait a moment and try again.',
      kind: AiErrorKind.rateLimited,
      statusCode: statusCode,
      cause: cause,
    );
  }
  if (statusCode == 404) {
    return AiException(
      '$providerName could not find that model or endpoint. Check the model '
      'name (and base URL, if set) in Settings.$suffix',
      statusCode: statusCode,
      cause: cause,
    );
  }
  if (statusCode == 408 || statusCode == 504) {
    return AiException(
      '$providerName timed out. Try again or shorten the input.',
      statusCode: statusCode,
      cause: cause,
    );
  }
  if (statusCode >= 500) {
    return AiException(
      '$providerName is temporarily unavailable or overloaded. Try again '
      'shortly.',
      statusCode: statusCode,
      cause: cause,
    );
  }
  return AiException(
    '$providerName rejected the request$suffix.',
    statusCode: statusCode,
    cause: cause,
  );
}

/// Parses model text into a JSON object. Tolerates Markdown code fences and
/// leading/trailing prose. Throws `AiException(kind: invalidOutput)` with a
/// [RawModelOutput] cause otherwise.
Map<String, dynamic> decodeJsonObject(String text, {String? providerName}) {
  final candidates = <String>[text.trim()];
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) candidates.add(fence.group(1)!.trim());
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) candidates.add(text.substring(start, end + 1));
  for (final c in candidates) {
    try {
      final decoded = jsonDecode(c);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // try next candidate
    }
  }
  throw AiException(
    '${providerName ?? 'The AI'} returned output that is not valid JSON.',
    kind: AiErrorKind.invalidOutput,
    cause: RawModelOutput(text),
  );
}

/// Joins a base URL and a path without doubling slashes.
Uri joinUrl(String base, String path) {
  final b = base.replaceAll(RegExp(r'/+$'), '');
  final p = path.startsWith('/') ? path : '/$path';
  return Uri.parse('$b$p');
}
