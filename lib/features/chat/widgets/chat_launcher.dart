import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/sync_status_indicator.dart'
    show formatRelativeTime;
import '../../../data/data_providers.dart';
import '../../../data/models/chat.dart';
import '../application/chat_launch.dart';

/// Opens (or starts) an AI chat about a subject, note or attachment.
///
/// Tap: the most recent chat about the scope, or a new one. Long-press,
/// right-click or the menu arrow: "New chat", earlier chats about the scope
/// and "All chats". Locked (AI gate) until AI is set up.
class ChatLauncherButton extends ConsumerWidget {
  const ChatLauncherButton({
    super.key,
    required this.scopeType,
    this.scopeId,
    required this.title,
    this.compact = false,
    this.tooltip,
  });

  final ChatScopeType scopeType;
  final String? scopeId;

  /// Name of the subject / note / file, used for the chat title.
  final String title;

  /// Icon-only form for app bars.
  final bool compact;

  /// Overrides the default tooltip / label ("Ask AI").
  final String? tooltip;

  String get _label => tooltip ?? 'Ask AI';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open({bool fresh = false}) => openScopedChat(
      context,
      ref,
      scopeType: scopeType,
      scopeId: scopeId,
      title: title,
      fresh: fresh,
    );
    final keySuffix = scopeId ?? scopeType.name;

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const Key('chat-launcher-new'),
          leadingIcon: const Icon(Icons.add, size: 18),
          onPressed: () => open(fresh: true),
          child: const Text('New chat'),
        ),
        _PreviousChats(scopeType: scopeType, scopeId: scopeId),
        MenuItemButton(
          key: const Key('chat-launcher-all'),
          leadingIcon: const Icon(Icons.forum_outlined, size: 18),
          onPressed: () => context.push(AppRoutes.chats),
          child: const Text('All chats'),
        ),
      ],
      builder: (context, controller, _) {
        void toggleMenu() =>
            controller.isOpen ? controller.close() : controller.open();
        final Widget button;
        if (compact) {
          // The tooltip sits outside the long-press detector (an inner
          // tooltip would claim the long press) and only shows on hover.
          button = Tooltip(
            message: _label,
            triggerMode: TooltipTriggerMode.manual,
            child: GestureDetector(
              onLongPress: toggleMenu,
              onSecondaryTap: toggleMenu,
              child: IconButton(
                key: Key('chat-launcher-$keySuffix'),
                icon: Icon(Icons.chat_bubble_outline, semanticLabel: _label),
                onPressed: open,
              ),
            ),
          );
        } else {
          button = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: toggleMenu,
                onSecondaryTap: toggleMenu,
                child: OutlinedButton.icon(
                  key: Key('chat-launcher-$keySuffix'),
                  onPressed: open,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(_label),
                ),
              ),
              IconButton(
                key: Key('chat-launcher-menu-$keySuffix'),
                tooltip: 'Chats',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.expand_more),
                onPressed: toggleMenu,
              ),
            ],
          );
        }
        return AiGate(onReady: open, child: button);
      },
    );
  }
}

/// Earlier chats about the scope (only built while the menu is open).
class _PreviousChats extends ConsumerWidget {
  const _PreviousChats({required this.scopeType, this.scopeId});

  final ChatScopeType scopeType;
  final String? scopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats =
        ref
            .watch(
              chatsByScopeProvider((
                type: scopeType,
                id: scopeType == ChatScopeType.general ? null : scopeId,
              )),
            )
            .value ??
        const <Chat>[];
    if (chats.isEmpty) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: Insets.sm),
        for (final chat in chats.take(8))
          MenuItemButton(
            key: Key('chat-launcher-item-${chat.id}'),
            leadingIcon: const Icon(Icons.chat_bubble_outline, size: 18),
            trailingIcon: Text(
              formatRelativeTime(chat.updatedAt),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.faintText),
            ),
            onPressed: () => context.push(AppRoutes.chat(chat.id)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                chat.title.isEmpty ? 'Untitled chat' : chat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        const Divider(height: Insets.sm),
      ],
    );
  }
}
