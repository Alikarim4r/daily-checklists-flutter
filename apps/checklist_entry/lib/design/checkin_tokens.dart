import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

// CheckIn design direction
//
// Purpose   Complete field inspections quickly and correctly, even with one
//           hand, poor connectivity, or interruptions.
// Audience  Technicians and inspectors moving through real facilities.
// Tone      A calm precision field instrument: practical, durable, direct.
// Signature The "field rail": a strong teal progress line that keeps current
//           task, completion, and exceptions visible without decorative UI.
// Rules     Current work before navigation; exceptions before metadata;
//           one primary action; evidence and sync state always explicit.

@immutable
class CheckInColors {
  const CheckInColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkMuted,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.onPrimary,
    required this.good,
    required this.goodSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
  });

  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color line;
  final Color lineStrong;
  final Color ink;
  final Color inkMuted;
  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color onPrimary;
  final Color good;
  final Color goodSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;

  bool get isDark => brightness == Brightness.dark;

  static const light = CheckInColors(
    brightness: Brightness.light,
    canvas: Color(0xFFF4F6F5),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF0F4F2),
    line: Color(0xFFE0E6E3),
    lineStrong: Color(0xFFB8C3BF),
    ink: Color(0xFF15211F),
    inkMuted: Color(0xFF53625E),
    primary: Color(0xFF08756A),
    primaryStrong: Color(0xFF064F49),
    primarySoft: Color(0xFFDDEFEA),
    onPrimary: Color(0xFFFFFFFF),
    good: Color(0xFF187354),
    goodSoft: Color(0xFFDDF1E8),
    warning: Color(0xFF9A5700),
    warningSoft: Color(0xFFFFE9C7),
    danger: Color(0xFFB42318),
    dangerSoft: Color(0xFFFFE2DE),
  );

  static const dark = CheckInColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF0B1312),
    surface: Color(0xFF121D1B),
    surfaceRaised: Color(0xFF1A2724),
    line: Color(0xFF263632),
    lineStrong: Color(0xFF425550),
    ink: Color(0xFFE7EFEC),
    inkMuted: Color(0xFFA6B5B0),
    primary: Color(0xFF70D7CA),
    primaryStrong: Color(0xFF84E1D5),
    primarySoft: Color(0xFF173934),
    onPrimary: Color(0xFF06211E),
    good: Color(0xFF76D6AE),
    goodSoft: Color(0xFF16382C),
    warning: Color(0xFFFFBE63),
    warningSoft: Color(0xFF3F2E16),
    danger: Color(0xFFFF8D83),
    dangerSoft: Color(0xFF442522),
  );

  static CheckInColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

abstract final class CiSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double gutter = 16;
}

abstract final class CiRadius {
  static const double indicator = 4;
  static const double control = 10;
  static const double panel = 14;
  static const double sheet = 20;
}

abstract final class CiBreakpoint {
  static const double tablet = 700;
  static const double wide = 1040;
}

abstract final class CiMotion {
  static const quick = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

const checkInName = 'CheckIn';
const checkInSupportEmail = 'Support@alielhassan.com';

/// Keeps legacy shared widgets on CheckIn's palette without changing the
/// existing application identity used by storage, auth, or analytics.
const checkInBrand = ChecklistBrand(
  id: 'entry',
  primary: Color(0xFF123B37),
  accent: Color(0xFF006B62),
  accentSoft: Color(0xFFD8EEEA),
  accentDeep: Color(0xFF004C46),
  onAccent: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF15211F),
  inkMuted: Color(0xFF53625E),
  borderLight: Color(0xFFD7DEDB),
  iconWellTop: Color(0xFFE5F3F0),
  iconWellBottom: Color(0xFFB9DAD4),
  iconGlyph: Color(0xFF004C46),
);
