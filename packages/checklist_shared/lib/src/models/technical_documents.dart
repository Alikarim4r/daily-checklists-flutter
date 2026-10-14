/// GLOB-001 P3: Technical documentation and workflow entities.
const technicalDocumentKinds = <String, String>{
  'method_statement': 'Method Statement',
  'risk_assessment': 'Risk Assessment',
  'jsa': 'Job Safety Analysis',
  'sop': 'Standard Operating Procedure',
  'cop': 'Code of Practice / Reference',
  'ptw': 'Permit to Work',
  'itp': 'Inspection & Test Plan',
  'ncr': 'Nonconformity Report',
};
const technicalDocumentKindsAr = <String, String>{
  'method_statement': 'طريقة تنفيذ الأعمال',
  'risk_assessment': 'تقييم المخاطر',
  'jsa': 'تحليل مخاطر العمل',
  'sop': 'إجراء تشغيلي قياسي',
  'cop': 'مدونة الممارسات / مرجع',
  'ptw': 'تصريح عمل',
  'itp': 'خطة الفحص والاختبار',
  'ncr': 'تقرير عدم المطابقة',
};

class TechnicalDocument {
  const TechnicalDocument({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.kind,
    required this.title,
    required this.status,
    required this.currentVersion,
    required this.createdBy,
    this.siteId,
    this.assetId,
    this.ppmJobId,
    this.approvedVersion,
    this.country,
    this.standard,
    this.edition,
    this.reviewerNote,
  });
  final String id, organizationId, code, kind, title, status, createdBy;
  final String? siteId,
      assetId,
      ppmJobId,
      country,
      standard,
      edition,
      reviewerNote;
  final int currentVersion;
  final int? approvedVersion;
  bool get isEditable => status == 'draft' || status == 'rejected';
  bool get isApproved => status == 'approved';
  String labelFor(String language) => language == 'ar'
      ? technicalDocumentKindsAr[kind] ?? kind
      : technicalDocumentKinds[kind] ?? kind;
  factory TechnicalDocument.fromJson(Map<String, dynamic> j) =>
      TechnicalDocument(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        code: j['document_code'] as String,
        kind: j['document_kind'] as String,
        title: j['title'] as String,
        status: j['status'] as String,
        createdBy: j['created_by'] as String,
        currentVersion: (j['current_version'] as num).toInt(),
        approvedVersion: (j['approved_version'] as num?)?.toInt(),
        siteId: j['site_id'] as String?,
        assetId: j['asset_id'] as String?,
        ppmJobId: j['ppm_job_id'] as String?,
        country: j['jurisdiction_country'] as String?,
        standard: j['standard_reference'] as String?,
        edition: j['standard_edition'] as String?,
        reviewerNote: j['reviewer_note'] as String?,
      );
}

class TechnicalVersion {
  const TechnicalVersion({
    required this.documentId,
    required this.versionNo,
    required this.payload,
    required this.authorId,
    required this.createdAt,
    this.changeNote = '',
  });
  final String documentId, authorId, changeNote;
  final int versionNo;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  factory TechnicalVersion.fromJson(Map<String, dynamic> j) => TechnicalVersion(
    documentId: j['document_id'] as String,
    versionNo: (j['version_no'] as num).toInt(),
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    authorId: j['author_id'] as String,
    changeNote: (j['change_note'] ?? '') as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class TechnicalDecision {
  const TechnicalDecision({
    required this.decision,
    required this.actorId,
    required this.createdAt,
    required this.version,
    this.remarks,
  });
  final String decision, actorId;
  final DateTime createdAt;
  final int version;
  final String? remarks;
  factory TechnicalDecision.fromJson(Map<String, dynamic> j) =>
      TechnicalDecision(
        decision: j['decision'] as String,
        actorId: j['actor_id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        version: (j['version_no'] as num).toInt(),
        remarks: j['remarks'] as String?,
      );
}
