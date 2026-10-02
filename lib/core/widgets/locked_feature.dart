import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Shows [child] normally when [locked] is false. When locked, [child] is
/// rendered dimmed and inert with a small lock badge, and the whole area
/// becomes one button that calls [onTap] (e.g. open a "Set up AI" sheet).
///
/// ```dart
/// LockedFeature(
///   locked: !aiReady,
///   tooltip: 'Set up AI in Settings',
///   onTap: () => showSetUpAiSheet(context),
///   child: FilledButton.icon(onPressed: generate, ...),
/// )
/// ```
class LockedFeature extends StatelessWidget {
  const LockedFeature({
    super.key,
    required this.child,
    this.locked = true,
    this.onTap,
    this.tooltip,
    this.semanticLabel,
    this.showBadge = true,
    this.dimOpacity = 0.45,
  });

  final Widget child;
  final bool locked;
  final VoidCallback? onTap;

  /// Hover tooltip while locked.
  final String? tooltip;

  /// Screen-reader label while locked (defaults to [tooltip], else "Locked").
  final String? semanticLabel;
  final bool showBadge;
  final double dimOpacity;

  static const IconData lockIcon = Icons.lock_outline;
  static const Key badgeKey = ValueKey('locked-feature-badge');

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    final colors = AppColors.of(context);
    Widget result = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.mdAll,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ExcludeFocus(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(opacity: dimOpacity, child: child),
                ),
              ),
            ),
            if (showBadge)
              PositionedDirectional(
                top: -5,
                end: -5,
                child: Container(
                  key: badgeKey,
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(lockIcon, size: 11, color: colors.mutedText),
                ),
              ),
          ],
        ),
      ),
    );
    result = Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? tooltip ?? 'Locked',
      child: result,
    );
    if (tooltip != null) result = Tooltip(message: tooltip!, child: result);
    return result;
  }
}
