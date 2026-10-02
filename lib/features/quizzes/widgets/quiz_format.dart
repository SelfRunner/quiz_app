import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz_attempt.dart';

/// Breakpoint between phone and wide (tablet/desktop/web) layouts.
const double wideBreakpoint = 840;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideBreakpoint;

String questionTypeLabel(QuestionType t) => switch (t) {
  QuestionType.mcqSingle => 'Single choice',
  QuestionType.mcqMulti => 'Multiple choice',
  QuestionType.trueFalse => 'True / False',
  QuestionType.shortAnswer => 'Short answer',
};

IconData questionTypeIcon(QuestionType t) => switch (t) {
  QuestionType.mcqSingle => Icons.radio_button_checked,
  QuestionType.mcqMulti => Icons.check_box_outlined,
  QuestionType.trueFalse => Icons.rule,
  QuestionType.shortAnswer => Icons.short_text,
};

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Score of an attempt as 0..100, or null when it has no questions.
int? attemptPercent(QuizAttempt a) =>
    a.total <= 0 ? null : (a.score / a.total * 100).round();

/// Points with partial credit: `3`, `2.5`.
String formatPoints(double points) {
  final rounded = (points * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}

String formatPercent(int? p) => p == null ? '–' : '$p%';

String formatDuration(Duration d) {
  if (d.isNegative) return '–';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// Exam time limit: "10 min", or a duration for odd values.
String formatTimeLimit(int seconds) => seconds % 60 == 0
    ? '${seconds ~/ 60} min'
    : formatDuration(Duration(seconds: seconds));

/// Countdown/stopwatch text: `m:ss`, or `h:mm:ss` from one hour.
String formatClock(Duration d) {
  final t = d.isNegative ? Duration.zero : d;
  final h = t.inHours;
  final m = t.inMinutes.remainder(60);
  final s = t.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Time spent on a completed attempt: `durationSeconds`, else the span
/// between start and completion (older rows).
Duration attemptDuration(QuizAttempt a) {
  final secs = a.durationSeconds;
  if (secs != null) return Duration(seconds: secs);
  final done = a.completedAt;
  return done == null ? Duration.zero : done.difference(a.startedAt);
}

/// Short label of an attempt's mode (null for regular practice).
String? attemptModeLabel(AttemptMode mode) => switch (mode) {
  AttemptMode.practice => null,
  AttemptMode.exam => 'Exam',
  AttemptMode.mistakes => 'Mistakes',
};

String formatDateTime(DateTime utc) =>
    DateFormat.yMMMd().add_jm().format(utc.toLocal());

String formatDate(DateTime utc) => DateFormat.yMMMd().format(utc.toLocal());

/// Completed attempts only (abandoned ones have no `completedAt`).
List<QuizAttempt> completedAttempts(List<QuizAttempt> all) => [
  for (final a in all)
    if (a.completedAt != null) a,
];

/// User-safe text for an error thrown by a repository.
String errorText(Object error) =>
    error is AppException ? error.message : 'Something went wrong.';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Centers [child] and caps its width on large screens.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.maxWidth = 920});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Simple centered message with an optional action (the design system's
/// [EmptyState]; kept for existing callers).
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      EmptyState(icon: icon, title: title, message: message, action: action);
}

/// Score color: success from 80%, warning from 50%, danger below; muted when
/// unknown.
Color scoreColor(BuildContext context, int? percent) {
  final c = AppColors.of(context);
  if (percent == null) return c.mutedText;
  if (percent >= 80) return c.success;
  if (percent >= 50) return c.warning;
  return c.danger;
}
