import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors/app_exception.dart';
import '../models/app_user.dart';
import 'auth_repository.dart';

/// [AuthRepository] backed by Supabase Auth.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {this.beforeSignOut, this.afterSignOut});

  final sb.SupabaseClient _client;

  /// Best-effort hook run before signing out (the data layer pushes pending
  /// changes, since local data is wiped on sign-out). Errors are ignored.
  final Future<void> Function()? beforeSignOut;

  /// Run after an explicit [signOut] once the session is gone (the data layer
  /// wipes user-scoped local data). Involuntary sign-outs (session expired /
  /// revoked) do not run it, so unsynced changes survive until the same user
  /// signs back in. Errors are ignored.
  final Future<void> Function()? afterSignOut;

  @override
  AppUser? get currentUser => _map(_client.auth.currentUser);

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield currentUser;
    yield* _client.auth.onAuthStateChange
        .map((state) => _map(state.session?.user))
        .distinct();
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) => _guard(
    () => _client.auth.signUp(
      email: email,
      password: password,
      data: {
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      },
    ),
  );

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _client.auth.signInWithPassword(email: email, password: password),
      );

  @override
  Future<void> signOut() async {
    final hook = beforeSignOut;
    if (hook != null) {
      try {
        await hook().timeout(const Duration(seconds: 10));
      } catch (_) {
        // Signing out must not be blocked by sync problems.
      }
    }
    try {
      await _guard(_client.auth.signOut);
    } finally {
      // The local session can be gone even if revoking it remotely failed.
      final hook = afterSignOut;
      if (hook != null && _client.auth.currentUser == null) {
        try {
          await hook();
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> resetPassword(String email) =>
      _guard(() => _client.auth.resetPasswordForEmail(email));

  static AppUser? _map(sb.User? user) {
    if (user == null) return null;
    final name = user.userMetadata?['display_name'];
    return AppUser(
      id: user.id,
      email: user.email,
      displayName: name is String ? name : null,
    );
  }

  static Future<void> _guard(Future<Object?> Function() body) async {
    try {
      await body();
    } on sb.AuthException catch (e, st) {
      throw AppAuthException(e.message, cause: e, stackTrace: st);
    } on TimeoutException catch (e, st) {
      throw NetworkException('Request timed out.', cause: e, stackTrace: st);
    } on AppException {
      rethrow;
    } catch (e, st) {
      throw NetworkException(
        'Could not reach the server.',
        cause: e,
        stackTrace: st,
      );
    }
  }
}
