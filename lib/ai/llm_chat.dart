import 'llm_provider.dart';

/// Speaker of an [LlmChatMessage].
enum LlmChatRole { user, assistant }

/// One message of a provider-level conversation (plain text).
class LlmChatMessage {
  const LlmChatMessage(this.role, this.text);
  const LlmChatMessage.user(this.text) : role = LlmChatRole.user;
  const LlmChatMessage.assistant(this.text) : role = LlmChatRole.assistant;

  final LlmChatRole role;
  final String text;

  @override
  String toString() => 'LlmChatMessage(${role.name}, ${text.length} chars)';
}

/// Why the model stopped.
enum LlmFinishReason {
  /// Natural end of the answer.
  stop,

  /// Output-token limit reached (answer cut off).
  length,

  /// The model declined to answer.
  refusal,

  /// Blocked by a safety / content filter.
  blocked,

  /// Unknown or provider-specific reason.
  other,
}

/// Events of [LlmChatProvider.streamChat].
sealed class LlmChatEvent {
  const LlmChatEvent();
}

/// A chunk of answer text (append to what came before).
final class LlmTextDelta extends LlmChatEvent {
  const LlmTextDelta(this.text);
  final String text;

  @override
  String toString() => 'LlmTextDelta(${text.length} chars)';
}

/// Last event of a successful stream.
final class LlmChatDone extends LlmChatEvent {
  const LlmChatDone(this.reason, {this.detail, this.streamed = true});

  final LlmFinishReason reason;

  /// Provider text for [LlmFinishReason.refusal] / [LlmFinishReason.blocked]
  /// / [LlmFinishReason.other] (refusal message, raw finish reason).
  final String? detail;

  /// False when the provider answered without streaming (endpoint rejected
  /// `stream`, or answered with plain JSON).
  final bool streamed;
}

/// Result of a non-streaming chat call.
class LlmChatCompletion {
  const LlmChatCompletion(this.text, this.reason, {this.detail});

  final String text;
  final LlmFinishReason reason;
  final String? detail;
}

/// Free-text, multi-turn chat with token streaming. Implemented by every
/// built-in provider next to [LlmProvider].
///
/// [messages] alternate user/assistant and end with a user message (see
/// `normalizeChatMessages`). [attachments] go into the LAST user message,
/// before its text, each preceded by a text part holding its label (same
/// wire encoding and limits as `LlmProvider.generateJson`).
///
/// Errors (thrown from the stream / future): the same typed errors as
/// `generateJson` (`AiException`, `ValidationException`,
/// `NetworkException`). Cancelling the stream subscription aborts the HTTP
/// request.
abstract interface class LlmChatProvider {
  LlmProviderId get id;

  /// Streams the answer: zero or more [LlmTextDelta]s, then one
  /// [LlmChatDone]. When the endpoint rejects streaming the provider falls
  /// back to [completeChat] once and emits the whole text as one delta
  /// (`LlmChatDone.streamed == false`), and remembers that for later calls.
  Stream<LlmChatEvent> streamChat({
    required List<LlmChatMessage> messages,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
    int? maxOutputTokens,
  });

  /// Non-streaming variant of [streamChat].
  Future<LlmChatCompletion> completeChat({
    required List<LlmChatMessage> messages,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
    int? maxOutputTokens,
  });
}

/// Makes [messages] valid for every provider: drops blank messages and
/// leading assistant messages, merges consecutive messages of the same role
/// (blank line between) and requires the result to end with a user message
/// (returns an empty list otherwise).
List<LlmChatMessage> normalizeChatMessages(List<LlmChatMessage> messages) {
  final out = <LlmChatMessage>[];
  for (final m in messages) {
    final text = m.text.trim();
    if (text.isEmpty) continue;
    if (out.isEmpty && m.role == LlmChatRole.assistant) continue;
    if (out.isNotEmpty && out.last.role == m.role) {
      out[out.length - 1] = LlmChatMessage(m.role, '${out.last.text}\n\n$text');
    } else {
      out.add(LlmChatMessage(m.role, text));
    }
  }
  if (out.isEmpty || out.last.role != LlmChatRole.user) return const [];
  return out;
}
