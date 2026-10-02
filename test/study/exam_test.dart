import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/study/exam.dart';

Question mcq(String id, List<int> correct, {QuestionType? type}) => Question(
  id: id,
  type: type ?? QuestionType.mcqMulti,
  prompt: id,
  options: const ['a', 'b', 'c'],
  correctIndices: correct,
);

void main() {
  final questions = [
    for (var i = 0; i < 10; i++) mcq('q$i', [0]),
  ];
  final t0 = DateTime.utc(2026, 1, 1, 9);

  QuizAttempt attempt({int? limit, List<String>? ids}) => QuizAttempt(
    id: 'a',
    quizId: 'quiz',
    ownerId: 'u',
    mode: AttemptMode.exam,
    timeLimitSeconds: limit,
    questionIds: ids,
    startedAt: t0,
    createdAt: t0,
    updatedAt: t0,
  );

  group('selectQuestionPool', () {
    test('random N without repeats, deterministic with a seed', () {
      final a = selectQuestionPool(questions, count: 4, random: math.Random(1));
      final b = selectQuestionPool(questions, count: 4, random: math.Random(1));
      expect(a, hasLength(4));
      expect(a.map((q) => q.id).toSet(), hasLength(4));
      expect(a, b);
      final c = selectQuestionPool(questions, count: 4, random: math.Random(2));
      expect(c.map((q) => q.id), isNot(a.map((q) => q.id)));
    });

    test('count null / too large returns all (shuffled); 0 returns none', () {
      final all = selectQuestionPool(questions, random: math.Random(3));
      expect(all.map((q) => q.id).toSet(), questions.map((q) => q.id).toSet());
      expect(selectQuestionPool(questions, count: 99), hasLength(10));
      expect(selectQuestionPool(questions, count: 0), isEmpty);
      expect(questions.first.id, 'q0', reason: 'input untouched');
    });
  });

  test('questionsForAttempt follows the pool order and skips removed ids', () {
    final quiz = Quiz(
      id: 'quiz',
      subjectId: 's',
      ownerId: 'u',
      title: 'Q',
      questions: questions,
      createdAt: t0,
      updatedAt: t0,
    );
    expect(
      questionsForAttempt(
        quiz,
        attempt(ids: ['q3', 'gone', 'q1']),
      ).map((q) => q.id),
      ['q3', 'q1'],
    );
    expect(questionsForAttempt(quiz, attempt()), hasLength(10));
  });

  test('gradeAnswer: exact set match; short answers self-graded', () {
    final multi = mcq('m', [0, 2]);
    expect(gradeAnswer(multi, null), isNull);
    expect(
      gradeAnswer(
        multi,
        const QuestionAnswer(questionId: 'm', selectedIndices: [2, 0]),
      ),
      isTrue,
    );
    expect(
      gradeAnswer(
        multi,
        const QuestionAnswer(questionId: 'm', selectedIndices: [0]),
      ),
      isFalse,
    );
    expect(gradeAnswer(multi, const QuestionAnswer(questionId: 'm')), isNull);
    final short = mcq('s', [], type: QuestionType.shortAnswer);
    expect(
      gradeAnswer(
        short,
        const QuestionAnswer(questionId: 's', textAnswer: 'x', isCorrect: true),
      ),
      isTrue,
    );
  });

  test('scoreExam / completeExam', () {
    final qs = [
      mcq('a', [0]),
      mcq('b', [1]),
      mcq('c', [0]),
      mcq('s', [], type: QuestionType.shortAnswer),
    ];
    const answers = [
      QuestionAnswer(questionId: 'a', selectedIndices: [0], isCorrect: false),
      QuestionAnswer(questionId: 'b', selectedIndices: [0]),
      QuestionAnswer(questionId: 's', textAnswer: 'my answer'),
    ];
    final result = scoreExam(qs, answers);
    expect(
      result.score,
      const ExamScore(correct: 1, total: 4, answered: 2, ungraded: 1),
    );
    expect(result.score.unanswered, 1);
    expect(result.score.percent, 25);
    expect(result.answers.first.isCorrect, isTrue, reason: 're-graded');

    final done = completeExam(
      attempt(limit: 60),
      questions: qs,
      answers: answers,
      now: t0.add(const Duration(seconds: 90)),
    );
    expect(done.score, 1);
    expect(done.total, 4);
    expect(done.completedAt, t0.add(const Duration(seconds: 90)));
    expect(done.durationSeconds, 60, reason: 'capped at the limit');
  });

  test('timer helpers', () {
    final timed = attempt(limit: 600);
    expect(
      examTimeRemaining(timed, t0.add(const Duration(minutes: 4))),
      const Duration(minutes: 6),
    );
    expect(
      examTimeRemaining(timed, t0.add(const Duration(hours: 1))),
      Duration.zero,
    );
    expect(isExamExpired(timed, t0.add(const Duration(minutes: 10))), isTrue);
    expect(isExamExpired(timed, t0.add(const Duration(minutes: 9))), isFalse);
    expect(examTimeRemaining(attempt(), t0), isNull);
    expect(isExamExpired(attempt(), t0.add(const Duration(days: 9))), isFalse);
    expect(
      examDurationSeconds(attempt(), t0.add(const Duration(seconds: 75))),
      75,
    );
  });
}
