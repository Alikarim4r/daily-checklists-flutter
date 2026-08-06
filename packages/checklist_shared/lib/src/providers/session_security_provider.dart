import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/biometric_auth_service.dart';
import '../security/session_security_store.dart';

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return BiometricAuthService();
});

/// Configure once per app via [sessionSecurityAppKeyProvider].
final sessionSecurityAppKeyProvider = Provider<String>((ref) {
  throw UnimplementedError('Override sessionSecurityAppKeyProvider per app');
});

final sessionSecurityStoreProvider = Provider<SessionSecurityStore>((ref) {
  return SessionSecurityStore(ref.watch(sessionSecurityAppKeyProvider));
});

class SessionSecurityState {
  const SessionSecurityState({
    this.biometricEnabled = false,
    this.canUseBiometrics = false,
    this.unlocked = true,
    this.biometricLabel = 'Biometrics',
    this.ready = false,
  });

  final bool biometricEnabled;
  final bool canUseBiometrics;
  final bool unlocked;
  final String biometricLabel;
  final bool ready;

  bool get requiresUnlock =>
      biometricEnabled && canUseBiometrics && !unlocked;

  SessionSecurityState copyWith({
    bool? biometricEnabled,
    bool? canUseBiometrics,
    bool? unlocked,
    String? biometricLabel,
    bool? ready,
  }) {
    return SessionSecurityState(
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      canUseBiometrics: canUseBiometrics ?? this.canUseBiometrics,
      unlocked: unlocked ?? this.unlocked,
      biometricLabel: biometricLabel ?? this.biometricLabel,
      ready: ready ?? this.ready,
    );
  }
}

class SessionSecurityNotifier extends StateNotifier<SessionSecurityState> {
  SessionSecurityNotifier(this._ref) : super(const SessionSecurityState()) {
    _bootstrap();
  }

  final Ref _ref;

  SessionSecurityStore get _store => _ref.read(sessionSecurityStoreProvider);
  BiometricAuthService get _bio => _ref.read(biometricAuthServiceProvider);

  Future<void> _bootstrap() async {
    await _store.load();
    final can = await _bio.canUseBiometrics();
    final label = await _bio.preferredLabel(isArabic: false);
    state = SessionSecurityState(
      biometricEnabled: _store.biometricEnabled && can,
      canUseBiometrics: can,
      unlocked: !(_store.biometricEnabled && can),
      biometricLabel: label,
      ready: true,
    );
  }

  Future<void> refreshLabel({required bool isArabic}) async {
    final label = await _bio.preferredLabel(isArabic: isArabic);
    state = state.copyWith(biometricLabel: label);
  }

  Future<void> onPasswordSignIn({
    required String email,
    required String password,
  }) async {
    if (_store.biometricEnabled && state.canUseBiometrics) {
      await _store.saveCredentials(email: email, password: password);
    }
    state = state.copyWith(unlocked: true);
  }

  Future<String?> enableBiometrics({
    required String email,
    required String password,
    required String reason,
  }) async {
    if (!state.canUseBiometrics) {
      return 'Biometrics unavailable on this device';
    }
    final ok = await _bio.authenticate(localizedReason: reason);
    if (!ok) return 'Biometric confirmation failed';
    await _store.saveCredentials(email: email, password: password);
    await _store.setBiometricEnabled(true);
    state = state.copyWith(biometricEnabled: true, unlocked: true);
    return null;
  }

  Future<void> disableBiometrics() async {
    await _store.setBiometricEnabled(false);
    state = state.copyWith(biometricEnabled: false, unlocked: true);
  }

  Future<bool> unlock({required String reason}) async {
    final ok = await _bio.authenticate(localizedReason: reason);
    if (ok) state = state.copyWith(unlocked: true);
    return ok;
  }

  Future<({String email, String password})?> storedCredentials() {
    return _store.readCredentials();
  }

  void lockForResume() {
    if (state.biometricEnabled && state.canUseBiometrics) {
      state = state.copyWith(unlocked: false);
    }
  }
}

final sessionSecurityProvider =
    StateNotifierProvider<SessionSecurityNotifier, SessionSecurityState>((ref) {
  return SessionSecurityNotifier(ref);
});
