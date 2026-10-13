/// Global PPM entities. Additive to the existing A4 checklist/inspection models.
class FmAsset {
  const FmAsset({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.nameEn,
    required this.type,
    required this.status,
    required this.criticality,
    this.nameAr,
    this.siteId,
    this.notes,
    this.buildingId,
    this.floorId,
    this.areaId,
  });
  final String id, organizationId, code, nameEn, type, status, criticality;
  final String? nameAr, siteId, notes, buildingId, floorId, areaId;
  String nameFor(String language) =>
      language == 'ar' && (nameAr?.isNotEmpty ?? false) ? nameAr! : nameEn;

  factory FmAsset.fromJson(Map<String, dynamic> json) => FmAsset(
    id: json['id'] as String,
    organizationId: json['organization_id'] as String,
    code: json['asset_code'] as String,
    nameEn: json['name_en'] as String,
    nameAr: json['name_ar'] as String?,
    siteId: json['site_id'] as String?,
    buildingId: json['building_id'] as String?,
    floorId: json['floor_id'] as String?,
    areaId: json['area_id'] as String?,
    type: (json['asset_type'] ?? 'other') as String,
    status: (json['status'] ?? 'operational') as String,
    criticality: (json['criticality'] ?? 'medium') as String,
    notes: json['notes'] as String?,
  );
}

class FmPpmPlan {
  const FmPpmPlan({
    required this.id,
    required this.organizationId,
    required this.assetId,
    required this.titleEn,
    required this.frequency,
    required this.intervalCount,
    required this.anchorDate,
    required this.nextDueOn,
    required this.isActive,
    this.titleAr,
    this.assignmentId,
    this.instructions,
    this.timezone = 'UTC',
  });
  final String id, organizationId, assetId, titleEn, frequency;
  final int intervalCount;
  final DateTime anchorDate, nextDueOn;
  final bool isActive;
  final String? titleAr, assignmentId, instructions;
  final String timezone;
  String titleFor(String language) =>
      language == 'ar' && (titleAr?.isNotEmpty ?? false) ? titleAr! : titleEn;

  factory FmPpmPlan.fromJson(Map<String, dynamic> json) => FmPpmPlan(
    id: json['id'] as String,
    organizationId: json['organization_id'] as String,
    assetId: json['asset_id'] as String,
    titleEn: json['title_en'] as String,
    titleAr: json['title_ar'] as String?,
    frequency: json['frequency'] as String,
    timezone: (json['timezone_id'] ?? 'UTC') as String,
    intervalCount: (json['interval_count'] as num?)?.toInt() ?? 1,
    anchorDate: DateTime.parse(json['anchor_date'] as String),
    nextDueOn: DateTime.parse(json['next_due_on'] as String),
    isActive: json['is_active'] as bool? ?? true,
    assignmentId: json['checklist_assignment_id'] as String?,
    instructions: json['instructions'] as String?,
  );
}

class FmPpmJob {
  const FmPpmJob({
    required this.id,
    required this.organizationId,
    required this.planId,
    required this.assetId,
    required this.dueOn,
    required this.status,
    this.siteId,
    this.assignedTo,
    this.executionNotes,
    this.readings = const {},
    this.inspectionId,
    this.completedAt,
    this.isOverdueOnPlanTimezone,
  });
  final String id, organizationId, planId, assetId, status;
  final DateTime dueOn;
  final String? siteId, assignedTo, executionNotes, inspectionId;
  final Map<String, dynamic> readings;
  final DateTime? completedAt;
  final bool? isOverdueOnPlanTimezone;
  bool get closed => status == 'completed' || status == 'skipped';
  bool get overdue =>
      isOverdueOnPlanTimezone ??
      !closed &&
          DateTime(dueOn.year, dueOn.month, dueOn.day).isBefore(
            DateTime.now().copyWith(
              hour: 0,
              minute: 0,
              second: 0,
              millisecond: 0,
              microsecond: 0,
            ),
          );
  factory FmPpmJob.fromJson(Map<String, dynamic> json) => FmPpmJob(
    id: json['id'] as String,
    organizationId: json['organization_id'] as String,
    planId: json['plan_id'] as String,
    assetId: json['asset_id'] as String,
    siteId: json['site_id'] as String?,
    assignedTo: json['assigned_to'] as String?,
    dueOn: DateTime.parse(json['due_on'] as String),
    status: (json['status'] ?? 'scheduled') as String,
    executionNotes: json['execution_notes'] as String?,
    readings: json['readings'] is Map
        ? Map<String, dynamic>.from(json['readings'] as Map)
        : const {},
    inspectionId: json['inspection_id'] as String?,
    isOverdueOnPlanTimezone: json['is_overdue'] as bool?,
    completedAt: json['completed_at'] == null
        ? null
        : DateTime.tryParse(json['completed_at'] as String),
  );
}

class FmPpmEvent {
  const FmPpmEvent({
    required this.id,
    required this.jobId,
    required this.action,
    required this.recordedAt,
    this.actorId,
    this.notes,
    this.inspectionId,
  });
  final String id, jobId, action;
  final DateTime recordedAt;
  final String? actorId, notes, inspectionId;
  factory FmPpmEvent.fromJson(Map<String, dynamic> json) => FmPpmEvent(
    id: json['id'] as String,
    jobId: json['job_id'] as String,
    action: json['action'] as String,
    actorId: json['actor_id'] as String?,
    notes: json['notes'] as String?,
    inspectionId: json['inspection_id'] as String?,
    recordedAt: DateTime.parse(json['recorded_at'] as String),
  );
}
