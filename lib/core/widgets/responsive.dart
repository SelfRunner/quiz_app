import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Layout breakpoints shared by all screens.
abstract final class Breakpoints {
  /// Navigation rail / wider layouts from here.
  static const double medium = 720;

  /// Side-by-side editors, two-pane layouts, extended sidebar.
  static const double expanded = 1000;

  static bool isMedium(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;

  /// Horizontal page gutter for the current width.
  static double gutter(BuildContext context) =>
      isMedium(context) ? Insets.gutterWide : Insets.gutter;
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

/// Top-centered content column capped at [maxWidth] with a responsive
/// horizontal gutter (16 on phones, 24 from the medium breakpoint).
/// Use [ContentWidth.readable] for notes, [ContentWidth.wide] for grids.
class ContentContainer extends StatelessWidget {
  const ContentContainer({
    super.key,
    required this.child,
    this.maxWidth = ContentWidth.readable,
    this.padding,
  });

  final Widget child;
  final double maxWidth;

  /// Overrides the default horizontal gutter.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding:
            padding ??
            EdgeInsets.symmetric(horizontal: Breakpoints.gutter(context)),
        child: child,
      ),
    ),
  );
}

/// A [Scaffold] whose body is laid out in a [ContentContainer]. With
/// [scrollable], the body scrolls full-width (scrollbar at the window edge)
/// with page padding above and below.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.maxWidth = ContentWidth.readable,
    this.scrollable = false,
    this.padding,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final double maxWidth;
  final bool scrollable;

  /// Overrides the content padding (defaults: horizontal gutter, plus
  /// vertical page padding when [scrollable]).
  final EdgeInsetsGeometry? padding;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (scrollable) {
      final wide = Breakpoints.isMedium(context);
      content = SingleChildScrollView(
        child: ContentContainer(
          maxWidth: maxWidth,
          padding: padding ?? (wide ? Insets.pageWide : Insets.page),
          child: body,
        ),
      );
    } else {
      content = ContentContainer(
        maxWidth: maxWidth,
        padding: padding,
        child: body,
      );
    }
    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: content,
    );
  }
}
