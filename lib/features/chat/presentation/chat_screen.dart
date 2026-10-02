import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_capabilities.dart';
import '../../../ai/ai_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../ai_generate/widgets/ai_error_card.dart';
import '../../subjects/presentation/widgets/subject_files_tab.dart'
    show openAttachment;
import '../application/chat_format.dart';
import '../application/chat_launch.dart';
import '../application/chat_session.dart';
import '../application/chat_sources.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_context_panel.dart';
import '../widgets/chat_message_view.dart';

/// One AI chat: streamed answers with source citations, a context panel
/// (scope + included sources) and a composer. History is read from the
/// local cache, so it works offline.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider(chatId));
    final value = chat.value;
    if (value != null) return _ChatView(key: ValueKey(chatId), chat: value);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncValueView<Chat?>(
        value: chat,
        loading: const ContentContainer(child: LoadingSkeleton()),
        onRetry: () => ref.invalidate(chatProvider(chatId)),
        data: (_) => const NotFoundView(what: 'Chat'),
      ),
    );
  }
}

class _ChatView extends ConsumerStatefulWidget {
  const _ChatView({super.key, required this.chat});

  final Chat chat;

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  late final ChatSession _session;
  final Map<String, Uint8List> _bytes = {};
  ChatSourceSelection? _selection;
  bool _panelOpen = true;

  Chat get chat => widget.chat;

  ChatScopeKey get _scopeKey => (type: chat.scopeType, id: chat.scopeId);

