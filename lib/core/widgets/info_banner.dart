import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

enum InfoBannerKind { info, success, warning, error }

/// Quiet inline callout (tinted background, icon, text, optional action and
/// dismiss button). Use inside page content, not as a toast.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.title,
    this.kind = InfoBannerKind.info,
    this.icon,
    this.action,
    this.onDismiss,
  });

  final String message;
  final String? title;
  final InfoBannerKind kind;

  /// Overrides the kind's default icon.
  final IconData? icon;

  /// Usually a `TextButton`.
  final Widget? action;

  /// Shows a close button when set.
  final VoidCallback? onDismiss;

  static IconData defaultIcon(InfoBannerKind kind) => switch (kind) {
    InfoBannerKind.info => Icons.info_outline,
    InfoBannerKind.success => Icons.check_circle_outline,
    InfoBannerKind.warning => Icons.warning_amber_rounded,
    InfoBannerKind.error => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final (accent, bg, fg) = switch (kind) {
      InfoBannerKind.info => (c.info, c.infoContainer, c.onInfoContainer),
      InfoBannerKind.success => (
        c.success,
        c.successContainer,
        c.onSuccessContainer,
      ),
      InfoBannerKind.warning => (
        c.warning,
        c.warningContainer,
        c.onWarningContainer,
      ),
      InfoBannerKind.error => (
        c.danger,
        c.dangerContainer,
        c.onDangerContainer,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: kind == InfoBannerKind.error,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Insets.md,
          Insets.sm + 2,
          Insets.sm,
          Insets.sm + 2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: Radii.mdAll,
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon ?? defaultIcon(kind), size: 18, color: accent),
            ),
            Gaps.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(color: fg),
                    ),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: fg,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              Gaps.w8,
              Theme(
                data: theme.copyWith(
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      foregroundColor: fg,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                child: action!,
              ),
            ],
            if (onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: fg,
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}
