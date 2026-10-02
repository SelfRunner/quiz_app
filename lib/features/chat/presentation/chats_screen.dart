import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/sync_status_indicator.dart'
    show formatRelativeTime;
import '../../../data/data_providers.dart';
import '../../../data/models/chat.dart';
import '../application/chat_format.dart';
import '../application/chat_launch.dart';

/// Display name of a chat's scope (null while loading; "Source
/// unavailable" when it is gone).
final chatScopeTitleProvider = Provider.autoDispose
    .family<String?, ({ChatScopeType type, String? id})>((ref, scope) {
      final id = scope.id;
      if (scope.type == ChatScopeType.general || id == null) return 'General';
      final AsyncValue<String?> title = switch (scope.type) {
        ChatScopeType.subject =>
          ref.watch(subjectProvider(id)).whenData((s) => s?.title),
        ChatScopeType.note =>
          ref.watch(noteProvider(id)).whenData((n) => n?.title),
        ChatScopeType.attachment =>
          ref.watch(attachmentProvider(id)).whenData((a) => a?.name),
        ChatScopeType.general => const AsyncData('General'),
      };
      if (!title.hasValue) return title.hasError ? 'Source unavailable' : null;
      return title.value ?? 'Source unavailable';
    });

/// Every chat, grouped by what it is about (most recent first), with the
/// last message, a title search and delete.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _delete(Chat chat) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete "${chat.title.isEmpty ? 'Untitled chat' : chat.title}"?',
      message: 'All of its messages are deleted on every device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(chatRepositoryProvider).delete(chat.id);
      if (mounted) showAppSnackBar(context, 'Chat deleted');
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  void _newGeneralChat() => openScopedChat(
    context,
    ref,
    scopeType: ChatScopeType.general,
    title: 'New chat',
    fresh: true,
  );

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    return ResponsiveScaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Insets.sm),
            child: AiGate(
              onReady: _newGeneralChat,
              child: FilledButton.tonalIcon(
                key: const Key('chats-new'),
                onPressed: _newGeneralChat,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New chat'),
              ),
            ),
          ),
        ],
      ),
      maxWidth: ContentWidth.readable,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('chats-search'),
            controller: _search,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search chats by title',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
          AsyncValueView<List<Chat>>(
            value: chats,
            loading: const LoadingSkeleton(),
            onRetry: () => ref.invalidate(chatsProvider),
            data: (all) {
              if (all.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: Insets.xxl),
                  child: EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No chats yet',
                    message:
                        'Open a subject, note or file and tap Ask AI to chat '
                        'about it. Chats are private to you.',
                  ),
                );
              }
              final visible = _query.isEmpty
                  ? all
                  : all
                        .where((c) => c.title.toLowerCase().contains(_query))
                        .toList();
              if (visible.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: Insets.xl),
                  child: EmptyState(
                    compact: true,
                    icon: Icons.search_off,
                    title: 'No chats match "${_search.text.trim()}"',
                  ),
                );
              }
              // Groups in order of their most recent chat.
              final groups = <String, List<Chat>>{};
              for (final c in visible) {
                groups
                    .putIfAbsent('${c.scopeType.name}/${c.scopeId}', () => [])
                    .add(c);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in groups.values)
                    _ChatGroup(chats: group, onDelete: _delete),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChatGroup extends ConsumerWidget {
  const _ChatGroup({required this.chats, required this.onDelete});

  final List<Chat> chats;
  final ValueChanged<Chat> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = chats.first;
    final scope = (type: first.scopeType, id: first.scopeId);
    final title = ref.watch(chatScopeTitleProvider(scope));
    final colors = AppColors.of(context);
    final canOpenScope =
        first.scopeType == ChatScopeType.subject ||
        first.scopeType == ChatScopeType.note;
    return Column(
      key: Key('chat-group-${first.scopeType.name}-${first.scopeId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title ?? '…',
          count: chats.length,
          subtitle: scopeKindLabel(first.scopeType),
          trailing: canOpenScope && title != 'Source unavailable'
              ? IconButton(
                  tooltip:
                      'Open ${scopeKindLabel(first.scopeType).toLowerCase()}',
                  icon: Icon(
                    scopeIcon(first.scopeType),
                    size: 18,
                    color: colors.mutedText,
                  ),
                  onPressed: () => context.push(
                    first.scopeType == ChatScopeType.subject
                        ? AppRoutes.subject(first.scopeId!)
                        : AppRoutes.note(first.scopeId!),
                  ),
                )
              : null,
        ),
        for (final chat in chats) _ChatRow(chat: chat, onDelete: onDelete),
      ],
    );
  }
}

class _ChatRow extends ConsumerWidget {
  const _ChatRow({required this.chat, required this.onDelete});

  final Chat chat;
  final ValueChanged<Chat> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatMessagesProvider(chat.id)).value;
    final last = messages == null || messages.isEmpty ? null : messages.last;
    final colors = AppColors.of(context);
    final snippet = last == null
        ? 'No messages yet'
        : '${last.role == ChatRole.user ? 'You: ' : ''}${messageSnippet(last)}';
    return ListRowTile(
      key: Key('chat-row-${chat.id}'),
      leading: Icon(
        Icons.chat_bubble_outline,
        size: 18,
        color: colors.mutedText,
      ),
      title: Text(
        chat.title.isEmpty ? 'Untitled chat' : chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(snippet, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatRelativeTime(chat.updatedAt),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.faintText),
      ),
      onTap: () => context.push(AppRoutes.chat(chat.id)),
      actions: [
        IconButton(
          key: Key('chat-delete-${chat.id}'),
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.delete_outline, color: colors.mutedText),
          onPressed: () => onDelete(chat),
        ),
      ],
    );
  }
}
