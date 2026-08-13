import '../theme/form_paper_theme.dart';

class Organization {
  const Organization({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    this.isActive = true,
    this.logoEnPath,
    this.logoArPath,
    this.formTheme = 'classic_gold',
    this.formThemeAccent,
  });

  final String id;
  final String nameEn;
  final String nameAr;
  final bool isActive;

  /// Header logo for English mode (storage path in report-logos).
  final String? logoEnPath;

  /// Header logo for Arabic mode (storage path in report-logos).
  final String? logoArPath;
  final String formTheme;
  final String? formThemeAccent;

  FormPaperTheme get paperTheme =>
      FormPaperTheme.resolve(themeDb: formTheme, accentHex: formThemeAccent);

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  String? logoPathFor(String language) => language == 'ar'
      ? (logoArPath?.isNotEmpty == true ? logoArPath : logoEnPath)
      : (logoEnPath?.isNotEmpty == true ? logoEnPath : logoArPath);

  Organization copyWith({
    String? nameEn,
    String? nameAr,
    bool? isActive,
    String? logoEnPath,
    String? logoArPath,
    bool clearLogoEn = false,
    bool clearLogoAr = false,
    String? formTheme,
    String? formThemeAccent,
    bool clearThemeAccent = false,
  }) {
    return Organization(
      id: id,
      nameEn: nameEn ?? this.nameEn,
      nameAr: nameAr ?? this.nameAr,
      isActive: isActive ?? this.isActive,
      logoEnPath: clearLogoEn ? null : (logoEnPath ?? this.logoEnPath),
      logoArPath: clearLogoAr ? null : (logoArPath ?? this.logoArPath),
      formTheme: formTheme ?? this.formTheme,
      formThemeAccent: clearThemeAccent
          ? null
          : (formThemeAccent ?? this.formThemeAccent),
    );
  }

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
    id: json['id'] as String,
    nameEn: (json['name_en'] ?? '') as String,
    nameAr: (json['name_ar'] ?? '') as String,
    isActive: json['is_active'] as bool? ?? true,
    logoEnPath: json['logo_en_path'] as String?,
    logoArPath: json['logo_ar_path'] as String?,
    formTheme: (json['form_theme'] as String?) ?? 'classic_gold',
    formThemeAccent: json['form_theme_accent'] as String?,
  );

  Map<String, dynamic> toInsertJson() => {
    'name_en': nameEn,
    'name_ar': nameAr,
    'is_active': isActive,
    if (logoEnPath != null) 'logo_en_path': logoEnPath,
    if (logoArPath != null) 'logo_ar_path': logoArPath,
    'form_theme': formTheme,
    'form_theme_accent': formThemeAccent,
  };

  Map<String, dynamic> toUpdateJson() => {
    'name_en': nameEn,
    'name_ar': nameAr,
    'is_active': isActive,
    'logo_en_path': logoEnPath,
    'logo_ar_path': logoArPath,
    'form_theme': formTheme,
    'form_theme_accent': formThemeAccent,
  };
}

class Zone {
  const Zone({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.isActive = true,
    this.sortOrder = 0,
    this.reportLogoPath,
    this.formTheme = 'inherit',
    this.formThemeAccent,
  });

  final String id;
  final String organizationId;
  final String code;
  final String nameEn;
  final String? nameAr;
  final bool isActive;
  final int sortOrder;

  /// Footer logo: EN bottom-right / AR bottom-left.
  final String? reportLogoPath;
  final String formTheme;
  final String? formThemeAccent;

  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').isNotEmpty ? nameAr! : nameEn;

  Zone copyWith({
    String? code,
    String? nameEn,
    String? nameAr,
    bool? isActive,
    int? sortOrder,
    String? reportLogoPath,
    bool clearLogo = false,
    String? formTheme,
    String? formThemeAccent,
    bool clearThemeAccent = false,
  }) {
    return Zone(
      id: id,
      organizationId: organizationId,
      code: code ?? this.code,
      nameEn: nameEn ?? this.nameEn,
      nameAr: nameAr ?? this.nameAr,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      reportLogoPath: clearLogo
          ? null
          : (reportLogoPath ?? this.reportLogoPath),
      formTheme: formTheme ?? this.formTheme,
      formThemeAccent: clearThemeAccent
          ? null
          : (formThemeAccent ?? this.formThemeAccent),
    );
  }

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
    id: json['id'] as String,
    organizationId: json['organization_id'] as String,
    code: (json['code'] ?? '') as String,
    nameEn: (json['name_en'] ?? '') as String,
    nameAr: json['name_ar'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    reportLogoPath: json['report_logo_path'] as String?,
    formTheme: (json['form_theme'] as String?) ?? 'inherit',
    formThemeAccent: json['form_theme_accent'] as String?,
  );

  Map<String, dynamic> toInsertJson() => {
    'organization_id': organizationId,
    'code': code,
    'name_en': nameEn,
    if (nameAr != null) 'name_ar': nameAr,
    'is_active': isActive,
    'sort_order': sortOrder,
    if (reportLogoPath != null) 'report_logo_path': reportLogoPath,
    'form_theme': formTheme,
    'form_theme_accent': formThemeAccent,
  };

  Map<String, dynamic> toUpdateJson() => {
    'code': code,
    'name_en': nameEn,
    'name_ar': nameAr,
    'is_active': isActive,
    'sort_order': sortOrder,
    'report_logo_path': reportLogoPath,
    'form_theme': formTheme,
    'form_theme_accent': formThemeAccent,
  };
}
