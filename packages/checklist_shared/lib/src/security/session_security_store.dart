import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-app biometric unlock preference.
///
/// Supabase owns the refresh session. Raw account passwords are never persisted.
class SessionSecurityStore {
  SessionSecurityStore(this.appKey);

  final String appKey;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
    mOptions: MacOsOptions(usesDataProtectionKeychain: true),
  );

  bool biometricEnabled = false;

  String get _prefsBio => 'checklist.session.$appKey.biometric_enabled';
  // Legacy keys are deleted during migration from password-based quick sign-in.
  String get _secureEmail => 'checklist.session.$appKey.email';
  String get _securePassword => 'checklist.session.$appKey.password';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    biometricEnabled = prefs.getBool(_prefsBio) ?? false;
    await _clearLegacyCredentials();
  }

  Future<void> setBiometricEnabled(bool value) async {
    biometricEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsBio, value);
  }

  Future<void> _clearLegacyCredentials() async {
    try {
      await _secure.delete(key: _secureEmail);
      await _secure.delete(key: _securePassword);
    } catch (_) {
      // A locked/unavailable keychain must not block application startup.
    }
  }
}
