import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors/app_exception.dart';
import '../models/app_user.dart';
import 'auth_repository.dart';

/// [AuthRepository] backed by Supabase Auth.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {this.beforeSignOut});

  final sb.SupabaseClient _client;

  /// Best-effort hook run before signing out (the data layer pushes pending
  /// changes, since local data is wiped on sign-out). Errors are ignored.
  final Future<void> Function()? beforeSignOut;

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
    await _guard(_client.auth.signOut);
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
