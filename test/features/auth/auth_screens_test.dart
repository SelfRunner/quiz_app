import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/features/auth/application/auth_validators.dart';
import 'package:quiz_app/features/auth/presentation/login_screen.dart';
import 'package:quiz_app/features/auth/presentation/signup_screen.dart';

import '../subjects/support/fakes.dart';

Widget _app(FakeAuthRepository auth, Widget home) => ProviderScope(
  overrides: [authRepositoryProvider.overrideWithValue(auth)],
  child: MaterialApp(home: home),
);

void main() {
  group('AuthValidators', () {
    test('email', () {
      expect(AuthValidators.email(''), isNotNull);
      expect(AuthValidators.email('nope'), isNotNull);
      expect(AuthValidators.email(' a@b.co '), isNull);
    });

    test('new password needs length, letters and digits', () {
      expect(AuthValidators.newPassword('short1'), contains('at least'));
      expect(AuthValidators.newPassword('onlyletters'), isNotNull);
      expect(AuthValidators.newPassword('letters123'), isNull);
    });

    test('friendly messages', () {
      expect(
        friendlyAuthMessage(
          const AppAuthException('Invalid login credentials'),
        ),
        'Wrong email or password.',
      );
      expect(friendlyAuthMessage(StateError('x')), isNot(contains('x')));
    });
  });

  group('LoginScreen', () {
    testWidgets('validates fields before calling the repository', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(_app(auth, const LoginScreen()));

      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('login-email')), 'bad');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('signs in with trimmed email', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(_app(auth, const LoginScreen()));

      await tester.enterText(
        find.byKey(const Key('login-email')),
        ' me@example.com ',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('login-password')),
          matching: find.byType(TextField),
        ),
        'secret123',
      );
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn:me@example.com']);
    });

    testWidgets('shows a friendly error', (tester) async {
      final auth = FakeAuthRepository()
        ..error = const AppAuthException('Invalid login credentials');
      await tester.pumpWidget(_app(auth, const LoginScreen()));

      await tester.enterText(find.byKey(const Key('login-email')), 'a@b.co');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('login-password')),
          matching: find.byType(TextField),
        ),
        'x',
      );
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Wrong email or password.'), findsOneWidget);
    });

    testWidgets('forgot password dialog sends a reset link', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(_app(auth, const LoginScreen()));
      await tester.enterText(find.byKey(const Key('login-email')), 'a@b.co');

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();

      expect(auth.calls, ['reset:a@b.co']);
      expect(find.text('Check your email'), findsOneWidget);
    });
  });

  group('SignupScreen', () {
    Future<void> fill(
      WidgetTester tester, {
      String password = 'abc12345',
      String confirm = 'abc12345',
    }) async {
      await tester.enterText(find.byKey(const Key('signup-name')), 'Ada');
      await tester.enterText(find.byKey(const Key('signup-email')), 'a@b.co');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('signup-password')),
          matching: find.byType(TextField),
        ),
        password,
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('signup-confirm')),
          matching: find.byType(TextField),
        ),
        confirm,
      );
    }

    testWidgets('rejects mismatched passwords', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(_app(auth, const SignupScreen()));
      await fill(tester, confirm: 'different1');
      await tester.ensureVisible(find.byKey(const Key('signup-submit')));
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('asks to confirm email when sign-up returns no session', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(_app(auth, const SignupScreen()));
      await fill(tester);
      await tester.ensureVisible(find.byKey(const Key('signup-submit')));
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pumpAndSettle();

      expect(auth.calls, ['signUp:a@b.co:Ada']);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('a@b.co'), findsOneWidget);
    });
  });
}
