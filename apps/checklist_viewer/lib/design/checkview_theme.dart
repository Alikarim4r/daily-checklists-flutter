import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'checkview_tokens.dart';

/// Built once per brightness. Do not key [MaterialApp] on these: a
/// theme-dependent key previously caused an `InheritedElement._dependents`
/// assertion when switching modes.
abstract final class CheckViewTheme {
  static final ThemeData light = _build(CheckViewColors.light);
  static final ThemeData dark = _build(CheckViewColors.dark);

  static ThemeData _build(CheckViewColors c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.accentFill,
      onPrimary: c.onAccentFill,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.ink,
      secondary: c.accent,
      onSecondary: c.onAccentFill,
      secondaryContainer: c.accentSoft,
      onSecondaryContainer: c.ink,
      tertiary: c.datum,
      onTertiary: c.canvas,
      error: c.rejected,
      onError: c.isDark ? c.canvas : Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.raised,
      outline: c.rule,
      outlineVariant: c.hairline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.isDark ? CheckViewColors.light.ink : c.ink,
      onInverseSurface: c.isDark ? CheckViewColors.light.surface : c.surface,
      inversePrimary: c.isDark ? CheckViewColors.light.accent : c.accentSoft,
      surfaceTint: Colors.transparent,
    );

    final base = c.isDark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final text = base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontSize: 40,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.8,
            height: 1.05,
            fontFeatures: cvTabular,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            height: 1.25,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            height: 1.25,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 1.3,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 1.3,
          ),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
          bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.4),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        )
        .apply(bodyColor: c.ink, displayColor: c.ink);
    // Supporting text is muted after `apply` sets the ink color everywhere.
    final textTheme = text.copyWith(
      bodySmall: text.bodySmall?.copyWith(color: c.inkMuted),
      labelSmall: text.labelSmall?.copyWith(color: c.inkMuted),
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CvRadius.control),
    );
    const controlMinSize = Size(64, 48);
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(CvRadius.control),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      cardColor: c.surface,
      dividerColor: c.hairline,
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.ink, size: 22),
        actionsIconTheme: IconThemeData(color: c.ink, size: 22),
        systemOverlayStyle:
            (c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.ink, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkMuted,
        textColor: c.ink,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: CvSpace.lg),
        minVerticalPadding: CvSpace.md,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CvSpace.lg,
          vertical: 14,
        ),
        labelStyle: TextStyle(color: c.inkMuted),
        floatingLabelStyle: TextStyle(color: c.accent),
        hintStyle: TextStyle(color: c.inkMuted),
        prefixIconColor: c.inkMuted,
        suffixIconColor: c.inkMuted,
        border: inputBorder(c.rule),
        enabledBorder: inputBorder(c.rule),
        focusedBorder: inputBorder(c.accent, 1.6),
        errorBorder: inputBorder(c.rejected),
        focusedErrorBorder: inputBorder(c.rejected, 1.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accentFill,
          foregroundColor: c.onAccentFill,
          disabledBackgroundColor: c.raised,
          disabledForegroundColor: c.inkMuted,
          minimumSize: controlMinSize,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          disabledForegroundColor: c.inkMuted,
          minimumSize: controlMinSize,
          padding: const EdgeInsets.symmetric(horizontal: CvSpace.lg),
          side: BorderSide(color: c.rule),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: controlMinSize,
          padding: const EdgeInsets.symmetric(horizontal: CvSpace.md),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(48, 48),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onAccentFill
              : c.inkMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.accentFill : c.raised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : c.rule,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CvRadius.sheet),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 6,
        dragHandleColor: c.rule,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CvRadius.sheet),
          ),
        ),
        constraints: const BoxConstraints(maxWidth: 640),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        width: 344,
        shape: const RoundedRectangleBorder(),
        endShape: const RoundedRectangleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CvRadius.control),
          side: BorderSide(color: c.hairline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.isDark ? c.raised : c.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: c.isDark ? c.ink : c.surface,
        ),
        actionTextColor: CheckViewColors.dark.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CvRadius.control),
        ),
        elevation: 2,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.isDark ? c.raised : c.ink,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: textTheme.labelMedium?.copyWith(
          color: c.isDark ? c.ink : c.surface,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.rejected,
        textColor: c.isDark ? c.canvas : Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: c.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CvRadius.control),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
            size: 22,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        indicatorColor: c.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CvRadius.control),
        ),
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: IconThemeData(color: c.ink, size: 22),
        unselectedIconTheme: IconThemeData(color: c.inkMuted, size: 22),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: c.ink,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: c.inkMuted,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.canvas,
        headerForegroundColor: c.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CvRadius.sheet),
        ),
      ),
    );
  }
}
