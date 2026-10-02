import 'package:meta/meta.dart';

import 'ai_service.dart';
import 'llm_provider.dart';

export 'ai_source.dart';

/// Speaker of a [ChatTurn].
enum ChatRole { user, assistant }

/// One earlier message of a chat (plain text / Markdown as shown).
@immutable
class ChatTurn {
  const ChatTurn({required this.role, required this.text});
  const ChatTurn.user(this.text) : role = ChatRole.user;
  const ChatTurn.assistant(this.text) : role = ChatRole.assistant;

  final ChatRole role;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ChatTurn && other.role == role && other.text == text;

  @override
  int get hashCode => Object.hash(role, text);

  @override
  String toString() => 'ChatTurn(${role.name}, ${text.length} chars)';
}

/// How much of a context source the model received.
enum ChatSourceStatus {
  /// Whole text / file sent.
  full,

  /// Long text cut to the context budget: beginning and end kept, the
  /// headings of the omitted middle listed.
  excerpt,

  /// Over the context budget: only the label was sent (not citable).
  omitted,

  /// Could not be sent: file type the model can't read, too large, empty,
  /// transcript unavailable, ... ([ChatSourceRef.note] says why; not
  /// citable).
  unreadable,
}

/// A context source as numbered for the model (`[S1]`, `[S2]`, ...).
/// Numbers follow the order of the `context` list.
@immutable
class ChatSourceRef {
  const ChatSourceRef({
    required this.number,
    required this.type,
    required this.title,
    this.id,
    this.status = ChatSourceStatus.full,
    this.note,
  });

  /// 1-based; the model cites it as `[S<number>]`.
  final int number;
  final AiSourceType type;

  /// `AiSource.id` (null when the caller gave none).
  final String? id;
  final String title;
  final ChatSourceStatus status;

  /// User-facing reason for [ChatSourceStatus.excerpt] / [omitted] /
  /// [unreadable] (e.g. "PDF files can't be read by gpt-4o-mini").
  final String? note;

  /// `S1`, `S2`, ...
  String get marker => 'S$number';

  /// Whether the model saw any content of this source (so citing it is
  /// meaningful).
  bool get isCitable =>
      status == ChatSourceStatus.full || status == ChatSourceStatus.excerpt;

  ChatCitation toCitation() =>
      ChatCitation(number: number, type: type, id: id, title: title);

  @override
  bool operator ==(Object other) =>
      other is ChatSourceRef &&
      other.number == number &&
      other.type == type &&
      other.id == id &&
      other.title == title &&
      other.status == status &&
      other.note == note;

  @override
  int get hashCode => Object.hash(number, type, id, title, status, note);

  @override
  String toString() =>
      'ChatSourceRef($marker ${type.wireName} "$title", ${status.name})';
}

/// A source the answer cites (`[S<number>]` marker in the text).
@immutable
class ChatCitation {
  const ChatCitation({
    required this.number,
    required this.type,
    required this.title,
    this.id,
  });

  /// From [toJson] (persisted chat messages). Unknown types map to
  /// [AiSourceType.text].
  factory ChatCitation.fromJson(Map<String, dynamic> json) => ChatCitation(
    number: (json['n'] as num?)?.toInt() ?? 0,
    type: AiSourceType.values.firstWhere(
      (t) => t.wireName == json['type'],
      orElse: () => AiSourceType.text,
    ),
    id: json['id'] as String?,
    title: json['title'] as String? ?? '',
  );

  final int number;
  final AiSourceType type;
  final String? id;
  final String title;

  String get marker => 'S$number';

  /// `{n, type, id, title}`; store it with the assistant message.
  Map<String, Object?> toJson() => {
    'n': number,
    'type': type.wireName,
    'id': id,
    'title': title,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatCitation &&
      other.number == number &&
      other.type == type &&
      other.id == id &&
      other.title == title;

  @override
  int get hashCode => Object.hash(number, type, id, title);

  @override
  String toString() =>
      'ChatCitation($marker ${type.wireName} "$title"${id == null ? '' : ' #$id'})';
}

/// Events of [AiChatService.send], in order: one [ChatStarted], any number
/// of [ChatTextDelta]s, one [ChatCompleted]. Errors arrive as stream errors.
sealed class ChatDelta {
  const ChatDelta();
}

/// Sent once the request is about to go out: the model in use and how each
/// context source was numbered / budgeted (show notices for
/// [ChatSourceStatus.omitted] / [ChatSourceStatus.unreadable]).
final class ChatStarted extends ChatDelta {
  const ChatStarted({required this.selection, required this.sources});

