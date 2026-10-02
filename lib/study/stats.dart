/// Progress dashboard statistics (pure functions over cached rows).
///
/// Days are local calendar days ([localDay]); pass `toLocal` to override the
/// device time zone (tests).
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../data/models/card_review.dart';
import '../data/models/deck.dart';
import '../data/models/mistake.dart';
import '../data/models/quiz.dart';
import '../data/models/quiz_attempt.dart';
import '../data/models/subject.dart';
import 'due_queue.dart';
import 'local_day.dart';

/// Everything the dashboard is computed from: the user's cached rows.
/// Rows are live (not soft-deleted); [attempts], [reviews] and [mistakes]
/// are the current user's own.
@immutable
class StudySnapshot {
  const StudySnapshot({
    this.subjects = const [],
    this.quizzes = const [],
    this.decks = const [],
    this.attempts = const [],
    this.reviews = const [],
    this.mistakes = const [],
  });

  final List<Subject> subjects;
  final List<Quiz> quizzes;
  final List<Deck> decks;
  final List<QuizAttempt> attempts;
  final List<CardReview> reviews;
  final List<Mistake> mistakes;
}

// -----------------------------------------------------------------------------
// Streak
// -----------------------------------------------------------------------------

@immutable
class StreakInfo {
  const StreakInfo({
    this.current = 0,
    this.longest = 0,
    this.activeToday = false,
  });

  /// Consecutive days with activity ending today, or ending yesterday when
  /// nothing was done yet today (the streak is still alive).
  final int current;

  /// Longest run of consecutive active days.
  final int longest;

  /// Whether there was activity today.
  final bool activeToday;

  @override
  bool operator ==(Object other) =>
      other is StreakInfo &&
      other.current == current &&
      other.longest == longest &&
      other.activeToday == activeToday;

  @override
  int get hashCode => Object.hash(current, longest, activeToday);

  @override
  String toString() =>
      'StreakInfo(current: $current, longest: $longest, today: $activeToday)';
}

/// Local days with any study activity: completed attempts (or in-progress
/// ones with answers, by last update) and flashcard reviews (first and last
/// review of each card; earlier review days are not stored).
Set<DateTime> activityDays({
  Iterable<QuizAttempt> attempts = const [],
  Iterable<CardReview> reviews = const [],
  ToLocal toLocal = deviceLocal,
}) => {
  for (final a in attempts)
    if (a.deletedAt == null)
      if (a.completedAt case final t?)
        localDay(t, toLocal)
      else if (a.answers.isNotEmpty)
        localDay(a.updatedAt, toLocal),
  for (final r in reviews)
    if (r.deletedAt == null && r.lastReviewAt != null) ...[
      localDay(r.lastReviewAt!, toLocal),
      localDay(r.createdAt, toLocal),
    ],
};

/// Streak from a set of active days ([localDay] values) as of [today].
StreakInfo computeStreak(Set<DateTime> days, DateTime today) {
  if (days.isEmpty) return const StreakInfo();
  final activeToday = days.contains(today);
  var current = 0;
  var cursor = activeToday ? today : today.subtract(const Duration(days: 1));
  while (days.contains(cursor)) {
    current++;
    cursor = _previousDay(cursor);
  }
  final sorted = days.toList()..sort();
  var longest = 1, run = 1;
  for (var i = 1; i < sorted.length; i++) {
    run = daysBetween(sorted[i - 1], sorted[i]) == 1 ? run + 1 : 1;
    longest = math.max(longest, run);
  }
  return StreakInfo(
    current: current,
    longest: math.max(longest, current),
    activeToday: activeToday,
  );
}

DateTime _previousDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day - 1);

// -----------------------------------------------------------------------------
// Quizzes
// -----------------------------------------------------------------------------

/// Completed attempts (any mode).
int quizzesTaken(Iterable<QuizAttempt> attempts) =>
    attempts.where((a) => a.deletedAt == null && a.completedAt != null).length;

