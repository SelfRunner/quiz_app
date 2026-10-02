import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// Row of `public.profiles` (1:1 with `auth.users`, created by trigger).
///
/// [email] may be null when the profile comes from `find_user_by_email`,
/// which only returns `id` and `display_name`.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    String? email,
    String? displayName,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}
