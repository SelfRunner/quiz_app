import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/study/study_settings.dart';

import 'support/fake_remote.dart';

void main() {
  test('Deck JSON matches the decks row (cards jsonb, extra keys ok)', () {
    final row = deckRow('d', 'u', 's', noteId: 'n');
    (row['cards'] as List<Object?>).add({
      'id': 'c3',
      'front': 'f',
      'back': 'b',
      'hint': 'h',
      'image': 'ignored-extra-key',
    });
    final deck = Deck.fromJson(
      jsonDecode(jsonEncode(row)) as Map<String, dynamic>,
    );
    expect(deck.noteId, 'n');
    expect(deck.cards.map((c) => c.id), ['c1', 'c2', 'c3']);
    expect(deck.cards.last.hint, 'h');
    final json = deck.toJson();
    expect(
      json.keys,
      containsAll(['subject_id', 'note_id', 'cards', 'source']),
    );
    expect((json['cards'] as List<Object?>).first, {
      'id': 'c1',
      'front': 'F c1',
      'back': 'B c1',
      'hint': null,
    });
  });

  test('CardReview JSON: state is the smallint, unknown -> new', () {
    final row = reviewRow('r', 'u', 'd', 'c1', state: 3);
    final review = CardReview.fromJson(row);
    expect(review.state, CardState.relearning);
    expect(review.toJson()['state'], 3);
    expect(review.toJson()['last_review_at'], isNotNull);
    expect(CardReview.fromJson({...row, 'state': 42}).state, CardState.newCard);
    // Postgres double precision may arrive as an integer.
    expect(CardReview.fromJson({...row, 'stability': 4}).stability, 4.0);
    final fsrs = review.toFsrs();
    expect(fsrs.state, CardState.relearning);
    expect(review.withFsrs(fsrs), review);
  });

  test('Mistake JSON and isOpen', () {
    final m = Mistake.fromJson({
      'id': 'm',
      'owner_id': 'u',
      'quiz_id': 'q',
      'question_id': 'x',
      'wrong_count': 2,
      'correct_streak': 1,
      'last_wrong_at': '2026-01-01T00:00:00Z',
      'resolved_at': null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'deleted_at': null,
    });
    expect(m.isOpen, isTrue);
    expect(m.copyWith(resolvedAt: DateTime.utc(2026)).isOpen, isFalse);
    expect(m.toJson()['correct_streak'], 1);
  });

  test('QuizAttempt exam fields are backward compatible', () {
    final legacy = {
      'id': 'a',
      'quiz_id': 'q',
      'owner_id': 'u',
      'answers': <Object?>[],
      'score': 1,
      'total': 2,
      'started_at': '2026-01-01T00:00:00Z',
      'completed_at': null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'deleted_at': null,
    };
    final old = QuizAttempt.fromJson(legacy);
    expect(old.mode, AttemptMode.practice);
    expect(old.questionIds, isNull);
    expect(old.timeLimitSeconds, isNull);
    expect(
      QuizAttempt.fromJson({...legacy, 'mode': null}).mode,
      AttemptMode.practice,
    );
    expect(
      QuizAttempt.fromJson({...legacy, 'mode': 'future'}).mode,
      AttemptMode.practice,
    );

    final exam = QuizAttempt.fromJson({
      ...legacy,
      'mode': 'exam',
      'time_limit_seconds': 900,
      'question_ids': ['x', 'y'],
      'duration_seconds': 300,
    });
    expect(exam.mode, AttemptMode.exam);
    expect(exam.questionIds, ['x', 'y']);
    final json = exam.toJson();
    expect(json['mode'], 'exam');
    expect(json['time_limit_seconds'], 900);
    expect(json['question_ids'], ['x', 'y']);
    expect(json['duration_seconds'], 300);
    expect(
      QuizAttempt.fromJson({...legacy, 'mode': 'mistakes'}).mode,
      AttemptMode.mistakes,
    );
  });

  test('ShareResourceType deck', () {
    final share = Share.fromJson({
      'id': 's',
      'owner_id': 'a',
      'recipient_id': 'b',
      'resource_type': 'deck',
      'resource_id': 'd',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(share.resourceType, ShareResourceType.deck);
    expect(share.toJson()['resource_type'], 'deck');
    expect(ShareResourceType.deck.wireName, 'deck');
  });

  test('SyncTables lists the study tables after their parents', () {
    const synced = SyncTables.synced;
    expect(synced.indexOf('decks'), greaterThan(synced.indexOf('notes')));
    expect(
      synced.indexOf('card_reviews'),
      greaterThan(synced.indexOf('decks')),
    );
    expect(synced.indexOf('mistakes'), greaterThan(synced.indexOf('quizzes')));
  });

  test('StudySettings decode/encode with defaults and clamping', () {
    expect(StudySettings.decode(null), const StudySettings());
    expect(StudySettings.decode('not json'), const StudySettings());
    const s = StudySettings(newCardsPerDay: 7, desiredRetention: 0.85);
    expect(StudySettings.decode(s.encode()), s);
    expect(
      StudySettings.decode('{"new_cards_per_day": -3, "desired_retention": 2}'),
      const StudySettings(newCardsPerDay: 0, desiredRetention: 0.99),
    );
    expect(s.scheduler().desiredRetention, 0.85);
  });
}