  final AiSelection selection;
  final List<ChatSourceRef> sources;
}

/// A piece of answer text: append it to the text so far. Markers may be
/// split across deltas; re-run [ChatCitations.parse] on the accumulated
/// text for live chips.
final class ChatTextDelta extends ChatDelta {
  const ChatTextDelta(this.text);
  final String text;

  @override
  String toString() => 'ChatTextDelta(${text.length} chars)';
}

/// The final answer.
final class ChatCompleted extends ChatDelta {
  const ChatCompleted(this.result);
  final ChatResult result;
}

/// A complete assistant answer.
@immutable
class ChatResult {
  const ChatResult({
    required this.text,
    required this.citations,
    required this.sources,
    required this.selection,
    this.truncated = false,
    this.streamed = true,
    this.droppedHistoryTurns = 0,
  });

  /// Markdown with `[S#]` markers (render them as chips; see
  /// [ChatCitations.strip] for plain text).
  final String text;

  /// Cited sources, in order of first appearance; only citable sources
  /// (numbers outside the list or of omitted/unreadable sources are
  /// ignored).
  final List<ChatCitation> citations;
  final List<ChatSourceRef> sources;
  final AiSelection selection;

  /// The answer hit the output-token limit (show "answer cut off").
  final bool truncated;

  /// False when the provider did not stream (endpoint fallback).
  final bool streamed;

  /// Oldest history turns left out to fit the history budget.
  final int droppedHistoryTurns;
}

/// Multi-turn chat grounded in user-selected sources, with token streaming
/// and `[S#]` citations.
///
/// Errors (stream errors): `AiException` (missingApiKey, invalidApiKey,
/// rateLimited, unsupported (model can't chat), provider (refusal, safety
/// block, empty answer, 5xx)), `ValidationException` (empty message, files
/// too large in total), `NetworkException` (offline, timeout, connection
/// lost mid-answer).
abstract interface class AiChatService {
  /// Answers [userMessage] given the earlier [history] (oldest first, as
  /// shown; the new message is NOT part of it) and the [context] sources.
  ///
  /// [context] order is the priority order: sources are numbered `S1, S2,
  /// ...` in that order (keep it stable within a chat so earlier citations
  /// stay valid) and, when the text budget is exceeded, earlier sources are
  /// kept whole first while later ones are shortened or omitted. Put the
  /// note/attachment the user is looking at first.
  ///
  /// Cancel the stream subscription to stop generating: the HTTP request is
  /// aborted and nothing more is emitted.
  Stream<ChatDelta> send({
    required List<ChatTurn> history,
    required String userMessage,
    required List<AiSource> context,

    /// Answer language; null = the user's message language.
    String? language,
    LlmProviderId? providerId,
    String? model,
  });
}

/// `[S#]` citation markers.
abstract final class ChatCitations {
  /// Matches one bracketed marker group: `[S1]`, `[S1, S3]`, `[S1; S2]`,
  /// `[S2-S4]` / `[S2–4]` (ranges, at most 20 numbers).
  static final pattern = RegExp(
    r'\[\s*(S\s?\d+(?:\s*[-–]\s*S?\s?\d+)?(?:\s*[,;]\s*S?\s?\d+(?:\s*[-–]\s*S?\s?\d+)?)*)\s*\]',
    caseSensitive: false,
  );

  static final _item = RegExp(
    r'S?\s?(\d+)(?:\s*[-–]\s*S?\s?(\d+))?',
    caseSensitive: false,
  );

  /// Source numbers cited in [text], in order of first appearance.
  static List<int> numbersIn(String text) {
    final seen = <int>{};
    for (final m in pattern.allMatches(text)) {
      for (final item in _item.allMatches(m.group(1)!)) {
        final from = int.parse(item.group(1)!);
        final toRaw = item.group(2);
        final to = toRaw == null ? from : int.parse(toRaw);
        if (to < from || to - from > 20) {
          seen.add(from);
          continue;
        }
        for (var n = from; n <= to; n++) {
          seen.add(n);
        }
      }
    }
    return seen.toList();
  }

  /// Citations for the markers in [text] that point at citable [sources].
  static List<ChatCitation> parse(String text, List<ChatSourceRef> sources) {
    final byNumber = {for (final s in sources) s.number: s};
    return [
      for (final n in numbersIn(text))
        if (byNumber[n] case final s? when s.isCitable) s.toCitation(),
    ];
  }

  /// [text] without markers (and without the space before them).
  static String strip(String text) => text.replaceAll(
    RegExp(r'[ \t]*' + pattern.pattern, caseSensitive: false),
    '',
  );
}
