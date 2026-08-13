import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/corrective_action.dart';

class CorrectiveActionRepository {
  CorrectiveActionRepository(this._client);

  final SupabaseClient _client;

  Future<List<CorrectiveAction>> list({
    String? siteId,
    String? inspectionId,
    CorrectiveActionStatus? status,
    CorrectiveActionPriority? priority,
    int limit = 200,
  }) async {
    var query = _client.from('checklist_corrective_actions').select();
    if (siteId != null) query = query.eq('site_id', siteId);
    if (inspectionId != null) {
      query = query.eq('inspection_id', inspectionId);
    }
    if (status != null) query = query.eq('status', status.dbValue);
    if (priority != null) query = query.eq('priority', priority.dbValue);
    final rows = await query
        .order('due_date')
        .order('created_at', ascending: false)
        .limit(limit.clamp(1, 500));
    return [
      for (final row in rows as List)
        CorrectiveAction.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<String> create({
    required String inspectionItemId,
    required String description,
    required CorrectiveActionPriority priority,
    required DateTime dueDate,
    String? assignedUserId,
    bool evidenceRequired = true,
  }) async {
    final iso =
        '${dueDate.year.toString().padLeft(4, '0')}-'
        '${dueDate.month.toString().padLeft(2, '0')}-'
        '${dueDate.day.toString().padLeft(2, '0')}';
    return await _client.rpc(
          'create_corrective_action',
          params: {
            'p_inspection_item_id': inspectionItemId,
            'p_description': description,
            'p_assigned_user_id': assignedUserId,
            'p_priority': priority.dbValue,
            'p_due_date': iso,
            'p_evidence_required': evidenceRequired,
          },
        )
        as String;
  }

  Future<int> transition({
    required CorrectiveAction action,
    required String transition,
    required String comment,
  }) async =>
      (await _client.rpc(
                'transition_corrective_action',
                params: {
                  'p_action_id': action.id,
                  'p_expected_version': action.version,
                  'p_transition': transition,
                  'p_comment': comment,
                },
              )
              as num)
          .toInt();

  Future<String> registerEvidence({
    required String actionId,
    required String storagePath,
    String mediaKind = 'action_photo',
  }) async =>
      await _client.rpc(
            'register_corrective_action_evidence',
            params: {
              'p_action_id': actionId,
              'p_storage_path': storagePath,
              'p_media_kind': mediaKind,
            },
          )
          as String;
}
