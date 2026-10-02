import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/router/routes.dart';
import 'package:quiz_app/core/utils/file_opener.dart';
import 'package:quiz_app/core/utils/file_saver.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/quizzes/widgets/quiz_import_dialog.dart';
import 'package:quiz_app/features/quizzes/widgets/quiz_list_section.dart';

import '../search/support/org_fakes.dart';
import 'support/fakes.dart';

class _Env extends TestEnv {
  _Env() {
    org.onItem = (kind, id, {tags, pinned}) {
      final q = quizzes.all.firstWhere((q) => q.id == id);
      quizzes.add(q.copyWith(tags: tags ?? q.tags, pinned: pinned ?? q.pinned));
    };
  }

  final org = FakeOrganizationRepository();
  final opener = FakeFileOpener();
  final saver = FakeFileSaver();

  @override
  List<Override> get extraOverrides => [
    organizationRepositoryProvider.overrideWithValue(org),
    fileOpenerProvider.overrideWithValue(opener),
    fileSaverProvider.overrideWithValue(saver),
  ];
}

const _phone = Size(360, 740);
const _laptop = Size(800, 600);
const _desktop = Size(1440, 900);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _mcq = Question(
  id: 'mcq',
  type: QuestionType.mcqSingle,
  prompt: 'Largest planet?',
  options: ['Mars', 'Jupiter', 'Venus'],
  correctIndices: [1],
  explanation: 'Gas giant.',
);
const _tf = Question(
  id: 'tf',
  type: QuestionType.trueFalse,
  prompt: 'Pluto is a planet.',
  options: ['True', 'False'],
  correctIndices: [1],
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// [finder]'s box lies inside the screen.
void _expectOnScreen(WidgetTester tester, Finder finder, {String? reason}) {
  final screen = Offset.zero & tester.view.physicalSize;
  final rect = tester.getRect(finder);
  expect(
    screen.inflate(0.5).contains(rect.topLeft) &&
        screen.inflate(0.5).contains(rect.bottomRight),
    isTrue,
    reason: '${reason ?? finder} at $rect is off screen $screen',
  );
}

/// The visible surface of the open dialog (the `Dialog` widget itself
/// fills the screen around it).
final _dialogSurface = find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

Rect _dialogRect(WidgetTester tester) => tester.getRect(_dialogSurface);

/// Edit screen is showing.
void _expectEditor() {
  expect(find.byKey(const Key('quiz-title')), findsOneWidget);
  expect(find.text('Edit quiz'), findsOneWidget);
}

void main() {
  group('edit discoverability', () {
    for (final size in const [_phone, _desktop]) {
      testWidgets('owner sees a labelled Edit questions button next to Play '
          '(${size.width.toInt()} wide)', (tester) async {
        _size(tester, size);
        final env = _Env()..quizzes.add(quiz('q1', [_mcq, _tf]));
        await tester.pumpWidget(env.app('/quizzes/q1'));
        await tester.pumpAndSettle();

        final edit = find.byKey(const Key('edit-questions'));
        expect(edit, findsOneWidget);
        expect(
          find.descendant(of: edit, matching: find.text('Edit questions')),
          findsOneWidget,
        );
        _expectOnScreen(tester, edit);
        // Next to Play, on the same row.
        final play = tester.getRect(find.byKey(const Key('play-quiz')));
        final editRect = tester.getRect(edit);
        expect((editRect.center.dy - play.center.dy).abs(), lessThan(1));
        expect(editRect.left, greaterThan(play.right));
        expect(tester.takeException(), isNull);

        await _tap(tester, edit);
        _expectEditor();
      });
    }

    testWidgets('empty quiz offers Add questions', (tester) async {
      final env = _Env()..quizzes.add(quiz('q1', const []));
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('edit-questions')),
          matching: find.text('Add questions'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shared quiz: no edit button, menu entry or row action', (
      tester,
    ) async {
      _size(tester, _phone);
      final env = _Env()..quizzes.add(quiz('q1', [_mcq], owner: 'other'));
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-questions')), findsNothing);
      expect(find.byKey(const Key('quiz-edit-action')), findsNothing);
      expect(find.byKey(const Key('quiz-more')), findsNothing);
      expect(find.byKey(const Key('play-quiz')), findsOneWidget);

      await tester.pumpWidget(
        env.app(
          '/',
          home: const Scaffold(
            body: SingleChildScrollView(
              child: QuizListSection(subjectId: 's1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quiz-row-q1')), findsOneWidget);
      expect(find.byKey(const ValueKey('quiz-row-menu-q1')), findsNothing);
    });

    testWidgets('More menu has Edit quiz', (tester) async {
      _size(tester, _desktop);
      final env = _Env()..quizzes.add(quiz('q1', [_mcq]));
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('quiz-more')));
      expect(find.text('Edit quiz'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('quiz-more-edit')));
      _expectEditor();
    });

    testWidgets('phone app bar: Share and Edit visible; pin, export, tags and '
        'delete live in More', (tester) async {
      _size(tester, _phone);
      final env = _Env()..quizzes.add(quiz('q1', [_mcq], title: 'Planets'));
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Share'), findsOneWidget);
      expect(find.byTooltip('Edit quiz'), findsOneWidget);
      expect(find.byTooltip('Pin'), findsNothing);
      expect(find.byTooltip('Export'), findsNothing);
      expect(tester.takeException(), isNull);

      await _tap(tester, find.byKey(const Key('quiz-more')));
      for (final label in [
        'Edit quiz',
        'Pin',
        'Export JSON (.json)',
        'Export CSV (.csv)',
        'Edit tags',
        'Delete quiz',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await _tap(tester, find.text('Pin'));
      expect(env.org.calls, ['setPinned:quiz:q1:true']);

      await _tap(tester, find.byKey(const Key('quiz-more')));
      expect(find.text('Unpin'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('export-quiz-json')));
      expect(env.saver.saved.single.name, 'Planets.json');
    });

    testWidgets('wide app bar keeps pin and export icons', (tester) async {
      _size(tester, _laptop);
      final env = _Env()..quizzes.add(quiz('q1', [_mcq]));
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin'), findsOneWidget);
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(find.byTooltip('Edit quiz'), findsOneWidget);
    });

    testWidgets('quiz list row menu opens the editor', (tester) async {
      _size(tester, _phone);
      final env = _Env()..quizzes.add(quiz('q1', [_mcq], title: 'Planets'));
      await tester.pumpWidget(
        env.app(
          '/',
          home: const Scaffold(
            body: SingleChildScrollView(
              child: QuizListSection(subjectId: 's1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('quiz-row-menu-q1')));
      expect(find.text('Edit questions'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('quiz-row-edit-q1')));
      _expectEditor();
    });

    testWidgets('read-only list hides the row menu', (tester) async {
      final env = _Env()..quizzes.add(quiz('q1', [_mcq]));
      await tester.pumpWidget(
        env.app(
          '/',
          home: const Scaffold(
            body: SingleChildScrollView(
              child: QuizListSection(subjectId: 's1', readOnly: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quiz-row-menu-q1')), findsNothing);
    });

    testWidgets('justCreated shows "Quiz saved" with an Edit action', (
      tester,
    ) async {
      expect(AppRoutes.quiz('q1'), '/quizzes/q1');
      expect(
        AppRoutes.quiz('q1', justCreated: true),
        '/quizzes/q1?justCreated=1',
      );
      final env = _Env()..quizzes.add(quiz('q1', [_mcq]));
      await tester.pumpWidget(env.app(AppRoutes.quiz('q1', justCreated: true)));
      await tester.pumpAndSettle();
      expect(find.text('Quiz saved'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('quiz-saved-edit')));
      _expectEditor();
    });

    testWidgets('no snackbar without justCreated', (tester) async {
      final env = _Env()..quizzes.add(quiz('q1', [_mcq]));
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();
      expect(find.text('Quiz saved'), findsNothing);
    });

    testWidgets('practice results link to Edit questions (owner only)', (
      tester,
    ) async {
      _size(tester, _phone);
      final env = _Env()
        ..quizzes.add(quiz('q1', [_tf]))
        ..quizzes.add(quiz('q2', [_tf], owner: 'other'));

      Future<void> playToResults(String id) async {
        await tester.pumpWidget(env.app('/quizzes/$id/play'));
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(const Key('start-quiz')));
        await _tap(tester, find.byKey(const Key('option-1')));
        await _tap(tester, find.byKey(const Key('primary-action')));
        await _tap(tester, find.byKey(const Key('primary-action')));
        expect(find.byKey(const Key('result-percent')), findsOneWidget);
      }

      await playToResults('q2');
      expect(find.byKey(const Key('results-edit-questions')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await playToResults('q1');
      await _tap(tester, find.byKey(const Key('results-edit-questions')));
      _expectEditor();
    });

    testWidgets('exam results link to Edit questions', (tester) async {
      _size(tester, _desktop);
      final env = _Env()..quizzes.add(quiz('q1', [_tf]));
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('exam-quiz')));
      await _tap(tester, find.byKey(const Key('start-exam')));
      await _tap(tester, find.byKey(const Key('option-1')));
      await _tap(tester, find.byKey(const Key('exam-finish')));
      await _tap(tester, find.byKey(const Key('confirm-submit')));
      expect(find.byKey(const Key('exam-results')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('results-edit-questions')));
      _expectEditor();
    });
  });

  group('dialog sizing', () {
    for (final size in const [_phone, _laptop, _desktop]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('question editor fits and keeps Done visible ($label)', (
        tester,
      ) async {
        _size(tester, size);
        final env = _Env()
          ..quizzes.add(
            quiz('q1', [
              const Question(
                id: 's',
                type: QuestionType.shortAnswer,
                prompt: 'Short?',
                answerText: 'Yes',
              ),
              _mcq,
            ]),
          );
        await tester.pumpWidget(env.app('/quizzes/q1/edit'));
        await tester.pumpAndSettle();

        // Short form: a content-sized dialog on wide screens.
        await _tap(tester, find.byTooltip('Edit question').first);
        expect(find.text('Edit question'), findsOneWidget);
        final done = find.byKey(const Key('question-editor-save'));
        _expectOnScreen(tester, done);
        expect(tester.takeException(), isNull);
        final dialog = find.byKey(const Key('question-editor-dialog'));
        if (size.width >= 720) {
          expect(dialog, findsOneWidget);
          final rect = _dialogRect(tester);
          expect(rect.width, lessThanOrEqualTo(720));
          expect(rect.height, lessThanOrEqualTo(size.height * 0.85 + 0.5));
          if (size.height >= 900) {
            // Room to spare: the dialog shrink-wraps the short form.
            expect(rect.height, lessThan(size.height * 0.85 - 1));
          }
        } else {
          expect(dialog, findsNothing);
          expect(find.byType(Dialog), findsNothing, reason: 'full screen');
        }
        await _tap(tester, find.byTooltip('Cancel'));
        expect(find.text('Edit question'), findsNothing);

        // Long form: capped, scrolls inside, Done stays visible.
        await _tap(tester, find.byTooltip('Edit question').at(1));
        _expectOnScreen(tester, done);
        if (size.width >= 720) {
          final rect = _dialogRect(tester);
          expect(rect.height, lessThanOrEqualTo(size.height * 0.85 + 0.5));
          _expectOnScreen(tester, _dialogSurface);
        }
        await tester.enterText(
          find.byKey(const Key('question-prompt')),
          'Biggest planet?',
        );
        await _tap(tester, done);
        expect(find.text('Biggest planet?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('exam setup and question grid fit ($label)', (tester) async {
        _size(tester, size);
        final questions = [
          for (var i = 0; i < 80; i++)
            Question(
              id: 'q$i',
              type: QuestionType.trueFalse,
              prompt: 'Statement $i',
              options: const ['True', 'False'],
              correctIndices: const [0],
            ),
        ];
        final env = _Env()..quizzes.add(quiz('q1', questions));
        await tester.pumpWidget(env.app('/quizzes/q1'));
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(const Key('exam-quiz')));
        expect(find.text('Exam mode'), findsOneWidget);
        _expectOnScreen(tester, _dialogSurface);
        _expectOnScreen(tester, find.byKey(const Key('start-exam')));
        expect(tester.takeException(), isNull);
        await _tap(tester, find.byKey(const Key('start-exam')));
        expect(find.text('Question 1 of 80'), findsOneWidget);

        final button = find.byKey(const Key('exam-grid-button'));
        if (size.width >= 1000) {
          // Side panel instead of a sheet.
          expect(button, findsNothing);
          expect(find.byKey(const Key('exam-cell-79')), findsOneWidget);
          return;
        }
        await _tap(tester, button);
        final panel = find.byKey(const Key('exam-grid-panel'));
        expect(panel, findsOneWidget);
        expect(find.byKey(const Key('exam-grid-scroll')), findsOneWidget);
        expect(find.text('Questions'), findsOneWidget);
        _expectOnScreen(tester, panel);
        expect(find.textContaining('Unanswered'), findsOneWidget);
        _expectOnScreen(tester, find.textContaining('Unanswered'));
        expect(tester.takeException(), isNull);
        if (size.width >= 720) {
          final rect = _dialogRect(tester);
          expect(rect.width, lessThanOrEqualTo(480));
          expect(rect.height, lessThanOrEqualTo(size.height * 0.8 + 0.5));
        } else {
          expect(
            tester.getRect(find.byType(BottomSheet)).height,
            lessThanOrEqualTo(size.height * 0.85 + 0.5),
          );
        }
        // The last cell scrolls into reach and jumps there.
        await _tap(tester, find.byKey(const Key('exam-cell-79')));
        expect(find.text('Question 80 of 80'), findsOneWidget);
      });

      testWidgets('explain panel is content-sized ($label)', (tester) async {
        _size(tester, size);
        final env = _Env()..quizzes.add(quiz('q1', [_tf]));
        await tester.pumpWidget(env.app('/quizzes/q1/play'));
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(const Key('start-quiz')));
        await _tap(tester, find.byKey(const Key('option-1')));
        await _tap(tester, find.byKey(const Key('primary-action')));
        await _tap(tester, find.byKey(const Key('primary-action')));
        await _tap(tester, find.byKey(const Key('explain-tf')).first);
        expect(find.byKey(const Key('explain-markdown')), findsOneWidget);
        final panel = find.byKey(const Key('explain-panel'));
        _expectOnScreen(tester, panel);
        expect(tester.takeException(), isNull);
        if (size.width >= 720) {
          final rect = _dialogRect(tester);
          expect(rect.width, lessThanOrEqualTo(640));
          expect(rect.height, lessThan(size.height * 0.6));
        } else {
          final sheet = tester.getRect(find.byType(BottomSheet));
          expect(sheet.height, lessThan(size.height * 0.6));
        }
      });

      testWidgets('import preview fits ($label)', (tester) async {
        _size(tester, size);
        final env = _Env();
        final rows = [
          'type,prompt,options,correct,answer,explanation',
          for (var i = 0; i < 40; i++) 'single,Question $i?,A|B|C,2,,',
          'single,No options?,,1,,',
        ];
        env.opener.text('Big.csv', rows.join('\n'));
        await tester.pumpWidget(
          env.app(
            '/',
            home: const Scaffold(
              body: SingleChildScrollView(
                child: QuizListSection(subjectId: 's1'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(const Key('quiz-import')));
        expect(find.byType(QuizImportPreviewDialog), findsOneWidget);
        _expectOnScreen(tester, _dialogSurface);
        _expectOnScreen(tester, find.byKey(QuizImportPreviewDialog.confirmKey));
        expect(_dialogRect(tester).width, lessThanOrEqualTo(640));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
