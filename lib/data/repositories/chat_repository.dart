import '../models/chat.dart';

/// The current user's private AI chats (local-first, synced, never shared).
///
/// Streams emit on listen and on every change; soft-deleted rows are
/// excluded. Chats are ordered by `updatedAt` desc (a chat is touched
/// whenever a message is saved), messages by `createdAt` asc (then id).
///
/// **Streaming answers**: create the assistant message with
/// `addMessage(..., draft: true)` (saved on this device only), update its
/// content with `updateMessage(m, finalize: false)` while tokens arrive
/// (local writes, no outbox traffic) and call `updateMessage(m)` (finalize)
/// once at the end, which queues a single upsert. A draft that is never
/// finalized (app killed mid-stream) stays local; [finalizeDrafts] pushes
/// leftovers.
abstract interface class ChatRepository {
  /// Every chat of the current user, `updatedAt` desc.
  Stream<List<Chat>> watchAll();

  /// Chats about one scope (`general` -> [scopeId] must be null),
  /// `updatedAt` desc.
  Stream<List<Chat>> watchByScope(ChatScopeType scopeType, String? scopeId);

  Stream<Chat?> watchById(String id);

  Future<Chat?> getById(String id);

  /// Messages of a chat, oldest first (drafts included).
  Stream<List<ChatMessage>> watchMessages(String chatId);

  Future<List<ChatMessage>> getMessages(String chatId);

  /// Creates a chat. The scope must be readable locally (own or shared
  /// subject / note / attachment; `NotFoundException` otherwise) and
  /// [scopeId] must be null iff [scopeType] is `general`
  /// (`ValidationException`). [title] is trimmed and cut to 500 chars.
  Future<Chat> create({
    required ChatScopeType scopeType,
    String? scopeId,
    String title = '',
    String? provider,
    String? model,
  });

  Future<Chat> rename(String chatId, String title);

  /// Changes the provider / model used for the next answers.
  Future<Chat> setModel(String chatId, {String? provider, String? model});

  /// Soft-deletes the chat and all of its messages.
  Future<void> delete(String chatId);

  /// Adds a message (content cut to 200 000 chars, invalid citations
  /// dropped). [draft] = saved locally only, pushed by [updateMessage]
  /// with `finalize: true`. Touches the chat's `updatedAt`.
  Future<ChatMessage> addMessage({
    required String chatId,
    required ChatRole role,
    String content = '',
    List<ChatCitation> citations = const [],
    bool draft = false,
  });

  /// Saves new [ChatMessage.content] / [ChatMessage.citations] (other
  /// fields are kept). [finalize] = false writes locally only (streaming);
  /// true also queues the upsert and touches the chat.
  Future<ChatMessage> updateMessage(
    ChatMessage message, {
    bool finalize = true,
  });

  /// Soft-deletes one message (e.g. before regenerating an answer).
  Future<void> deleteMessage(String messageId);

  /// Queues every local-only draft message (e.g. on app start). Returns how
  /// many were queued.
  Future<int> finalizeDrafts();
}