/// Correct / graded answers.
@immutable
class Accuracy {
  const Accuracy({this.correct = 0, this.answered = 0});

  final int correct;

  /// Graded answers (`isCorrect != null`).
  final int answered;

  /// 0..1, null when nothing was answered.
  double? get ratio => answered == 0 ? null : correct / answered;

  Accuracy operator +(Accuracy other) => Accuracy(
    correct: correct + other.correct,
    answered: answered + other.answered,
  );

  @override
  bool operator ==(Object other) =>
      other is Accuracy &&
      other.correct == correct &&
      other.answered == answered;

  @override
  int get hashCode => Object.hash(correct, answered);

  @override
  String toString() => 'Accuracy($correct/$answered)';
}

/// Accuracy of the graded answers of completed [attempts].
Accuracy overallAccuracy(Iterable<QuizAttempt> attempts) {
  var acc = const Accuracy();
  for (final a in _completed(attempts)) {
    acc += _attemptAccuracy(a);
  }
  return acc;
}

Accuracy _attemptAccuracy(QuizAttempt a) {
  var correct = 0, answered = 0;
  for (final ans in a.answers) {
    if (ans.isCorrect == null) continue;
    answered++;
    if (ans.isCorrect!) correct++;
  }
  return Accuracy(correct: correct, answered: answered);
}

Iterable<QuizAttempt> _completed(Iterable<QuizAttempt> attempts) =>
    attempts.where((a) => a.deletedAt == null && a.completedAt != null);

@immutable
class SubjectAccuracy {
  const SubjectAccuracy({
    required this.subjectId,
    required this.title,
    this.color,
    required this.accuracy,
    required this.attempts,
  });

  final String subjectId;

  /// Subject title ('' when the subject isn't cached).
  final String title;
  final int? color;
  final Accuracy accuracy;

  /// Completed attempts counted.
  final int attempts;

  @override
  bool operator ==(Object other) =>
      other is SubjectAccuracy &&
      other.subjectId == subjectId &&
      other.title == title &&
      other.color == color &&
      other.accuracy == accuracy &&
      other.attempts == attempts;

  @override
  int get hashCode => Object.hash(subjectId, title, color, accuracy, attempts);
}

/// Accuracy per subject over completed attempts of cached quizzes, sorted
/// by title. Subjects without graded answers are omitted.
List<SubjectAccuracy> accuracyBySubject({
  required Iterable<QuizAttempt> attempts,
  required Iterable<Quiz> quizzes,
  required Iterable<Subject> subjects,
}) {
  final quizById = {for (final q in quizzes) q.id: q};
  final subjectById = {for (final s in subjects) s.id: s};
  final acc = <String, Accuracy>{};
  final counts = <String, int>{};
  for (final a in _completed(attempts)) {
    final quiz = quizById[a.quizId];
    if (quiz == null) continue;
    final sid = quiz.subjectId;
    acc[sid] = (acc[sid] ?? const Accuracy()) + _attemptAccuracy(a);
    counts[sid] = (counts[sid] ?? 0) + 1;
  }
  final result = [
    for (final MapEntry(key: sid, value: a) in acc.entries)
      if (a.answered > 0)
        SubjectAccuracy(
          subjectId: sid,
          title: subjectById[sid]?.title ?? '',
          color: subjectById[sid]?.color,
          accuracy: a,
          attempts: counts[sid] ?? 0,
        ),
  ];
  result.sort((x, y) {
    final c = x.title.toLowerCase().compareTo(y.title.toLowerCase());
    return c != 0 ? c : x.subjectId.compareTo(y.subjectId);
  });
  return result;
}

/// A question the user often gets wrong.
@immutable
class WeakQuestion {
  const WeakQuestion({
    required this.quizId,
    required this.quizTitle,
    required this.subjectId,
    required this.questionId,
    required this.prompt,
    required this.accuracy,
  });

