import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';

/// Width at which sharing UI switches to dialogs / wide layouts (matches the
/// app shell's rail breakpoint).
const double kSharingWideBreakpoint = 720;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kSharingWideBreakpoint;

/// User-facing labels and icons per shareable resource type.
extension ShareResourceTypeUi on ShareResourceType {
  /// Lower-case singular noun, e.g. "subject".
  String get noun => switch (this) {
    ShareResourceType.subject => 'subject',
    ShareResourceType.note => 'note',
    ShareResourceType.quiz => 'quiz',
  };

  /// Section title, e.g. "Subjects".
  String get pluralTitle => switch (this) {
    ShareResourceType.subject => 'Subjects',
    ShareResourceType.note => 'Notes',
    ShareResourceType.quiz => 'Quizzes',
  };

  IconData get icon => switch (this) {
    ShareResourceType.subject => Icons.library_books_outlined,
    ShareResourceType.note => Icons.description_outlined,
    ShareResourceType.quiz => Icons.quiz_outlined,
  };

  /// What recipients get when this kind of resource is shared.
  String get shareExplanation => switch (this) {
    ShareResourceType.subject =>
      'Recipients can view all notes and quizzes in this subject, including '
          'ones you add later. They can\'t edit anything, but they can copy '
          'it into their own account.',
    ShareResourceType.note =>
      'Recipients can view this note, its images and the quizzes attached to '
          'it. They can\'t edit, but they can copy it into their own account.',
    ShareResourceType.quiz =>
      'Recipients can view and take this quiz (their attempts stay private). '
          'They can\'t edit it, but they can copy it into their own account.',
  };
}

/// Primary label for a profile: display name, else email, else [fallback].
String profileLabel(Profile? profile, {String fallback = 'Unknown user'}) {
  final name = profile?.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = profile?.email?.trim();
  if (email != null && email.isNotEmpty) return email;
  return fallback;
}

/// Secondary label: the email when the primary label is the display name.
String? profileSecondary(Profile? profile) {
  final name = profile?.displayName?.trim();
  final email = profile?.email?.trim();
  if (name == null || name.isEmpty) return null;
  if (email == null || email.isEmpty) return null;
  return email;
}

/// One or two upper-case initials for an avatar.
String initialsOf(String label) {
  final words = label
      .split(RegExp(r'[\s@._-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final second = words.length > 1 ? words[1].characters.first : '';
  return (first + second).toUpperCase();
}

/// "Oct 2, 2026" in local time.
String formatShareDate(DateTime date) =>
    DateFormat.yMMMd().format(date.toLocal());

/// User-safe message for any error thrown by the data layer.
String friendlyError(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Something went wrong. Please try again.',
};

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool looksLikeEmail(String value) => _emailPattern.hasMatch(value.trim());

/// Small circular avatar with initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.label, this.radius = 18});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.sidebar,
      foregroundColor: colors.mutedText,
      child: Text(
        initialsOf(label),
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600),
      ),
    );
  }
}
