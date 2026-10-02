import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/repositories/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

void main() {
  test(
    'explicit signOut: final push, sign-out, then local wipe hook',
    () async {
      // No session: signing out is purely local (no network request).
      final client = sb.SupabaseClient(
        'http://localhost:9',
        'anon-key',
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final calls = <String>[];
      final repo = SupabaseAuthRepository(
        client,
        beforeSignOut: () async => calls.add('before'),
        afterSignOut: () async =>
            calls.add('after (signed in: ${client.auth.currentUser != null})'),
      );

      await repo.signOut();

      expect(calls, ['before', 'after (signed in: false)']);
    },
  );

  test('a failing wipe hook does not fail signOut', () async {
    final client = sb.SupabaseClient(
      'http://localhost:9',
      'anon-key',
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final repo = SupabaseAuthRepository(
      client,
      afterSignOut: () async => throw StateError('disk full'),
    );
    await repo.signOut();
  });
}
