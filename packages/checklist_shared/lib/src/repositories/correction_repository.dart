import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inspection.dart';

class CorrectionRepository {
  CorrectionRepository(this._client);

  final SupabaseClient _client;

  Future<List<ChecklistCorrection>> listForInspection(
    String inspectionId,
  ) async {
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
    required Inspection inspection,
    required String itemId,
    required String fieldName,
    String? newValue,
    String reason = '',
  }) async {
    final nextVersion = await _client.rpc(
      'correct_checklist_inspection_item',
      params: {
        'p_item_id': itemId,
        'p_expected_version': inspection.version,
        'p_field_name': fieldName,
        'p_new_value': newValue,
        'p_reason': reason,
      },
    );
    inspection.version = (nextVersion as num).toInt();
  }
}
