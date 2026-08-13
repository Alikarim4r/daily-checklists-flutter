import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/audit_event.dart';
import '../models/client_error_log.dart';

class AuditRepository {
  AuditRepository(this._client);

  final SupabaseClient _client;

  Future<List<ChecklistAuditEvent>> listEvents({
    String? action,
    String? entityType,
    String? siteId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    var query = _client.from('checklist_audit_log').select();
    if (action != null && action.trim().isNotEmpty) {
      query = query.eq('action', action.trim());
    }
    if (entityType != null && entityType.trim().isNotEmpty) {
      query = query.eq('entity_type', entityType.trim());
    }
    if (siteId != null && siteId.isNotEmpty) {
      query = query.eq('site_id', siteId);
    }
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lte('created_at', to.toUtc().toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: false)
        .limit(limit.clamp(1, 500));
    return [
      for (final row in rows as List)
        ChecklistAuditEvent.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<ClientErrorLog>> listClientErrors({
    String? appKey,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    var query = _client.from('client_error_logs').select();
    if (appKey != null && appKey.trim().isNotEmpty) {
      query = query.eq('app_key', appKey.trim());
    }
    if (from != null) {
      query = query.gte('occurred_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lte('occurred_at', to.toUtc().toIso8601String());
    }
    final rows = await query
        .order('occurred_at', ascending: false)
        .limit(limit.clamp(1, 500));
    return [
      for (final row in rows as List)
        ClientErrorLog.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }
}
