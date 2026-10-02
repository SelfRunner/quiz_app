import 'package:flutter/material.dart';

import '../../../ai/ai_chat_service.dart' as ai;
import '../../../data/models/chat.dart';

/// Stored citation types (`chat_messages.citations[].type`).
abstract final class CitationTypes {
  static const subject = 'subject';
  static const note = 'note';
  static const attachment = 'attachment';
}

/// Appended to an assistant message the user stopped (or that was
/// interrupted by an error) so the partial answer is marked when read back.
const String kStoppedSuffix = '\n\n*(stopped)*';

/// Appended when the answer hit the model's output limit.
const String kCutOffSuffix = '\n\n*(answer cut off)*';

/// An assistant message's stored content split into its answer text and
/// the status markers this feature appends.
typedef AssistantContent = ({String text, bool stopped, bool cutOff});

AssistantContent parseAssistantContent(String content) {
  if (content.endsWith(kStoppedSuffix)) {
    return (
      text: content.substring(0, content.length - kStoppedSuffix.length),
      stopped: true,
      cutOff: false,
    );
  }
  if (content.endsWith(kCutOffSuffix)) {
    return (
      text: content.substring(0, content.length - kCutOffSuffix.length),
      stopped: false,
      cutOff: true,
    );
  }
  return (text: content, stopped: false, cutOff: false);
}

/// Message text without status markers (for history and copying).
String messageBody(ChatMessage m) => m.role == ChatRole.assistant
    ? parseAssistantContent(m.content).text
    : m.content;

/// Converts an AI-layer citation into the stored form. The `[S#]` marker
/// is kept in `snippet` so the answer's markers can be mapped back to the
/// stored citations when the chat is read again. Null when the source had
/// no id.
ChatCitation? storedCitation(ai.ChatCitation c, Map<String, String> typeById) {
  final id = c.id;
  if (id == null || id.isEmpty) return null;
  return ChatCitation(
    type:
        typeById[id] ??
        switch (c.type) {
          ai.AiSourceType.note => CitationTypes.note,
          ai.AiSourceType.file => CitationTypes.attachment,
          _ => c.type.wireName,
        },
    id: id,
    title: c.title,
    snippet: c.marker,
  );
}

List<ChatCitation> storedCitations(
  Iterable<ai.ChatCitation> citations,
  Map<String, String> typeById,
) => [for (final c in citations) ?storedCitation(c, typeById)];

final _markerNumber = RegExp(r'^S(\d+)$');

/// The `[S#]` number of a stored citation (null when unknown).
int? citationNumber(ChatCitation c) {
  final m = _markerNumber.firstMatch(c.snippet ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}

/// Citations by `[S#]` number. Citations stored without a marker are
/// numbered by order of first appearance in [text] as a fallback.
Map<int, ChatCitation> citationsByNumber(
  String text,
  List<ChatCitation> citations,
) {
  final result = <int, ChatCitation>{};
  final unnumbered = <ChatCitation>[];
  for (final c in citations) {
    final n = citationNumber(c);
    if (n == null) {
      unnumbered.add(c);
    } else {
      result[n] = c;
    }
  }
  if (unnumbered.isNotEmpty) {
    final free = ai.ChatCitations.numbersIn(text)
        .where((n) => !result.containsKey(n))
        .iterator;
    for (final c in unnumbered) {
      if (!free.moveNext()) break;
      result[free.current] = c;
    }
  }
  return result;
}

/// Scheme of the Markdown links that [linkifyCitations] produces.
const String kCitationScheme = 'cite';

/// Replaces `[S#]` markers outside code blocks with Markdown links
/// `[[n]](cite:n)` for the numbers in [known]; markers of unknown sources
/// are removed.
String linkifyCitations(String text, Set<int> known) {
  final out = StringBuffer();
  var inFence = false;
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      out.write(line);
    } else if (inFence) {
      out.write(line);
    } else {
      out.write(
        line.replaceAllMapped(ai.ChatCitations.pattern, (m) {
          final numbers = ai.ChatCitations.numbersIn(m.group(0)!);
          return numbers
              .where(known.contains)
              .map((n) => '[\\[$n\\]]($kCitationScheme:$n)')
              .join();
        }),
      );
    }
    if (i < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

/// Source number of a `cite:n` link, else null.
int? citationLinkNumber(String? href) {
  if (href == null || !href.startsWith('$kCitationScheme:')) return null;
  return int.tryParse(href.substring(kCitationScheme.length + 1));
}

IconData citationIcon(String type) => switch (type) {
  CitationTypes.note => Icons.description_outlined,
  CitationTypes.attachment => Icons.attach_file,
  CitationTypes.subject => Icons.folder_outlined,
  _ => Icons.link,
};

IconData scopeIcon(ChatScopeType type) => switch (type) {
  ChatScopeType.subject => Icons.folder_outlined,
  ChatScopeType.note => Icons.description_outlined,
  ChatScopeType.attachment => Icons.attach_file,
  ChatScopeType.general => Icons.chat_bubble_outline,
};

String scopeKindLabel(ChatScopeType type) => switch (type) {
  ChatScopeType.subject => 'Subject',
  ChatScopeType.note => 'Note',
  ChatScopeType.attachment => 'File',
  ChatScopeType.general => 'General',
};

/// One-line plain-text preview of a message.
String messageSnippet(ChatMessage m, {int maxChars = 120}) {
  final text = ai.ChatCitations.strip(messageBody(m))
      .replaceAll(RegExp(r'```[^\n]*'), ' ')
      .replaceAll(RegExp(r'[#>*_`~|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length <= maxChars
      ? text
      : '${text.substring(0, maxChars).trimRight()}…';
}
