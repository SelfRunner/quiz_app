import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/app.dart';
import 'package:quiz_app/core/router/app_router.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/auth_repository.dart';
import 'package:quiz_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:quiz_app/features/subjects/presentation/subjects_screen.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(this._user);

  AppUser? _user;
  final _controller = StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _user = AppUser(id: 'u1', email: email);
    _controller.add(_user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {}

  @override
  Future<void> resetPassword(String email) async {}
}

void main() {
  testWidgets('redirects to login when signed out and back after sign-in', (
    tester,
  ) async {
    final auth = _FakeAuth(null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: const QuizApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);

    await auth.signIn(email: 'a@b.c', password: 'x');
    await tester.pumpAndSettle();
    // Signed in on /login -> the dashboard (/home).
    final router = ProviderScope.containerOf(
      tester.element(find.byType(QuizApp)),
    ).read(routerProvider);
    expect(router.state.matchedLocation, '/home');
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Subjects'), findsWidgets);
    // Default test surface is 800px wide -> navigation rail.
    expect(find.byType(NavigationRail), findsOneWidget);

    // Auth screens keep redirecting to /home; '/' stays Subjects.
    router.go('/signup');
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/home');
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.byType(SubjectsScreen), findsOneWidget);
  });
}