  final String quizId;
  final String quizTitle;
  final String subjectId;
  final String questionId;
  final String prompt;
  final Accuracy accuracy;

  @override
  bool operator ==(Object other) =>
      other is WeakQuestion &&
      other.quizId == quizId &&
      other.questionId == questionId &&
      other.quizTitle == quizTitle &&
      other.prompt == prompt &&
      other.subjectId == subjectId &&
      other.accuracy == accuracy;

  @override
  int get hashCode =>
      Object.hash(quizId, questionId, quizTitle, prompt, subjectId, accuracy);
}

/// Questions (still in their cached quiz) with the lowest accuracy over
/// completed attempts, answered at least [minAnswers] times and not always
/// correct. Lowest accuracy first, then most answered.
List<WeakQuestion> weakestQuestions({
  required Iterable<QuizAttempt> attempts,
  required Iterable<Quiz> quizzes,
  int minAnswers = 2,
  int limit = 5,
}) {
  final quizById = {for (final q in quizzes) q.id: q};
  final stats = <(String, String), Accuracy>{};
  for (final a in _completed(attempts)) {
    if (!quizById.containsKey(a.quizId)) continue;
    for (final ans in a.answers) {
      final ok = ans.isCorrect;
      if (ok == null) continue;
      final key = (a.quizId, ans.questionId);
      stats[key] =
          (stats[key] ?? const Accuracy()) +
          Accuracy(correct: ok ? 1 : 0, answered: 1);
    }
  }
  final result = <WeakQuestion>[];
  for (final MapEntry(key: (quizId, questionId), value: acc) in stats.entries) {
    if (acc.answered < minAnswers || acc.correct == acc.answered) continue;
    final quiz = quizById[quizId]!;
    final question = quiz.questions
        .where((q) => q.id == questionId)
        .firstOrNull;
    if (question == null) continue;
    result.add(
      WeakQuestion(
        quizId: quizId,
        quizTitle: quiz.title,
        subjectId: quiz.subjectId,
        questionId: questionId,
        prompt: question.prompt,
        accuracy: acc,
      ),
    );
  }
  result.sort((a, b) {
    final c = a.accuracy.ratio!.compareTo(b.accuracy.ratio!);
    if (c != 0) return c;
    final d = b.accuracy.answered.compareTo(a.accuracy.answered);
    if (d != 0) return d;
    final e = a.quizId.compareTo(b.quizId);
    return e != 0 ? e : a.questionId.compareTo(b.questionId);
  });
  return result.take(limit).toList();
}

/// A quiz with a low average score.
@immutable
class WeakQuiz {
  const WeakQuiz({
    required this.quizId,
    required this.title,
    required this.subjectId,
    required this.accuracy,
    required this.attempts,
  });

  final String quizId;
  final String title;
  final String subjectId;
  final Accuracy accuracy;
  final int attempts;

  @override
  bool operator ==(Object other) =>
      other is WeakQuiz &&
      other.quizId == quizId &&
      other.title == title &&
      other.subjectId == subjectId &&
      other.accuracy == accuracy &&
      other.attempts == attempts;

  @override
  int get hashCode => Object.hash(quizId, title, subjectId, accuracy, attempts);
}

