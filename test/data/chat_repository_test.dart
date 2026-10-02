import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/local/local_database.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/local_chat_repository.dart';
import 'package:quiz_app/data/repositories/local_note_repository.dart';
import 'package:quiz_app/data/repositories/local_subject_repository.dart';
import 'package:quiz_app/data/repositories/repository_support.dart';
import 'package:quiz_app/data/sync/default_sync_engine.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';

import 'support/fake_remote.dart';
import 'support/test_db.dart';

void main() {
  final h = TestHive();
  late LocalChatRepository chats;
  late DataContext ctx;

  setUp(() async {
    await h.setUp();
    h.userId = 'user-a';
    ctx = h.context();
    chats = LocalChatRepository(ctx);
  });

  tearDown(h.tearDown);

  List<OutboxOp> ops(String table) =>
      h.db.outbox.pending().where((o) => o.table == table).toList();

  group('models', () {
    test('Chat / ChatMessage JSON matches the columns', () {
      final chat = Chat(
        id: 'c1',
        ownerId: 'u',
        scopeType: ChatScopeType.note,
        scopeId: 'n1',
        title: 'T',
        provider: 'gemini',
        model: 'm',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final json = chat.toJson();
      expect(json['scope_type'], 'note');
      expect(json['scope_id'], 'n1');
      expect(json.containsKey('deleted_at'), isTrue);
      expect(Chat.fromJson(json), chat);

      final message = ChatMessage(
        id: 'm1',
        chatId: 'c1',
        ownerId: 'u',
        role: ChatRole.assistant,
        content: 'Hi',
        citations: const [
          ChatCitation(type: 'note', id: 'n1', title: 'N', snippet: 'x'),
          ChatCitation(type: 'web', id: 'https://e.test', title: 'W'),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final mj = message.toJson();
      expect(mj['role'], 'assistant');
      expect((mj['citations'] as List).first, {
        'type': 'note',
        'id': 'n1',
        'title': 'N',
        'snippet': 'x',
      });
      expect(ChatMessage.fromJson(mj), message);
    });

    test('unknown enum values and missing keys decode', () {
      final chat = Chat.fromJson({
        'id': 'c',
        'owner_id': 'u',
        'scope_type': 'galaxy',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(chat.scopeType, ChatScopeType.general);
      expect(chat.title, '');
      final m = ChatMessage.fromJson({
        'id': 'm',
        'chat_id': 'c',
        'owner_id': 'u',
        'role': 'tool',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(m.role, ChatRole.system);
      expect(m.citations, isEmpty);
    });
  });

  group('ChatRepository', () {
    test('create validates the scope', () async {
      expect(
        () => chats.create(scopeType: ChatScopeType.general, scopeId: 'x'),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => chats.create(scopeType: ChatScopeType.note),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => chats.create(scopeType: ChatScopeType.note, scopeId: 'nope'),
        throwsA(isA<NotFoundException>()),
      );
      final s = await LocalSubjectRepository(ctx).create(title: 'S');
      final c = await chats.create(
        scopeType: ChatScopeType.subject,
        scopeId: s.id,
        title: '  ${'x' * 600} ',
        provider: 'gemini',
        model: 'gemini-pro',
      );
      expect(c.title.length, Chat.maxTitleLength);
      expect(c.ownerId, 'user-a');
      expect(ops(SyncTables.chats), hasLength(1));
    });

    test('watchByScope / watchAll order by recent activity', () async {
      final s = await LocalSubjectRepository(ctx).create(title: 'S');
      final n = await LocalNoteRepository(ctx)
          .create(subjectId: s.id, title: 'N');
      final general = await chats.create(scopeType: ChatScopeType.general);
      final onNote = await chats.create(
        scopeType: ChatScopeType.note,
        scopeId: n.id,
      );
      expect((await chats.watchAll().first).map((c) => c.id), [
        onNote.id,
        general.id,
      ]);
      await chats.addMessage(
        chatId: general.id,
        role: ChatRole.user,
        content: 'q',
      );
      expect((await chats.watchAll().first).map((c) => c.id), [
        general.id,
        onNote.id,
      ]);
      expect(
        (await chats.watchByScope(ChatScopeType.note, n.id).first).map(
          (c) => c.id,
        ),
        [onNote.id],
      );
      expect(
        await chats.watchByScope(ChatScopeType.general, null).first,
        hasLength(1),
      );
    });

    test('other users\' chats are invisible and read-only', () async {
      final now = DateTime.utc(2026);
      await h.db.chats.put(
        Chat(id: 'foreign', ownerId: 'user-b', createdAt: now, updatedAt: now),
      );
      expect(await chats.getById('foreign'), isNull);
      expect(await chats.watchAll().first, isEmpty);
      expect(
        () => chats.rename('foreign', 'x'),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(
        () => chats.addMessage(chatId: 'foreign', role: ChatRole.user),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('messages: add, order, citations sanitized, content cut', () async {
      final c = await chats.create(scopeType: ChatScopeType.general);
      final m1 = await chats.addMessage(
        chatId: c.id,
        role: ChatRole.user,
        content: 'Hello',
      );
      final m2 = await chats.addMessage(
        chatId: c.id,
        role: ChatRole.assistant,
        content: 'y' * (ChatMessage.maxContentLength + 10),
        citations: const [
          ChatCitation(type: 'note', id: 'n1', title: 'N'),
          ChatCitation(type: '', id: 'n2'),
          ChatCitation(type: 'note', id: ''),
        ],
      );
      expect(m2.content.length, ChatMessage.maxContentLength);
      expect(m2.citations, hasLength(1));
      final list = await chats.watchMessages(c.id).first;
      expect(list.map((m) => m.id), [m1.id, m2.id]);
      expect(ops(SyncTables.chatMessages), hasLength(2));
      // The chat upsert coalesces (one op, touched).
      expect(ops(SyncTables.chats), hasLength(1));
    });

    test('streaming: drafts stay local until finalized', () async {
      final c = await chats.create(scopeType: ChatScopeType.general);
      await chats.addMessage(chatId: c.id, role: ChatRole.user, content: 'q');
      final before = h.db.outbox.length;
      var m = await chats.addMessage(
        chatId: c.id,
        role: ChatRole.assistant,
        draft: true,
      );
      for (final chunk in ['Hel', 'lo', ' world']) {
        m = await chats.updateMessage(
          m.copyWith(content: m.content + chunk),
          finalize: false,
        );
      }
      expect(h.db.outbox.length, before, reason: 'no outbox spam');
      expect(h.db.meta.chatDraftIds, {m.id});
      expect((await chats.getMessages(c.id)).last.content, 'Hello world');

      final done = await chats.updateMessage(
        m.copyWith(
          citations: const [ChatCitation(type: 'note', id: 'n', title: 'N')],
        ),
      );
      expect(done.content, 'Hello world');
      expect(done.role, ChatRole.assistant);
      expect(h.db.meta.chatDraftIds, isEmpty);
      final pushed = ops(SyncTables.chatMessages).last;
      expect(pushed.rowId, m.id);
      expect(pushed.payload!['content'], 'Hello world');
      expect(pushed.payload!['citations'], hasLength(1));
    });

    test('finalizeDrafts queues leftovers', () async {
      final c = await chats.create(scopeType: ChatScopeType.general);
      final m = await chats.addMessage(
        chatId: c.id,
        role: ChatRole.assistant,
        content: 'partial',
        draft: true,
      );
      expect(ops(SyncTables.chatMessages), isEmpty);
      expect(await chats.finalizeDrafts(), 1);
      expect(ops(SyncTables.chatMessages).single.rowId, m.id);
      expect(await chats.finalizeDrafts(), 0);
    });

    test('rename, setModel, deleteMessage', () async {
      final c = await chats.create(scopeType: ChatScopeType.general);
      expect((await chats.rename(c.id, ' New ')).title, 'New');
      final withModel = await chats.setModel(
        c.id,
        provider: 'openai',
        model: 'gpt',
      );
      expect((withModel.provider, withModel.model), ('openai', 'gpt'));
      final m = await chats.addMessage(chatId: c.id, role: ChatRole.user);
      await chats.deleteMessage(m.id);
      expect(await chats.getMessages(c.id), isEmpty);
      expect(h.db.chatMessages.get(m.id)!.deletedAt, isNotNull);
    });

    test('delete tombstones the chat and every message', () async {
      final c = await chats.create(scopeType: ChatScopeType.general);
      final m1 = await chats.addMessage(chatId: c.id, role: ChatRole.user);
      final m2 = await chats.addMessage(
        chatId: c.id,
        role: ChatRole.assistant,
        draft: true,
      );
      final messages = chats.watchMessages(c.id);
      await chats.delete(c.id);
      expect(await chats.getById(c.id), isNull);
      expect(await messages.first, isEmpty);
      for (final id in [m1.id, m2.id]) {
        expect(h.db.chatMessages.get(id)!.deletedAt, isNotNull);
        expect(
          h.db.outbox
              .pendingFor(SyncTables.chatMessages, id)!
              .payload!['deleted_at'],
          isNotNull,
        );
      }
      expect(h.db.meta.chatDraftIds, isEmpty);
      await chats.delete(c.id); // idempotent
    });

    test('signed out -> AppAuthException', () async {
      h.userId = null;
      expect(
        () => chats.create(scopeType: ChatScopeType.general),
        throwsA(isA<AppAuthException>()),
      );
    });
  });

  group('sync', () {
    late FakeRemote remote;
    final engines = <DefaultSyncEngine>[];

    DefaultSyncEngine makeEngine([LocalDatabase? db]) {
      final e = DefaultSyncEngine(
        db: db ?? h.db,
        remote: remote,
        imageRemote: remote,
        currentUserId: () => h.userId,
        connectivity: FakeConnectivity(),
        clock: h.clockFn,
      );
      engines.add(e);
      return e;
    }

    setUp(() => remote = FakeRemote(userId: 'user-a'));

    tearDown(() async {
      for (final e in engines) {
        await e.dispose();
      }
      engines.clear();
    });

    test('chats and messages round-trip to another device', () async {
      final s = await LocalSubjectRepository(ctx).create(title: 'S');
      final c = await chats.create(
        scopeType: ChatScopeType.subject,
        scopeId: s.id,
        title: 'About S',
      );
      final m = await chats.addMessage(
        chatId: c.id,
        role: ChatRole.assistant,
        content: 'Answer',
        citations: const [
          ChatCitation(type: 'subject', id: 's', title: 'S', snippet: 'x'),
        ],
      );
      await makeEngine().sync();
      expect(h.db.outbox.length, 0);
      expect(remote.tables[SyncTables.chats]!.keys, [c.id]);
      expect(remote.tables[SyncTables.chatMessages]!.keys, [m.id]);
      // FIFO: chat before its message.
      expect(
        remote.log.indexOf('upsert:chats:${c.id}'),
        lessThan(remote.log.indexOf('upsert:chat_messages:${m.id}')),
      );

      final db2 = await h.openDb(suffix: '2');
      await makeEngine(db2).sync();
      final repo2 = LocalChatRepository(
        DataContext(
          db: db2,
          clock: h.clockFn,
          newId: h.ids.call,
          currentUserId: () => h.userId,
        ),
      );
      final pulled = (await repo2.getMessages(c.id)).single;
      expect(pulled.content, 'Answer');
      expect(pulled.citations.single.snippet, 'x');
      expect((await repo2.getById(c.id))!.title, 'About S');

      // Delete on device 2 -> tombstones reach device 1.
      await repo2.delete(c.id);
      await makeEngine(db2).sync();
      expect(
        remote.tables[SyncTables.chatMessages]![m.id]!['deleted_at'],
        isNotNull,
      );
      await engines.first.sync();
      expect(await chats.getById(c.id), isNull);
      expect(await chats.getMessages(c.id), isEmpty);
    });

    test('draft messages are not pushed until finalized', () async {
      final c = await chats.create(scopeType: ChatScopeType.general);
      final m = await chats.addMessage(
        chatId: c.id,
        role: ChatRole.assistant,
        draft: true,
      );
      final engine = makeEngine();
      await engine.sync();
      expect(remote.tables[SyncTables.chatMessages], isEmpty);
      await chats.updateMessage(m.copyWith(content: 'final'));
      await engine.sync();
      expect(
        remote.tables[SyncTables.chatMessages]![m.id]!['content'],
        'final',
      );
    });

    test('chat on an unreadable scope is rejected (42501, dropped)', () async {
      final now = DateTime.utc(2026);
      // A note cached locally that the server no longer lets us read.
      await h.db.notes.put(
        Note(
          id: 'gone',
          subjectId: 's',
          ownerId: 'user-b',
          title: 'N',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final c = await chats.create(
        scopeType: ChatScopeType.note,
        scopeId: 'gone',
      );
      final engine = makeEngine();
      await engine.sync();
      expect(h.db.outbox.length, 0);
      expect(remote.tables[SyncTables.chats], isEmpty);
      expect(engine.rejectedChanges.single.rowId, c.id);
    });

    test(
      'missing chat tables: kept queued, server outdated, others sync',
      () async {
        remote.missingTables.addAll({
          SyncTables.chats,
          SyncTables.chatMessages,
        });
        final s = await LocalSubjectRepository(ctx).create(title: 'S');
        final c = await chats.create(scopeType: ChatScopeType.general);
        await chats.addMessage(chatId: c.id, role: ChatRole.user, content: 'q');
        final engine = makeEngine();
        await engine.sync();
        expect(remote.tables[SyncTables.subjects]!.keys, [s.id]);
        expect(engine.currentStatus.serverOutdated, isTrue);
        expect(
          engine.currentStatus.unavailableTables,
          containsAll([SyncTables.chats, SyncTables.chatMessages]),
        );
        expect(engine.currentStatus.state, SyncState.error);
        expect(h.db.outbox.length, 2);
        expect(engine.rejectedChanges, isEmpty);

        remote.missingTables.clear();
        await engine.sync();
        expect(engine.currentStatus.serverOutdated, isFalse);
        expect(h.db.outbox.length, 0);
        expect(remote.tables[SyncTables.chatMessages], hasLength(1));
      },
    );

    test(
      'organization columns round-trip; missing columns keep ops queued',
      () async {
        final s = await LocalSubjectRepository(ctx).create(title: 'S');
        final n = await LocalNoteRepository(ctx)
            .create(subjectId: s.id, title: 'N');
        await LocalNoteRepository(ctx)
            .update(n.copyWith(tags: ['a', 'b'], pinned: true));
        await LocalSubjectRepository(
          ctx,
        ).update(s.copyWith(pinned: true, archivedAt: DateTime.utc(2026, 2)));
        remote.missingColumns[SyncTables.notes] = {'tags', 'pinned'};
        final engine = makeEngine();
        await engine.sync();
        expect(engine.currentStatus.unavailableTables, [SyncTables.notes]);
        expect(remote.tables[SyncTables.subjects]![s.id]!['pinned'], isTrue);
        remote.missingColumns.clear();
        await engine.sync();
        expect(remote.tables[SyncTables.notes]![n.id]!['tags'], ['a', 'b']);

        final db2 = await h.openDb(suffix: '2');
        await makeEngine(db2).sync();
        final note2 = db2.notes.get(n.id)!;
        expect(note2.tags, ['a', 'b']);
        expect(note2.pinned, isTrue);
        final subject2 = db2.subjects.get(s.id)!;
        expect(subject2.pinned, isTrue);
        expect(subject2.archivedAt, DateTime.utc(2026, 2));
      },
    );
  });
}
