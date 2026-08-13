import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override sharedPreferencesProvider in main()');
});

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) {
    return ThemeModeController(ref.watch(sharedPreferencesProvider));
  },
);

/// Whether operational notification badges and notice centres are enabled.
final notificationsEnabledProvider =
    StateNotifierProvider<BoolPreferenceController, bool>((ref) {
      return BoolPreferenceController(
        ref.watch(sharedPreferencesProvider),
        key: 'checklist_notifications_enabled',
        defaultValue: true,
      );
    });

/// Whether important actions and newly detected follow-ups play system sounds.
final soundEnabledProvider =
    StateNotifierProvider<BoolPreferenceController, bool>((ref) {
      return BoolPreferenceController(
        ref.watch(sharedPreferencesProvider),
        key: 'checklist_sound_enabled',
        defaultValue: true,
      );
    });

/// Whether taps, successful saves, and alerts use device haptic feedback.
final hapticsEnabledProvider =
    StateNotifierProvider<BoolPreferenceController, bool>((ref) {
      return BoolPreferenceController(
        ref.watch(sharedPreferencesProvider),
        key: 'checklist_haptics_enabled',
        defaultValue: true,
      );
    });

class BoolPreferenceController extends StateNotifier<bool> {
  BoolPreferenceController(
    this._prefs, {
    required this.key,
    required bool defaultValue,
  }) : super(_prefs.getBool(key) ?? defaultValue);

  final SharedPreferences _prefs;
  final String key;

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _prefs.setBool(key, enabled);
  }
}

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;
  static const _key = 'checklist_theme_mode';

  static ThemeMode _read(SharedPreferences prefs) {
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final v = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_key, v);
  }
}
