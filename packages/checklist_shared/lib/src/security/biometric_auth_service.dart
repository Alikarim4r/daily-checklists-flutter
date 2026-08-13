import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around [LocalAuthentication] with web-safe fallbacks.
class BiometricAuthService {
  BiometricAuthService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<bool> canUseBiometrics() async {
    if (!isSupportedPlatform) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck || supported;
    } catch (_) {
      return false;
    }
  }

  Future<String> preferredLabel({required bool isArabic}) async {
    if (!isSupportedPlatform) {
      return isArabic ? 'البصمة / الوجه' : 'Biometrics';
    }
    try {
      final types = await _auth.getAvailableBiometrics();
      final hasFace = types.contains(BiometricType.face);
      final hasFinger =
          types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong) ||
          types.contains(BiometricType.weak);
      if (hasFace && hasFinger) {
        return isArabic ? 'البصمة أو الوجه' : 'Fingerprint or Face ID';
      }
      if (hasFace) return isArabic ? 'الوجه' : 'Face ID';
      if (hasFinger) return isArabic ? 'بصمة الإصبع' : 'Fingerprint';
    } catch (_) {}
    return isArabic ? 'البصمة / الوجه' : 'Biometrics';
  }

  Future<bool> authenticate({required String localizedReason}) async {
    if (!isSupportedPlatform) return false;
    try {
      final canAuth = await canUseBiometrics();
      if (!canAuth) return false;
      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e, st) {
      debugPrint('BiometricAuthService.authenticate failed: $e\n$st');
      return false;
    }
  }
}
