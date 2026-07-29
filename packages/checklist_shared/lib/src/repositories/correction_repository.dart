import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inspection.dart';

class CorrectionRepository {
  CorrectionRepository(this._client);

  final SupabaseClient _client;

  Future<List<ChecklistCorrection>> listForInspection(String inspectionId) async {
    final rows = await _client
        .from('checklist_corrections')
        .select()
        .eq('inspection_id', inspectionId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map(
          (e) =>
              ChecklistCorrection.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<void> correctItem({
    required String inspectionId,
    required String itemId,
    required String fieldName,
    String? oldValue,
    String? newValue,
    String reason = '',
    Map<String, dynamic>? itemPatch,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Not signed in');

    if (itemPatch != null && itemPatch.isNotEmpty) {
      await _client
          .from('checklist_inspection_items')
          .update(itemPatch)
          .eq('id', itemId);
    }

    await _client.from('checklist_corrections').insert({
      'inspection_id': inspectionId,
      'item_id': itemId,
      'field_name': fieldName,
      'old_value': oldValue,
      'new_value': newValue,
      'reason': reason,
      'corrected_by': userId,
    });
  }
}
