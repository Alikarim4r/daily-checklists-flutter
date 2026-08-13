import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workflow_notification.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<WorkflowNotification>> listUnread({int limit = 50}) async {
    final rows = await _client
        .from('checklist_notifications')
        .select()
        .isFilter('read_at', null)
        .order('created_at', ascending: false)
        .limit(limit.clamp(1, 200));
    return [
      for (final row in rows as List)
        WorkflowNotification.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<void> markAllRead() async {
    await _client
        .from('checklist_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .isFilter('read_at', null);
  }
}
