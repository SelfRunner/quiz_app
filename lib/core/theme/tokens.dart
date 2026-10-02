import 'package:flutter/widgets.dart';

/// Spacing scale (8pt grid with 4pt half-steps). Use these instead of magic
/// numbers for padding/margins: `EdgeInsets.all(Insets.md)`.
abstract final class Insets {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal page gutter on phones / on wider screens.
  static const double gutter = lg;
  static const double gutterWide = xl;

  /// Default padding inside an `AppCard` / panel.
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// Default padding of a list row.
  static const EdgeInsets row = EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );

  /// Page padding for scrollable content (phones).
  static const EdgeInsets page = EdgeInsets.fromLTRB(lg, lg, lg, xxl);

  /// Page padding for scrollable content (>= medium breakpoint).
  static const EdgeInsets pageWide = EdgeInsets.fromLTRB(xl, xl, xl, xxxl);
}

/// Ready-made gap widgets for `Row`/`Column` children.
abstract final class Gaps {
  static const SizedBox w2 = SizedBox(width: Insets.xxs);
  static const SizedBox w4 = SizedBox(width: Insets.xs);
  static const SizedBox w8 = SizedBox(width: Insets.sm);
  static const SizedBox w12 = SizedBox(width: Insets.md);
  static const SizedBox w16 = SizedBox(width: Insets.lg);
  static const SizedBox w24 = SizedBox(width: Insets.xl);
  static const SizedBox w32 = SizedBox(width: Insets.xxl);

  static const SizedBox h2 = SizedBox(height: Insets.xxs);
  static const SizedBox h4 = SizedBox(height: Insets.xs);
  static const SizedBox h8 = SizedBox(height: Insets.sm);
  static const SizedBox h12 = SizedBox(height: Insets.md);
  static const SizedBox h16 = SizedBox(height: Insets.lg);
  static const SizedBox h24 = SizedBox(height: Insets.xl);
  static const SizedBox h32 = SizedBox(height: Insets.xxl);
  static const SizedBox h48 = SizedBox(height: Insets.xxxl);
}

/// Corner radii. `md` is the default for cards, inputs and buttons.
abstract final class Radii {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;

  /// Same as [lg]: one radius for cards, dialogs and sheets.
  static const double xl = lg;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Max content widths for `ContentContainer` / `ResponsiveScaffold`.
abstract final class ContentWidth {
  /// Forms and settings.
  static const double form = 640;

  /// Long-form reading (notes, quiz play).
  static const double readable = 880;

  /// Running prose (note bodies): ~75 characters per line at body size.
  static const double prose = 720;

  /// Lists and card grids.
  static const double wide = 1200;
}

/// Animation durations.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  /// Default easing for enter/move transitions.
  static const Curve curve = Cubic(0.16, 1, 0.3, 1);

  /// [d], or zero when the platform asks to reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}