/// Cached quizzes with the lowest accuracy over at least [minAttempts]
/// completed attempts (perfect quizzes excluded), lowest first.
List<WeakQuiz> weakestQuizzes({
  required Iterable<QuizAttempt> attempts,
  required Iterable<Quiz> quizzes,
  int minAttempts = 2,
  int limit = 5,
}) {
  final quizById = {for (final q in quizzes) q.id: q};
  final acc = <String, Accuracy>{};
  final counts = <String, int>{};
  for (final a in _completed(attempts)) {
    if (!quizById.containsKey(a.quizId)) continue;
    acc[a.quizId] = (acc[a.quizId] ?? const Accuracy()) + _attemptAccuracy(a);
    counts[a.quizId] = (counts[a.quizId] ?? 0) + 1;
  }
  final result = [
    for (final MapEntry(key: id, value: a) in acc.entries)
      if ((counts[id] ?? 0) >= minAttempts &&
          a.answered > 0 &&
          a.correct < a.answered)
        WeakQuiz(
          quizId: id,
          title: quizById[id]!.title,
          subjectId: quizById[id]!.subjectId,
          accuracy: a,
          attempts: counts[id]!,
        ),
  ];
  result.sort((a, b) {
    final c = a.accuracy.ratio!.compareTo(b.accuracy.ratio!);
    if (c != 0) return c;
    final d = b.attempts.compareTo(a.attempts);
    return d != 0 ? d : a.quizId.compareTo(b.quizId);
  });
  return result.take(limit).toList();
}

// -----------------------------------------------------------------------------
// Recent activity
// -----------------------------------------------------------------------------

/// One entry of the recent activity feed.
@immutable
sealed class ActivityItem {
  const ActivityItem();

  /// When it happened (UTC); the feed is sorted by it, newest first.
  DateTime get at;
}

/// A completed quiz attempt.
final class QuizActivity extends ActivityItem {
  const QuizActivity({
    required this.attempt,
    required this.quizTitle,
    required this.subjectId,
  });

  final QuizAttempt attempt;
  final String quizTitle;
  final String subjectId;

  AttemptMode get mode => attempt.mode;

  @override
  DateTime get at => attempt.completedAt!;

  @override
  bool operator ==(Object other) =>
      other is QuizActivity &&
      other.attempt == attempt &&
      other.quizTitle == quizTitle &&
      other.subjectId == subjectId;

  @override
  int get hashCode => Object.hash(attempt, quizTitle, subjectId);
}

/// Flashcards of one deck last reviewed on one local day.
final class ReviewActivity extends ActivityItem {
  const ReviewActivity({
    required this.deckId,
    required this.deckTitle,
    required this.subjectId,
    required this.day,
    required this.cards,
    required this.at,
  });

  final String deckId;
  final String deckTitle;
  final String subjectId;

  /// Local day ([localDay]).
  final DateTime day;

  /// Cards whose last review was that day.
  final int cards;

  /// Latest review of the group.
  @override
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ReviewActivity &&
      other.deckId == deckId &&
      other.deckTitle == deckTitle &&
      other.subjectId == subjectId &&
      other.day == day &&
      other.cards == cards &&
      other.at == at;

  @override
  int get hashCode => Object.hash(deckId, deckTitle, subjectId, day, cards, at);
}

/// Newest-first feed of completed attempts (of cached quizzes) and review
/// sessions (cards grouped per deck and local day of their last review).
List<ActivityItem> recentActivity({
  required Iterable<QuizAttempt> attempts,
  required Iterable<Quiz> quizzes,
  Iterable<CardReview> reviews = const [],
  Iterable<Deck> decks = const [],
  int limit = 20,
  ToLocal toLocal = deviceLocal,
}) {
  final quizById = {for (final q in quizzes) q.id: q};
  final deckById = {for (final d in decks) d.id: d};
  final items = <ActivityItem>[
    for (final a in _completed(attempts))
      if (quizById[a.quizId] case final quiz?)
        QuizActivity(
          attempt: a,
          quizTitle: quiz.title,
          subjectId: quiz.subjectId,
        ),
  ];
  final sessions = <(String, DateTime), ({int cards, DateTime at})>{};
  for (final r in reviews) {
    final last = r.lastReviewAt;
    if (r.deletedAt != null || last == null) continue;
    if (!deckById.containsKey(r.deckId)) continue;
    final key = (r.deckId, localDay(last, toLocal));
    final prev = sessions[key];
    sessions[key] = (
      cards: (prev?.cards ?? 0) + 1,
      at: prev == null || last.isAfter(prev.at) ? last : prev.at,
    );
  }
  for (final MapEntry(key: (deckId, day), value: s) in sessions.entries) {
    final deck = deckById[deckId]!;
    items.add(
      ReviewActivity(
        deckId: deckId,
        deckTitle: deck.title,
        subjectId: deck.subjectId,
        day: day,
        cards: s.cards,
        at: s.at,
      ),
    );
  }
  items.sort((a, b) => b.at.compareTo(a.at));
  return items.take(limit).toList();
}

