import 'ai_chat_service.dart';
import 'llm_chat.dart';

/// Context-window budget for chat (characters, ~4 per token).
class ChatBudget {
  const ChatBudget({
    this.maxContextChars = 60000,
    this.minExcerptChars = 2000,
    this.maxHistoryChars = 24000,
  });

  /// Total text of all context sources (notes, pasted text, text files,
  /// transcripts). Attachments sent as files don't count.
  final int maxContextChars;

  /// Every text source gets at least this much (or its whole text if
  /// shorter) before earlier sources get more, so later sources are
  /// excerpted instead of dropped while the budget allows.
  final int minExcerptChars;

  /// Earlier turns kept (newest first); older turns are dropped.
  final int maxHistoryChars;
}

/// Splits [budget] among texts of [lengths] in priority order (index 0
/// first). Returns the characters allowed per text:
///
/// 1. Everything fits -> every text whole.
/// 2. Otherwise each text, in order, gets `min(length, floor)` while that
///    fits (a text whose floor doesn't fit gets 0 = omitted; later, shorter
///    ones may still fit).
/// 3. What is left goes to the texts in priority order, so the first ones
///    are kept whole and later ones become excerpts.
List<int> allocateTextBudget(List<int> lengths, int budget, int floor) {
  final total = lengths.fold<int>(0, (a, b) => a + b);
  if (total <= budget) return [...lengths];
  final alloc = List<int>.filled(lengths.length, 0);
  var remaining = budget;
  for (var i = 0; i < lengths.length; i++) {
    final f = lengths[i] < floor ? lengths[i] : floor;
    if (f > 0 && f <= remaining) {
      alloc[i] = f;
      remaining -= f;
    }
  }
  for (var i = 0; i < lengths.length && remaining > 0; i++) {
    if (alloc[i] == 0) continue;
    final want = lengths[i] - alloc[i];
    final extra = want < remaining ? want : remaining;
    alloc[i] += extra;
    remaining -= extra;
  }
  return alloc;
}

final _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$', multiLine: true);

/// Cuts [text] to about [max] characters: keeps the beginning (80%) and the
/// end (20%), cut at line/word boundaries, and replaces the middle with a
/// note that lists the Markdown headings it contained (a cheap outline of
/// what was left out).
String excerptText(String text, int max) {
  if (text.length <= max) return text;
  if (max <= 0) return '';
  var headEnd = _boundaryBefore(text, (max * 0.8).floor());
  if (headEnd <= 0) headEnd = (max * 0.8).floor();
  var tailStart = _boundaryAfter(text, text.length - (max - headEnd));
  if (tailStart < headEnd) tailStart = headEnd;
  final middle = text.substring(headEnd, tailStart);
  final headings = [
    for (final m in _heading.allMatches(middle)) m.group(1)!.trim(),
  ].where((h) => h.isNotEmpty).toList();
  final shown = headings.take(15).join('; ');
  final more = headings.length > 15 ? '; …' : '';
  final outline = headings.isEmpty ? '' : ' Omitted sections: $shown$more.';
  return '${text.substring(0, headEnd).trimRight()}\n\n'
      '[… ${middle.length} characters omitted to fit the context.$outline …]'
      '\n\n${text.substring(tailStart).trimLeft()}';
}

/// Last line break (or space) at or before [i], if reasonably close.
int _boundaryBefore(String text, int i) {
  if (i >= text.length) return text.length;
  final nl = text.lastIndexOf('\n', i);
  if (nl > 0 && i - nl < 400) return nl;
  final sp = text.lastIndexOf(' ', i);
  if (sp > 0 && i - sp < 80) return sp;
  return i;
}

/// First line break (or space) at or after [i], if reasonably close.
int _boundaryAfter(String text, int i) {
  if (i <= 0) return 0;
  if (i >= text.length) return text.length;
  final nl = text.indexOf('\n', i);
  if (nl >= 0 && nl - i < 400) return nl + 1;
  final sp = text.indexOf(' ', i);
  if (sp >= 0 && sp - i < 80) return sp + 1;
  return i;
}

