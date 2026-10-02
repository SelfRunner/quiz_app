import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/core/theme/app_theme.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/settings/presentation/settings_screen.dart';
import 'package:quiz_app/features/settings/presentation/widgets/ai_settings_section.dart';

import '../subjects/support/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester tester, TestDeps deps) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: deps.overrides,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
}

void main() {
  test('parseHeaderLines', () {
    expect(parseHeaderLines('A: 1\n\n X-Title :  Quiz '), {
      'A': '1',
      'X-Title': 'Quiz',
    });
    expect(() => parseHeaderLines('nocolon'), throwsFormatException);
  });

  testWidgets('saves the API key and model via ApiKeyStore', (tester) async {
    final deps = TestDeps(
      user: const AppUser(id: kUserId, email: 'ada@example.com'),
    );
    await _pump(tester, deps);
    expect(find.text('ada@example.com'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ai-api-key')), ' sk-test ');
    await tester.enterText(find.byKey(const Key('ai-model')), 'gemini-pro');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();

    expect(deps.keys.keys[LlmProviderId.gemini], 'sk-test');
    expect(deps.keys.models[LlmProviderId.gemini], 'gemini-pro');
    expect(deps.keys.selected, LlmProviderId.gemini);
    expect(find.text('Saved on this device'), findsOneWidget);
  });

  testWidgets('loads stored settings, tests the connection, clears the key', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.keys
      ..selected = LlmProviderId.openai
      ..keys[LlmProviderId.openai] = 'sk-old';
    await _pump(tester, deps);

    final keyField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('ai-api-key')),
        matching: find.byType(TextField),
      ),
    );
    expect(keyField.controller!.text, 'sk-old');
    expect(keyField.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('ai-test')));
    await tester.pumpAndSettle();
    expect(find.text('Connection works.'), findsOneWidget);

    deps.ai.testError = const AiException(
      'The API key was rejected.',
      kind: AiErrorKind.invalidApiKey,
    );
    await tester.tap(find.byKey(const Key('ai-test')));
    await tester.pumpAndSettle();
    expect(find.text('The API key was rejected.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-api-key-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(deps.keys.keys, isEmpty);
  });

  testWidgets('OpenAI-compatible shows base URL and headers', (tester) async {
    final deps = TestDeps();
    deps.keys.selected = LlmProviderId.openaiCompatible;
    await _pump(tester, deps);

    await tester.enterText(
      find.byKey(const Key('ai-base-url')),
      'http://localhost:11434/v1',
    );
    await tester.enterText(
      find.byKey(const Key('ai-headers')),
      'X-Title: Quiz',
    );
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();

    const p = LlmProviderId.openaiCompatible;
    expect(deps.keys.baseUrls[p], 'http://localhost:11434/v1');
    expect(deps.keys.headers[p], {'X-Title': 'Quiz'});
  });

  testWidgets('rejects an http:// base URL to a remote host', (tester) async {
    final deps = TestDeps();
    deps.keys.selected = LlmProviderId.openaiCompatible;
    await _pump(tester, deps);

    await tester.enterText(
      find.byKey(const Key('ai-base-url')),
      'http://api.example.com/v1',
    );
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Use https:// for remote servers'), findsOne);
    expect(deps.keys.baseUrls, isEmpty);
  });

  testWidgets('"Remove all saved keys" clears the current user', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.keys
      ..selected = LlmProviderId.openai
      ..keys[LlmProviderId.openai] = 'sk-old'
      ..keys[LlmProviderId.gemini] = 'g-old';
    await _pump(tester, deps);

    await tester.ensureVisible(find.byKey(const Key('ai-clear-all')));
    await tester.tap(find.byKey(const Key('ai-clear-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove all'));
    await tester.pumpAndSettle();

    expect(deps.keys.clearedUsers, [kUserId]);
    expect(deps.keys.keys, isEmpty);
    expect(find.text('All saved keys removed'), findsOneWidget);
    final keyField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('ai-api-key')),
        matching: find.byType(TextField),
      ),
    );
    expect(keyField.controller!.text, isEmpty);
  });

  bool supported(WidgetTester tester, String kind) =>
      tester.widget<CapabilityChip>(find.byKey(Key('ai-cap-$kind'))).supported;

  testWidgets('readiness banner and capability chips for the model', (
    tester,
  ) async {
    final deps = TestDeps();
    await _pump(tester, deps);
    final banner = find.byKey(const Key('ai-readiness'));
    expect(
      find.descendant(of: banner, matching: find.text('AI is not set up')),
      findsOneWidget,
    );
    // Gemini default model: everything.
    for (final k in ['text', 'pdf', 'image', 'audio', 'video', 'youtube']) {
      expect(supported(tester, k), isTrue, reason: k);
    }

    await tester.enterText(find.byKey(const Key('ai-api-key')), 'g-key');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: banner, matching: find.text('AI is ready')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Using ${LlmProviderId.gemini.displayName}'),
      findsOneWidget,
    );
  });

  testWidgets('OpenAI vision vs text-only models', (tester) async {
    final deps = TestDeps();
    deps.keys
      ..selected = LlmProviderId.openai
      ..keys[LlmProviderId.openai] = 'sk'
      ..models[LlmProviderId.openai] = 'gpt-4.1-mini';
    await _pump(tester, deps);
    expect(supported(tester, 'pdf'), isTrue);
    expect(supported(tester, 'image'), isTrue);
    expect(supported(tester, 'audio'), isFalse);
    expect(supported(tester, 'video'), isFalse);

    await tester.enterText(find.byKey(const Key('ai-model')), 'gpt-3.5-turbo');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(supported(tester, 'pdf'), isFalse);
    expect(supported(tester, 'image'), isFalse);
    expect(supported(tester, 'text'), isTrue);
  });

  testWidgets('OpenRouter capabilities come from model metadata', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.aiHttp.models['vendor/vision'] = ['text', 'image'];
    deps.keys
      ..selected = LlmProviderId.openaiCompatible
      ..keys[LlmProviderId.openaiCompatible] = 'or-key'
      ..models[LlmProviderId.openaiCompatible] = 'vendor/vision';
    await _pump(tester, deps);
    expect(supported(tester, 'image'), isTrue);
    expect(supported(tester, 'pdf'), isFalse);
    // OpenRouter is detected: no manual override.
    expect(find.byKey(const Key('ai-override-image')), findsNothing);
  });

  testWidgets('local endpoint: image / PDF override toggles', (tester) async {
    final deps = TestDeps();
    const p = LlmProviderId.openaiCompatible;
    deps.keys
      ..selected = p
      ..baseUrls[p] = 'http://localhost:11434/v1'
      ..models[p] = 'llava';
    await _pump(tester, deps);
    expect(supported(tester, 'image'), isFalse);

    await tester.ensureVisible(find.byKey(const Key('ai-override-image')));
    await tester.tap(find.byKey(const Key('ai-override-image')));
    await tester.pumpAndSettle();
    expect(deps.keys.overrides['openai_compatible/llava'], {AiInputKind.image});
    expect(supported(tester, 'image'), isTrue);
    expect(supported(tester, 'pdf'), isFalse);

    await tester.tap(find.byKey(const Key('ai-override-image')));
    await tester.pumpAndSettle();
    expect(deps.keys.overrides, isEmpty);
    expect(supported(tester, 'image'), isFalse);
  });

  testWidgets('theme mode and manual sync', (tester) async {
    final deps = TestDeps();
    final container = await _pump(tester, deps);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);

    await tester.tap(find.byKey(const Key('settings-sync')));
    await tester.pumpAndSettle();
    expect(deps.sync.syncCalls, 1);
  });
}
