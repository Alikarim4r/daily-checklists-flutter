import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-app biometric unlock prefs + optional saved email/password.
class SessionSecurityStore {
  SessionSecurityStore(this.appKey);

  final String appKey;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  bool biometricEnabled = false;
  String? savedEmail;

  String get _prefsBio => 'checklist.session.$appKey.biometric_enabled';
  String get _secureEmail => 'checklist.session.$appKey.email';
  String get _securePassword => 'checklist.session.$appKey.password';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    biometricEnabled = prefs.getBool(_prefsBio) ?? false;
    savedEmail = await _safeRead(_secureEmail);
  }

  Future<void> setBiometricEnabled(bool value) async {
    biometricEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsBio, value);
    if (!value) await clearCredentials();
  }

  Future<bool> get hasStoredCredentials async {
    final email = await _safeRead(_secureEmail);
    final password = await _safeRead(_securePassword);
    return email != null &&
        email.isNotEmpty &&
        password != null &&
        password.isNotEmpty;
  }

  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    await _secure.write(key: _secureEmail, value: email.trim());
    await _secure.write(key: _securePassword, value: password);
    savedEmail = email.trim();
  }

  Future<({String email, String password})?> readCredentials() async {
    final email = await _safeRead(_secureEmail);
    final password = await _safeRead(_securePassword);
    if (email == null || password == null) return null;
    if (email.isEmpty || password.isEmpty) return null;
    return (email: email, password: password);
  }

  Future<void> clearCredentials() async {
    await _secure.delete(key: _secureEmail);
    await _secure.delete(key: _securePassword);
    savedEmail = null;
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }
}
