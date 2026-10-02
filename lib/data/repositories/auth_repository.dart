import '../models/app_user.dart';

/// Email/password authentication.
///
/// Errors: throws `AppAuthException` (bad credentials, email taken, ...) or
/// `NetworkException`.
abstract interface class AuthRepository {
  /// Signed-in user, or null.
  AppUser? get currentUser;

  /// Emits the current user immediately on listen, then on every change.
  Stream<AppUser?> authStateChanges();

  /// Creates an account. Depending on project settings the user may need to
  /// confirm the email before a session exists (then [currentUser] stays
  /// null).
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> signIn({required String email, required String password});

  /// Signs out. The data layer clears local Hive data for the user.
  Future<void> signOut();

  /// Sends a password reset email.
  Future<void> resetPassword(String email);
}
