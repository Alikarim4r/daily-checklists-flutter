import 'package:flutter/material.dart';

/// Paper-form chrome themes for checklist tables (header labels, title bar).
enum FormThemeKey {
  classicGold('classic_gold'),
  navySand('navy_sand'),
  forest('forest'),
  slate('slate'),
  crimson('crimson'),
  teal('teal'),
  custom('custom'),
  inherit('inherit');

  const FormThemeKey(this.dbValue);
  final String dbValue;

  static FormThemeKey fromDb(String? value) {
    if (value == null || value.isEmpty) return FormThemeKey.classicGold;
    return FormThemeKey.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => FormThemeKey.classicGold,
    );
  }

  String get labelEn => switch (this) {
    FormThemeKey.classicGold => 'Classic Gold',
    FormThemeKey.navySand => 'Navy & Sand',
    FormThemeKey.forest => 'Forest',
    FormThemeKey.slate => 'Slate',
    FormThemeKey.crimson => 'Crimson',
    FormThemeKey.teal => 'Teal',
    FormThemeKey.custom => 'Custom color',
    FormThemeKey.inherit => 'Inherit from parent level',
  };

  String get labelAr => switch (this) {
    FormThemeKey.classicGold => 'ذهبي كلاسيكي',
    FormThemeKey.navySand => 'بحري ورملي',
    FormThemeKey.forest => 'غابة',
    FormThemeKey.slate => 'رمادي',
    FormThemeKey.crimson => 'خمري',
    FormThemeKey.teal => 'تركواز',
    FormThemeKey.custom => 'لون مخصص',
    FormThemeKey.inherit => 'وراثة من المستوى الأعلى',
  };

  String labelFor(String language) => language == 'ar' ? labelAr : labelEn;

  bool get isSelectablePreset =>
      this != FormThemeKey.inherit && this != FormThemeKey.custom;
}

/// Colors used by on-screen + PDF checklist paper chrome.
class FormPaperTheme {
  const FormPaperTheme({
    required this.key,
    required this.accent,
    required this.accentText,
    required this.border,
    this.customHex,
  });

  final FormThemeKey key;

  /// Header label / title banner fill.
  final Color accent;

  /// Text on accent fills.
  final Color accentText;
  final Color border;
  final String? customHex;

  static const classicGold = FormPaperTheme(
    key: FormThemeKey.classicGold,
    accent: Color(0xFFE8C547),
    accentText: Color(0xFF111827),
    border: Color(0xFF000000),
  );

  static const navySand = FormPaperTheme(
    key: FormThemeKey.navySand,
    accent: Color(0xFF1E3A5F),
    accentText: Color(0xFFF8FAFC),
    border: Color(0xFF0F172A),
  );

  static const forest = FormPaperTheme(
    key: FormThemeKey.forest,
    accent: Color(0xFF3F6212),
    accentText: Color(0xFFF7FEE7),
    border: Color(0xFF1A2E05),
  );

  static const slate = FormPaperTheme(
    key: FormThemeKey.slate,
    accent: Color(0xFF64748B),
    accentText: Color(0xFFF8FAFC),
    border: Color(0xFF0F172A),
  );

  static const crimson = FormPaperTheme(
    key: FormThemeKey.crimson,
    accent: Color(0xFF9F1239),
    accentText: Color(0xFFFFF1F2),
    border: Color(0xFF4C0519),
  );

  static const teal = FormPaperTheme(
    key: FormThemeKey.teal,
    accent: Color(0xFF0F766E),
    accentText: Color(0xFFF0FDFA),
    border: Color(0xFF134E4A),
  );

  static FormPaperTheme preset(FormThemeKey key) => switch (key) {
    FormThemeKey.classicGold => classicGold,
    FormThemeKey.navySand => navySand,
    FormThemeKey.forest => forest,
    FormThemeKey.slate => slate,
    FormThemeKey.crimson => crimson,
    FormThemeKey.teal => teal,
    FormThemeKey.custom => classicGold,
    FormThemeKey.inherit => classicGold,
  };

  /// Resolve effective theme for a site row (optionally with parent campus).
  static FormPaperTheme resolve({
    required String? themeDb,
    String? accentHex,
    String? parentThemeDb,
    String? parentAccentHex,
  }) {
    final key = FormThemeKey.fromDb(themeDb);
    if (key == FormThemeKey.inherit) {
      // A campus cannot inherit in the UI, but guard corrupt/legacy rows so
      // recursive `inherit -> inherit` data can never overflow the stack.
      final parentKey = FormThemeKey.fromDb(parentThemeDb);
      if (parentKey == FormThemeKey.inherit) return classicGold;
      return resolve(themeDb: parentKey.dbValue, accentHex: parentAccentHex);
    }
    if (key == FormThemeKey.custom) {
      final parsed = parseHex(accentHex) ?? const Color(0xFFE8C547);
      return FormPaperTheme(
        key: FormThemeKey.custom,
        accent: parsed,
        accentText: contrastInk(parsed),
        border: Color.lerp(parsed, Colors.black, 0.55) ?? Colors.black,
        customHex: accentHex,
      );
    }
    return preset(key);
  }

  static Color? parseHex(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 3) {
      h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
    }
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  static Color contrastInk(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.55 ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
  }

  static String hexOf(Color c) {
    // ignore: deprecated_member_use
    final v = c.value & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static int asArgb32(Color c) {
    // ignore: deprecated_member_use
    return c.value;
  }

  /// Preset cards shown in the admin picker (excludes inherit/custom).
  static List<FormPaperTheme> get pickerPresets => const [
    classicGold,
    navySand,
    forest,
    slate,
    crimson,
    teal,
  ];
}
