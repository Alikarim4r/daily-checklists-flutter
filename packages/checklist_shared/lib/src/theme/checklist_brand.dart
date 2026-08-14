import 'package:flutter/material.dart';

/// Brand tokens aligned with smart-meters Trial B palettes.
class ChecklistBrand {
  const ChecklistBrand({
    required this.id,
    required this.primary,
    required this.accent,
    required this.accentSoft,
    required this.accentDeep,
    required this.onAccent,
    required this.surface,
    required this.ink,
    required this.inkMuted,
    required this.borderLight,
    required this.iconWellTop,
    required this.iconWellBottom,
    required this.iconGlyph,
  });

  final String id;
  final Color primary;
  final Color accent;
  final Color accentSoft;
  final Color accentDeep;
  final Color onAccent;
  final Color surface;
  final Color ink;
  final Color inkMuted;
  final Color borderLight;
  final Color iconWellTop;
  final Color iconWellBottom;
  final Color iconGlyph;

  /// Viewer ≈ dashboard (charcoal + slate).
  static const viewer = ChecklistBrand(
    id: 'viewer',
    primary: Color(0xFF1B2430),
    accent: Color(0xFF3D5A80),
    accentSoft: Color(0xFFD9E2EC),
    accentDeep: Color(0xFF2B405C),
    onAccent: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF1B2430),
    inkMuted: Color(0xFF5C6775),
    borderLight: Color(0xFFE2E6EB),
    iconWellTop: Color(0xFFEEF2F6),
    iconWellBottom: Color(0xFF9AAFCB),
    iconGlyph: Color(0xFF1B2430),
  );

  /// Entry ≈ meters entry (turquoise).
  static const entry = ChecklistBrand(
    id: 'entry',
    primary: Color(0xFF0E6B6A),
    accent: Color(0xFF14919B),
    accentSoft: Color(0xFFD5EEF0),
    accentDeep: Color(0xFF0A5251),
    onAccent: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF0E3F3E),
    inkMuted: Color(0xFF5A7373),
    borderLight: Color(0xFFD5E3E3),
    iconWellTop: Color(0xFFEAF6F6),
    iconWellBottom: Color(0xFF7FBFBF),
    iconGlyph: Color(0xFF0E6B6A),
  );

  /// Admin ≈ meters admin (burgundy).
  static const admin = ChecklistBrand(
    id: 'admin',
    primary: Color(0xFF6B2D3C),
    accent: Color(0xFF8B3A4A),
    accentSoft: Color(0xFFF0D9DE),
    accentDeep: Color(0xFF4E212C),
    onAccent: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF3F1A24),
    inkMuted: Color(0xFF7A5A62),
    borderLight: Color(0xFFE6D5D9),
    iconWellTop: Color(0xFFF8EEF0),
    iconWellBottom: Color(0xFFC999A3),
    iconGlyph: Color(0xFF6B2D3C),
  );
}

/// Active chrome — call [ChecklistChrome.use] once in each app `main`.
abstract final class ChecklistChrome {
  /// List cards and working panes remain visible over the patterned canvas.
  static const double listSurfaceOpacity = 0.50;

  static ChecklistBrand _brand = ChecklistBrand.viewer;

  static ChecklistBrand get brand => _brand;

  static void use(ChecklistBrand brand) => _brand = brand;

  static Color get primary => _brand.primary;
  static Color get accent => _brand.accent;
  static Color get accentSoft => _brand.accentSoft;
  static Color get accentDeep => _brand.accentDeep;
  static Color get onAccent => _brand.onAccent;
  static Color get surface => _brand.surface;
  static Color get ink => _brand.ink;
  static Color get inkMuted => _brand.inkMuted;
  static Color get borderLight => _brand.borderLight;
  static Color get iconGlyph => _brand.iconGlyph;

