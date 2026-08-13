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
    'xmlhttprequest error',
    'network request failed',
    'timed out',
    'timeoutexception',
  ];

  /// True only for transport failures. Validation, permissions, conflicts,
  /// and other server responses must remain visible to the operator.
  static bool isTransportFailure(Object error) {
    final value = '$error'.toLowerCase();
    return _networkMarkers.any(value.contains);
  }

  /// Probes the actual backend. An attached Wi-Fi/mobile interface does not
  /// prove that DNS, the internet, or Supabase is reachable.
  static Future<bool> canReachBackend(
    SupabaseClient client, {
    Duration timeout = const Duration(seconds: 5),
    Future<void> Function()? probe,
  }) async {
    try {
      if (probe != null) {
        await probe().timeout(timeout);
      } else {
        await client
            .from('checklist_templates')
            .select('id')
            .limit(1)
            .timeout(timeout);
      }
      return true;
    } catch (error) {
      // Any PostgREST response proves the server is reachable, even if that
      // response is a policy/authorization error.
      return !isTransportFailure(error);
    }
  }
}
