import 'package:flutter/material.dart';

/// Typography-first text theme on the platform's default font (no bundled
/// font: works offline everywhere). Headings are semibold with slightly tight
/// tracking; body text has generous line height for reading.
abstract final class AppTypography {
  static TextStyle _s(
    double size,
    double height,
    FontWeight weight, [
    double letterSpacing = 0,
  ]) => TextStyle(
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Sizes/weights/heights only; colors are applied by [textTheme].
  static final TextTheme base = TextTheme(
    displayLarge: _s(44, 1.15, FontWeight.w700, -0.8),
    displayMedium: _s(36, 1.18, FontWeight.w700, -0.6),
    displaySmall: _s(30, 1.2, FontWeight.w600, -0.45),
    headlineLarge: _s(28, 1.25, FontWeight.w600, -0.4),
    headlineMedium: _s(24, 1.28, FontWeight.w600, -0.3),
    headlineSmall: _s(20, 1.3, FontWeight.w600, -0.2),
    titleLarge: _s(18, 1.35, FontWeight.w600, -0.1),
    titleMedium: _s(15, 1.4, FontWeight.w600),
    titleSmall: _s(14, 1.4, FontWeight.w600),
    bodyLarge: _s(16, 1.6, FontWeight.w400),
    bodyMedium: _s(14, 1.55, FontWeight.w400),
    bodySmall: _s(12, 1.5, FontWeight.w400, 0.1),
    labelLarge: _s(14, 1.3, FontWeight.w500, 0.05),
    labelMedium: _s(12, 1.3, FontWeight.w500, 0.2),
    labelSmall: _s(11, 1.3, FontWeight.w500, 0.4),
  );

  static TextTheme textTheme(ColorScheme scheme) =>
      base.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
}
