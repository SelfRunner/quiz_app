import 'package:flutter/material.dart';

import '../../../data/models/chat.dart';

/// Opens (or starts) an AI chat about a subject, note or attachment.
///
/// Cross-feature entry point: subject / note / file screens embed this; the
/// chat feature owns the implementation (AI gating included).
class ChatLauncherButton extends StatelessWidget {
  const ChatLauncherButton({
    super.key,
    required this.scopeType,
    this.scopeId,
    required this.title,
    this.compact = false,
  });

  final ChatScopeType scopeType;
  final String? scopeId;

  /// Name of the subject / note / file, used for the chat title.
  final String title;

  /// Icon-only form for app bars.
  final bool compact;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
