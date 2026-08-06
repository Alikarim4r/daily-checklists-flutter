class Organization {
  const Organization({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    this.isActive = true,
  });

  final String id;
  final String nameEn;
  final String nameAr;
  final bool isActive;

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: (json['name_ar'] ?? '') as String,
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toInsertJson() => {
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

class Zone {
  const Zone({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String organizationId;
  final String code;
  final String nameEn;
  final String? nameAr;
  final bool isActive;
  final int sortOrder;

  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').isNotEmpty ? nameAr! : nameEn;

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String,
        code: (json['code'] ?? '') as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: json['name_ar'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toInsertJson() => {
        'organization_id': organizationId,
        'code': code,
        'name_en': nameEn,
        if (nameAr != null) 'name_ar': nameAr,
        'is_active': isActive,
        'sort_order': sortOrder,
      };

  Map<String, dynamic> toUpdateJson() => {
        'code': code,
        'name_en': nameEn,
        'name_ar': nameAr,
        'is_active': isActive,
        'sort_order': sortOrder,
      };
}
