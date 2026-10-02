import 'package:flutter/material.dart';

/// Semantic colors that Material's [ColorScheme] does not cover. Read with
/// `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.sidebar,
    required this.card,
    required this.hairline,
    required this.border,
    required this.hover,
    required this.pressed,
    required this.focusRing,
    required this.mutedText,
    required this.faintText,
    required this.skeleton,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.onDangerContainer,
  });

  /// Navigation sidebar / bottom bar background.
  final Color sidebar;

  /// Cards, dialogs, sheets and menus (slightly lifted from the page).
  final Color card;

  /// 1px separators and card outlines.
  final Color hairline;

  /// Stronger 1px borders (inputs, outlined buttons).
  final Color border;

  /// Hover / pressed overlays for rows and cards.
  final Color hover;
  final Color pressed;

  /// Keyboard focus outline.
  final Color focusRing;

  /// Secondary text (subtitles, metadata) and tertiary text (hints).
  final Color mutedText;
  final Color faintText;

  /// Loading skeleton blocks.
  final Color skeleton;

  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;

  static const AppColors light = AppColors(
    sidebar: Color(0xFFF4F3F1),
    card: Color(0xFFFFFFFF),
    hairline: Color(0xFFE8E6E3),
    border: Color(0xFFD7D4D0),
    hover: Color(0x0A1C1B1A),
    pressed: Color(0x141C1B1A),
    focusRing: Color(0xFF3E63DD),
    mutedText: Color(0xFF6B6863),
    faintText: Color(0xFF9C9893),
    skeleton: Color(0xFFECEAE7),
    info: Color(0xFF3E63DD),
    infoContainer: Color(0xFFEEF2FE),
    onInfoContainer: Color(0xFF1F2D5C),
    success: Color(0xFF2B8A3E),
    successContainer: Color(0xFFEAF6EC),
    onSuccessContainer: Color(0xFF1B4D26),
    warning: Color(0xFFB0700B),
    warningContainer: Color(0xFFFDF4E3),
    onWarningContainer: Color(0xFF5C3A06),
    danger: Color(0xFFCD2B31),
    dangerContainer: Color(0xFFFDECEC),
    onDangerContainer: Color(0xFF7A1A1D),
  );

  static const AppColors dark = AppColors(
    sidebar: Color(0xFF202020),
    card: Color(0xFF212121),
    hairline: Color(0xFF2E2E2E),
    border: Color(0xFF424242),
    hover: Color(0x0FFFFFFF),
    pressed: Color(0x1AFFFFFF),
    focusRing: Color(0xFF8DA4EF),
    mutedText: Color(0xFFA19F9B),
    faintText: Color(0xFF75736F),
    skeleton: Color(0xFF2A2A2A),
    info: Color(0xFF8DA4EF),
    infoContainer: Color(0xFF1C2340),
    onInfoContainer: Color(0xFFD6DEFB),
    success: Color(0xFF6CC47F),
    successContainer: Color(0xFF16291B),
    onSuccessContainer: Color(0xFFCDEED4),
    warning: Color(0xFFF0B85A),
    warningContainer: Color(0xFF2E2310),
    onWarningContainer: Color(0xFFF8E3BD),
    danger: Color(0xFFF2777A),
    dangerContainer: Color(0xFF3A1A1B),
    onDangerContainer: Color(0xFFFFD7D7),
  );

  /// The extension of the current theme (falls back to [light]/[dark] by
  /// brightness when a theme without it is in use, e.g. in tests).
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith({
    Color? sidebar,
    Color? card,
    Color? hairline,
    Color? border,
    Color? hover,
    Color? pressed,
    Color? focusRing,
    Color? mutedText,
    Color? faintText,
    Color? skeleton,
    Color? info,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? onDangerContainer,
  }) => AppColors(
    sidebar: sidebar ?? this.sidebar,
    card: card ?? this.card,
    hairline: hairline ?? this.hairline,
    border: border ?? this.border,
    hover: hover ?? this.hover,
    pressed: pressed ?? this.pressed,
    focusRing: focusRing ?? this.focusRing,
    mutedText: mutedText ?? this.mutedText,
    faintText: faintText ?? this.faintText,
    skeleton: skeleton ?? this.skeleton,
    info: info ?? this.info,
    infoContainer: infoContainer ?? this.infoContainer,
    onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warning: warning ?? this.warning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    danger: danger ?? this.danger,
    dangerContainer: dangerContainer ?? this.dangerContainer,
    onDangerContainer: onDangerContainer ?? this.onDangerContainer,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      sidebar: l(sidebar, other.sidebar),
      card: l(card, other.card),
      hairline: l(hairline, other.hairline),
      border: l(border, other.border),
      hover: l(hover, other.hover),
      pressed: l(pressed, other.pressed),
      focusRing: l(focusRing, other.focusRing),
      mutedText: l(mutedText, other.mutedText),
      faintText: l(faintText, other.faintText),
      skeleton: l(skeleton, other.skeleton),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      onInfoContainer: l(onInfoContainer, other.onInfoContainer),
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      danger: l(danger, other.danger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      onDangerContainer: l(onDangerContainer, other.onDangerContainer),
    );
  }
}

