import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

// CheckAdmin — Command Grid
// Executive operations console: dense, calm, precise and permission-aware.
@immutable
class CheckAdminColors {
  const CheckAdminColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.rule,
    required this.ruleStrong,
    required this.ink,
    required this.inkMuted,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.onPrimary,
    required this.brass,
    required this.brassSoft,
    required this.good,
    required this.goodSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
  });

  final Brightness brightness;
  final Color canvas, surface, surfaceRaised, rule, ruleStrong;
  final Color ink, inkMuted, primary, primaryStrong, primarySoft, onPrimary;
  final Color brass,
      brassSoft,
      good,
      goodSoft,
      warning,
      warningSoft,
      danger,
      dangerSoft;
  bool get isDark => brightness == Brightness.dark;

  static const light = CheckAdminColors(
    brightness: Brightness.light,
    canvas: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF0F2F5),
    rule: Color(0xFFE5E8ED),
    ruleStrong: Color(0xFFC7CED8),
    ink: Color(0xFF0B1B2E),
    inkMuted: Color(0xFF5A6678),
    primary: Color(0xFF2854C7),
    primaryStrong: Color(0xFF173FAD),
    primarySoft: Color(0xFFE9EEF9),
    onPrimary: Color(0xFFFFFFFF),
    brass: Color(0xFF8D6B2E),
    brassSoft: Color(0xFFF4EDDC),
    good: Color(0xFF1E7A52),
    goodSoft: Color(0xFFE1F1E9),
    warning: Color(0xFFB45309),
    warningSoft: Color(0xFFFFE9D5),
    danger: Color(0xFFB3261E),
    dangerSoft: Color(0xFFFBE5E3),
  );

  static const dark = CheckAdminColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF09111B),
    surface: Color(0xFF101A28),
    surfaceRaised: Color(0xFF172438),
    rule: Color(0xFF233149),
    ruleStrong: Color(0xFF40516B),
    ink: Color(0xFFE8EDF5),
    inkMuted: Color(0xFF9AA7BA),
    primary: Color(0xFF8AA9FF),
    primaryStrong: Color(0xFF3D6BF0),
    primarySoft: Color(0xFF1A2A52),
    onPrimary: Color(0xFFFFFFFF),
    brass: Color(0xFFD2B27A),
    brassSoft: Color(0xFF2B2418),
    good: Color(0xFF59BE92),
    goodSoft: Color(0xFF16382C),
    warning: Color(0xFFFFB86B),
    warningSoft: Color(0xFF3C2B19),
    danger: Color(0xFFFF8E86),
    dangerSoft: Color(0xFF402523),
  );

  static CheckAdminColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

abstract final class CaSpace {
  // V2 scale: 2 · 4 · 8 · 12 · 16 · 24 · 32
  static const double xxs = 2,
      xs = 4,
      sm = 8,
      md = 12,
      lg = 16,
      xl = 24,
      xxl = 32;
  static const double gutter = 16;
}

abstract final class CaRadius {
  // V2 uses square ledgers, compact controls, and restrained sheet/dialog radii.
  static const double mark = 4, control = 9, panel = 12, sheet = 16;
}

abstract final class CaBreakpoint {
  static const double inset = 600,
      rail = 840,
      extendedRail = 1100,
      twoPane = 900;
}

abstract final class CaMotion {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 210);
  static const curve = Curves.easeOutCubic;
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

const checkAdminName = 'CheckAdmin';
const checkAdminSupportEmail = 'Support@alielhassan.com';

const checkAdminBrand = ChecklistBrand(
  id: 'admin',
  primary: Color(0xFF0B1B2E),
  accent: Color(0xFF1F4FD8),
  accentSoft: Color(0xFFE8EEFC),
  accentDeep: Color(0xFF173EAF),
  onAccent: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF0B1B2E),
  inkMuted: Color(0xFF5A6678),
  borderLight: Color(0xFFE2E6EC),
  iconWellTop: Color(0xFFE8EEFC),
  iconWellBottom: Color(0xFFD5E0FB),
  iconGlyph: Color(0xFF1F4FD8),
);
