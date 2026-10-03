import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'checkin_tokens.dart';

abstract final class CheckInTheme {
  static final ThemeData light = _build(CheckInColors.light);
  static final ThemeData dark = _build(CheckInColors.dark);

  static ThemeData _build(CheckInColors c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.ink,
      secondary: c.primaryStrong,
      onSecondary: c.onPrimary,
      secondaryContainer: c.primarySoft,
      onSecondaryContainer: c.ink,
      tertiary: c.warning,
      onTertiary: c.isDark ? c.canvas : Colors.white,
      tertiaryContainer: c.warningSoft,
      onTertiaryContainer: c.ink,
      error: c.danger,
      onError: c.isDark ? c.canvas : Colors.white,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.ink,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.lineStrong,
      outlineVariant: c.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.isDark ? CheckInColors.light.ink : c.ink,
      onInverseSurface: c.isDark ? CheckInColors.light.surface : c.surface,
      inversePrimary: c.isDark
          ? CheckInColors.light.primary
          : CheckInColors.dark.primary,
      surfaceTint: Colors.transparent,
    );

    final base = c.isDark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final text = base
        .copyWith(
          headlineMedium: base.headlineMedium?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.45,
            height: 1.15,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
            height: 1.2,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 14.5, height: 1.45),
          bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.4),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        )
        .apply(
          bodyColor: c.ink,
          displayColor: c.ink,
          fontFamilyFallback: const ['Noto Sans Arabic', 'Noto Sans'],
        );
    final textTheme = text.copyWith(
      bodySmall: text.bodySmall?.copyWith(color: c.inkMuted),
      labelSmall: text.labelSmall?.copyWith(color: c.inkMuted),
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CiRadius.control),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(CiRadius.control),
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
      dividerColor: c.line,
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
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
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CiRadius.panel),
        ),
      ),
      iconTheme: IconThemeData(color: c.ink, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkMuted,
        textColor: c.ink,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        minVerticalPadding: CiSpace.sm,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CiSpace.md,
          vertical: 15,
        ),
        labelStyle: TextStyle(color: c.inkMuted),
        floatingLabelStyle: TextStyle(color: c.primary),
        hintStyle: TextStyle(color: c.inkMuted),
        prefixIconColor: c.inkMuted,
        suffixIconColor: c.inkMuted,
        border: inputBorder(c.lineStrong),
        enabledBorder: inputBorder(c.lineStrong),
        focusedBorder: inputBorder(c.primary, 1.8),
        errorBorder: inputBorder(c.danger),
        focusedErrorBorder: inputBorder(c.danger, 1.8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primaryStrong,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.surfaceRaised,
          disabledForegroundColor: c.inkMuted,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: CiSpace.lg),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          disabledForegroundColor: c.inkMuted,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: CiSpace.md),
          side: BorderSide(color: c.lineStrong),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(48, 48),
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
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.line,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CiRadius.sheet),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 8,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CiRadius.sheet),
          ),
        ),
        constraints: const BoxConstraints(maxWidth: 680),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        width: 344,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.isDark ? c.surfaceRaised : c.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: c.isDark ? c.ink : c.surface,
        ),
        actionTextColor: CheckInColors.dark.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CiRadius.control),
        ),
        elevation: 4,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.isDark ? c.surfaceRaised : c.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.labelMedium?.copyWith(
          color: c.isDark ? c.ink : c.surface,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.danger,
        textColor: c.isDark ? c.canvas : Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primarySoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? c.primaryStrong
                : c.inkMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? c.primaryStrong
                : c.inkMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? c.primary
                  : c.lineStrong,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? c.primarySoft
                : c.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.primaryStrong : c.ink,
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.primarySoft,
        headerForegroundColor: c.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CiRadius.sheet),
        ),
      ),
    );
  }
}
