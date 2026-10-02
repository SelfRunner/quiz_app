import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/design_system.dart';

/// Whether Enter sends (desktop / web keyboards); on phones Enter inserts a
/// newline and the send button sends.
bool enterSends() =>
    kIsWeb ||
    switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };

/// Multi-line message field with a send / stop button. Enter sends and
/// Shift+Enter adds a newline on desktop.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.enabled,
    required this.streaming,
    required this.onSend,
    required this.onStop,
    this.hint = 'Ask a question…',
    this.disabledHint = 'Set up AI to chat',
  });

  /// False when AI isn't ready (or the chat can't take messages).
  final bool enabled;

  /// An answer is being generated: shows the stop button.
  final bool streaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final String hint;
  final String disabledHint;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend =>
      widget.enabled && !widget.streaming && _controller.text.trim().isNotEmpty;

  void _send() {
    if (!_canSend) return;
    final text = _controller.text.trim();
    _controller.clear();
    widget.onSend(text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (!enterSends() || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.md,
          Insets.xs,
          Insets.xs,
          Insets.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('chat-input'),
                controller: _controller,
                focusNode: _focus,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: widget.enabled ? widget.hint : widget.disabledHint,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: Insets.sm + 2,
                  ),
                ),
              ),
            ),
            Gaps.w4,
            if (widget.streaming)
              IconButton.filledTonal(
                key: const Key('chat-stop'),
                tooltip: 'Stop',
                onPressed: widget.onStop,
                icon: const Icon(Icons.stop_rounded),
              )
            else
              IconButton.filled(
                key: const Key('chat-send'),
                tooltip: enterSends() ? 'Send (Enter)' : 'Send',
                onPressed: _canSend ? _send : null,
                icon: const Icon(Icons.arrow_upward),
              ),
          ],
        ),
      ),
    );
  }
}
