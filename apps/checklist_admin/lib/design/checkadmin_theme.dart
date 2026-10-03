import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'checkadmin_tokens.dart';

abstract final class CheckAdminTheme {
  static final ThemeData light = _build(CheckAdminColors.light);
  static final ThemeData dark = _build(CheckAdminColors.dark);

  static ThemeData _build(CheckAdminColors c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.ink,
      secondary: c.brass,
      onSecondary: c.isDark ? c.canvas : Colors.white,
      secondaryContainer: c.brassSoft,
      onSecondaryContainer: c.ink,
      tertiary: c.good,
      onTertiary: c.isDark ? c.canvas : Colors.white,
      tertiaryContainer: c.goodSoft,
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
      outline: c.ruleStrong,
      outlineVariant: c.rule,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.isDark ? CheckAdminColors.light.ink : c.ink,
      onInverseSurface: c.isDark ? CheckAdminColors.light.surface : c.surface,
      inversePrimary: c.isDark
          ? CheckAdminColors.light.primary
          : CheckAdminColors.dark.primary,
      surfaceTint: Colors.transparent,
    );

    final base = c.isDark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final text = base
        .copyWith(
          headlineMedium: base.headlineMedium?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -.3,
            height: 1.2,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -.2,
            height: 1.3,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -.2,
            height: 1.3,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.33,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.38,
          ),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.4),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 13, height: 1.38),
          bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.35),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 1.4,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 1.33,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 1.28,
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

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CaRadius.control),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(CaRadius.control),
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
      dividerColor: c.rule,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        toolbarHeight: 54,
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
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
      ),
      dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkMuted,
        textColor: c.ink,
        selectedColor: c.primaryStrong,
        selectedTileColor: c.primarySoft,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
        minVerticalPadding: 9,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        labelStyle: TextStyle(color: c.inkMuted),
        floatingLabelStyle: TextStyle(color: c.primary),
        hintStyle: TextStyle(color: c.inkMuted),
        prefixIconColor: c.inkMuted,
        suffixIconColor: c.inkMuted,
        border: inputBorder(c.ruleStrong),
        enabledBorder: inputBorder(c.ruleStrong),
        focusedBorder: inputBorder(c.primary, 1.7),
        errorBorder: inputBorder(c.danger),
        focusedErrorBorder: inputBorder(c.danger, 1.7),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primaryStrong,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: shape,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: BorderSide(color: c.ruleStrong),
          shape: shape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(48, 48),
          shape: shape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceRaised,
        selectedColor: c.primarySoft,
        side: BorderSide(color: c.rule),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.labelMedium,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(c.surfaceRaised),
        headingTextStyle: textTheme.labelMedium?.copyWith(color: c.inkMuted),
        dataTextStyle: textTheme.bodySmall,
        dividerThickness: 1,
        horizontalMargin: 14,
        columnSpacing: 22,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 60,
        backgroundColor: c.surface,
        indicatorColor: c.primarySoft,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
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
                : FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primarySoft,
        selectedIconTheme: IconThemeData(color: c.primaryStrong),
        unselectedIconTheme: IconThemeData(color: c.inkMuted),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: c.primaryStrong,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: c.inkMuted,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? c.primary
                  : c.ruleStrong,
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
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.rule,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CaRadius.sheet),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.ruleStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CaRadius.sheet),
          ),
        ),
        constraints: const BoxConstraints(maxWidth: 760),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        width: 360,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.isDark ? c.surfaceRaised : c.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: c.isDark ? c.ink : c.surface,
        ),
        actionTextColor: CheckAdminColors.dark.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CaRadius.control),
        ),
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
    );
  }
}