  /// Theme-aware text colors for widgets drawn on application chrome.
  ///
  /// Do not use the brand's light [ink] tokens directly on a dark canvas: the
  /// Entry palette is intentionally deep teal and becomes unreadable there.
  static Color inkFor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color inkMutedFor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static LinearGradient get iconWellGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_brand.iconWellTop, _brand.iconWellBottom],
  );

  static LinearGradient get cardWash => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withValues(alpha: listSurfaceOpacity),
      Color.alphaBlend(
        accentSoft.withValues(alpha: 0.10),
        Colors.white,
      ).withValues(alpha: listSurfaceOpacity),
    ],
  );

  static LinearGradient get appBarGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accentDeep],
  );

  /// Deep navy / ink dark surfaces — higher-contrast readable chrome.
  static const Color darkCanvas = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF1C2740);
  static const Color darkSurfaceHigh = Color(0xFF273652);
  static const Color darkInk = Color(0xFFF5F8FC);
  static const Color darkInkMuted = Color(0xFFC2CEDE);
  static const Color darkBorder = Color(0xFF3A4D6A);

  static LinearGradient cardWashFor(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          darkSurface.withValues(alpha: listSurfaceOpacity),
          Color.alphaBlend(
            accent.withValues(alpha: 0.18),
            darkSurfaceHigh,
          ).withValues(alpha: listSurfaceOpacity),
        ],
      );
    }
    return cardWash;
  }

  static BoxDecoration cardDecoration({
    double radius = 16,
    Color? borderColor,
    double borderWidth = 1.2,
    Brightness brightness = Brightness.light,
  }) {
    final dark = brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? (dark ? darkBorder : borderLight),
        width: borderWidth,
      ),
      gradient: cardWashFor(brightness),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: dark ? 0.22 : 0.10),
          blurRadius: dark ? 14 : 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      primary: primary,
      secondary: accent,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: onAccent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface.withValues(alpha: listSurfaceOpacity),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: borderLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Stable light theme for printable A4 paper content (answers, signature).
  /// Kept as a single instance so theme-mode switches do not recreate nested
  /// Theme InheritedWidgets under a live [Material] / signature pad.
  static final ThemeData paperFormTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Colors.white,
    canvasColor: Colors.white,
    iconTheme: const IconThemeData(color: Colors.black87),
    textTheme: Typography.material2021().black.apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    ),
  );

  /// Deep navy ink dark theme aligned with brand accent.
  static ThemeData darkTheme() {
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      surface: darkSurface,
      onSurface: darkInk,
      onSurfaceVariant: darkInkMuted,
      outline: darkBorder,
      surfaceContainerHighest: darkSurfaceHigh,
      error: const Color(0xFFF87171),
      onError: darkCanvas,
    );
    final textTheme = Typography.material2021().white.apply(
      bodyColor: darkInk,
      displayColor: darkInk,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: darkCanvas,
      dialogTheme: const DialogThemeData(backgroundColor: darkSurface),
      drawerTheme: const DrawerThemeData(backgroundColor: darkSurface),
      popupMenuTheme: const PopupMenuThemeData(
        color: darkSurfaceHigh,
        textStyle: TextStyle(color: darkInk),
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      listTileTheme: const ListTileThemeData(
        iconColor: darkInk,
        textColor: darkInk,
        subtitleTextStyle: TextStyle(color: darkInkMuted, fontSize: 13),
        titleTextStyle: TextStyle(
          color: darkInk,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: darkBorder,
      dividerTheme: const DividerThemeData(color: darkBorder, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: onAccent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: darkSurface.withValues(alpha: listSurfaceOpacity),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceHigh,
        labelStyle: const TextStyle(color: darkInkMuted),
        hintStyle: const TextStyle(color: darkInkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkInk,
          side: const BorderSide(color: darkBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return onAccent;
            return darkInk;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return darkSurfaceHigh;
          }),
          side: const WidgetStatePropertyAll(BorderSide(color: darkBorder)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: darkSurfaceHigh,
        contentTextStyle: TextStyle(color: darkInk),
      ),
      iconTheme: const IconThemeData(color: darkInk),
    );
  }
}

class ChecklistBrandCard extends StatelessWidget {
  const ChecklistBrandCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.borderColor,
    this.borderWidth = 1.2,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: ChecklistChrome.cardDecoration(
              borderColor: borderColor,
              borderWidth: borderWidth,
              brightness: brightness,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: brightness == Brightness.dark
                    ? ChecklistChrome.darkInk
                    : ChecklistChrome.ink,
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class ChecklistIconWell extends StatelessWidget {
  const ChecklistIconWell({
    super.key,
    required this.icon,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: dark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ChecklistChrome.darkSurfaceHigh,
                  Color.alphaBlend(
                    ChecklistChrome.accent.withValues(alpha: 0.45),
                    ChecklistChrome.darkSurface,
                  ),
                ],
              )
            : ChecklistChrome.iconWellGradient,
        border: Border.all(
          color: ChecklistChrome.accent.withValues(alpha: dark ? 0.55 : 0.35),
        ),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: dark ? ChecklistChrome.darkInk : ChecklistChrome.iconGlyph,
      ),
    );
  }
}

PreferredSizeWidget checklistGradientAppBar({
  required String title,
  List<Widget>? actions,
  Widget? leading,
  bool automaticallyImplyLeading = true,
  Size preferredSize = const Size.fromHeight(kToolbarHeight),
}) {
  return PreferredSize(
    preferredSize: preferredSize,
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: ChecklistChrome.appBarGradient),
      child: AppBar(
        title: Text(title),
        actions: actions,
        // Only pass [leading] when set — explicit null used to suppress
        // imply + Drawer stealing the back affordance.
        leading: leading,
        automaticallyImplyLeading: leading == null && automaticallyImplyLeading,
        backgroundColor: Colors.transparent,
        foregroundColor: ChecklistChrome.onAccent,
        elevation: 0,
      ),
    ),
  );
}

/// Prefer this over relying on [AppBar.automaticallyImplyLeading] when the
/// scaffold also has a [Drawer] (drawer steals the leading slot).
Widget checklistBackButton(
  BuildContext context, {
  VoidCallback? onPressed,
  Color? color,
}) {
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    color: color ?? ChecklistChrome.onAccent,
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
  );
}
