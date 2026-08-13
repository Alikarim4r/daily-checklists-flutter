import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Connectivity checks that distinguish a device-interface report from
/// actual reachability of the checklist backend.
abstract final class ChecklistConnectivity {
  static const _networkMarkers = <String>[
    'socketexception',
    'failed host lookup',
    'connection refused',
    'connection reset',
    'connection closed',
    'network is unreachable',
    'network unreachable',
    'no route to host',
    'software caused connection abort',
    'clientexception',
    'xmlhttprequest error',
    'timed out',
    'timeoutexception',
  ];

  /// True only for transport failures. Validation, permissions, conflicts,
  /// and other server responses must remain visible to the operator.
  static bool isTransportFailure(Object error) {
    final value = '$error'.toLowerCase();
    return _networkMarkers.any(value.contains);
  }

  /// Uses the OS interface state as a fast path, then probes Supabase when
  /// macOS/desktop incorrectly reports `none` despite a working connection.
  static Future<bool> canReachBackend(
    SupabaseClient client, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final interfaces = await Connectivity().checkConnectivity();
      if (interfaces.any((value) => value != ConnectivityResult.none)) {
        return true;
      }
    } catch (_) {
      // Continue to the authoritative backend probe.
    }

    try {
      await client
          .from('checklist_templates')
          .select('id')
          .limit(1)
          .timeout(timeout);
      return true;
    } catch (error) {
      // Any PostgREST response proves the server is reachable, even if that
      // response is a policy/authorization error.
      return !isTransportFailure(error);
    }
  }
}
