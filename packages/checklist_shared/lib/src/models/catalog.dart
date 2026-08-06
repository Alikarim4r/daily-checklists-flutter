class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.code,
    required this.nameEn,
    required this.nameAr,
    this.isActive = true,
    this.items = const [],
  });

  final String id;
  final String code;
  final String nameEn;
  final String nameAr;
  final bool isActive;
  final List<CatalogItem> items;

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  factory ChecklistTemplate.fromJson(
    Map<String, dynamic> json, {
    List<CatalogItem>? items,
  }) =>
      ChecklistTemplate(
        id: json['id'] as String,
        code: (json['code'] ?? '') as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: (json['name_ar'] ?? '') as String,
        isActive: json['is_active'] as bool? ?? true,
        items: items ?? const [],
      );

  Map<String, dynamic> toInsertJson() => {
        'code': code,
        'name_en': nameEn,
        'name_ar': nameAr,
        'is_active': isActive,
      };

  Map<String, dynamic> toUpdateJson() => {
        'name_en': nameEn,
        'name_ar': nameAr,
        'is_active': isActive,
      };
}

class CatalogItem {
  const CatalogItem({
    this.id,
    required this.itemIndex,
    required this.defaultAnswer,
    required this.descriptionEn,
    this.descriptionAr,
    this.sortOrder = 0,
    this.isActive = true,
    this.isCustom = false,
    this.overdueAfterDays = 3,
  });

  final String? id;
  final int itemIndex;
  final String defaultAnswer;
  final String descriptionEn;
  final String? descriptionAr;
  final int sortOrder;
  final bool isActive;
  final bool isCustom;
  /// Consecutive problem days before Overdue for this item only.
  final int overdueAfterDays;

  String descriptionFor(String language) =>
      language == 'ar' && (descriptionAr ?? '').isNotEmpty
          ? descriptionAr!
          : descriptionEn;

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        id: json['id'] as String?,
        itemIndex: (json['item_index'] as num).toInt(),
        defaultAnswer: (json['default_answer'] ?? 'Y') as String,
        descriptionEn: (json['description_en'] ?? json['description'] ?? '')
            as String,
        descriptionAr:
            (json['description_ar'] ?? json['description_ar']) as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ??
            (json['item_index'] as num?)?.toInt() ??
            0,
        isActive: json['is_active'] as bool? ?? true,
        isCustom: json['is_custom'] as bool? ?? false,
        overdueAfterDays:
            (json['overdue_after_days'] as num?)?.toInt() ?? 3,
      );

  Map<String, dynamic> toTemplateInsertJson(String templateId) => {
        'template_id': templateId,
        'item_index': itemIndex,
        'default_answer': defaultAnswer,
        'description_en': descriptionEn,
        if (descriptionAr != null) 'description_ar': descriptionAr,
        'sort_order': sortOrder,
        'is_active': isActive,
        'overdue_after_days': overdueAfterDays,
      };

  Map<String, dynamic> toTemplateUpdateJson() => {
        'item_index': itemIndex,
        'default_answer': defaultAnswer,
        'description_en': descriptionEn,
        'description_ar': descriptionAr,
        'sort_order': sortOrder,
        'is_active': isActive,
        'overdue_after_days': overdueAfterDays,
      };

  Map<String, dynamic> toSiteInsertJson(String siteId) => {
        'site_id': siteId,
        'item_index': itemIndex,
        'default_answer': defaultAnswer,
        'description_en': descriptionEn,
        if (descriptionAr != null) 'description_ar': descriptionAr,
        'sort_order': sortOrder,
        'is_active': isActive,
        'overdue_after_days': overdueAfterDays,
      };
}

enum PolicySeverity {
  info('info'),
  warning('warning'),
  critical('critical');

  const PolicySeverity(this.dbValue);
  final String dbValue;

  static PolicySeverity fromDb(String? v) => PolicySeverity.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => PolicySeverity.warning,
      );

  String get labelAr => switch (this) {
        PolicySeverity.info => 'معلومة',
        PolicySeverity.warning => 'تحذير',
        PolicySeverity.critical => 'حرج',
      };
}

class ChecklistOrgPolicy {
  const ChecklistOrgPolicy({
    required this.organizationId,
    this.photoRequiredOnProblem = true,
    this.missingPhotoSeverity = PolicySeverity.warning,
    this.requireFixPhoto = false,
    this.ongoingProblemOverdueDays = 3,
  });

  final String organizationId;
  final bool photoRequiredOnProblem;
  final PolicySeverity missingPhotoSeverity;
  final bool requireFixPhoto;
  final int ongoingProblemOverdueDays;

  factory ChecklistOrgPolicy.fromJson(Map<String, dynamic> json) =>
      ChecklistOrgPolicy(
        organizationId: json['organization_id'] as String,
        photoRequiredOnProblem:
            json['photo_required_on_problem'] as bool? ?? true,
        missingPhotoSeverity:
            PolicySeverity.fromDb(json['missing_photo_severity'] as String?),
        requireFixPhoto: json['require_fix_photo'] as bool? ?? false,
        ongoingProblemOverdueDays:
            (json['ongoing_problem_overdue_days'] as num?)?.toInt() ?? 3,
      );

  Map<String, dynamic> toUpsertJson() => {
        'organization_id': organizationId,
        'photo_required_on_problem': photoRequiredOnProblem,
        'missing_photo_severity': missingPhotoSeverity.dbValue,
        'require_fix_photo': requireFixPhoto,
        'ongoing_problem_overdue_days': ongoingProblemOverdueDays,
      };

  ChecklistOrgPolicy copyWith({
    bool? photoRequiredOnProblem,
    PolicySeverity? missingPhotoSeverity,
    bool? requireFixPhoto,
    int? ongoingProblemOverdueDays,
  }) =>
      ChecklistOrgPolicy(
        organizationId: organizationId,
        photoRequiredOnProblem:
            photoRequiredOnProblem ?? this.photoRequiredOnProblem,
        missingPhotoSeverity:
            missingPhotoSeverity ?? this.missingPhotoSeverity,
        requireFixPhoto: requireFixPhoto ?? this.requireFixPhoto,
        ongoingProblemOverdueDays:
            ongoingProblemOverdueDays ?? this.ongoingProblemOverdueDays,
      );
}
