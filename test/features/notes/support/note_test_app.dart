import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/ai_tools_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/notes/presentation/note_edit_screen.dart';
import 'package:quiz_app/features/notes/presentation/note_view_screen.dart';

import '../../subjects/support/fakes.dart';

/// Scriptable [AiToolsService] for note tool tests.
class FakeAiToolsService implements AiToolsService {
  final List<(String markdown, NoteTool tool)> calls = [];

  /// Result markdown per call; default `AI <tool>: <first line>`.
  String Function(String markdown, NoteTool tool)? respond;

  /// Error thrown by the next call (cleared after use).
  Object? nextError;

  /// When set, calls wait for it.
  Completer<void>? gate;

  bool truncated = false;

  @override
  Future<NoteToolResult> transformNote(
    String markdown,
    NoteTool tool, {
    String? title,
    String? language,
    String? extraInstructions,
    LlmProviderId? providerId,
    String? model,
  }) async {
    calls.add((markdown, tool));
    final gate = this.gate;
    if (gate != null) await gate.future;
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return NoteToolResult(
      markdown: respond?.call(markdown, tool) ?? '## AI ${tool.kind.name}',
      title: tool.kind == NoteToolKind.translate ? 'Células' : null,
      inputTruncated: truncated,
      selection: const AiSelection(
        providerId: LlmProviderId.gemini,
        model: 'test-model',
      ),
    );
  }

  @override
  Future<AiExplanation> explainAnswer(
    Question question,
    QuestionAnswer? userAnswer, {
    List<AiSource> sources = const [],
    String? language,
    LlmProviderId? providerId,
    String? model,
  }) => throw UnimplementedError();

  @override
  Future<ShortAnswerGrade> gradeShortAnswer(
    String question,
    String modelAnswer,
    String userAnswer, {
    String? language,
    LlmProviderId? providerId,
    String? model,
  }) => throw UnimplementedError();
}

/// Notes routes (view, edit, plus stubs for links) with fakes.
Widget noteTestApp(TestDeps deps, String initial, {FakeAiToolsService? tools}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/notes/:id',
        builder: (_, state) =>
            NoteViewScreen(noteId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) =>
                NoteEditScreen(noteId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/subjects/:id',
        builder: (_, state) => Text('subject ${state.pathParameters['id']}'),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(
        path: '/ai/generate',
        builder: (_, state) => Text(state.uri.toString()),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ...deps.overrides,
      aiToolsServiceProvider.overrideWithValue(tools ?? FakeAiToolsService()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Sets a logical window size for the test.
void setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
