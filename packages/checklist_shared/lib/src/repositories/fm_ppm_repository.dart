import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fm_ppm.dart';

/// Tenant-protected PPM repository. All writes use server authorization RPCs.
/// Existing inspection, A4, and offline queue APIs remain unchanged.
class FmPpmRepository {
  const FmPpmRepository(this._client);
  final SupabaseClient _client;

  Future<List<FmAsset>> listAssets(String organizationId) async {
    final rows = await _client
        .from('fm_assets')
        .select()
        .eq('organization_id', organizationId)
        .order('name_en');
    return [
      for (final row in rows) FmAsset.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<List<FmPpmPlan>> listPlans(String organizationId) async {
    final rows = await _client
        .from('fm_ppm_plans')
        .select()
        .eq('organization_id', organizationId)
        .order('next_due_on');
    return [
      for (final row in rows)
        FmPpmPlan.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<List<FmPpmJob>> listJobs(
    String organizationId, {
    String? status,
    int limit = 400,
  }) async {
    var q = _client
        .from('fm_ppm_jobs_view')
        .select()
        .eq('organization_id', organizationId);
    if (status != null && status != 'all') q = q.eq('status', status);
    final rows = await q
        .order('due_on', ascending: true)
        .limit(limit.clamp(1, 1000));
    return [
      for (final row in rows) FmPpmJob.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<List<FmPpmEvent>> listEvents(String jobId) async {
    final rows = await _client
        .from('fm_ppm_job_events')
        .select()
        .eq('job_id', jobId)
        .order('recorded_at', ascending: false);
    return [
      for (final row in rows)
        FmPpmEvent.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<String> saveAsset({
    required String organizationId,
    required String code,
    required String name,
    required String type,
    String? siteId,
    String? assetId,
    String? nameAr,
    String criticality = 'medium',
    String? notes,
    String? manufacturer,
    String? model,
    String? serial,
    String? buildingId,
    String? floorId,
    String? areaId,
  }) async {
    final result = await _client.rpc(
      'fm_ppm_save_asset',
      params: {
        'p_org': organizationId,
        'p_code': code.trim(),
        'p_name': name.trim(),
        'p_type': type.trim(),
        'p_site': siteId,
        'p_asset': assetId,
        'p_name_ar': nameAr,
        'p_criticality': criticality,
        'p_notes': notes,
        'p_manufacturer': manufacturer,
        'p_model': model,
        'p_serial': serial,
        'p_building': buildingId,
        'p_floor': floorId,
        'p_area': areaId,
      },
    );
    return result as String;
  }

  Future<String> savePlan({
    required String organizationId,
    required String assetId,
    required String title,
    required String frequency,
    required DateTime anchorDate,
    int every = 1,
    String? planId,
    String? titleAr,
    String? instructions,
    String? checklistAssignmentId,
    String timezone = 'UTC',
  }) async {
    final result = await _client.rpc(
      'fm_ppm_save_plan',
      params: {
        'p_org': organizationId,
        'p_asset': assetId,
        'p_title': title.trim(),
        'p_frequency': frequency,
        'p_anchor': _isoDate(anchorDate),
        'p_every': every,
        'p_plan': planId,
        'p_title_ar': titleAr,
        'p_instructions': instructions,
        'p_assignment': checklistAssignmentId,
        'p_timezone': timezone.trim(),
      },
    );
    return result as String;
  }

  Future<int> generateDueJobs(
    String organizationId, {
    int horizonDays = 45,
    int maxJobs = 200,
  }) async {
    final result = await _client.rpc(
      'fm_ppm_generate_due_jobs',
      params: {
        'p_org': organizationId,
        'p_horizon_days': horizonDays,
        'p_max_jobs': maxJobs,
      },
    );
    return (result as num).toInt();
  }

  Future<void> startJob(String jobId) async =>
      _client.rpc('fm_ppm_start_job', params: {'p_job': jobId});

  Future<void> completeJob(
    String jobId, {
    required String notes,
    Map<String, dynamic> readings = const {},
    String? inspectionId,
  }) async {
    await _client.rpc(
      'fm_ppm_complete_job',
      params: {
        'p_job': jobId,
        'p_notes': notes.trim(),
        'p_readings': readings,
        'p_inspection': inspectionId,
      },
    );
  }

  Future<void> skipJob(String jobId, {required String reason}) async {
    await _client.rpc(
      'fm_ppm_skip_job',
      params: {'p_job': jobId, 'p_reason': reason.trim()},
    );
  }

  Future<void> setPlanActive(String planId, bool active) async {
    await _client.rpc(
      'fm_ppm_set_plan_active',
      params: {'p_plan': planId, 'p_active': active},
    );
  }

  Future<void> assignJob(String jobId, String? userId) async {
    await _client.rpc(
      'fm_ppm_assign_job',
      params: {'p_job': jobId, 'p_user': userId},
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
