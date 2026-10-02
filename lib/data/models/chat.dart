import 'package:freezed_annotation/freezed_annotation.dart';

import 'syncable.dart';

part 'chat.freezed.dart';
part 'chat.g.dart';

/// What a chat is about (`chats.scope_type`). Fixed at creation.
enum ChatScopeType {
  @JsonValue('subject')
  subject,
  @JsonValue('note')
  note,
  @JsonValue('attachment')
  attachment,

  /// No source (`scope_id` is null).
  @JsonValue('general')
  general;

  String get wireName => name;
}

/// Author of a chat message (`chat_messages.role`).
enum ChatRole {
  @JsonValue('user')
  user,
  @JsonValue('assistant')
  assistant,
  @JsonValue('system')
  system;

  String get wireName => name;
}

/// Row of `public.chats`: a private AI chat of the current user (never
/// shared), optionally about a subject / note / attachment ([scopeId] is
/// null iff [scopeType] is [ChatScopeType.general]).
@freezed
abstract class Chat with _$Chat implements Syncable {
  const factory Chat({
    required String id,
    required String ownerId,
    @JsonKey(unknownEnumValue: ChatScopeType.general)
    @Default(ChatScopeType.general)
    ChatScopeType scopeType,
    String? scopeId,
    @Default('') String title,

    /// AI provider (`LlmProviderId.wireName`) and model used.
    String? provider,
    String? model,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Chat;

  factory Chat.fromJson(Map<String, dynamic> json) => _$ChatFromJson(json);

  /// Server limits (CHECK constraints).
  static const int maxTitleLength = 500;
  static const int maxProviderLength = 255;
}

/// A source cited by an assistant message (`chat_messages.citations[]`).
///
/// [type] is free text (1..64 chars; suggested `subject`, `note`,
/// `attachment`, `quiz`, `deck`, `web`), [id] the cited row's uuid (or a
/// URL for `web`, 1..255 chars).
@freezed
abstract class ChatCitation with _$ChatCitation {
  const factory ChatCitation({
    required String type,
    required String id,
    @Default('') String title,
    String? snippet,
  }) = _ChatCitation;

  factory ChatCitation.fromJson(Map<String, dynamic> json) =>
      _$ChatCitationFromJson(json);

  static const int maxTypeLength = 64;
  static const int maxIdLength = 255;
}

/// Row of `public.chat_messages` (same owner as its chat). Ordered by
/// [createdAt], then [id].
@freezed
abstract class ChatMessage with _$ChatMessage implements Syncable {
  const factory ChatMessage({
    required String id,
    required String chatId,
    required String ownerId,
    @JsonKey(unknownEnumValue: ChatRole.system) required ChatRole role,
    @Default('') String content,
    @Default(<ChatCitation>[]) List<ChatCitation> citations,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  /// Server limit on [content] (CHECK constraint).
  static const int maxContentLength = 200000;
}