// -----------------------------------------------------------------------------
// Dashboard
// -----------------------------------------------------------------------------

/// Everything the progress dashboard shows.
@immutable
class DashboardStats {
  const DashboardStats({
    this.streak = const StreakInfo(),
    this.quizzesTaken = 0,
    this.overallAccuracy = const Accuracy(),
    this.accuracyBySubject = const [],
    this.weakestQuestions = const [],
    this.weakestQuizzes = const [],
    this.due = const DueQueue(),
    this.reviewsToday = 0,
    this.openMistakes = 0,
    this.recentActivity = const [],
  });

  final StreakInfo streak;
  final int quizzesTaken;
  final Accuracy overallAccuracy;
  final List<SubjectAccuracy> accuracyBySubject;
  final List<WeakQuestion> weakestQuestions;
  final List<WeakQuiz> weakestQuizzes;

  /// Today's flashcard queue (`due.count` = cards to study today).
  final DueQueue due;

  /// Cards whose last review was today.
  final int reviewsToday;

  /// Open mistakes of cached quizzes (questions still present).
  final int openMistakes;
  final List<ActivityItem> recentActivity;

  int get dueCards => due.count;
}

/// Computes the dashboard from [s] as of [now].
DashboardStats computeDashboard(
  StudySnapshot s, {
  required DateTime now,
  int newCardsPerDay = 20,
  ToLocal toLocal = deviceLocal,
  int minAnswers = 2,
  int weakLimit = 5,
  int activityLimit = 20,
}) {
  final today = localDay(now, toLocal);
  final quizById = {for (final q in s.quizzes) q.id: q};
  final openMistakes = s.mistakes.where((m) {
    if (!m.isOpen) return false;
    final quiz = quizById[m.quizId];
    return quiz != null && quiz.questions.any((q) => q.id == m.questionId);
  }).length;
  return DashboardStats(
    streak: computeStreak(
      activityDays(attempts: s.attempts, reviews: s.reviews, toLocal: toLocal),
      today,
    ),
    quizzesTaken: quizzesTaken(s.attempts),
    overallAccuracy: overallAccuracy(s.attempts),
    accuracyBySubject: accuracyBySubject(
      attempts: s.attempts,
      quizzes: s.quizzes,
      subjects: s.subjects,
    ),
    weakestQuestions: weakestQuestions(
      attempts: s.attempts,
      quizzes: s.quizzes,
      minAnswers: minAnswers,
      limit: weakLimit,
    ),
    weakestQuizzes: weakestQuizzes(
      attempts: s.attempts,
      quizzes: s.quizzes,
      minAttempts: minAnswers,
      limit: weakLimit,
    ),
    due: buildDueQueue(
      decks: s.decks,
      reviews: s.reviews,
      now: now,
      newCardsPerDay: newCardsPerDay,
      toLocal: toLocal,
    ),
    reviewsToday: s.reviews
        .where(
          (r) =>
              r.deletedAt == null &&
              r.lastReviewAt != null &&
              localDay(r.lastReviewAt!, toLocal) == today,
        )
        .length,
    openMistakes: openMistakes,
    recentActivity: recentActivity(
      attempts: s.attempts,
      quizzes: s.quizzes,
      reviews: s.reviews,
      decks: s.decks,
      limit: activityLimit,
      toLocal: toLocal,
    ),
  );
}
