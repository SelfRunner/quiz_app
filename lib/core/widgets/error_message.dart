import 'package:flutter/material.dart';

import '../errors/app_exception.dart';

/// User-safe message for any error: [AppException.message], else a generic
/// fallback (raw errors may contain internals and are never shown).
String errorMessage(
  Object? error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is AppException) return error.message;
  return fallback;
}

/// Shows a floating error snackbar with a user-safe message for [error].
void showErrorSnackBar(BuildContext context, Object? error, {String? prefix}) {
  final message = errorMessage(error);
  showAppSnackBar(
    context,
    prefix == null ? message : '$prefix: $message',
    isError: true,
  );
}

/// Shows a floating snackbar, replacing the current one.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: isError ? TextStyle(color: scheme.onErrorContainer) : null,
        ),
        backgroundColor: isError ? scheme.errorContainer : null,
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
}
