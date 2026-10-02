import 'package:flutter/material.dart';

/// Layout breakpoints shared by all screens.
abstract final class Breakpoints {
  /// Navigation rail / wider layouts from here.
  static const double medium = 720;

  /// Side-by-side editors, two-pane layouts.
  static const double expanded = 1000;

  static bool isMedium(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;
}

/// Centers [child] horizontally and caps its width (readable line lengths on
/// wide screens).
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, this.maxWidth = 960, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
