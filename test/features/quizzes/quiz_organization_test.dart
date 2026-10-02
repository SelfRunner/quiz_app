import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/utils/file_opener.dart';
import 'package:quiz_app/core/utils/file_saver.dart';
import 'package:quiz_app/core/widgets/tag_widgets.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';
import 'package:quiz_app/features/quizzes/application/quiz_io_actions.dart';
import 'package:quiz_app/features/quizzes/widgets/quiz_import_dialog.dart';
import 'package:quiz_app/features/quizzes/widgets/quiz_list_section.dart';
import 'package:quiz_app/io/quiz_io.dart';

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

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _q1 = Question(
  id: 'a',
  type: QuestionType.mcqSingle,
  prompt: 'Largest planet?',
  options: ['Mars', 'Jupiter'],
  correctIndices: [1],
  explanation: 'Gas giant',
);
const _q2 = Question(
  id: 'b',
  type: QuestionType.shortAnswer,
  prompt: 'Closest star?',
  answerText: 'The Sun',
);

Widget _section(_Env env, {String? noteId, bool readOnly = false}) => env.app(
  '/',
  home: Scaffold(
    body: SingleChildScrollView(
      child: QuizListSection(
        subjectId: 's1',
        noteId: noteId,
        readOnly: readOnly,
      ),
    ),
  ),
);

const _csv =
    'type,prompt,options,correct,answer,explanation\n'
    'single,Largest planet?,Mars|Jupiter,2,,\n'
    'single,No options?,,1,,\n'
    'short,Closest star?,,,The Sun,\n'
    ',,,,,\n'
    'multi,Pick primes,2|3|4,9,,\n';