/// The newest [history] turns that fit in [maxChars] (oldest first) and how
/// many older turns were dropped. A single newest turn longer than the
/// budget is cut to its last [maxChars] characters.
({List<LlmChatMessage> messages, int dropped}) fitHistory(
  List<ChatTurn> history,
  int maxChars,
) {
  final kept = <LlmChatMessage>[];
  var used = 0;
  var i = history.length - 1;
  for (; i >= 0; i--) {
    final t = history[i];
    final text = t.text.trim();
    if (text.isEmpty) continue;
    final role = t.role == ChatRole.user
        ? LlmChatRole.user
        : LlmChatRole.assistant;
    if (used + text.length <= maxChars) {
      kept.add(LlmChatMessage(role, text));
      used += text.length;
      continue;
    }
    if (kept.isEmpty && maxChars > 0) {
      kept.add(
        LlmChatMessage(role, '…${text.substring(text.length - maxChars)}'),
      );
      i--;
    }
    break;
  }
  var dropped = 0;
  for (var j = i; j >= 0; j--) {
    if (history[j].text.trim().isNotEmpty) dropped++;
  }
  return (messages: kept.reversed.toList(), dropped: dropped);
}

/// Prompt text for chat.
abstract final class ChatPrompts {
  static String system({String? language, bool hasSources = true}) {
    final lang = (language == null || language.trim().isEmpty)
        ? 'Answer in the language of the user\'s latest message.'
        : 'Answer in this language: ${language.trim()}.';
    if (!hasSources) {
      return '''
You are a friendly, precise study assistant inside a notes and quiz app.
- $lang
- Use GitHub-flavored Markdown (short paragraphs, bullet lists, tables when they help; LaTeX math between \$...\$ or \$\$...\$\$).
- Be accurate and say so when you are unsure. Keep answers focused on what was asked.''';
    }
    return '''
You are a friendly, precise study assistant inside a notes and quiz app. The user's study material is provided as numbered sources [S1], [S2], ... in their latest message (files may be attached; each attachment is preceded by its source label).

Rules:
- Ground your answer in the sources. After each sentence or bullet that uses a source, cite it with its marker, e.g. "Mitochondria produce ATP [S1]." Cite several as [S1][S3]. Only cite sources you actually used, and never invent source numbers.
- Never cite sources marked as omitted or unavailable; you have not seen their content.
- If the sources don't contain the answer, say so clearly. You may then add general knowledge, but mark it as not from the sources and do not cite anything for it.
- Don't quote long passages; explain in your own words. Keep numbers, names and definitions exact.
- $lang
- Use GitHub-flavored Markdown (short paragraphs, bullet lists, tables when they help; LaTeX math between \$...\$ or \$\$...\$\$). Don't add a "Sources" list at the end; the app shows citations.''';
  }

  static String _quoted(String s) => '"${s.replaceAll('"', "'")}"';

  /// `[S1] note "Title"`.
  static String label(ChatSourceRef s) =>
      '[${s.marker}] ${s.type.wireName} ${_quoted(s.title)}';

  /// The final user message: numbered sources ([sourcesBlock]), then the
  /// question.
  static String userMessage({
    required String message,
    required String sourcesBlock,
  }) {
    if (sourcesBlock.isEmpty) return message.trim();
    return '$sourcesBlock\n\nMy question:\n${message.trim()}';
  }

  /// `Sources (cite them as [S1], ...)` followed by every source: text in
  /// `<source id="S1">`, attachments by label, omitted / unavailable ones
  /// with a "do not cite" note. Empty when [sources] is empty.
  static String sourcesBlock({
    required List<ChatSourceRef> sources,
    required Map<int, String> texts,
    required Set<int> attached,
  }) {
    if (sources.isEmpty) return '';
    final b = StringBuffer()
      ..writeln('Sources (cite them as [S1], [S2], ...):');
    for (final s in sources) {
      b.writeln();
      final text = texts[s.number];
      switch (s.status) {
        case ChatSourceStatus.full || ChatSourceStatus.excerpt
            when text != null:
          b
            ..writeln(
              '${label(s)}'
              '${s.status == ChatSourceStatus.excerpt ? ' (excerpt: the source is longer than the context allows)' : ''}',
            )
            ..writeln('<source id="${s.marker}">')
            ..writeln(text)
            ..writeln('</source>');
        case ChatSourceStatus.full || ChatSourceStatus.excerpt
            when attached.contains(s.number):
          b.writeln('${label(s)}: attached to this message.');
        case ChatSourceStatus.omitted:
          b.writeln(
            '${label(s)}: omitted (too much material); content not '
            'available, do not cite it.',
          );
        default:
          b.writeln(
            '${label(s)}: unavailable${s.note == null ? '' : ' (${s.note})'}; '
            'do not cite it.',
          );
      }
    }
    return b.toString().trimRight();
  }
}
