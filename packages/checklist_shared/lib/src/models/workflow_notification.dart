class WorkflowNotification {
  const WorkflowNotification({
    required this.id,
    required this.kind,
    required this.titleEn,
    required this.titleAr,
    required this.bodyEn,
    required this.bodyAr,
    required this.createdAt,
    this.inspectionId,
    this.siteId,
    this.readAt,
  });

  final int id;
  final String kind;
  final String titleEn;
  final String titleAr;
  final String bodyEn;
  final String bodyAr;
  final String? inspectionId;
  final String? siteId;
  final DateTime createdAt;
  final DateTime? readAt;

  String titleFor(String language) => language == 'ar' ? titleAr : titleEn;
  String bodyFor(String language) => language == 'ar' ? bodyAr : bodyEn;

  factory WorkflowNotification.fromJson(Map<String, dynamic> json) {
    return WorkflowNotification(
      id: (json['id'] as num).toInt(),
      kind: (json['kind'] ?? '') as String,
      titleEn: (json['title_en'] ?? '') as String,
      titleAr: (json['title_ar'] ?? '') as String,
      bodyEn: (json['body_en'] ?? '') as String,
      bodyAr: (json['body_ar'] ?? '') as String,
      inspectionId: json['inspection_id'] as String?,
      siteId: json['site_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] == null
          ? null
          : DateTime.tryParse(json['read_at'] as String),
    );
  }
}
