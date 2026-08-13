import 'package:flutter/services.dart';

/// Native, dependency-free sound and haptic feedback used by both field apps.
abstract final class ChecklistFeedback {
  static Future<void> success({
    required bool soundEnabled,
    required bool hapticsEnabled,
  }) async {
    if (soundEnabled) {
      await SystemSound.play(SystemSoundType.click);
    }
    if (hapticsEnabled) {
      await HapticFeedback.mediumImpact();
    }
  }

  static Future<void> alert({
    required bool soundEnabled,
    required bool hapticsEnabled,
  }) async {
    if (soundEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
    if (hapticsEnabled) {
      await HapticFeedback.heavyImpact();
    }
  }

  static Future<void> selection({required bool hapticsEnabled}) async {
    if (hapticsEnabled) {
      await HapticFeedback.selectionClick();
    }
  }
}
