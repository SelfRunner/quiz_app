import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/question.dart';
import 'package:quiz_app/features/quizzes/domain/question_rules.dart';
import 'package:quiz_app/features/quizzes/widgets/question_editor.dart';

/// Hosts the editor and captures what it returns.
class _Host extends StatefulWidget {
  const _Host(this.initial);

  final Question initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Question? result;
  bool closed = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async {
          final r = await showQuestionEditor(context, initial: widget.initial);
          setState(() {
            result = r;
            closed = true;
          });
        },
        child: const Text('open'),
      ),
    ),
  );
}

Future<_HostState> _open(WidgetTester tester, Question initial) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: _Host(initial)));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host));
}

Future<void> _done(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('question-editor-save')));
  await tester.pumpAndSettle();
}

void main() {
  group('validateQuestion', () {
    test('rules per type', () {
      final single = blankQuestion('a');
      expect(validateQuestion(single).prompt, QuestionMessages.prompt);
      expect(validateQuestion(single).choice, QuestionMessages.markOne);

      final ok = single.copyWith(
        prompt: 'P',
        options: ['x', 'y'],
        correctIndices: [0],
      );
      expect(validateQuestion(ok).isEmpty, isTrue);
      expect(
        validateQuestion(ok.copyWith(options: ['x', 'X'])).optionErrors[1],
        QuestionMessages.duplicateOption,
      );
      expect(
        validateQuestion(ok.copyWith(options: ['x'], correctIndices: [0]))
            .choice,
        QuestionMessages.tooFewOptions,
      );
      expect(
        validateQuestion(
          ok.copyWith(type: QuestionType.mcqSingle, correctIndices: [0, 1]),
        ).choice,
        QuestionMessages.markOne,
      );
      expect(
        validateQuestion(
          ok.copyWith(type: QuestionType.mcqMulti, correctIndices: []),
        ).choice,
        QuestionMessages.markAtLeastOne,
      );
      expect(
        validateQuestion(
          ok.copyWith(type: QuestionType.mcqMulti, correctIndices: [0, 1]),
        ).isEmpty,
        isTrue,
      );
      final short = blankQuestion(
        'b',
        type: QuestionType.shortAnswer,
      ).copyWith(prompt: 'Q');
      expect(validateQuestion(short).answer, QuestionMessages.answer);
      expect(
        validateQuestion(short.copyWith(answerText: ' A ')).isEmpty,
        isTrue,
      );
      final tf = blankQuestion(
        'c',
        type: QuestionType.trueFalse,
      ).copyWith(prompt: 'S', correctIndices: []);
      expect(validateQuestion(tf).choice, QuestionMessages.trueOrFalse);
    });

    test('normalizeQuestion trims and enforces shape', () {
      final q = normalizeQuestion(
        const Question(
          id: 'x',
          type: QuestionType.shortAnswer,
          prompt: '  Hi ',
          options: ['a'],
          correctIndices: [0],
          answerText: ' yes ',
          explanation: '  ',
        ),
      );
      expect(q.prompt, 'Hi');
      expect(q.options, isEmpty);
      expect(q.correctIndices, isEmpty);
      expect(q.answerText, 'yes');
      expect(q.explanation, isNull);
    });
  });

  group('QuestionEditor', () {
    testWidgets('single choice: inline errors, then saves', (tester) async {
      final host = await _open(tester, blankQuestion('q1'));
      await _done(tester);
      expect(find.text(QuestionMessages.prompt), findsOneWidget);
      expect(find.text(QuestionMessages.emptyOption), findsNWidgets(4));
      expect(find.text(QuestionMessages.markOne), findsOneWidget);
      expect(host.closed, isFalse);

      await tester.enterText(find.byKey(const Key('question-prompt')), 'Q?');
      await tester.enterText(find.byKey(const Key('question-option-0')), 'A');
      await tester.enterText(find.byKey(const Key('question-option-1')), 'a');
      // Remove the two trailing blank options.
      await tester.tap(find.byTooltip('Remove option').last);
      await tester.pump();
      await tester.tap(find.byTooltip('Remove option').last);
      await tester.pumpAndSettle();
      expect(find.text(QuestionMessages.prompt), findsNothing);
      expect(find.text(QuestionMessages.duplicateOption), findsOneWidget);
      // Can't go below two options.
      expect(
        tester
            .widget<IconButton>(
              find
                  .widgetWithIcon(IconButton, Icons.remove_circle_outline)
                  .first,
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byKey(const Key('question-option-1')), 'B');
      await tester.tap(find.byType(Radio<int>).at(1));
      await tester.pump();
      await _done(tester);

      expect(host.closed, isTrue);
      expect(host.result!.type, QuestionType.mcqSingle);
      expect(host.result!.prompt, 'Q?');
      expect(host.result!.options, ['A', 'B']);
      expect(host.result!.correctIndices, [1]);
    });

    testWidgets('multiple choice needs at least one correct option', (
      tester,
    ) async {
      final host = await _open(tester, blankQuestion('q1'));
      await tester.tap(find.text('Multiple choice'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('question-prompt')), 'Q?');
      for (var i = 0; i < 4; i++) {
        await tester.enterText(find.byKey(Key('question-option-$i')), 'opt $i');
      }
      await _done(tester);
      expect(find.text(QuestionMessages.markAtLeastOne), findsOneWidget);

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      await _done(tester);
      expect(host.result!.type, QuestionType.mcqMulti);
      expect(host.result!.correctIndices, [0, 2]);
      expect(host.result!.options, hasLength(4));
    });

    testWidgets('true/false has fixed options', (tester) async {
      final host = await _open(tester, blankQuestion('q1'));
      await tester.tap(find.text('True / False'));
      await tester.pump();
      expect(find.byKey(const Key('question-option-0')), findsNothing);
      await _done(tester);
      expect(find.text(QuestionMessages.prompt), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('question-prompt')),
        'The sky is green.',
      );
      await tester.tap(find.text('False'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('question-explanation')),
        'It is blue.',
      );
      await _done(tester);
      expect(host.result!.type, QuestionType.trueFalse);
      expect(host.result!.options, ['True', 'False']);
      expect(host.result!.correctIndices, [1]);
      expect(host.result!.explanation, 'It is blue.');
    });

    testWidgets('short answer requires the expected answer', (tester) async {
      final host = await _open(tester, blankQuestion('q1'));
      await tester.tap(find.text('Short answer'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('question-prompt')), 'Q?');
      await _done(tester);
      expect(find.text(QuestionMessages.answer), findsOneWidget);

      await tester.enterText(find.byKey(const Key('question-answer')), '42');
      await tester.pumpAndSettle();
      expect(find.text(QuestionMessages.answer), findsNothing);
      await _done(tester);
      expect(host.result!.type, QuestionType.shortAnswer);
      expect(host.result!.answerText, '42');
      expect(host.result!.options, isEmpty);
    });

    testWidgets('switching types keeps choice options', (tester) async {
      final host = await _open(
        tester,
        const Question(
          id: 'q1',
          type: QuestionType.mcqMulti,
          prompt: 'Pick',
          options: ['a', 'b', 'c'],
          correctIndices: [0, 1],
        ),
      );
      await tester.tap(find.text('Short answer'));
      await tester.pump();
      await tester.tap(find.text('Single choice'));
      await tester.pump();
      await tester.tap(find.byType(Radio<int>).at(2));
      await tester.pump();
      await _done(tester);
      expect(host.result!.options, ['a', 'b', 'c']);
      expect(host.result!.correctIndices, [2]);
    });

    testWidgets('cancel with changes asks to discard', (tester) async {
      final host = await _open(tester, blankQuestion('q1'));
      await tester.enterText(find.byKey(const Key('question-prompt')), 'x');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(host.closed, isTrue);
      expect(host.result, isNull);
    });
  });
}
