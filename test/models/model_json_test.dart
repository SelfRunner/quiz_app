import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';

/// Round-trips through a JSON string, as Hive storage does.
Map<String, dynamic> _roundTrip(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  final now = DateTime.utc(2026, 1, 2, 3, 4, 5);

  test('Quiz round-trips with snake_case keys and embedded questions', () {
    final quiz = Quiz(
      id: 'q1',
      subjectId: 's1',
      noteId: 'n1',
      ownerId: 'u1',
      title: 'Cells',
      source: const QuizSource(
        youtubeUrl: 'https://youtu.be/x',
        provider: 'gemini',
      ),
      questions: const [
        Question(
          id: 'qq1',
          type: QuestionType.mcqMulti,
          prompt: 'Pick organelles',
          options: ['Nucleus', 'Rock', 'Ribosome'],
          correctIndices: [0, 2],
        ),
        Question(
          id: 'qq2',
          type: QuestionType.shortAnswer,
          prompt: 'Powerhouse of the cell?',
          answerText: 'Mitochondria',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final json = _roundTrip(quiz.toJson());
    expect(json['subject_id'], 's1');
    expect(json['note_id'], 'n1');
    expect(json['deleted_at'], isNull);
    expect(json.containsKey('deleted_at'), isTrue);
    final questions = json['questions'] as List<dynamic>;
    expect((questions.first as Map<String, dynamic>)['type'], 'mcq_multi');
    expect((questions.first as Map<String, dynamic>)['correct_indices'], [
      0,
      2,
    ]);
    expect(Quiz.fromJson(json), quiz);
  });

  test('Supabase timestamp format parses to UTC', () {
    final subject = Subject.fromJson({
      'id': 's1',
      'owner_id': 'u1',
      'title': 'Biology',
      'description': null,
      'color': 0xFF3F51B5,
      'created_at': '2026-01-02T03:04:05.123456+00:00',
      'updated_at': '2026-01-02T03:04:05+00:00',
      'deleted_at': null,
    });
    expect(subject.createdAt.isUtc, isTrue);
    expect(Subject.fromJson(_roundTrip(subject.toJson())), subject);
    expect(subject.isOwnedBy('u1'), isTrue);
    expect(subject.isDeleted, isFalse);
  });

  test('QuizAttempt, Share, OutboxOp round-trip', () {
    final attempt = QuizAttempt(
      id: 'a1',
      quizId: 'q1',
      ownerId: 'u1',
      answers: const [
        QuestionAnswer(
          questionId: 'qq1',
          selectedIndices: [0],
          isCorrect: true,
        ),
      ],
      score: 1,
      total: 2,
      startedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(QuizAttempt.fromJson(_roundTrip(attempt.toJson())), attempt);

    final share = Share.fromJson({
      'id': 'sh1',
      'owner_id': 'u1',
      'recipient_id': 'u2',
      'resource_type': 'subject',
      'resource_id': 's1',
      'created_at': '2026-01-02T03:04:05Z',
      'recipient': {'id': 'u2', 'display_name': 'Bob'},
    });
    expect(share.resourceType, ShareResourceType.subject);
    expect(share.recipient?.displayName, 'Bob');
    expect(share.toJson().containsKey('recipient'), isFalse);

    final op = OutboxOp(
      id: 'o1',
      table: SyncTables.notes,
      op: OutboxOpType.upsert,
      rowId: 'n1',
      payload: {'id': 'n1', 'title': 'T'},
      createdAt: now,
    );
    final opJson = _roundTrip(op.toJson());
    expect(opJson['op'], 'upsert');
    expect(OutboxOp.fromJson(opJson), op);
  });

  test('QuizDraft parses AI output and converts to questions', () {
    final draft = QuizDraft.fromJson({
      'title': 'T',
      'description': null,
      'questions': [
        {
          'type': 'true_false',
          'prompt': 'Sky is blue',
          'options': ['True', 'False'],
          'correct_indices': [0],
          'answer_text': null,
          'explanation': null,
        },
      ],
    });
    var n = 0;
    final questions = draft.toQuestions(() => 'id${n++}');
    expect(questions.single.id, 'id0');
    expect(questions.single.type, QuestionType.trueFalse);
    expect(
      NoteDraft.fromJson({'title': 'N', 'content_markdown': '# Hi'})
          .contentMarkdown,
      '# Hi',
    );
    expect(quizDraftJsonSchema['required'], contains('questions'));
    expect(noteDraftJsonSchema['required'], contains('content_markdown'));
  });

  test('NoteImageRef builds and parses markdown urls', () {
    const ref = NoteImageRef(ownerId: 'u1', noteId: 'n1', fileName: 'a.png');
    expect(ref.markdownUrl, 'note-image://u1/n1/a.png');
    expect(NoteImageRef.tryParse(ref.markdownUrl), ref);
    expect(NoteImageRef.tryParse('u1/n1/a.png'), ref);
    expect(NoteImageRef.tryParse('https://x/y'), isNull);
  });
}