  @override
  void initState() {
    super.initState();
    _session = ChatSession(
      chatId: chat.id,
      repository: ref.read(chatRepositoryProvider),
      service: ref.read(aiChatServiceProvider),
      buildContext: _buildContext,
      selection: () {
        final r = ref.read(aiReadinessProvider).value;
        return (provider: r?.providerId, model: r?.model);
      },
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  AiCapabilities get _caps =>
      ref.read(aiReadinessProvider).value?.capabilities ??
      AiCapabilities.textOnly;

  ChatSourceSelection _effective(ChatScopeData scope, AiCapabilities caps) =>
      _selection ?? ChatSourceSelection.defaults(scope, caps);

  Future<ChatContextSources> _buildContext() async {
    final scope = ref.read(chatScopeDataProvider(_scopeKey)).value;
    if (scope == null || !scope.available) {
      return (sources: const <Never>[], typeById: const <String, String>{});
    }
    final caps = _caps;
    final repo = ref.read(attachmentRepositoryProvider);
    return buildChatContext(
      scope,
      _effective(scope, caps),
      caps,
      (a) async => _bytes[a.id] ??= await repo.getBytes(a),
    );
  }

  void _toggle(ChatScopeData scope, String id) {
    setState(() => _selection = _effective(scope, _caps).toggle(id));
  }

  Future<void> _openCitation(ChatCitation c) async {
    switch (c.type) {
      case CitationTypes.note:
        await context.push(AppRoutes.note(c.id));
      case CitationTypes.subject:
        await context.push(AppRoutes.subject(c.id));
      case CitationTypes.attachment:
        final a = await ref.read(attachmentRepositoryProvider).getById(c.id);
        if (!mounted) return;
        if (a == null || a.isDeleted) {
          showAppSnackBar(context, '"${c.title}" is no longer available');
          return;
        }
        await openAttachment(context, ref, a);
      default:
        break;
    }
  }

  Future<void> _rename() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameChatDialog(initial: chat.title),
    );
    if (title == null || title == chat.title) return;
    try {
      await ref.read(chatRepositoryProvider).rename(chat.id, title);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, prefix: 'Could not rename');
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this chat?',
      message: 'All of its messages are deleted on every device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _session.stop();
    try {
      await ref.read(chatRepositoryProvider).delete(chat.id);
      if (!mounted) return;
      showAppSnackBar(context, 'Chat deleted');
      context.canPop() ? context.pop() : context.go(AppRoutes.chats);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _newChat(ChatScopeData? scope) async {
    try {
      final created = await createScopedChat(
        ref,
        scopeType: chat.scopeType,
        scopeId: chat.scopeId,
        title: scope?.title ?? chat.title,
      );
      if (mounted) context.pushReplacement(AppRoutes.chat(created.id));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, prefix: 'Could not start');
    }
  }

  void _showPanelSheet(ChatScopeData scope) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.7,
          child: ChatContextPanel(
            scope: scope,
            selection: _effective(scope, _caps),
            capabilities: _caps,
            lastSources: _session.lastSources,
            onToggle: (id) {
              _toggle(scope, id);
              setSheetState(() {});
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(aiReadinessProvider).value;
    final ready = readiness?.isConfigured ?? false;
    final caps = readiness?.capabilities ?? AiCapabilities.textOnly;
    final scope = ref.watch(chatScopeDataProvider(_scopeKey)).value;
    final messages = ref.watch(chatMessagesProvider(chat.id));
    final wide = Breakpoints.isExpanded(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    final panel = scope == null
        ? null
        : ChatContextPanel(
            scope: scope,
            selection: _effective(scope, caps),
            capabilities: caps,
            lastSources: _session.lastSources,
            onToggle: (id) => _toggle(scope, id),
          );

    final scopeLine = switch (chat.scopeType) {
      ChatScopeType.general => 'General chat',
      _ when scope == null => scopeKindLabel(chat.scopeType),
      _ => scope.title ?? 'Source unavailable',
    };

    final appBar = AppBar(
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chat.title.isEmpty ? 'Untitled chat' : chat.title,
            key: const Key('chat-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                scopeIcon(chat.scopeType),
                size: 13,
                color: colors.faintText,
              ),
              Gaps.w4,
              Flexible(
                child: Text(
                  scopeLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (scope != null)
          IconButton(
            key: const Key('chat-sources'),
            tooltip: 'Sources',
            isSelected: wide && _panelOpen,
            icon: const Icon(Icons.library_books_outlined),
            onPressed: () => wide
                ? setState(() => _panelOpen = !_panelOpen)
                : _showPanelSheet(scope),
          ),
        AiGate(
          onReady: () => _newChat(scope),
          child: IconButton(
            key: const Key('chat-new'),
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => _newChat(scope),
          ),
        ),
        PopupMenuButton<String>(
          key: const Key('chat-menu'),
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz),
          onSelected: (v) => switch (v) {
            'rename' => _rename(),
            'delete' => _delete(),
            _ => context.push(AppRoutes.chats),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'rename',
              child: ListTile(
                leading: Icon(Icons.drive_file_rename_outline),
                title: Text('Rename'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'all',
              child: ListTile(
                leading: Icon(Icons.forum_outlined),
                title: Text('All chats'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete chat'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        Gaps.w4,
      ],
    );

    final items = messages.value ?? const <ChatMessage>[];
    final lastAssistant = items.lastIndexWhere(
      (m) => m.role == ChatRole.assistant,
    );
    final canRetry =
        ready && !_session.busy && lastAssistant == items.length - 1;

    final Widget list;
    if (messages.isLoading && !messages.hasValue) {
      list = const ContentContainer(child: LoadingSkeleton());
    } else if (items.isEmpty) {
      list = _EmptyChat(
        scopeTitle: chat.scopeType == ChatScopeType.general
            ? null
            : scope?.title,
        enabled: ready && !_session.busy,
        onSuggestion: _session.send,
      );
    } else {
      list = ListView.builder(
        key: const Key('chat-messages'),
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: Insets.lg),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final index = items.length - 1 - i;
          final m = items[index];
          final streaming = m.id == _session.streamingMessageId;
          return ContentContainer(
            child: ChatMessageView(
              key: ValueKey(m.id),
              message: m,
              streamingText: streaming ? _session.streamingText : null,
              streamingCitations: streaming
                  ? _session.streamingCitations
                  : const [],
              onOpenCitation: _openCitation,
              onRetry: canRetry && index == lastAssistant
                  ? _session.retry
                  : null,
            ),
          );
        },
      );
    }

    final error = _session.error;
    final bottom = ContentContainer(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Insets.md, top: Insets.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!ready) ...[
              InfoBanner(
                key: const Key('chat-ai-not-ready'),
                icon: Icons.lock_outline,
                message:
                    readiness?.reason ??
                    'Set up an AI provider in Settings to ask questions. '
                        'You can still read this chat.',
                action: TextButton(
                  onPressed: () =>
                      showAiSetupSheet(context, reason: readiness?.reason),
                  child: const Text('Set up AI'),
                ),
              ),
              Gaps.h8,
            ],
            if (error != null) ...[
              AiErrorCard(
                error: error,
                onRetry: ready ? _session.retry : null,
                onOpenSettings: () => context.push(AppRoutes.settings),
                onDismiss: _session.clearError,
              ),
              Gaps.h8,
            ],
            if (items.isNotEmpty &&
                items.last.role == ChatRole.user &&
                !_session.busy &&
                error == null &&
                ready) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('chat-answer-again'),
                  onPressed: _session.retry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Get an answer'),
                ),
              ),
              Gaps.h4,
            ],
            ChatComposer(
              enabled: ready,
              streaming: _session.streamingMessageId != null,
              onSend: _session.send,
              onStop: _session.stop,
              hint: scope?.title == null
                  ? 'Ask a question…'
                  : 'Ask about ${scope!.title}…',
            ),
          ],
        ),
      ),
    );

    final conversation = Column(
      children: [
        Expanded(child: list),
        bottom,
      ],
    );

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        top: false,
        child: wide && _panelOpen && panel != null
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: conversation),
                  VerticalDivider(width: 1, color: colors.hairline),
                  SizedBox(width: 320, child: panel),
                ],
              )
            : conversation,
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.scopeTitle,
    required this.enabled,
    required this.onSuggestion,
  });

  final String? scopeTitle;
  final bool enabled;
  final ValueChanged<String> onSuggestion;

  static const _suggestions = [
    'Summarize the key points',
    'Explain the hardest concept simply',
    'Quiz me with 3 questions',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            key: const Key('chat-empty'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 32,
                color: colors.faintText,
              ),
              Gaps.h12,
              Text(
                scopeTitle == null ? 'Ask anything' : 'Ask about $scopeTitle',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              Gaps.h4,
              Text(
                scopeTitle == null
                    ? 'Answers come from the model’s general knowledge.'
                    : 'Answers are grounded in your material and cite their '
                          'sources.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
                textAlign: TextAlign.center,
              ),
              if (enabled) ...[
                Gaps.h16,
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        label: Text(s),
                        onPressed: () => onSuggestion(s),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameChatDialog extends StatefulWidget {
  const _RenameChatDialog({required this.initial});

  final String initial;

  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  late final _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _name.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename chat'),
    content: SizedBox(
      width: 400,
      child: TextField(
        key: const Key('chat-rename-field'),
        controller: _name,
        autofocus: true,
        maxLength: Chat.maxTitleLength,
        decoration: const InputDecoration(labelText: 'Title'),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('chat-rename-save'),
        onPressed: _submit,
        child: const Text('Rename'),
      ),
    ],
  );
}
