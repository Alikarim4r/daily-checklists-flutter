enum CorrectiveActionPriority {
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const CorrectiveActionPriority(this.dbValue);
  final String dbValue;

  static CorrectiveActionPriority fromDb(String? value) => values.firstWhere(
    (item) => item.dbValue == value,
    orElse: () => CorrectiveActionPriority.medium,
  );

  String labelFor(String language) => switch ((this, language == 'ar')) {
    (CorrectiveActionPriority.low, true) => 'منخفضة',
    (CorrectiveActionPriority.medium, true) => 'متوسطة',
    (CorrectiveActionPriority.high, true) => 'عالية',
    (CorrectiveActionPriority.critical, true) => 'حرجة',
    (CorrectiveActionPriority.low, false) => 'Low',
    (CorrectiveActionPriority.medium, false) => 'Medium',
    (CorrectiveActionPriority.high, false) => 'High',
    (CorrectiveActionPriority.critical, false) => 'Critical',
  };
}

enum CorrectiveActionStatus {
  open('open'),
  inProgress('in_progress'),
  pendingVerification('pending_verification'),
  closed('closed'),
  canceled('canceled');

  const CorrectiveActionStatus(this.dbValue);
  final String dbValue;

  static CorrectiveActionStatus fromDb(String? value) => values.firstWhere(
    (item) => item.dbValue == value,
    orElse: () => CorrectiveActionStatus.open,
  );

  bool get isTerminal =>
      this == CorrectiveActionStatus.closed ||
      this == CorrectiveActionStatus.canceled;

  String labelFor(String language) => switch ((this, language == 'ar')) {
    (CorrectiveActionStatus.open, true) => 'مفتوح',
    (CorrectiveActionStatus.inProgress, true) => 'قيد التنفيذ',
    (CorrectiveActionStatus.pendingVerification, true) => 'بانتظار التحقق',
    (CorrectiveActionStatus.closed, true) => 'مغلق',
    (CorrectiveActionStatus.canceled, true) => 'ملغى',
    (CorrectiveActionStatus.open, false) => 'Open',
    (CorrectiveActionStatus.inProgress, false) => 'In progress',
    (CorrectiveActionStatus.pendingVerification, false) =>
      'Pending verification',
    (CorrectiveActionStatus.closed, false) => 'Closed',
    (CorrectiveActionStatus.canceled, false) => 'Canceled',
  };
}

class CorrectiveAction {
  const CorrectiveAction({
    required this.id,
    required this.referenceNo,
    required this.organizationId,
    required this.siteId,
    required this.inspectionId,
    required this.inspectionItemId,
    required this.description,
    required this.priority,
    required this.status,
    required this.dueDate,
    required this.evidenceRequired,
    required this.createdBy,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.assignedUserId,
    this.closureComment,
    this.closedBy,
    this.closedAt,
  });

  final String id;
  final String referenceNo;
  final String organizationId;
  final String siteId;
  final String inspectionId;
  final String inspectionItemId;
  final String description;
  final String? assignedUserId;
  final CorrectiveActionPriority priority;
  final CorrectiveActionStatus status;
  final DateTime dueDate;
  final bool evidenceRequired;
  final String? closureComment;
  final String createdBy;
  final String? closedBy;
  final DateTime? closedAt;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOverdue =>
      !status.isTerminal &&
      DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(
        DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0),
      );

  factory CorrectiveAction.fromJson(Map<String, dynamic> json) =>
      CorrectiveAction(
        id: json['id'] as String,
        referenceNo: (json['reference_no'] ?? '') as String,
        organizationId: json['organization_id'] as String,
        siteId: json['site_id'] as String,
        inspectionId: json['inspection_id'] as String,
        inspectionItemId: json['inspection_item_id'] as String,
        description: (json['description'] ?? '') as String,
        assignedUserId: json['assigned_user_id'] as String?,
        priority: CorrectiveActionPriority.fromDb(json['priority'] as String?),
        status: CorrectiveActionStatus.fromDb(json['status'] as String?),
        dueDate: DateTime.parse(json['due_date'] as String),
        evidenceRequired: json['evidence_required'] as bool? ?? true,
        closureComment: json['closure_comment'] as String?,
        createdBy: json['created_by'] as String,
        closedBy: json['closed_by'] as String?,
        closedAt: json['closed_at'] == null
            ? null
            : DateTime.tryParse(json['closed_at'] as String),
        version: (json['version'] as num?)?.toInt() ?? 1,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
