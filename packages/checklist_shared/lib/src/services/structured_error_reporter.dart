import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Installs privacy-conscious, best-effort client error reporting.
///
/// The reporter never sends form answers, evidence, access tokens, email
/// addresses, or arbitrary application state. Reporting failures are swallowed
/// so an unavailable monitoring endpoint cannot affect the user workflow.
class StructuredErrorReporter {
  StructuredErrorReporter._();

  static String? _appKey;
  static PackageInfo? _packageInfo;
  static int _sentCount = 0;
  static final Map<String, DateTime> _recentFingerprints = {};

  /// Installs global Flutter and platform error handlers once for this app.
  static void install({required String appKey}) {
    if (_appKey != null) return;
    _appKey = appKey;
    unawaited(_loadPackageInfo());

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
      unawaited(
        capture(
          details.exception,
          details.stack ?? StackTrace.current,
          module: details.library ?? 'flutter',
        ),
      );
    };

    final dispatcher = ui.PlatformDispatcher.instance;
    final previousPlatformHandler = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      unawaited(capture(error, stack, module: 'platform'));
      return previousPlatformHandler?.call(error, stack) ?? false;
    };
  }

  /// Records a handled error without interrupting the current operation.
  static Future<void> capture(
    Object error,
    StackTrace stack, {
    String module = 'application',
  }) async {
    final appKey = _appKey;
    if (appKey == null || _sentCount >= 30) return;

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final type = error.runtimeType.toString();
      final message = _sanitize(error.toString(), 2000);
      final stackSummary = _sanitizeStack(stack.toString());
      final fingerprint = '$appKey|$module|$type|$message';
      final now = DateTime.now().toUtc();
      final lastSent = _recentFingerprints[fingerprint];
      if (lastSent != null && now.difference(lastSent).inMinutes < 5) return;

      _recentFingerprints[fingerprint] = now;
      _recentFingerprints.removeWhere(
        (_, timestamp) => now.difference(timestamp).inHours >= 1,
      );
      _sentCount += 1;

      final info = _packageInfo ?? await _tryLoadPackageInfo();
      await client.from('client_error_logs').insert({
        'user_id': user.id,
        'app_key': _sanitize(appKey, 80),
        'app_version': _sanitize(info?.version ?? '', 40),
        'build_number': _sanitize(info?.buildNumber ?? '', 40),
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'module': _sanitize(module, 120),
        'error_type': _sanitize(type, 160),
        'error_message': message,
        'stack_summary': stackSummary,
        'occurred_at': now.toIso8601String(),
      });
    } catch (_) {
      // Error reporting is deliberately best-effort and must never recurse.
    }
  }

  static Future<void> _loadPackageInfo() async {
    _packageInfo = await _tryLoadPackageInfo();
  }

  static Future<PackageInfo?> _tryLoadPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  static String _sanitizeStack(String value) {
    final lines = value
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(45)
        .join('\n');
    return _sanitize(lines, 6000);
  }

  static String _sanitize(String value, int maxLength) {
    var result = value
        .replaceAll(
          RegExp(r'bearer\s+[a-z0-9._~-]+', caseSensitive: false),
          'Bearer [REDACTED]',
        )
        .replaceAll(
          RegExp(
            r'\b[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}\b',
          ),
          '[REDACTED_TOKEN]',
        )
        .replaceAll(
          RegExp(
            r'\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b',
            caseSensitive: false,
          ),
          '[REDACTED_EMAIL]',
        )
        .replaceAll(RegExp(r'([?&][^=\s]+)=([^&\s]+)'), r'$1=[REDACTED]')
        .replaceAll(
          RegExp(
            r'(access_token|refresh_token|anon_key|apikey|password)\s*[:=]\s*[^\s,}]+',
            caseSensitive: false,
          ),
          r'$1=[REDACTED]',
        )
        .replaceAll(RegExp(r'[A-Za-z0-9_\-/+=]{96,}'), '[REDACTED_VALUE]')
        .trim();
    if (result.length > maxLength) {
      result = '${result.substring(0, maxLength - 1)}…';
    }
    return result;
  }
}
