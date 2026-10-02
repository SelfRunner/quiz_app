import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';

/// The signed-in user, decoupled from the Supabase SDK type.
@freezed
abstract class AppUser with _$AppUser {
  const factory AppUser({
    required String id,
    String? email,
    String? displayName,
  }) = _AppUser;
}
