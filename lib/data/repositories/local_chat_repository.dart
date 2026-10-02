import '../../core/errors/app_exception.dart';
import '../local/local_table.dart';
import '../models/chat.dart';
import '../models/syncable.dart';
import 'chat_repository.dart';
import 'repository_support.dart';

/// Hive-backed [ChatRepository] (writes go through the outbox, except
/// streaming drafts).
class LocalChatRepository implements ChatRepository {
  LocalChatRepository(this._ctx);

  final DataContext _ctx;

  LocalTable<Chat> get _chats => _ctx.db.chats;
  LocalTable<ChatMessage> get _messages => _ctx.db.chatMessages;

  static int _byUpdatedDesc(Chat a, Chat b) {
    final c = b.updatedAt.compareTo(a.updatedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  static int _byCreated(ChatMessage a, ChatMessage b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  bool _mine(Syncable row) => row.isOwnedBy(_ctx.currentUserId);

  @override
  Stream<List<Chat>> watchAll() =>
      _chats.watchWhere(_mine, compare: _byUpdatedDesc);

  @override
  Stream<List<Chat>> watchByScope(ChatScopeType scopeType, String? scopeId) =>
      _chats.watchWhere(
        (c) => _mine(c) && c.scopeType == scopeType && c.scopeId == scopeId,
        compare: _byUpdatedDesc,
      );

  @override
  Stream<Chat?> watchById(String id) =>
      _chats.watchById(id).map((c) => c != null && _mine(c) ? c : null);

  @override
  Future<Chat?> getById(String id) async {
    final chat = _chats.getLive(id);
    return chat != null && _mine(chat) ? chat : null;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId) => watchQuery(
    [_chats.box, _messages.box],
    () => _liveMessages(chatId),
    equals: _listEquals,
  );

  @override
  Future<List<ChatMessage>> getMessages(String chatId) async =>
      _liveMessages(chatId);

  /// Messages of a live chat (none for a deleted chat, whose message
  /// tombstones may still be queued).
  List<ChatMessage> _liveMessages(String chatId) {
    final chat = _chats.getLive(chatId);
    if (chat == null || !_mine(chat)) return const [];
    return _messages.where((m) => m.chatId == chatId, compare: _byCreated);
  }

  @override
  Future<Chat> create({
    required ChatScopeType scopeType,
    String? scopeId,
    String title = '',
    String? provider,
    String? model,
  }) async {
    final userId = _ctx.requireUserId();
    _checkScope(scopeType, scopeId);
    final now = _ctx.clock();
    final chat = Chat(
      id: _ctx.newId(),
      ownerId: userId,
      scopeType: scopeType,
      scopeId: scopeId,
      title: _title(title),
      provider: _short(provider),
      model: _short(model),
      createdAt: now,
      updatedAt: now,
    );
    await _ctx.save(_chats, chat);
    return chat;
  }

  void _checkScope(ChatScopeType type, String? scopeId) {
    if ((type == ChatScopeType.general) != (scopeId == null)) {
      throw ValidationException(
        type == ChatScopeType.general
            ? 'A general chat has no source.'
            : 'Choose what the chat is about.',
      );
    }
    final db = _ctx.db;
    switch (type) {
      case ChatScopeType.general:
        return;
      case ChatScopeType.subject:
        _ctx.requireLive(db.subjects, scopeId!, 'subject');
      case ChatScopeType.note:
        _ctx.requireLive(db.notes, scopeId!, 'note');
      case ChatScopeType.attachment:
        _ctx.requireLive(db.attachments, scopeId!, 'file');
    }
  }

  @override
  Future<Chat> rename(String chatId, String title) async {
    final chat = _requireChat(chatId);
    final next = chat.copyWith(title: _title(title), updatedAt: _ctx.clock());
    await _ctx.save(_chats, next);
    return next;
  }

  @override
  Future<Chat> setModel(
    String chatId, {
    String? provider,
    String? model,
  }) async {
    final chat = _requireChat(chatId);
    final next = chat.copyWith(
      provider: _short(provider),
      model: _short(model),
      updatedAt: _ctx.clock(),
    );
    await _ctx.save(_chats, next);
    return next;
  }

  @override
  Future<void> delete(String chatId) async {
    final userId = _ctx.requireUserId();
    final chat = _chats.getLive(chatId);
    if (chat == null) return;
    _ctx.ensureOwned(chat, userId, 'chat');
    final now = _ctx.clock();
    // The server does not cascade soft deletes: tombstone every message
    // (drafts too: a tombstone of a never-pushed row is harmless).
    final drafts = _ctx.db.meta.chatDraftIds;
    for (final m in _messages.where((m) => m.chatId == chatId)) {
      drafts.remove(m.id);
      await _ctx.save(_messages, m.copyWith(deletedAt: now, updatedAt: now));
    }
    await _ctx.db.meta.setChatDraftIds(drafts);
    await _ctx.save(_chats, chat.copyWith(deletedAt: now, updatedAt: now));
  }

  @override
  Future<ChatMessage> addMessage({
    required String chatId,
    required ChatRole role,
    String content = '',
    List<ChatCitation> citations = const [],
    bool draft = false,
  }) async {
    final chat = _requireChat(chatId);
    final now = _ctx.clock();
    final message = ChatMessage(
      id: _ctx.newId(),
      chatId: chatId,
      ownerId: chat.ownerId,
      role: role,
      content: _content(content),
      citations: sanitizeCitations(citations),
      createdAt: now,
      updatedAt: now,
    );
    if (draft) {
      await _putDraft(message);
    } else {
      await _ctx.save(_messages, message);
      await _touch(chat, now);
    }
    return message;
  }

  @override
  Future<ChatMessage> updateMessage(
    ChatMessage message, {
    bool finalize = true,
  }) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.requireLive(_messages, message.id, 'message');
    _ctx.ensureOwned(existing, userId, 'message');
    final chat = _requireChat(existing.chatId);
    final now = _ctx.clock();
    final next = existing.copyWith(
      content: _content(message.content),
      citations: sanitizeCitations(message.citations),
      updatedAt: now,
    );
    if (!finalize) {
      // Streaming: local write only; remembered as a draft so it is pushed
      // by a later finalize / [finalizeDrafts] even if the app is killed.
      await _putDraft(next);
      return next;
    }
    await _forgetDraft(next.id);
    await _ctx.save(_messages, next);
    await _touch(chat, now);
    return next;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final userId = _ctx.requireUserId();
    final existing = _messages.getLive(messageId);
    if (existing == null) return;
    _ctx.ensureOwned(existing, userId, 'message');
    await _forgetDraft(messageId);
    final now = _ctx.clock();
    await _ctx.save(
      _messages,
      existing.copyWith(deletedAt: now, updatedAt: now),
    );
  }

  @override
  Future<int> finalizeDrafts() async {
    final userId = _ctx.currentUserId;
    if (userId == null) return 0;
    final drafts = _ctx.db.meta.chatDraftIds;
    if (drafts.isEmpty) return 0;
    var queued = 0;
    for (final id in drafts) {
      final m = _messages.getLive(id);
      if (m == null || !m.isOwnedBy(userId)) continue;
      await _ctx.save(_messages, m);
      queued++;
    }
    await _ctx.db.meta.setChatDraftIds(const {});
    return queued;
  }

  // ---------------------------------------------------------------------------

  Chat _requireChat(String chatId) {
    final userId = _ctx.requireUserId();
    final chat = _ctx.requireLive(_chats, chatId, 'chat');
    _ctx.ensureOwned(chat, userId, 'chat');
    return chat;
  }

  Future<void> _putDraft(ChatMessage message) async {
    final drafts = _ctx.db.meta.chatDraftIds;
    if (drafts.add(message.id)) await _ctx.db.meta.setChatDraftIds(drafts);
    try {
      await _messages.put(message);
    } catch (e, st) {
      throw StorageException(
        'Could not save changes on this device.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Returns whether [id] was a draft.
  Future<bool> _forgetDraft(String id) async {
    final drafts = _ctx.db.meta.chatDraftIds;
    if (!drafts.remove(id)) return false;
    await _ctx.db.meta.setChatDraftIds(drafts);
    return true;
  }

  /// Bumps the chat's `updatedAt` (chat lists sort by recent activity).
  Future<void> _touch(Chat chat, DateTime now) async {
    final current = _chats.getLive(chat.id) ?? chat;
    await _ctx.save(_chats, current.copyWith(updatedAt: now));
  }

  static String _title(String title) {
    final t = title.trim();
    return t.length > Chat.maxTitleLength
        ? t.substring(0, Chat.maxTitleLength)
        : t;
  }

  static String? _short(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    return v.length > Chat.maxProviderLength
        ? v.substring(0, Chat.maxProviderLength)
        : v;
  }

  static String _content(String content) =>
      content.length > ChatMessage.maxContentLength
      ? content.substring(0, ChatMessage.maxContentLength)
      : content;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Citations the server accepts: `type` 1..64 chars, `id` 1..255 chars
/// (others are dropped; titles are kept as given).
List<ChatCitation> sanitizeCitations(List<ChatCitation> citations) => [
  for (final c in citations)
    if (c.type.isNotEmpty &&
        c.type.length <= ChatCitation.maxTypeLength &&
        c.id.isNotEmpty &&
        c.id.length <= ChatCitation.maxIdLength)
      c,
];
