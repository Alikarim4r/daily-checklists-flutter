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

  static LinearGradient get iconWellGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_brand.iconWellTop, _brand.iconWellBottom],
      );

  static LinearGradient get cardWash => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white,
          Color.alphaBlend(accentSoft.withValues(alpha: 0.10), Colors.white),
        ],
      );

  static LinearGradient get appBarGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, accentDeep],
      );

  static BoxDecoration cardDecoration({
    double radius = 16,
    Color? borderColor,
    double borderWidth = 1.2,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? borderLight,
          width: borderWidth,
        ),
        gradient: cardWash,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      );

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
      scaffoldBackgroundColor: Color.alphaBlend(
        accentSoft.withValues(alpha: 0.35),
        const Color(0xFFF5F7F8),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: onAccent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
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
            ),
            child: Padding(padding: padding, child: child),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: ChecklistChrome.iconWellGradient,
        border: Border.all(
          color: ChecklistChrome.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Icon(icon, size: iconSize, color: ChecklistChrome.iconGlyph),
    );
  }
}

PreferredSizeWidget checklistGradientAppBar({
  required String title,
  List<Widget>? actions,
  Widget? leading,
  preferredSize = const Size.fromHeight(kToolbarHeight),
}) {
  return PreferredSize(
    preferredSize: preferredSize,
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: ChecklistChrome.appBarGradient),
      child: AppBar(
        title: Text(title),
        actions: actions,
        leading: leading,
        backgroundColor: Colors.transparent,
        foregroundColor: ChecklistChrome.onAccent,
        elevation: 0,
      ),
    ),
  );
}
