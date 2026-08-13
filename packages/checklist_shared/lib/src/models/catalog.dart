import '../theme/form_paper_theme.dart';

class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.code,
    required this.nameEn,
    required this.nameAr,
    this.isActive = true,
    this.formTheme = 'inherit',
    this.formThemeAccent,
    this.familyCode = '',
    this.versionNumber = 1,
    this.lifecycleStatus = 'published',
    this.sourceTemplateId,
    this.publishedAt,
    this.publishedBy,
    this.items = const [],
  });

  final String id;
  final String code;
  final String nameEn;
  final String nameAr;
  final bool isActive;
  final String formTheme;
  final String? formThemeAccent;
  final String familyCode;
  final int versionNumber;
  final String lifecycleStatus;
  final String? sourceTemplateId;
  final DateTime? publishedAt;
  final String? publishedBy;
  final List<CatalogItem> items;

  FormPaperTheme get paperTheme =>
      FormPaperTheme.resolve(themeDb: formTheme, accentHex: formThemeAccent);

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  bool get isDraftVersion => lifecycleStatus == 'draft';
  bool get isPublishedVersion => lifecycleStatus == 'published';

  factory ChecklistTemplate.fromJson(
    Map<String, dynamic> json, {
    List<CatalogItem>? items,
  }) => ChecklistTemplate(
    id: json['id'] as String,
    code: (json['code'] ?? '') as String,
    nameEn: (json['name_en'] ?? '') as String,
    nameAr: (json['name_ar'] ?? '') as String,
    isActive: json['is_active'] as bool? ?? true,
    formTheme: (json['form_theme'] as String?) ?? 'inherit',
    formThemeAccent: json['form_theme_accent'] as String?,
    familyCode: (json['family_code'] ?? json['code'] ?? '') as String,
    versionNumber: (json['version_number'] as num?)?.toInt() ?? 1,
    lifecycleStatus: (json['lifecycle_status'] ?? 'published') as String,
    sourceTemplateId: json['source_template_id'] as String?,
    publishedAt: json['published_at'] == null
        ? null
        : DateTime.tryParse(json['published_at'] as String),
    publishedBy: json['published_by'] as String?,
    items: items ?? const [],
  );

  Map<String, dynamic> toInsertJson() => {
    'code': code,
    'name_en': nameEn,
    'name_ar': nameAr,
    'is_active': isActive,
    'form_theme': formTheme,
    'form_theme_accent': formThemeAccent,
    'family_code': familyCode.isEmpty ? code : familyCode,
    'version_number': versionNumber,
    'lifecycle_status': lifecycleStatus,
  };

  Map<String, dynamic> toUpdateJson() => {
    'name_en': nameEn,
    'name_ar': nameAr,
    'is_active': isActive,
    'form_theme': formTheme,
    'form_theme_accent': formThemeAccent,
  };
}

class CatalogItem {
  const CatalogItem({
    this.id,
    required this.itemIndex,
    required this.defaultAnswer,
    required this.descriptionEn,
    this.descriptionAr,
    this.localizedDescriptions = const {},
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
  final Map<String, String> localizedDescriptions;
  final int sortOrder;
  final bool isActive;
  final bool isCustom;

  /// Consecutive problem days before Overdue for this item only.
  final int overdueAfterDays;

  Map<String, String> get descriptions => {
    'en': descriptionEn,
    if ((descriptionAr ?? '').isNotEmpty) 'ar': descriptionAr!,
    ...localizedDescriptions,
  };

  String descriptionFor(String language) =>
      descriptions[language] ?? descriptionEn;

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
    id: json['id'] as String?,
    itemIndex: (json['item_index'] as num).toInt(),
    defaultAnswer: (json['default_answer'] ?? 'Y') as String,
    descriptionEn:
        (json['description_en'] ?? json['description'] ?? '') as String,
    descriptionAr:
        (json['description_ar'] ?? json['description_ar']) as String?,
    localizedDescriptions: {
      for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
        if ((json['description_$language'] as String?)?.trim().isNotEmpty ==
            true)
          language: (json['description_$language'] as String).trim(),
    },
    sortOrder:
        (json['sort_order'] as num?)?.toInt() ??
        (json['item_index'] as num?)?.toInt() ??
        0,
    isActive: json['is_active'] as bool? ?? true,
    isCustom: json['is_custom'] as bool? ?? false,
    overdueAfterDays: (json['overdue_after_days'] as num?)?.toInt() ?? 3,
  );

  Map<String, dynamic> toTemplateInsertJson(String templateId) => {
    'template_id': templateId,
    'item_index': itemIndex,
    'default_answer': defaultAnswer,
    'description_en': descriptionEn,
    if (descriptionAr != null) 'description_ar': descriptionAr,
    for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
      'description_$language': localizedDescriptions[language],
    'sort_order': sortOrder,
    'is_active': isActive,
    'overdue_after_days': overdueAfterDays,
  };

  Map<String, dynamic> toTemplateUpdateJson() => {
    'item_index': itemIndex,
    'default_answer': defaultAnswer,
    'description_en': descriptionEn,
    'description_ar': descriptionAr,
    for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
      'description_$language': localizedDescriptions[language],
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
    for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
      'description_$language': localizedDescriptions[language],
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
        missingPhotoSeverity: PolicySeverity.fromDb(
          json['missing_photo_severity'] as String?,
        ),
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
  }) => ChecklistOrgPolicy(
    organizationId: organizationId,
    photoRequiredOnProblem:
        photoRequiredOnProblem ?? this.photoRequiredOnProblem,
    missingPhotoSeverity: missingPhotoSeverity ?? this.missingPhotoSeverity,
    requireFixPhoto: requireFixPhoto ?? this.requireFixPhoto,
    ongoingProblemOverdueDays:
        ongoingProblemOverdueDays ?? this.ongoingProblemOverdueDays,
  );
}
