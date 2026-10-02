import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/error_message.dart';

/// Form validators for the auth screens. Return null when valid.
abstract final class AuthValidators {
  static const int minPasswordLength = 8;

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Sign-in: only checks presence (server decides).
  static String? passwordPresent(String? value) =>
      (value ?? '').isEmpty ? 'Enter your password' : null;

  /// Sign-up: length plus at least one letter and one digit.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Choose a password';
    if (v.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    if (!RegExp('[A-Za-z]').hasMatch(v) || !RegExp('[0-9]').hasMatch(v)) {
      return 'Use letters and numbers';
    }
    return null;
  }

  static String? Function(String?) confirmPassword(
    String Function() password,
  ) => (value) {
    if ((value ?? '').isEmpty) return 'Repeat your password';
    if (value != password()) return 'Passwords do not match';
    return null;
  };

  static String? displayName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter a display name';
    if (v.length > 60) return 'Keep it under 60 characters';
    return null;
  }
}

/// Friendlier wording for common Supabase auth errors.
String friendlyAuthMessage(Object error) {
  if (error is! AppException) return errorMessage(error);
  final raw = error.message;
  final lower = raw.toLowerCase();
  if (lower.contains('invalid login credentials')) {
    return 'Wrong email or password.';
  }
  if (lower.contains('email not confirmed')) {
    return 'Please confirm your email first. Check your inbox for the link.';
  }
  if (lower.contains('already registered') ||
      lower.contains('already exists')) {
    return 'An account with this email already exists. Try signing in.';
  }
  if (lower.contains('rate limit') || lower.contains('too many')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (error is NetworkException) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return raw;
}
