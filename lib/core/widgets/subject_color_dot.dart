import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small round subject color marker. Subject colors are only ever used as
/// small accents like this (or an `AppCard.accentColor` left border).
///
/// [color] is the ARGB32 value stored in `Subject.color`; when null, [fallback]
/// is used, else a hollow ring is drawn.
class SubjectColorDot extends StatelessWidget {
  const SubjectColorDot({
    super.key,
    this.color,
    this.fallback,
    this.size = 10,
    this.semanticLabel,
  });

  final int? color;
  final Color? fallback;
  final double size;
  final String? semanticLabel;

  /// The resolved fill color, or null for "no color".
  Color? get resolvedColor => color == null ? fallback : Color(color!);

  @override
  Widget build(BuildContext context) {
    final fill = resolvedColor;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: fill == null
            ? Border.all(color: AppColors.of(context).border, width: 1.5)
            : null,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: dot);
    return Semantics(label: semanticLabel, child: dot);
  }
}
