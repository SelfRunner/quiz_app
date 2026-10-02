import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/data_providers.dart';
import '../../features/ai_generate/presentation/ai_generate_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/notes/presentation/note_edit_screen.dart';
import '../../features/notes/presentation/note_view_screen.dart';
import '../../features/quizzes/presentation/quiz_detail_screen.dart';
import '../../features/quizzes/presentation/quiz_edit_screen.dart';
import '../../features/quizzes/presentation/quiz_play_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/sharing/presentation/shared_with_me_screen.dart';
import '../../features/subjects/presentation/subject_detail_screen.dart';
import '../../features/subjects/presentation/subjects_screen.dart';
import 'app_shell.dart';
import 'routes.dart';

/// App router. Redirects to /login when signed out and away from auth
/// screens when signed in. Re-evaluated on every auth state change.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final refresh = _StreamListenable(auth.authStateChanges());
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.subjects,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = auth.currentUser != null;
      final onPublic = AppRoutes.public.contains(state.matchedLocation);
      if (!signedIn && !onPublic) return AppRoutes.login;
      if (signedIn && onPublic) return AppRoutes.subjects;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.subjects,
            builder: (context, state) => const SubjectsScreen(),
          ),
          GoRoute(
            path: AppRoutes.shared,
            builder: (context, state) => const SharedWithMeScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/subjects/:id',
        builder: (context, state) =>
            SubjectDetailScreen(subjectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notes/:id',
        builder: (context, state) =>
            NoteViewScreen(noteId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                NoteEditScreen(noteId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/quizzes/:id',
        builder: (context, state) =>
            QuizDetailScreen(quizId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                QuizEditScreen(quizId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'play',
            builder: (context, state) =>
                QuizPlayScreen(quizId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.aiGenerate,
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return AiGenerateScreen(
            kind: q['kind'] == AiGenerateKind.note.name
                ? AiGenerateKind.note
                : AiGenerateKind.quiz,
            subjectId: q['subjectId'],
            noteId: q['noteId'],
          );
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Adapts a stream to a [Listenable] for `GoRouter.refreshListenable`.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
