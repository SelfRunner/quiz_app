import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';

/// A generation error translated for people, with the actions that help.
class FriendlyAiError {
  const FriendlyAiError({
    required this.title,
    required this.message,
    this.hint,
    this.openSettings = false,
    this.canRetry = true,
  });

  final String title;
  final String message;
  final String? hint;

  /// Offer an "Open settings" button (missing/invalid key, provider switch).
  final bool openSettings;
  final bool canRetry;
}

/// Maps errors thrown by `AiService` (see the AI layer notes in
/// `docs/CONTRACTS.md`) to user-facing text and actions.
FriendlyAiError describeAiError(Object error) {
  switch (error) {
    case AiException(kind: AiErrorKind.missingApiKey):
      return FriendlyAiError(
        title: 'No AI provider set up',
        message: error.message,
        hint:
            'Add an API key for Gemini, OpenAI, Anthropic or an '
            'OpenAI-compatible service in Settings. Keys stay on this device.',
        openSettings: true,
        canRetry: false,
      );
    case AiException(kind: AiErrorKind.invalidApiKey):
      return FriendlyAiError(
        title: 'The API key was rejected',
        message: error.message,
        hint: 'Check or replace the key in Settings.',
        openSettings: true,
        canRetry: false,
      );
    case AiException(kind: AiErrorKind.rateLimited):
      return FriendlyAiError(
        title: 'Rate limit or quota reached',
        message: error.message,
        hint:
            'Wait a minute and try again, or check the quota/credits of '
            'your plan with the provider.',
      );
    case AiException(kind: AiErrorKind.invalidOutput):
      return FriendlyAiError(
        title: "The AI's answer couldn't be used",
        message: error.message,
        hint:
            'Try again, ask for fewer questions, or pick another model in '
            'Settings.',
        openSettings: true,
      );
    case AiException():
      return FriendlyAiError(
        title: 'The AI provider returned an error',
        message: error.message,
        openSettings: true,
      );
    case TranscriptUnavailableException():
      return FriendlyAiError(
        title: "Couldn't read the video's captions",
        message: error.message,
        hint:
            'Gemini can watch YouTube videos directly: switch to it in '
            'Settings. Or paste the transcript or your notes into the text '
            'field.',
        openSettings: true,
      );
    case ValidationException():
      return FriendlyAiError(
        title: 'Check your input',
        message: error.message,
        canRetry: false,
      );
    case NetworkException():
      return FriendlyAiError(
        title: 'Connection problem',
        message: error.message,
        hint: 'Check your internet connection and try again.',
      );
    case AppException():
      return FriendlyAiError(
        title: 'Something went wrong',
        message: error.message,
      );
    default:
      return const FriendlyAiError(
        title: 'Something went wrong',
        message: 'An unexpected error occurred while generating.',
      );
  }
}

/// Error banner with "Open settings" / "Try again" actions.
class AiErrorCard extends StatelessWidget {
  const AiErrorCard({
    super.key,
    required this.error,
    this.onOpenSettings,
    this.onRetry,
    this.onDismiss,
  });

  final Object error;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = describeAiError(error);
    return Card(
      key: const Key('ai-error'),
      color: scheme.errorContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.error_outline,
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.message,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                      if (info.hint != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          info.hint!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: Icon(Icons.close, color: scheme.onErrorContainer),
                    onPressed: onDismiss,
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  if (info.openSettings && onOpenSettings != null)
                    TextButton.icon(
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open settings'),
                    ),
                  if (info.canRetry && onRetry != null)
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
