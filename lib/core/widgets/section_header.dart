import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Small, quiet heading above a group of content ("Notes 4   + New").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(top: Insets.lg, bottom: Insets.sm),
  });

  final String title;

  /// Optional item count shown faintly after the title.
  final int? count;
  final String? subtitle;

  /// Usually a `TextButton`/`IconButton` (e.g. "New").
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      text: title,
                      children: [
                        if (count != null)
                          TextSpan(
                            text: '  $count',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.faintText,
                            ),
                          ),
                      ],
                    ),
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[Gaps.w8, trailing!],
        ],
      ),
    );
  }
}
