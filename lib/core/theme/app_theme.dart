import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../data/local/hive_boxes.dart';
import 'app_colors.dart';
import 'app_typography.dart';
import 'tokens.dart';

export 'app_colors.dart';
export 'app_typography.dart';
export 'tokens.dart';

/// Minimal Material 3 light/dark themes: neutral surfaces, one restrained
/// accent ([AppPalette.accent]), hairline borders instead of shadows, flat
/// app bars and a tuned platform-font [TextTheme]. Tokens: [Insets], [Gaps],
/// [Radii], [ContentWidth]; extra semantic colors: [AppColors].
abstract final class AppTheme {
  /// The accent color (kept for backwards compatibility).
  static const Color seed = AppPalette.accent;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = AppPalette.scheme(brightness);
    final colors = brightness == Brightness.light
        ? AppColors.light
        : AppColors.dark;
    final text = AppTypography.textTheme(scheme);
    final dark = brightness == Brightness.dark;

    const roundedMd = RoundedRectangleBorder(borderRadius: Radii.mdAll);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: Insets.lg,
      vertical: Insets.sm,
    );
    const buttonMinSize = Size(64, 40);
    final buttonText = text.labelLarge!.copyWith(fontWeight: FontWeight.w600);

    WidgetStateProperty<BorderSide?> focusSide(
      Color ring, [
      BorderSide? otherwise,
    ]) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: ring, width: 2)
          : otherwise,
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: Radii.mdAll,
      borderSide: BorderSide(color: colors.border),
    );

    final popupShape = RoundedRectangleBorder(
      borderRadius: Radii.mdAll,
      side: BorderSide(color: colors.hairline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: colors.hairline,
      hoverColor: colors.hover,
      focusColor: colors.pressed,
      highlightColor: colors.pressed,
      splashColor: colors.pressed,
      splashFactory: InkRipple.splashFactory,
      extensions: [colors],
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: Insets.lg,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
        actionsIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.lgAll,
          side: BorderSide(color: colors.hairline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        horizontalTitleGap: Insets.md,
        minLeadingWidth: 24,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: text.bodyLarge!.copyWith(
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        subtitleTextStyle: text.bodyMedium!.copyWith(color: colors.mutedText),
        leadingAndTrailingTextStyle: text.labelMedium!.copyWith(
          color: colors.mutedText,
        ),
        selectedColor: scheme.onSurface,
        selectedTileColor: colors.hover,
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.md,
        ),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        disabledBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: colors.hairline),
        ),
        focusedBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: colors.focusRing, width: 1.5),
        ),
        errorBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        hintStyle: text.bodyLarge!.copyWith(color: colors.faintText),
        labelStyle: text.bodyLarge!.copyWith(color: colors.mutedText),
        floatingLabelStyle: text.bodyMedium!.copyWith(color: colors.mutedText),
        helperStyle: text.bodySmall!.copyWith(color: colors.mutedText),
        prefixIconColor: colors.mutedText,
        suffixIconColor: colors.mutedText,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(buttonPadding),
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          shape: const WidgetStatePropertyAll(roundedMd),
          textStyle: WidgetStatePropertyAll(buttonText),
          side: focusSide(scheme.onSurface),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(colors.card),
          foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
          padding: const WidgetStatePropertyAll(buttonPadding),
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          shape: const WidgetStatePropertyAll(roundedMd),
          textStyle: WidgetStatePropertyAll(buttonText),
          side: focusSide(colors.focusRing, BorderSide(color: colors.border)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? colors.faintText
                : scheme.onSurface,
          ),
          padding: const WidgetStatePropertyAll(buttonPadding),
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          shape: const WidgetStatePropertyAll(roundedMd),
          textStyle: WidgetStatePropertyAll(buttonText),
          side: focusSide(colors.focusRing, BorderSide(color: colors.border)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
          shape: const WidgetStatePropertyAll(roundedMd),
          textStyle: WidgetStatePropertyAll(buttonText),
          side: focusSide(colors.focusRing),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(roundedMd),
          side: focusSide(colors.focusRing),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(roundedMd),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? scheme.secondaryContainer
                : Colors.transparent,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        focusElevation: 2,
        hoverElevation: 2,
        highlightElevation: 1,
        shape: const RoundedRectangleBorder(borderRadius: Radii.xlAll),
        extendedTextStyle: buttonText,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: scheme.secondaryContainer,
        disabledColor: colors.hover,
        side: BorderSide(color: colors.border),
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
        labelStyle: text.labelLarge!.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.labelLarge!.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
        iconTheme: IconThemeData(color: colors.mutedText, size: 16),
        checkmarkColor: scheme.onSurface,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.xlAll,
          side: BorderSide(color: colors.hairline),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        iconColor: colors.mutedText,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        modalBackgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: colors.border,
        dragHandleSize: const Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.xl),
          ),
          side: BorderSide(color: colors.hairline),
        ),
        constraints: const BoxConstraints(maxWidth: ContentWidth.form),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium!.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xs,
        ),
        textStyle: text.labelMedium!.copyWith(color: scheme.onInverseSurface),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: Radii.smAll,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.1),
        shape: popupShape,
        textStyle: text.bodyMedium,
        labelTextStyle: WidgetStatePropertyAll(text.bodyMedium),
        menuPadding: const EdgeInsets.symmetric(vertical: Insets.xs),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(popupShape),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.sidebar,
        elevation: 0,
        useIndicator: true,
        indicatorColor: colors.pressed,
        indicatorShape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
        selectedIconTheme: IconThemeData(color: scheme.onSurface, size: 20),
        unselectedIconTheme: IconThemeData(color: colors.mutedText, size: 20),
        selectedLabelTextStyle: text.labelLarge!.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelLarge!.copyWith(
          color: colors.mutedText,
        ),
        minWidth: 72,
        minExtendedWidth: 232,
        groupAlignment: -1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.sidebar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: colors.pressed,
        indicatorShape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected)
                ? scheme.onSurface
                : colors.mutedText,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium!.copyWith(
            color: s.contains(WidgetState.selected)
                ? scheme.onSurface
                : colors.mutedText,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: colors.mutedText,
        indicatorColor: scheme.onSurface,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: colors.hairline,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall!.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) ? 8 : 6,
        ),
        radius: const Radius.circular(Radii.sm),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => scheme.onSurface.withValues(
            alpha: s.contains(WidgetState.dragged)
                ? 0.45
                : s.contains(WidgetState.hovered)
                ? 0.32
                : 0.18,
          ),
        ),
        crossAxisMargin: 2,
        mainAxisMargin: 2,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Radii.xsAll),
        side: BorderSide(color: colors.mutedText, width: 1.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.24),
        selectionHandleColor: scheme.primary,
      ),
    );
  }
}

/// App theme mode, persisted in the Hive `prefs` box (device-scoped, kept on
/// sign-out). Falls back to in-memory when the box is not open (tests).
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const String prefsKey = 'theme_mode';

  static Box<String>? get _prefs => Hive.isBoxOpen(HiveBoxes.prefs)
      ? Hive.box<String>(HiveBoxes.prefs)
      : null;

  @override
  ThemeMode build() =>
      ThemeMode.values.asNameMap()[_prefs?.get(prefsKey)] ?? ThemeMode.system;

  void set(ThemeMode mode) {
    state = mode;
    _prefs?.put(prefsKey, mode.name).ignore();
  }
}
