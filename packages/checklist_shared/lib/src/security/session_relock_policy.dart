/// Tracks genuine background time before requiring another biometric unlock.
///
/// Desktop window resizing and brief mobile interruptions can emit lifecycle
/// transitions. They must not immediately lock an active working session.
class SessionRelockPolicy {
  SessionRelockPolicy({
    this.timeout = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration timeout;
  final DateTime Function() _clock;
  DateTime? _backgroundedAt;

  void onBackgrounded() {
    _backgroundedAt ??= _clock();
  }

  /// Returns true only when the app remained outside the foreground for at
  /// least [timeout]. A resize, route change, or brief interruption is ignored.
  bool onResumed() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return false;
    return _clock().difference(backgroundedAt) >= timeout;
  }
}
