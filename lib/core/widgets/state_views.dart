import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import 'error_message.dart';

/// Minimal empty state: a thin line icon, a title, an optional message and
/// action. Centered and scrollable by default; [compact] renders it inline
/// (e.g. inside a section) with less padding.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 28 : 36, color: colors.faintText),
          compact ? Gaps.h8 : Gaps.h16,
          Text(
            title,
            style: compact
                ? theme.textTheme.titleSmall
                : theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            Gaps.h4,
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.mutedText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[compact ? Gaps.h12 : Gaps.h16, action!],
        ],
      ),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xl),
        child: Center(child: content),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xxl),
        child: content,
      ),
    );
  }
}

/// Error message with an optional retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: 'Could not load',
    message: errorMessage(error),
    action: onRetry == null
        ? null
        : OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
  );
}

/// Shows loading / error / data for an [AsyncValue]. Keeps showing previous
/// data while reloading.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  /// Shown while loading without data (defaults to a centered spinner; e.g.
  /// pass `const LoadingSkeleton()` for lists).
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return data(value.requireValue);
    if (value.hasError) return ErrorView(error: value.error, onRetry: onRetry);
    return loading ?? const Center(child: CircularProgressIndicator());
  }
}

/// Body for a deleted / no-longer-shared item.
class NotFoundView extends StatelessWidget {
  const NotFoundView({super.key, required this.what});

  final String what;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.search_off,
    title: '$what not found',
    message: 'It may have been deleted, or it is no longer shared with you.',
  );
}
