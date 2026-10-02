// In-memory fakes for the chat UI tests.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/ai/ai_capabilities.dart';
import 'package:quiz_app/ai/ai_chat_service.dart' as ai;
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_readiness.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/chat.dart';
import 'package:quiz_app/data/repositories/chat_repository.dart';
import 'package:quiz_app/features/chat/presentation/chat_screen.dart';
import 'package:quiz_app/features/chat/presentation/chats_screen.dart';

import '../../subjects/support/fakes.dart';

/// In-memory [ChatRepository] that records finalized writes.
class FakeChatRepository implements ChatRepository {
  final Map<String, Chat> chats = {};
  final Map<String, ChatMessage> messages = {};
  final Set<String> drafts = {};

  /// Message ids passed to `updateMessage(finalize: true)`, in order.
  final List<String> finalized = [];
  final List<String> deletedMessages = [];
  final List<Chat> created = [];
  int _n = 0;
  int _tick = 0;
  final _changes = StreamController<void>.broadcast();

  DateTime _now() => kNow.add(Duration(seconds: ++_tick));

  void _changed() => _changes.add(null);

  Stream<R> _watch<R>(R Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  List<Chat> get _live =>
      chats.values.where((c) => c.deletedAt == null).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<ChatMessage> messagesOf(String chatId) =>
      messages.values
          .where((m) => m.chatId == chatId && m.deletedAt == null)
          .toList()
        ..sort((a, b) {
          final c = a.createdAt.compareTo(b.createdAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        });

  Chat seedChat({
    String? id,
    ChatScopeType scopeType = ChatScopeType.subject,
    String? scopeId = 's1',
    String title = 'Biology',
  }) {
    final now = _now();
    final c = Chat(
      id: id ?? 'c${++_n}',
      ownerId: kUserId,
      scopeType: scopeType,
      scopeId: scopeType == ChatScopeType.general ? null : scopeId,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    chats[c.id] = c;
    _changed();
    return c;
  }

  ChatMessage seedMessage(
    String chatId,
    ChatRole role,
    String content, {
    List<ChatCitation> citations = const [],
  }) {
    final now = _now();
    final m = ChatMessage(
      id: 'm${++_n}',
      chatId: chatId,
      ownerId: kUserId,
      role: role,
      content: content,
      citations: citations,
      createdAt: now,
      updatedAt: now,
    );
    messages[m.id] = m;
    chats[chatId] = chats[chatId]!.copyWith(updatedAt: now);
    _changed();
    return m;
  }

  @override
  Stream<List<Chat>> watchAll() => _watch(() => _live);

  @override
  Stream<List<Chat>> watchByScope(ChatScopeType scopeType, String? scopeId) =>
      _watch(
        () => _live
            .where((c) => c.scopeType == scopeType && c.scopeId == scopeId)
            .toList(),
      );

  @override
  Stream<Chat?> watchById(String id) => _watch(() {
    final c = chats[id];
    return c == null || c.deletedAt != null ? null : c;
  });

  @override
  Future<Chat?> getById(String id) async => chats[id];

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId) =>
      _watch(() => messagesOf(chatId));

  @override
  Future<List<ChatMessage>> getMessages(String chatId) async =>
      messagesOf(chatId);

  @override
  Future<Chat> create({
    required ChatScopeType scopeType,
    String? scopeId,
    String title = '',
    String? provider,
    String? model,
  }) async {
    if ((scopeType == ChatScopeType.general) != (scopeId == null)) {
      throw const ValidationException('Bad scope');
    }
    final c = seedChat(
      scopeType: scopeType,
      scopeId: scopeId,
      title: title,
    ).copyWith(provider: provider, model: model);
    chats[c.id] = c;
    created.add(c);
    _changed();
    return c;
  }

  @override
  Future<Chat> rename(String chatId, String title) async {
    final c = chats[chatId]!.copyWith(title: title.trim());
    chats[chatId] = c;
    _changed();
    return c;
  }

  @override
  Future<Chat> setModel(
    String chatId, {
    String? provider,
    String? model,
  }) async {
    final c = chats[chatId]!.copyWith(provider: provider, model: model);
    chats[chatId] = c;
    _changed();
    return c;
  }

  @override
  Future<void> delete(String chatId) async {
    final now = _now();
    chats[chatId] = chats[chatId]!.copyWith(deletedAt: now);
    for (final m in messagesOf(chatId)) {
      messages[m.id] = m.copyWith(deletedAt: now);
    }
    _changed();
  }

  @override
  Future<ChatMessage> addMessage({
    required String chatId,
    required ChatRole role,
    String content = '',
    List<ChatCitation> citations = const [],
    bool draft = false,
  }) async {
    final m = seedMessage(chatId, role, content, citations: citations);
    if (draft) drafts.add(m.id);
    return m;
  }

  @override
  Future<ChatMessage> updateMessage(
    ChatMessage message, {
    bool finalize = true,
  }) async {
    final stored = messages[message.id]!;
    final m = stored.copyWith(
      content: message.content,
      citations: message.citations,
      updatedAt: _now(),
    );
    messages[m.id] = m;
    if (finalize) {
      drafts.remove(m.id);
      finalized.add(m.id);
    }
    _changed();
    return m;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final m = messages[messageId];
    if (m == null) return;
    messages[messageId] = m.copyWith(deletedAt: _now());
    drafts.remove(messageId);
    deletedMessages.add(messageId);
    _changed();
  }

  @override
  Future<int> finalizeDrafts() async => 0;
}

/// One [FakeAiChatService.send] call: inspect its inputs and drive its
/// stream.
class ChatCall {
  ChatCall({
    required this.history,
    required this.userMessage,
    required this.context,
  }) {
    controller = StreamController<ai.ChatDelta>(
      onCancel: () => cancelled = true,
    );
  }

  final List<ai.ChatTurn> history;
  final String userMessage;
  final List<ai.AiSource> context;
  late final StreamController<ai.ChatDelta> controller;
  bool cancelled = false;
  List<ai.ChatSourceRef> sources = const [];
  final _text = StringBuffer();

  static const selection = AiSelection(
    providerId: LlmProviderId.gemini,
    model: 'gemini-test',
  );

  /// Emits [ai.ChatStarted] numbering every context source `S1, S2, ...`.
  void start() {
    sources = [
      for (var i = 0; i < context.length; i++)
        ai.ChatSourceRef(
          number: i + 1,
          type: context[i].type,
          id: context[i].id,
          title: context[i].label,
        ),
    ];
    controller.add(ai.ChatStarted(selection: selection, sources: sources));
  }

  void delta(String text) {
    _text.write(text);
    controller.add(ai.ChatTextDelta(text));
  }

  /// Emits [ai.ChatCompleted] with the citations parsed from the text.
  void complete({bool truncated = false}) {
    final text = _text.toString();
    controller
      ..add(
        ai.ChatCompleted(
          ai.ChatResult(
            text: text,
            citations: ai.ChatCitations.parse(text, sources),
            sources: sources,
            selection: selection,
            truncated: truncated,
          ),
        ),
      )
      ..close();
  }

  void fail(Object error) {
    controller
      ..addError(error)
      ..close();
  }
}

/// [ai.AiChatService] whose answers the test emits by hand.
class FakeAiChatService implements ai.AiChatService {
  final List<ChatCall> calls = [];

  ChatCall get last => calls.last;

  @override
  Stream<ai.ChatDelta> send({
    required List<ai.ChatTurn> history,
    required String userMessage,
    required List<ai.AiSource> context,
    String? language,
    LlmProviderId? providerId,
    String? model,
  }) {
    final call = ChatCall(
      history: history,
      userMessage: userMessage,
      context: context,
    );
    calls.add(call);
    return call.controller.stream;
  }
}

AiReadiness readyWith([
  AiCapabilities caps = const AiCapabilities(pdf: true),
]) => AiReadiness(
  isConfigured: true,
  providerId: LlmProviderId.gemini,
  model: 'gemini-test',
  capabilities: caps,
);

const notReady = AiReadiness.notReady(
  reason: 'Add your Gemini API key in Settings.',
  issue: AiReadinessIssue.missingApiKey,
);

/// Test dependencies: the shared subject/note/attachment fakes plus chat.
class ChatTestDeps extends TestDeps {
  final chats = FakeChatRepository();
  final chatAi = FakeAiChatService();
  AiReadiness readiness = readyWith();

  List<Override> get chatOverrides => [
    ...overrides,
    chatRepositoryProvider.overrideWithValue(chats),
    aiChatServiceProvider.overrideWithValue(chatAi),
    aiReadinessProvider.overrideWith((ref) async => readiness),
  ];
}

/// Pumps a router app at [location] with stub routes for the targets the
/// chat UI navigates to.
Future<GoRouter> pumpChatApp(
  WidgetTester tester,
  ChatTestDeps deps, {
  required String location,
  Widget Function(BuildContext context, GoRouterState state)? home,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/',
        builder: home ?? (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(path: '/chats', builder: (_, _) => const ChatsScreen()),
      GoRoute(
        path: '/chats/:id',
        builder: (_, state) => ChatScreen(chatId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notes/:id',
        builder: (_, state) =>
            Scaffold(body: Text('note ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/subjects/:id',
        builder: (_, state) =>
            Scaffold(body: Text('subject ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('settings')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: deps.chatOverrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
