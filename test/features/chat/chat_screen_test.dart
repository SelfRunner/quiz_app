import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_capabilities.dart';
import 'package:quiz_app/ai/ai_chat_service.dart' as ai;
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/chat.dart';
import 'package:quiz_app/features/chat/application/chat_format.dart';

import 'support/chat_fakes.dart';

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat-input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('chat-send')));
  await tester.pump();
  await tester.pump();
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

void main() {
  late ChatTestDeps deps;

  setUp(() {
    deps = ChatTestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    deps.notes.seed(
      id: 'n1',
      subjectId: 's1',
      title: 'Cells',
      contentMd: 'Mitochondria produce ATP.',
    );
  });

  testWidgets('streams the answer, shows live citations and finalizes once', (
    tester,
  ) async {
    final chat = deps.chats.seedChat(id: 'c1');
    await pumpChatApp(tester, deps, location: '/chats/${chat.id}');
    expect(find.byKey(const Key('chat-empty')), findsOneWidget);
    expect(find.text('Ask about Biology'), findsOneWidget);

    await _send(tester, 'What makes ATP?');
    final call = deps.chatAi.last;
    expect(call.userMessage, 'What makes ATP?');
    expect(call.history, isEmpty);
    expect(call.context.single, isA<ai.NoteSource>());
    expect(call.context.single.id, 'n1');

    call.start();
    await tester.pump();
    expect(find.byKey(const Key('chat-thinking')), findsOneWidget);
    expect(find.byKey(const Key('chat-stop')), findsOneWidget);

    call.delta('Mitochondria make ATP ');
    await tester.pump();
    expect(_rich('Mitochondria make ATP'), findsOneWidget);
    expect(find.byKey(const Key('citation-chip-1')), findsNothing);

    call.delta('[S1].');
    await tester.pump();
    expect(find.byKey(const Key('citation-chip-1')), findsOneWidget);
    // Streaming writes stay local until the answer completes.
    expect(deps.chats.finalized, isEmpty);
    final draftId = deps.chats.drafts.single;
    expect(deps.chats.messages[draftId]!.content, contains('Mitochondria'));

    call.complete();
    await tester.pumpAndSettle();

    final stored = deps.chats.messagesOf('c1');
    expect(stored.map((m) => m.role), [ChatRole.user, ChatRole.assistant]);
    expect(stored.last.content, 'Mitochondria make ATP [S1].');
    expect(stored.last.citations, [
      const ChatCitation(
        type: CitationTypes.note,
        id: 'n1',
        title: 'Cells',
        snippet: 'S1',
      ),
    ]);
    expect(deps.chats.finalized, [stored.last.id]);
    expect(deps.chats.drafts, isEmpty);
    expect(find.byKey(const Key('chat-stop')), findsNothing);
    expect(find.byKey(const Key('chat-send')), findsOneWidget);
    expect(find.byKey(const Key('citation-chip-1')), findsOneWidget);
    expect(find.byKey(const Key('chat-retry')), findsOneWidget);
    // The chat remembers the model that answered.
    expect(deps.chats.chats['c1']!.model, 'gemini-test');

    // Follow-up questions carry the history (without markers' status).
    await _send(tester, 'And where?');
    expect(deps.chatAi.last.history.map((t) => t.text), [
      'What makes ATP?',
      'Mitochondria make ATP [S1].',
    ]);
  });

  testWidgets('stop keeps the partial answer with a stopped marker', (
    tester,
  ) async {
    deps.chats.seedChat(id: 'c1');
    await pumpChatApp(tester, deps, location: '/chats/c1');
    await _send(tester, 'Explain cells');
    final call = deps.chatAi.last
      ..start()
      ..delta('Cells are the basic unit');
    await tester.pump();

    await tester.tap(find.byKey(const Key('chat-stop')));
    await tester.pumpAndSettle();

    expect(call.cancelled, isTrue);
    final answer = deps.chats.messagesOf('c1').last;
    expect(answer.content, 'Cells are the basic unit$kStoppedSuffix');
    expect(deps.chats.finalized, [answer.id]);
    expect(find.byKey(const Key('chat-stopped')), findsOneWidget);
    expect(_rich('(stopped)'), findsNothing);

    // Stopping before any text arrived drops the empty draft.
    await _send(tester, 'Again');
    deps.chatAi.last.start();
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-stop')));
    await tester.pumpAndSettle();
    expect(deps.chats.messagesOf('c1').last.content, 'Again');
    expect(find.byKey(const Key('chat-answer-again')), findsOneWidget);
  });

  testWidgets('citation chips open the cited note', (tester) async {
    deps.chats.seedChat(id: 'c1');
    deps.chats.seedMessage('c1', ChatRole.user, 'What makes ATP?');
    deps.chats.seedMessage(
      'c1',
      ChatRole.assistant,
      'Mitochondria [S2].',
      citations: const [
        ChatCitation(type: 'note', id: 'n1', title: 'Cells', snippet: 'S2'),
      ],
    );
    final router = await pumpChatApp(tester, deps, location: '/chats/c1');
    expect(find.byKey(const Key('citation-chip-2')), findsOneWidget);
    expect(find.text('Cells'), findsWidgets);

    await tester.tap(find.byKey(const Key('citation-chip-2')));
    await tester.pumpAndSettle();
    expect(find.text('note n1'), findsOneWidget);
    expect(router.state.uri.toString(), '/notes/n1');
  });

  testWidgets('history is readable while AI is not set up', (tester) async {
    deps.readiness = notReady;
    deps.chats.seedChat(id: 'c1');
    deps.chats.seedMessage('c1', ChatRole.user, 'Hello');
    deps.chats.seedMessage('c1', ChatRole.assistant, 'Hi **there**');
    await pumpChatApp(tester, deps, location: '/chats/c1');

    expect(find.text('Hello'), findsOneWidget);
    expect(_rich('Hi there'), findsOneWidget);
    expect(find.byKey(const Key('chat-ai-not-ready')), findsOneWidget);
    final input = tester.widget<TextField>(find.byKey(const Key('chat-input')));
    expect(input.enabled, isFalse);
    expect(find.byKey(const Key('chat-retry')), findsNothing);

    await tester.tap(find.text('Set up AI').last);
    await tester.pumpAndSettle();
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('AI errors show a banner; retry asks again', (tester) async {
    deps.chats.seedChat(id: 'c1');
    await pumpChatApp(tester, deps, location: '/chats/c1');
    await _send(tester, 'Hi');
    deps.chatAi.last.fail(
      const AiException('Slow down', kind: AiErrorKind.rateLimited),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-error')), findsOneWidget);
    expect(find.text('Rate limit or quota reached'), findsOneWidget);
    expect(deps.chats.messagesOf('c1').map((m) => m.content), ['Hi']);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(deps.chatAi.calls, hasLength(2));
    expect(deps.chatAi.last.userMessage, 'Hi');
    expect(find.byKey(const Key('ai-error')), findsNothing);
    deps.chatAi.last
      ..start()
      ..delta('Hello!')
      ..complete();
    await tester.pumpAndSettle();
    expect(deps.chats.messagesOf('c1').map((m) => m.content), ['Hi', 'Hello!']);
  });

  testWidgets('retry replaces the last answer', (tester) async {
    deps.chats.seedChat(id: 'c1');
    deps.chats.seedMessage('c1', ChatRole.user, 'Q');
    final old = deps.chats.seedMessage('c1', ChatRole.assistant, 'Old');
    await pumpChatApp(tester, deps, location: '/chats/c1');

    await tester.tap(find.byKey(const Key('chat-retry')));
    await tester.pump();
    await tester.pump();
    expect(deps.chats.deletedMessages, [old.id]);
    expect(deps.chatAi.last.userMessage, 'Q');
    expect(deps.chatAi.last.history, isEmpty);
    deps.chatAi.last
      ..start()
      ..delta('New')
      ..complete();
    await tester.pumpAndSettle();
    expect(deps.chats.messagesOf('c1').map((m) => m.content), ['Q', 'New']);
  });

  testWidgets('files the model cannot read are gated in the context panel', (
    tester,
  ) async {
    deps.readiness = readyWith(AiCapabilities.textOnly);
    deps.attachments.seed(id: 'a1', subjectId: 's1', name: 'slides.pdf');
    deps.attachments.seed(
      id: 'a2',
      subjectId: 's1',
      name: 'summary.md',
      extractedText: '# Summary',
    );
    deps.chats.seedChat(id: 'c1');
    await pumpChatApp(tester, deps, location: '/chats/c1');

    final panel = find.byKey(const Key('chat-context-panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(
        of: panel,
        matching: find.textContaining("can't read PDFs"),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat-source-check-a1')), findsNothing);
    // Notes are included by default, files are opt-in.
    final note = tester.widget<Checkbox>(
      find.byKey(const Key('chat-source-check-n1')),
    );
    expect(note.value, isTrue);
    await tester.tap(find.byKey(const Key('chat-source-check-a2')));
    await tester.tap(find.byKey(const Key('chat-source-check-n1')));
    await tester.pump();

    await _send(tester, 'Summarize');
    final sources = deps.chatAi.last.context;
    expect(sources.map((s) => s.id), ['a2']);
    expect(sources.single, isA<ai.TextSource>());
    expect(sources.single.type, ai.AiSourceType.file);
  });

  testWidgets('rename and delete from the chat menu', (tester) async {
    deps.chats.seedChat(id: 'c1', title: 'Biology');
    await pumpChatApp(tester, deps, location: '/chats/c1');

    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat-rename-field')), 'ATP');
    await tester.tap(find.byKey(const Key('chat-rename-save')));
    await tester.pumpAndSettle();
    expect(deps.chats.chats['c1']!.title, 'ATP');
    expect(find.text('ATP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deps.chats.chats['c1']!.deletedAt, isNotNull);
    expect(find.text('No chats yet'), findsOneWidget);
  });

  test('linkifyCitations links known markers outside code', () {
    expect(
      linkifyCitations('A [S1][S3] b [S2-S3]\n```\nx[S1]\n```', {1, 3}),
      'A [\\[1\\]](cite:1)[\\[3\\]](cite:3) b [\\[3\\]](cite:3)\n```\nx[S1]\n```',
    );
    expect(parseAssistantContent('x$kCutOffSuffix').cutOff, isTrue);
    expect(
      citationsByNumber('a [S2] b [S5]', const [
        ChatCitation(type: 'note', id: 'x', title: 'X'),
      ]).keys,
      [2],
    );
  });
}