void main() {
  group('quiz organization', () {
    testWidgets('detail screen shows tags, pins and edits tags (owner)', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.org.tags.add(const TagCount('astronomy', 3));
      env.quizzes.add(
        quiz('q1', [_q1], title: 'Planets').copyWith(tags: ['space']),
      );
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tag-chip-space')), findsOneWidget);
      expect(find.text('#space'), findsOneWidget);

      await tester.tap(find.byTooltip('Pin'));
      await tester.pumpAndSettle();
      expect(env.org.calls, ['setPinned:quiz:q1:true']);
      expect(find.byTooltip('Unpin'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quiz-tags-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'astro');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-option-astronomy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-dialog-save')));
      await tester.pumpAndSettle();
      expect(env.org.calls.last, 'setTags:quiz:q1:space|astronomy');
      expect(find.byKey(const ValueKey('tag-chip-astronomy')), findsOneWidget);
    });

    testWidgets('shared quizzes show tags and export, but no pin / edit', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.quizzes.add(
        quiz('q1', [_q1], owner: 'other').copyWith(tags: ['space']),
      );
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();
      expect(find.text('#space'), findsOneWidget);
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(find.byTooltip('Pin'), findsNothing);
      expect(find.byKey(const Key('quiz-tags-button')), findsNothing);
    });

    testWidgets('QuizListSection lists pinned quizzes first with tags', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.quizzes
        ..add(quiz('q1', [_q1], title: 'Alpha'))
        ..add(
          quiz(
            'q2',
            [_q1],
            title: 'Beta',
            noteId: 'n1',
          ).copyWith(pinned: true, tags: ['exam', 'hard']),
        );
      await tester.pumpWidget(_section(env));
      await tester.pumpAndSettle();

      final beta = tester.getTopLeft(find.byKey(const ValueKey('quiz-row-q2')));
      final alpha = tester.getTopLeft(
        find.byKey(const ValueKey('quiz-row-q1')),
      );
      expect(beta.dy, lessThan(alpha.dy));
      expect(find.byKey(const ValueKey('quiz-pinned-q2')), findsOneWidget);
      expect(find.byKey(const ValueKey('quiz-pinned-q1')), findsNothing);
      expect(find.text('#exam'), findsOneWidget);
      expect(find.text('#hard'), findsOneWidget);
      expect(pinnedQuizzesFirst(env.quizzes.all).first.id, 'q2');
    });
  });

  group('quiz export', () {
    testWidgets('JSON and CSV exports save the expected bytes', (tester) async {
      _tall(tester);
      final env = _Env();
      final q = env.quizzes.add(
        quiz('q1', [_q1, _q2], title: 'Space: basics').copyWith(tags: ['x']),
      );
      await tester.pumpWidget(env.app('/quizzes/q1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-quiz-json')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-quiz-csv')));
      await tester.pumpAndSettle();

      final [json, csv] = env.saver.saved;
      expect(json.name, 'Space basics.json');
      expect(json.mimeType, 'application/json');
      expect(utf8.decode(json.bytes), quizToJson(q));
      final round = importQuizJson(utf8.decode(json.bytes));
      expect(round.errors, isEmpty);
      expect(round.items, [_q1, _q2]);
      expect(round.title, 'Space: basics');
      expect(csv.name, 'Space basics.csv');
      expect(csv.mimeType, 'text/csv');
      expect(utf8.decode(csv.bytes), quizToCsv(q));
      expect(
        utf8.decode(csv.bytes),
        startsWith('type,prompt,options,correct,answer,explanation'),
      );
      expect(find.text('Exported "Space basics.csv"'), findsOneWidget);
    });
  });

  group('quiz import', () {
    testWidgets('preview lists questions and skipped lines; cancel is a no-op', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.opener.text('Planets.csv', _csv);
      await tester.pumpWidget(_section(env));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiz-import')));
      await tester.pumpAndSettle();
      expect(env.opener.lastExtensions, ['json', 'csv']);
      expect(find.byType(QuizImportPreviewDialog), findsOneWidget);

      final result = importQuizCsv(_csv);
      expect(result.items, hasLength(2));
      expect(result.errors, isNotEmpty);
      expect(
        find.text(
          '2 questions ready · '
          '${result.errors.length} problem${result.errors.length == 1 ? '' : 's'} skipped',
        ),
        findsOneWidget,
      );
      for (final e in result.errors) {
        expect(e.line, isNotNull);
        expect(find.text(QuizImportPreviewDialog.issueText(e)), findsOneWidget);
      }
      expect(
        find.textContaining(RegExp(r'^Line 3\b')),
        findsWidgets,
        reason: 'the row without options is reported by its line',
      );
      expect(find.text('1. Largest planet?'), findsOneWidget);
      expect(find.text('Answer: Jupiter'), findsOneWidget);
      expect(find.text('2. Closest star?'), findsOneWidget);
      expect(find.text('Answer: The Sun'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(QuizImportPreviewDialog), findsNothing);
      expect(env.quizzes.all, isEmpty);

      // Picker cancelled: no dialog.
      env.opener.next = null;
      await tester.tap(find.byKey(const Key('quiz-import')));
      await tester.pumpAndSettle();
      expect(find.byType(QuizImportPreviewDialog), findsNothing);
    });

    testWidgets('a file without valid questions cannot be imported', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.opener.text('broken.json', '{"quiz": ');
      await tester.pumpWidget(_section(env));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiz-import')));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 questions ready'), findsOneWidget);
      expect(find.byKey(QuizImportPreviewDialog.errorsKey), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.byKey(QuizImportPreviewDialog.confirmKey),
      );
      expect(confirm.onPressed, isNull);
    });

    testWidgets('confirm creates the quiz in the note with the chosen title, '
        'tags from the file, and opens it', (tester) async {
      _tall(tester);
      final env = _Env();
      final source = quiz(
        'orig',
        [_q1, _q2],
        title: 'Exported title',
      ).copyWith(description: 'From JSON', tags: ['space']);
      env.opener.text('export.json', quizToJson(source));
      await tester.pumpWidget(_section(env, noteId: 'n1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiz-import')));
      await tester.pumpAndSettle();
      expect(find.text('2 questions ready'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(QuizImportPreviewDialog.titleKey),
      );
      expect(field.controller!.text, 'Exported title');

      // Empty title disables import.
      await tester.enterText(find.byKey(QuizImportPreviewDialog.titleKey), ' ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(QuizImportPreviewDialog.confirmKey),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(QuizImportPreviewDialog.titleKey),
        '  My planets ',
      );
      await tester.pump();
      await tester.tap(find.byKey(QuizImportPreviewDialog.confirmKey));
      await tester.pumpAndSettle();

      final created = env.quizzes.all.single;
      expect(created.title, 'My planets');
      expect(created.subjectId, 's1');
      expect(created.noteId, 'n1');
      expect(created.description, 'From JSON');
      expect(created.questions, [_q1, _q2]);
      expect(created.id, isNot('orig'));
      expect(env.org.calls, ['setTags:quiz:${created.id}:space']);
      expect(created.tags, ['space']);
      // Navigated to the new quiz's detail screen.
      expect(find.text('My planets'), findsWidgets);
      expect(find.byKey(const Key('play-quiz')), findsOneWidget);
    });

    testWidgets('import is hidden when read-only', (tester) async {
      _tall(tester);
      final env = _Env();
      await tester.pumpWidget(_section(env, readOnly: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quiz-import')), findsNothing);
    });

    test('parseQuizFile picks the format; title falls back to the file', () {
      var n = 0;
      String id() => 'x${n++}';
      final csv = parseQuizFile('a.csv', _csv, newId: id);
      expect(csv.items, hasLength(2));
      final json = parseQuizFile(
        'a.txt',
        '[{"type":"short_answer","prompt":"P","answer_text":"A"}]',
        newId: id,
      );
      expect(json.items.single.prompt, 'P');
      expect(suggestedQuizTitle('Chapter 1.csv', csv), 'Chapter 1');
      expect(suggestedQuizTitle('.csv', csv), '.csv');
      expect(
        suggestedQuizTitle(
          'x.json',
          importQuizJson(quizToJson(quiz('q', [_q1]))),
        ),
        'Sample quiz',
      );
      expect(userId, isNotEmpty);
    });
  });
}
