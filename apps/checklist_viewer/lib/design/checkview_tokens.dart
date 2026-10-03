import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

// CheckView design direction (viewer-local; Entry and Admin are untouched).
//
// Purpose   Review, approve and act on facility inspections across
//           organization > zone > campus > checklist, with operations
//           oversight and corrective actions.
// Audience  Supervisors, reviewers and owners scanning the same screens every
//           day, mostly on Android phones, sometimes on desktop.
// Tone      A quiet, precise instrument: architectural drawings, not a
//           marketing dashboard.
// Signature The drawing "title block": every screen opens with a ruled strip
//           of labelled context cells closed by a brass datum line. While data
//           loads, the datum line itself becomes the progress indicator.
// Rules     Context first, state next, exceptions next, history last.
//           Surfaces are separated by tone and hairlines, never by shadows.
//           Brass is reserved for the datum line. Status colors carry meaning
//           only. Figures use tabular numerals. Motion answers user actions.

/// Color tokens for one brightness. Resolve with [CheckViewColors.of].
@immutable
class CheckViewColors {
  const CheckViewColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.hairline,
    required this.rule,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.accentFill,
    required this.onAccentFill,
    required this.accentSoft,
    required this.datum,
    required this.approved,
    required this.pending,
    required this.returned,
    required this.rejected,
    required this.neutral,
  });

  final Brightness brightness;

  /// Concrete canvas behind everything.
  final Color canvas;

  /// Ledger and sheet surface.
  final Color surface;

  /// Pressed / selected / skeleton tone one step above [surface].
  final Color raised;

  /// Dividers between rows and title-block cells.
  final Color hairline;

  /// Stronger outline for controls.
  final Color rule;

  final Color ink;
  final Color inkMuted;

  /// Interactive text and icons.
  final Color accent;

  /// Filled primary actions.
  final Color accentFill;
  final Color onAccentFill;

  /// Selection wash.
  final Color accentSoft;

  /// Brass datum line — the one signature element.
  final Color datum;

  final Color approved;
  final Color pending;
  final Color returned;
  final Color rejected;
  final Color neutral;

  bool get isDark => brightness == Brightness.dark;

  static const light = CheckViewColors(
    brightness: Brightness.light,
    canvas: Color(0xFFECEEF0),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF3F5F7),
    hairline: Color(0xFFD9DEE4),
    rule: Color(0xFFB8C0CA),
    ink: Color(0xFF1B2430),
    inkMuted: Color(0xFF586374),
    accent: Color(0xFF2F4E73),
    accentFill: Color(0xFF2F4E73),
    onAccentFill: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE3EAF2),
    datum: Color(0xFFA27A38),
    approved: Color(0xFF2B7A57),
    pending: Color(0xFF955800),
    returned: Color(0xFFB04A0C),
    rejected: Color(0xFFB42318),
    neutral: Color(0xFF586374),
  );

  static const dark = CheckViewColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF0F141A),
    surface: Color(0xFF171E27),
    raised: Color(0xFF1F2833),
    hairline: Color(0xFF2A3441),
    rule: Color(0xFF3B4757),
    ink: Color(0xFFE8ECF1),
    inkMuted: Color(0xFF9EA9B8),
    accent: Color(0xFF9BBBE0),
    accentFill: Color(0xFF3D5F88),
    onAccentFill: Color(0xFFFFFFFF),
    accentSoft: Color(0xFF223246),
    datum: Color(0xFFC9A764),
    approved: Color(0xFF63C79B),
    pending: Color(0xFFF0B659),
    returned: Color(0xFFF2915A),
    rejected: Color(0xFFF7837A),
    neutral: Color(0xFF9EA9B8),
  );

  static CheckViewColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 4-point spacing scale.
abstract final class CvSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter.
  static const double gutter = 16;
}

/// Radii are tied to hierarchy, not applied uniformly.
abstract final class CvRadius {
  /// Status marks and skeleton bars.
  static const double mark = 3;

  /// Buttons, inputs, choice strips.
  static const double control = 10;

  /// Ledger panels.
  static const double ledger = 12;

  /// Sheets and dialogs.
  static const double sheet = 20;
}

abstract final class CvMotion {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  /// Honors the platform "reduce motion" setting.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Layout breakpoints shared by the shell and screens.
abstract final class CvBreakpoint {
  /// Navigation rail instead of a bottom bar.
  static const double rail = 640;

  /// List + detail side by side on the inspections screen.
  static const double split = 960;

  /// Two-column operations overview.
  static const double twoColumn = 1040;
}

/// Tabular numerals keep counts and dates aligned in ledgers.
const cvTabular = [FontFeature.tabularFigures()];

/// Shared widgets (auth gate, notices, A4 sheet, subscription screen) read
/// [ChecklistChrome]; this keeps them on CheckView's palette without changing
/// shared code. The `viewer` id is unchanged.
const checkViewBrand = ChecklistBrand(
  id: 'viewer',
  primary: Color(0xFF1B2430),
  accent: Color(0xFF2F4E73),
  accentSoft: Color(0xFFE3EAF2),
  accentDeep: Color(0xFF213953),
  onAccent: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF1B2430),
  inkMuted: Color(0xFF586374),
  borderLight: Color(0xFFD9DEE4),
  iconWellTop: Color(0xFFEFF2F5),
  iconWellBottom: Color(0xFFB9C6D6),
  iconGlyph: Color(0xFF1B2430),
);

/// Public product name; identifiers (package, bundle, application id) stay.
const checkViewName = 'CheckView';

/// The only support channel shown anywhere in CheckView.
const checkViewSupportEmail = 'Support@alielhassan.com';
