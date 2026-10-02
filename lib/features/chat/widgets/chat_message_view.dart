import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../ai/ai_chat_service.dart' as ai;
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../data/models/chat.dart';
import '../application/chat_format.dart';

/// One chat message in a minimal style: user messages as a quiet bubble on
/// the right, assistant answers as full-width Markdown with citation chips
/// and small actions (copy, retry).
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    this.streamingText,
    this.streamingCitations = const [],
    this.onRetry,
    this.onOpenCitation,
  });

  final ChatMessage message;

  /// Live text while this answer is being streamed (null otherwise).
  final String? streamingText;
  final List<ChatCitation> streamingCitations;

  /// Set on the last answer: regenerate it.
  final VoidCallback? onRetry;
  final ValueChanged<ChatCitation>? onOpenCitation;

  bool get _streaming => streamingText != null;

  @override
  Widget build(BuildContext context) {
    return message.role == ChatRole.user
        ? _UserBubble(message: message)
        : _assistant(context);
  }

  Widget _assistant(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final parsed = _streaming
        ? (text: streamingText!, stopped: false, cutOff: false)
        : parseAssistantContent(message.content);
    final citations = _streaming ? streamingCitations : message.citations;
    final byNumber = citationsByNumber(parsed.text, citations);
    final chips = <int, ChatCitation>{};
    for (final n in ai.ChatCitations.numbersIn(parsed.text)) {
      if (byNumber[n] case final c?) chips[n] = c;
    }
    // Citations stored without a marker in the text still get a chip.
    for (final e in byNumber.entries) {
      chips.putIfAbsent(e.key, () => e.value);
    }
    final uniqueChips = <String, MapEntry<int, ChatCitation>>{};
    for (final e in chips.entries) {
      uniqueChips.putIfAbsent('${e.value.type}/${e.value.id}', () => e);
    }

    void copy() {
      Clipboard.setData(
        ClipboardData(text: ai.ChatCitations.strip(parsed.text).trim()),
      ).ignore();
      showAppSnackBar(context, 'Copied');
    }

    return Padding(
      key: Key('chat-message-${message.id}'),
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_streaming && parsed.text.isEmpty)
            Text(
              'Thinking…',
              key: const Key('chat-thinking'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.mutedText,
              ),
            )
          else
            ChatMarkdown(
              data: linkifyCitations(parsed.text, byNumber.keys.toSet()),
              selectable: !_streaming,
              onTapCitation: (n) {
                final c = byNumber[n];
                if (c != null) onOpenCitation?.call(c);
              },
            ),
          if (uniqueChips.isNotEmpty) ...[
            Gaps.h8,
            Wrap(
              spacing: Insets.xs,
              runSpacing: Insets.xs,
              children: [
                for (final e in uniqueChips.values)
                  CitationChip(
                    number: e.key,
                    citation: e.value,
                    onTap: onOpenCitation == null
                        ? null
                        : () => onOpenCitation!(e.value),
                  ),
              ],
            ),
          ],
          if (!_streaming) ...[
            Gaps.h4,
            Row(
              children: [
                if (parsed.stopped)
                  const _StatusLabel(
                    key: Key('chat-stopped'),
                    icon: Icons.stop_circle_outlined,
                    label: 'Stopped',
                  ),
                if (parsed.cutOff)
                  const _StatusLabel(
                    key: Key('chat-cut-off'),
                    icon: Icons.content_cut,
                    label: 'Answer cut off',
                  ),
                _SmallAction(
                  key: Key('chat-copy-${message.id}'),
                  tooltip: 'Copy',
                  icon: Icons.copy_outlined,
                  onPressed: copy,
                ),
                if (onRetry != null)
                  _SmallAction(
                    key: const Key('chat-retry'),
                    tooltip: 'Retry',
                    icon: Icons.refresh,
                    onPressed: onRetry!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      key: Key('chat-message-${message.id}'),
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.82),
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: message.content))
                    .ignore();
                showAppSnackBar(context, 'Copied');
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.hover,
                  borderRadius: Radii.lgAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.md + 2,
                    vertical: Insets.sm + 2,
                  ),
                  child: SelectableText(
                    message.content,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Insets.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.faintText),
          Gaps.w4,
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.faintText),
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    iconSize: 16,
    color: AppColors.of(context).mutedText,
    icon: Icon(icon),
  );
}

/// Source chip under an answer: `1  Title` with the source kind's icon.
class CitationChip extends StatelessWidget {
  const CitationChip({
    super.key,
    required this.number,
    required this.citation,
    this.onTap,
  });

  final int number;
  final ChatCitation citation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final title = citation.title.isEmpty ? 'Source $number' : citation.title;
    return Tooltip(
      message: 'Open $title',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('citation-chip-$number'),
          onTap: onTap,
          borderRadius: Radii.smAll,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.sm,
              vertical: Insets.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: Radii.smAll,
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$number',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Gaps.w4,
                Icon(
                  citationIcon(citation.type),
                  size: 14,
                  color: colors.mutedText,
                ),
                Gaps.w4,
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// GitHub-flavored Markdown for answers: code blocks, tables, lists;
/// `cite:n` links call [onTapCitation], other links are copied.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.onTapCitation,
  });

  final String data;
  final bool selectable;
  final ValueChanged<int>? onTapCitation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      height: 1.45,
    );
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium,
      code: mono?.copyWith(backgroundColor: colors.hover),
      codeblockDecoration: BoxDecoration(
        color: colors.hover,
        borderRadius: Radii.mdAll,
        border: Border.all(color: colors.hairline),
      ),
      codeblockPadding: const EdgeInsets.all(Insets.md),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.border, width: 3)),
      ),
      a: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
      tableBorder: TableBorder.all(color: colors.hairline),
    );
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: styleSheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) {
        final n = citationLinkNumber(href);
        if (n != null) {
          onTapCitation?.call(n);
          return;
        }
        if (href == null || href.isEmpty) return;
        Clipboard.setData(ClipboardData(text: href)).ignore();
        showAppSnackBar(context, 'Link copied: $href');
      },
    );
  }
}
