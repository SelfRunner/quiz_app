import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/draft_validator.dart';
import 'package:quiz_app/data/models/models.dart';

import 'test_helpers.dart';

Map<String, dynamic> quizWith(List<Map<String, dynamic>> questions) => {
  'title': 'T',
  'description': null,
  'questions': questions,
};

Map<String, dynamic> q(
  String type, {
  String prompt = 'What?',
  List<Object?> options = const [],
  List<Object?> correct = const [],
  String? answer,
}) => {
  'type': type,
  'prompt': prompt,
  'options': options,
  'correct_indices': correct,
  'answer_text': answer,
  'explanation': null,
};

void main() {
  group('validateQuiz', () {
    test('accepts a valid quiz and maps all fields', () {
      final r = DraftValidator.validateQuiz(validQuizJson(n: 3));
      expect(r.isValid, isTrue);
      expect(r.errors, isEmpty);
      final draft = r.value!;
      expect(draft.title, 'Cells');
      expect(draft.description, 'Basics of cells.');
      expect(draft.questions, hasLength(3));
      expect(draft.questions.first.type, QuestionType.mcqSingle);
      expect(draft.questions.first.correctIndices, [1]);
      expect(draft.questions.first.explanation, 'Because B0.');
    });

    test('accepts every question type', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q('mcq_single', prompt: 'a', options: ['x', 'y'], correct: [0]),
          q(
            'mcq_multi',
            prompt: 'b',
            options: ['x', 'y', 'z'],
            correct: [0, 2],
          ),
          q(
            'true_false',
            prompt: 'c',
            options: ['True', 'False'],
            correct: [1],
          ),
          q('short_answer', prompt: 'd', answer: 'Mitochondria'),
        ]),
      );
      expect(r.errors, isEmpty);
      expect(r.value!.questions.map((e) => e.type), [
        QuestionType.mcqSingle,
        QuestionType.mcqMulti,
        QuestionType.trueFalse,
        QuestionType.shortAnswer,
      ]);
      expect(r.value!.questions.last.answerText, 'Mitochondria');
    });

    test('rejects unknown type', () {
      final r = DraftValidator.validateQuiz(quizWith([q('essay')]));
      expect(r.value, isNull);
      expect(r.errors.first, contains('type'));
    });

    test('mcq_single needs exactly one correct index', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q('mcq_single', options: ['a', 'b', 'c'], correct: [0, 1]),
        ]),
      );
      expect(r.value, isNull);
      expect(r.errors.join(), contains('exactly 1'));
    });

    test('mcq_multi needs at least one correct index', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q('mcq_multi', options: ['a', 'b', 'c']),
        ]),
      );
      expect(r.errors.join(), contains('at least 1'));
    });

    test('indices out of range are rejected', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q('mcq_single', options: ['a', 'b'], correct: [2]),
        ]),
      );
      expect(r.errors.join(), contains('out of range'));
    });

    test('mcq needs >= 2 distinct, non-empty options', () {
      expect(
        DraftValidator.validateQuiz(
          quizWith([
            q('mcq_single', options: ['a'], correct: [0]),
          ]),
        ).errors.join(),
        contains('at least 2'),
      );
      expect(
        DraftValidator.validateQuiz(
          quizWith([
            q('mcq_single', options: ['a', 'A'], correct: [0]),
          ]),
        ).errors.join(),
        contains('duplicate'),
      );
    });

    test('true_false normalizes casing and reversed options', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q(
            'true_false',
            prompt: 'x',
            options: ['true', 'false'],
            correct: [0],
          ),
          q(
            'true_false',
            prompt: 'y',
            options: ['False', 'True'],
            correct: [0],
          ),
          q('true_false', prompt: 'z', correct: [1]),
        ]),
      );
      expect(r.errors, isEmpty);
      for (final d in r.value!.questions) {
        expect(d.options, ['True', 'False']);
      }
      expect(r.value!.questions[0].correctIndices, [0]);
      expect(r.value!.questions[1].correctIndices, [1]); // remapped
      expect(r.value!.questions[2].correctIndices, [1]);
    });

    test('true_false with other options is rejected', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q('true_false', options: ['Yes', 'No'], correct: [0]),
        ]),
      );
      expect(r.errors.join(), contains('true_false'));
    });

    test('short_answer requires answer_text and clears options', () {
      final bad = DraftValidator.validateQuiz(quizWith([q('short_answer')]));
      expect(bad.errors.join(), contains('answer_text'));

      final ok = DraftValidator.validateQuiz(
        quizWith([
          q('short_answer', options: ['junk'], correct: [0], answer: 'ATP'),
        ]),
      );
      expect(ok.errors, isEmpty);
      expect(ok.value!.questions.single.options, isEmpty);
      expect(ok.value!.questions.single.correctIndices, isEmpty);
    });

    test('empty prompt is rejected', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q('mcq_single', prompt: '  ', options: ['a', 'b'], correct: [0]),
        ]),
      );
      expect(r.errors.join(), contains('prompt'));
    });

    test('dedupes near-identical prompts and duplicate indices', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q(
            'mcq_multi',
            prompt: 'What is ATP?',
            options: ['a', 'b'],
            correct: [1, 1, 0],
          ),
          q(
            'mcq_single',
            prompt: 'what is ATP',
            options: ['a', 'b'],
            correct: [0],
          ),
        ]),
      );
      expect(r.errors, isEmpty);
      expect(r.value!.questions, hasLength(1));
      expect(r.value!.questions.single.correctIndices, [0, 1]);
    });

    test('lenient: camelCase keys, numeric strings, type casing', () {
      final r = DraftValidator.validateQuiz({
        'title': ' T ',
        'questions': [
          {
            'type': 'MCQ-Single',
            'prompt': 'p',
            'options': ['a', 'b'],
            'correctIndices': ['1'],
          },
        ],
      });
      expect(r.errors, isEmpty);
      expect(r.value!.title, 'T');
      expect(r.value!.questions.single.correctIndices, [1]);
    });

    test('disallowed type is an error', () {
      final r = DraftValidator.validateQuiz(
        quizWith([q('short_answer', answer: 'x')]),
        allowedTypes: {QuestionType.mcqSingle},
      );
      expect(r.errors.join(), contains('not allowed'));
    });

    test('keeps valid questions but reports invalid ones', () {
      final r = DraftValidator.validateQuiz(
        quizWith([
          q('mcq_single', prompt: 'good', options: ['a', 'b'], correct: [0]),
          q('mcq_single', prompt: 'bad', options: ['a', 'b'], correct: [5]),
        ]),
      );
      expect(r.isValid, isFalse);
      expect(r.value!.questions, hasLength(1));
      expect(r.errors, hasLength(1));
      expect(r.errors.single, startsWith('questions[1]'));
    });

    test('trims to maxQuestions', () {
      final r = DraftValidator.validateQuiz(
        validQuizJson(n: 5),
        maxQuestions: 3,
      );
      expect(r.value!.questions, hasLength(3));
    });

    test('missing questions array', () {
      final r = DraftValidator.validateQuiz({'title': 'x'});
      expect(r.value, isNull);
      expect(r.errors.join(), contains('questions'));
    });
  });

  group('validateNote', () {
    test('valid note', () {
      final r = DraftValidator.validateNote({
        'title': 'Cells',
        'content_markdown': '## Overview\n- a',
      });
      expect(r.isValid, isTrue);
      expect(
        r.value,
        const NoteDraft(title: 'Cells', contentMarkdown: '## Overview\n- a'),
      );
    });

    test('empty content is rejected', () {
      final r = DraftValidator.validateNote({
        'title': 'x',
        'content_markdown': '',
      });
      expect(r.value, isNull);
      expect(r.errors.join(), contains('content_markdown'));
    });
  });
}
