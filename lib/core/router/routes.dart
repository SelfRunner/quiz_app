import '../../features/ai_generate/presentation/ai_generate_screen.dart';

/// Route paths and location builders. Always navigate with these helpers,
/// e.g. `context.push(AppRoutes.note(id))`.
abstract final class AppRoutes {
  static const String login = '/login';
  static const String signup = '/signup';
  static const String subjects = '/';
  static const String shared = '/shared';
  static const String settings = '/settings';
  static const String aiGenerate = '/ai/generate';

  /// Routes reachable without a session.
  static const Set<String> public = {login, signup};

  static String subject(String id) => '/subjects/$id';
  static String note(String id) => '/notes/$id';
  static String noteEdit(String id) => '/notes/$id/edit';
  static String quiz(String id) => '/quizzes/$id';
  static String quizEdit(String id) => '/quizzes/$id/edit';
  static String quizPlay(String id) => '/quizzes/$id/play';

  /// `/ai/generate?kind=quiz|note&subjectId=..&noteId=..`
  static String generate({
    required AiGenerateKind kind,
    String? subjectId,
    String? noteId,
  }) => Uri(
    path: aiGenerate,
    queryParameters: {
      'kind': kind.name,
      'subjectId': ?subjectId,
      'noteId': ?noteId,
    },
  ).toString();
}
