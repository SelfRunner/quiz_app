import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/widgets/locked_feature.dart';
import 'package:quiz_app/data/models/chat.dart';
import 'package:quiz_app/features/chat/widgets/chat_launcher.dart';

import 'support/chat_fakes.dart';

Widget _launcherHome(BuildContext context, Object? _) => Scaffold(
  appBar: AppBar(
    actions: const [
      ChatLauncherButton(
        scopeType: ChatScopeType.subject,
        scopeId: 's1',
        title: 'Biology',
        compact: true,
      ),
    ],
  ),
  body: const Center(
    child: ChatLauncherButton(
      scopeType: ChatScopeType.note,
      scopeId: 'n1',
      title: 'Cells',
    ),
  ),
);

void main() {
  late ChatTestDeps deps;

  setUp(() {
    deps = ChatTestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    deps.notes.seed(id: 'n1', subjectId: 's1', title: 'Cells');
  });

  testWidgets('launcher is locked until AI is set up', (tester) async {
    deps.readiness = notReady;
    await pumpChatApp(tester, deps, location: '/', home: _launcherHome);

    expect(find.byKey(LockedFeature.badgeKey), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('chat-launcher-s1')));
    await tester.pumpAndSettle();
    expect(find.text('Set up AI'), findsOneWidget);
    expect(deps.chats.created, isEmpty);
  });

  testWidgets('launcher creates a chat once, then reopens the latest', (
    tester,
  ) async {
    final router = await pumpChatApp(
      tester,
      deps,
      location: '/',
      home: _launcherHome,
    );

    await tester.tap(find.byKey(const Key('chat-launcher-s1')));
    await tester.pumpAndSettle();
    final chat = deps.chats.created.single;
    expect(chat.scopeType, ChatScopeType.subject);
    expect(chat.scopeId, 's1');
    expect(chat.title, 'Biology');
    expect(chat.provider, 'gemini');
    expect(chat.model, 'gemini-test');
    expect(router.state.uri.toString(), '/chats/${chat.id}');
    expect(find.text('Ask about Biology'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-launcher-s1')));
    await tester.pumpAndSettle();
    expect(deps.chats.created, hasLength(1));
    expect(router.state.uri.toString(), '/chats/${chat.id}');
  });

  testWidgets('launcher menu: new chat and previous chats', (tester) async {
    final older = deps.chats.seedChat(
      id: 'old',
      scopeType: ChatScopeType.note,
      scopeId: 'n1',
      title: 'Earlier chat',
    );
    final router = await pumpChatApp(
      tester,
      deps,
      location: '/',
      home: _launcherHome,
    );

    await tester.tap(find.byKey(const Key('chat-launcher-menu-n1')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('chat-launcher-item-${older.id}')), findsOneWidget);
    expect(find.text('All chats'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-launcher-new')));
    await tester.pumpAndSettle();
    final created = deps.chats.created.single;
    expect(created.scopeType, ChatScopeType.note);
    expect(created.title, 'Cells');
    expect(router.state.uri.toString(), '/chats/${created.id}');

    router.pop();
    await tester.pumpAndSettle();
    // Long-press on the compact form opens the menu too.
    await tester.longPress(find.byKey(const Key('chat-launcher-s1')));
    await tester.pumpAndSettle();
    expect(find.text('New chat'), findsOneWidget);
    await tester.tap(find.text('All chats'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/chats');
  });

  testWidgets('chats list groups by scope, searches and deletes', (
    tester,
  ) async {
    final a = deps.chats.seedChat(id: 'ca', title: 'Photosynthesis basics');
    deps.chats.seedMessage(a.id, ChatRole.user, 'What is chlorophyll?');
    deps.chats.seedMessage(
      a.id,
      ChatRole.assistant,
      'A **green** pigment [S1].',
    );
    final b = deps.chats.seedChat(
      id: 'cb',
      scopeType: ChatScopeType.note,
      scopeId: 'n1',
      title: 'Cell walls',
    );
    deps.chats.seedMessage(b.id, ChatRole.user, 'Do animals have them?');
    deps.chats.seedChat(
      id: 'cg',
      scopeType: ChatScopeType.general,
      title: 'Random',
    );
    deps.chats.seedChat(
      id: 'cx',
      scopeType: ChatScopeType.attachment,
      scopeId: 'gone',
      title: 'Lost file chat',
    );
    final router = await pumpChatApp(tester, deps, location: '/chats');

    expect(find.byKey(const Key('chat-group-subject-s1')), findsOneWidget);
    expect(find.byKey(const Key('chat-group-note-n1')), findsOneWidget);
    expect(find.text('Biology  1'), findsOneWidget);
    expect(find.text('Cells  1'), findsOneWidget);
    expect(find.text('General  1'), findsOneWidget);
    expect(find.text('Source unavailable  1'), findsOneWidget);
    expect(find.text('A green pigment.'), findsOneWidget);
    expect(find.text('You: Do animals have them?'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chats-search')), 'cell');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-row-cb')), findsOneWidget);
    expect(find.byKey(const Key('chat-row-ca')), findsNothing);

    await tester.enterText(find.byKey(const Key('chats-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No chats match'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chats-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-delete-ca')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deps.chats.chats['ca']!.deletedAt, isNotNull);
    expect(find.byKey(const Key('chat-row-ca')), findsNothing);

    await tester.tap(find.byKey(const Key('chat-row-cb')));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/chats/cb');
  });
}
