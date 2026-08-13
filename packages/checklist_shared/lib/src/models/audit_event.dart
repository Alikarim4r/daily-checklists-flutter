class ChecklistAuditEvent {
  const ChecklistAuditEvent({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.entityId,
    this.actorUserId,
    this.actorName,
    this.actorRole,
    this.organizationId,
    this.siteId,
    this.reason,
    this.oldValue,
    this.newValue,
    this.metadata = const {},
  });

  final int id;
  final String action;
  final String entityType;
  final String? entityId;
  final String? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String? organizationId;
  final String? siteId;
  final String? reason;
  final Map<String, dynamic>? oldValue;
  final Map<String, dynamic>? newValue;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  factory ChecklistAuditEvent.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? optionalMap(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : null;

    return ChecklistAuditEvent(
      id: (json['id'] as num).toInt(),
      action: (json['action'] ?? '') as String,
      entityType: (json['entity_type'] ?? '') as String,
      entityId: json['entity_id'] as String?,
      actorUserId: json['actor_user_id'] as String?,
      actorName: json['actor_name'] as String?,
      actorRole: json['actor_role'] as String?,
      organizationId: json['organization_id'] as String?,
      siteId: json['site_id'] as String?,
      reason: json['reason'] as String?,
      oldValue: optionalMap(json['old_value']),
      newValue: optionalMap(json['new_value']),
      metadata: optionalMap(json['metadata']) ?? const {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
