import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Small keycaps showing a keyboard shortcut ("Ctrl" "S" / "⌘" "S"), with an
/// optional label before them. Use [KeyboardShortcutHint.activator] to render
/// a [SingleActivator] with platform-appropriate modifier names.
class KeyboardShortcutHint extends StatelessWidget {
  const KeyboardShortcutHint({super.key, required this.keys, this.label})
    : activator = null;

  const KeyboardShortcutHint.activator(
    SingleActivator this.activator, {
    super.key,
    this.label,
  }) : keys = const [];

  final List<String> keys;
  final SingleActivator? activator;
  final String? label;

  static bool _isApple(TargetPlatform p) =>
      p == TargetPlatform.macOS || p == TargetPlatform.iOS;

  /// Key labels for [activator] on [platform] (`⌘ ⇧ S` on Apple platforms,
  /// `Ctrl Shift S` elsewhere). `meta` maps to Ctrl's slot on Apple.
  static List<String> keysFor(
    SingleActivator activator,
    TargetPlatform platform,
  ) {
    final apple = _isApple(platform);
    final trigger = activator.trigger;
    final keyLabel = trigger.keyLabel.isNotEmpty
        ? trigger.keyLabel
        : (trigger.debugName ?? '?');
    return [
      if (activator.control) apple ? '⌃' : 'Ctrl',
      if (activator.meta) apple ? '⌘' : 'Meta',
      if (activator.alt) apple ? '⌥' : 'Alt',
      if (activator.shift) apple ? '⇧' : 'Shift',
      keyLabel.length == 1 ? keyLabel.toUpperCase() : keyLabel,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final resolved = activator == null
        ? keys
        : keysFor(activator!, theme.platform);
    final keyStyle = theme.textTheme.labelSmall!.copyWith(
      color: colors.mutedText,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0,
    );
    return Semantics(
      label: [?label, 'Shortcut ${resolved.join('+')}'].join(', '),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.mutedText,
                ),
              ),
              Gaps.w8,
            ],
            for (var i = 0; i < resolved.length; i++) ...[
              if (i > 0) Gaps.w2,
              Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: Radii.xsAll,
                  border: Border(
                    top: BorderSide(color: colors.border),
                    left: BorderSide(color: colors.border),
                    right: BorderSide(color: colors.border),
                    bottom: BorderSide(color: colors.border, width: 2),
                  ),
                ),
                child: Text(resolved[i], style: keyStyle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
