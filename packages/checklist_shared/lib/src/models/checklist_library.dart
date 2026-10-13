/// Localized sector/domain facet returned by Global Library 2.0.
class GlobalLibraryFacet {
  const GlobalLibraryFacet({
    required this.slug,
    required this.nameEn,
    required this.nameAr,
    this.count = 0,
  });

  final String slug;
  final String nameEn;
  final String nameAr;
  final int count;

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  factory GlobalLibraryFacet.fromJson(Map<String, dynamic> json) =>
      GlobalLibraryFacet(
        slug: (json['slug'] ?? '') as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: (json['name_ar'] ?? json['name_en'] ?? '') as String,
        count: (json['template_count'] as num?)?.toInt() ?? 0,
      );
}

class ChecklistLibraryTemplate {
  const ChecklistLibraryTemplate({
    required this.id,
    required this.categoryId,
    required this.categorySlug,
    required this.categoryNameEn,
    required this.categoryNameAr,
    required this.slug,
    required this.versionNumber,
    required this.nameEn,
    required this.nameAr,
    required this.facilityTags,
    required this.languages,
    required this.accessModel,
    required this.minimumPlanTier,
    required this.itemCount,
    required this.canAccess,
    this.descriptionEn,
    this.descriptionAr,
    this.googlePlayProductId,
    this.listPriceMinor,
    this.listPriceCurrency = 'QAR',
    this.formTheme = 'inherit',
    this.formThemeAccent,
    this.installedTemplateId,
    this.installedLibraryVersion,
    this.industries = const [],
    this.domains = const [],
    this.documentKind = 'checklist',
    this.documentKindNameEn = 'Checklist',
    this.documentKindNameAr = 'قائمة فحص',
    this.validationStatus = 'unreviewed',
  });

  final String id;
  final String categoryId;
  final String categorySlug;
  final String categoryNameEn;
  final String categoryNameAr;
  final String slug;
  final int versionNumber;
  final String nameEn;
  final String nameAr;
  final String? descriptionEn;
  final String? descriptionAr;
  final List<String> facilityTags;
  final List<String> languages;
  final String accessModel;
  final String minimumPlanTier;
  final String? googlePlayProductId;
  final int? listPriceMinor;
  final String listPriceCurrency;
  final String formTheme;
  final String? formThemeAccent;
  final int itemCount;
  final bool canAccess;
  final String? installedTemplateId;
  final int? installedLibraryVersion;
  final List<GlobalLibraryFacet> industries;
  final List<GlobalLibraryFacet> domains;
  final String documentKind;
  final String documentKindNameEn;
  final String documentKindNameAr;
  final String validationStatus;

  String documentKindNameFor(String language) =>
      language == 'ar' ? documentKindNameAr : documentKindNameEn;

  bool get isPremium => accessModel == 'premium';
  bool get isInstalled => installedTemplateId != null;
  bool get hasUpdate =>
      isInstalled &&
      installedLibraryVersion != null &&
      installedLibraryVersion! < versionNumber;

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;
  String? descriptionFor(String language) =>
      language == 'ar' ? descriptionAr : descriptionEn;
  String categoryNameFor(String language) =>
      language == 'ar' ? categoryNameAr : categoryNameEn;

  factory ChecklistLibraryTemplate.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) {
      if (value is List) {
        return [
          for (final item in value)
            if (item != null) item.toString(),
        ];
      }
      return const [];
    }

    List<GlobalLibraryFacet> terms(Object? value) => value is List
        ? [
            for (final row in value)
              if (row is Map)
                GlobalLibraryFacet.fromJson(Map<String, dynamic>.from(row)),
          ]
        : const [];

    return ChecklistLibraryTemplate(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      categorySlug: (json['category_slug'] ?? '') as String,
      categoryNameEn: (json['category_name_en'] ?? '') as String,
      categoryNameAr: (json['category_name_ar'] ?? '') as String,
      slug: (json['slug'] ?? '') as String,
      versionNumber: (json['version_number'] as num?)?.toInt() ?? 1,
      nameEn: (json['name_en'] ?? '') as String,
      nameAr: (json['name_ar'] ?? '') as String,
      descriptionEn: json['description_en'] as String?,
      descriptionAr: json['description_ar'] as String?,
      facilityTags: strings(json['facility_tags']),
      languages: strings(json['languages']),
      accessModel: (json['access_model'] ?? 'starter_included') as String,
      minimumPlanTier: (json['minimum_plan_tier'] ?? 'starter') as String,
      googlePlayProductId: json['google_play_product_id'] as String?,
      listPriceMinor: (json['list_price_minor'] as num?)?.toInt(),
      listPriceCurrency: (json['list_price_currency'] ?? 'QAR') as String,
      formTheme: (json['form_theme'] ?? 'inherit') as String,
      formThemeAccent: json['form_theme_accent'] as String?,
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      canAccess: json['can_access'] == true,
      installedTemplateId: json['installed_template_id'] as String?,
      installedLibraryVersion: (json['installed_library_version'] as num?)
          ?.toInt(),
      industries: terms(json['industries']),
      domains: terms(json['domains']),
      documentKind: (json['document_kind'] ?? 'checklist') as String,
      documentKindNameEn:
          (json['document_kind_name_en'] ?? 'Checklist') as String,
      documentKindNameAr:
          (json['document_kind_name_ar'] ?? 'قائمة فحص') as String,
      validationStatus: (json['validation_status'] ?? 'unreviewed') as String,
    );
  }
}
