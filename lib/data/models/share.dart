import 'package:freezed_annotation/freezed_annotation.dart';

import 'profile.dart';

part 'share.freezed.dart';
part 'share.g.dart';

enum ShareResourceType {
  @JsonValue('subject')
  subject,
  @JsonValue('note')
  note,
  @JsonValue('quiz')
  quiz,

  /// Flashcard deck (Wave 2).
  @JsonValue('deck')
  deck;

  String get wireName => name;
}

/// Row of `public.shares` (view-only share of one resource with one user).
/// Unique per (resource_type, resource_id, recipient_id). Online-only: not
/// part of the outbox; created/revoked directly against Supabase.
@freezed
abstract class Share with _$Share {
  const factory Share({
    required String id,
    required String ownerId,
    required String recipientId,
    required ShareResourceType resourceType,
    required String resourceId,
    required DateTime createdAt,

    /// Joined profile of the recipient (select alias `recipient`), if loaded.
    @JsonKey(includeToJson: false) Profile? recipient,

    /// Joined profile of the owner (select alias `owner`), if loaded.
    @JsonKey(includeToJson: false) Profile? owner,

    /// Title of the shared resource, if the query joined it (UI convenience).
    @JsonKey(includeToJson: false) String? resourceTitle,
  }) = _Share;

  factory Share.fromJson(Map<String, dynamic> json) => _$ShareFromJson(json);
}