/// Neutral color schemes with one restrained accent (indigo).
abstract final class AppPalette {
  static const Color accent = Color(0xFF3E63DD);
  static const Color accentDark = Color(0xFF8DA4EF);

  static ColorScheme scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    if (brightness == Brightness.light) {
      return base.copyWith(
        primary: accent,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE6ECFD),
        onPrimaryContainer: const Color(0xFF1F2D5C),
        secondary: const Color(0xFF57534E),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFECEAE7),
        onSecondaryContainer: const Color(0xFF1C1B1A),
        tertiary: const Color(0xFF0F766E),
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFE3F3F0),
        onTertiaryContainer: const Color(0xFF0B3D39),
        error: const Color(0xFFCD2B31),
        onError: Colors.white,
        errorContainer: const Color(0xFFFDECEC),
        onErrorContainer: const Color(0xFF7A1A1D),
        surface: const Color(0xFFFBFBFA),
        onSurface: const Color(0xFF1C1B1A),
        onSurfaceVariant: const Color(0xFF6B6863),
        surfaceDim: const Color(0xFFE6E4E1),
        surfaceBright: const Color(0xFFFFFFFF),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF6F5F3),
        surfaceContainer: const Color(0xFFF1F0EE),
        surfaceContainerHigh: const Color(0xFFECEAE7),
        surfaceContainerHighest: const Color(0xFFE6E4E1),
        outline: const Color(0xFFD7D4D0),
        outlineVariant: const Color(0xFFE8E6E3),
        inverseSurface: const Color(0xFF2A2927),
        onInverseSurface: const Color(0xFFF4F3F1),
        inversePrimary: accentDark,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: Colors.transparent,
      );
    }
    return base.copyWith(
      primary: accentDark,
      onPrimary: const Color(0xFF0F1A3D),
      primaryContainer: const Color(0xFF263163),
      onPrimaryContainer: const Color(0xFFDCE3FC),
      secondary: const Color(0xFFC8C6C2),
      onSecondary: const Color(0xFF1C1B1A),
      secondaryContainer: const Color(0xFF2F2F2F),
      onSecondaryContainer: const Color(0xFFEDEDEC),
      tertiary: const Color(0xFF5EC4B6),
      onTertiary: const Color(0xFF062B27),
      tertiaryContainer: const Color(0xFF133A35),
      onTertiaryContainer: const Color(0xFFCFF0EA),
      error: const Color(0xFFF2777A),
      onError: const Color(0xFF3B0A0C),
      errorContainer: const Color(0xFF3A1A1B),
      onErrorContainer: const Color(0xFFFFD7D7),
      surface: const Color(0xFF191919),
      onSurface: const Color(0xFFEDEDEC),
      onSurfaceVariant: const Color(0xFFA19F9B),
      surfaceDim: const Color(0xFF141414),
      surfaceBright: const Color(0xFF383838),
      surfaceContainerLowest: const Color(0xFF141414),
      surfaceContainerLow: const Color(0xFF1F1F1F),
      surfaceContainer: const Color(0xFF242424),
      surfaceContainerHigh: const Color(0xFF2B2B2B),
      surfaceContainerHighest: const Color(0xFF333333),
      outline: const Color(0xFF424242),
      outlineVariant: const Color(0xFF2E2E2E),
      inverseSurface: const Color(0xFFEDEDEC),
      onInverseSurface: const Color(0xFF1C1B1A),
      inversePrimary: accent,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
  }
}
