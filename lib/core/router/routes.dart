import '../../features/ai_generate/presentation/ai_generate_screen.dart';

/// Route paths and location builders. Always navigate with these helpers,
/// e.g. `context.push(AppRoutes.note(id))`.
abstract final class AppRoutes {
  static const String login = '/login';
  static const String signup = '/signup';
  static const String subjects = '/';
  static const String home = '/home';
  static const String study = '/study';
  static const String mistakes = '/mistakes';
  static const String chats = '/chats';
  static const String search = '/search';
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
  /// `mode`: null/practice, `exam` (time limit + pool, feedback at end) or
  /// `mistakes` (only open mistakes of this quiz).
  static String quizPlay(String id, {String? mode}) =>
      mode == null ? '/quizzes/$id/play' : '/quizzes/$id/play?mode=$mode';
  static String chat(String id) => '/chats/$id';
  static String searchFor(String query) =>
      Uri(path: search, queryParameters: {'q': query}).toString();
  static String deck(String id) => '/decks/$id';
  static String deckEdit(String id) => '/decks/$id/edit';
  static String deckStudy(String id) => '/decks/$id/study';

  /// `/ai/generate?kind=quiz|note|deck&subjectId=..&noteId=..`
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
