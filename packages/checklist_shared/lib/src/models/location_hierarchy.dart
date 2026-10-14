import 'enums.dart';

class FacilityBuilding {
  const FacilityBuilding({
    required this.id,
    required this.siteId,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.isActive = true,
    this.sortOrder = 0,
    this.legacySiteId,
  });

  final String id;
  final String siteId;
  final String code;
  final String nameEn;
  final String? nameAr;
  final bool isActive;
  final int sortOrder;
  final String? legacySiteId;

  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').trim().isNotEmpty ? nameAr! : nameEn;

  factory FacilityBuilding.fromJson(Map<String, dynamic> json) =>
      FacilityBuilding(
        id: json['id'] as String,
        siteId: json['site_id'] as String,
        code: (json['code'] ?? '') as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: json['name_ar'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        legacySiteId: json['legacy_site_id'] as String?,
      );
}

class FacilityFloor {
  const FacilityFloor({
    required this.id,
    required this.buildingId,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.levelNumber,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String buildingId;
  final String code;
  final String nameEn;
  final String? nameAr;
  final int? levelNumber;
  final bool isActive;
  final int sortOrder;

  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').trim().isNotEmpty ? nameAr! : nameEn;

  factory FacilityFloor.fromJson(Map<String, dynamic> json) => FacilityFloor(
    id: json['id'] as String,
    buildingId: json['building_id'] as String,
    code: (json['code'] ?? '') as String,
    nameEn: (json['name_en'] ?? '') as String,
    nameAr: json['name_ar'] as String?,
    levelNumber: (json['level_number'] as num?)?.toInt(),
    isActive: json['is_active'] as bool? ?? true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );
}

class FacilityArea {
  const FacilityArea({
    required this.id,
    required this.floorId,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.areaType = 'other',
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String floorId;
  final String code;
  final String nameEn;
  final String? nameAr;
  final String areaType;
  final bool isActive;
  final int sortOrder;

  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').trim().isNotEmpty ? nameAr! : nameEn;

  factory FacilityArea.fromJson(Map<String, dynamic> json) => FacilityArea(
    id: json['id'] as String,
    floorId: json['floor_id'] as String,
    code: (json['code'] ?? '') as String,
    nameEn: (json['name_en'] ?? '') as String,
    nameAr: json['name_ar'] as String?,
    areaType: (json['area_type'] ?? 'other') as String,
    isActive: json['is_active'] as bool? ?? true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );
}

class ChecklistServiceType {
  const ChecklistServiceType({
    required this.code,
    required this.nameEn,
    required this.nameAr,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String code;
  final String nameEn;
  final String nameAr;
  final bool isActive;
  final int sortOrder;

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  factory ChecklistServiceType.fromJson(Map<String, dynamic> json) =>
      ChecklistServiceType(
        code: json['code'] as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: (json['name_ar'] ?? '') as String,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class ChecklistAssignment {
  const ChecklistAssignment({
    required this.id,
    required this.organizationId,
    required this.siteId,
    required this.buildingId,
    required this.floorId,
    required this.areaId,
    required this.nameEn,
    this.nameAr,
    this.templateId,
    this.templateCodeSnapshot = '',
    this.serviceTypeCode = 'other',
    this.legacySiteId,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String organizationId;
  final String siteId;
  final String buildingId;
  final String floorId;
  final String areaId;
  final String nameEn;
  final String? nameAr;
  final String? templateId;
  final String templateCodeSnapshot;
  final String serviceTypeCode;
  final String? legacySiteId;
  final bool isActive;
  final int sortOrder;

  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').trim().isNotEmpty ? nameAr! : nameEn;

  factory ChecklistAssignment.fromJson(Map<String, dynamic> json) =>
      ChecklistAssignment(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String,
        siteId: json['site_id'] as String,
        buildingId: json['building_id'] as String,
        floorId: json['floor_id'] as String,
        areaId: json['area_id'] as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: json['name_ar'] as String?,
        templateId: json['template_id'] as String?,
        templateCodeSnapshot: (json['template_code_snapshot'] ?? '') as String,
        serviceTypeCode: (json['service_type_code'] ?? 'other') as String,
        legacySiteId: json['legacy_site_id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

enum LocationFilterDimension {
  organization,
  zone,
  site,
  building,
  floor,
  area,
  checklistType,
  sector,
  serviceClass,
  department,
  coverage,
  documentKind,
}

class LocationFilterOption {
  const LocationFilterOption({
    required this.value,
    required this.nameEn,
    this.nameAr,
    this.code,
  });

  final String value;
  final String nameEn;
  final String? nameAr;
  final String? code;

  String labelFor(String language) =>
      language == 'ar' && (nameAr ?? '').trim().isNotEmpty ? nameAr! : nameEn;

  @override
  bool operator ==(Object other) =>
      other is LocationFilterOption && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class LocationFilterSelection {
  const LocationFilterSelection({
    this.organizationId,
    this.zoneId,
    this.siteId,
    this.buildingId,
    this.floorId,
    this.areaId,
    this.serviceTypeCode,
    this.sectorId,
    this.serviceClassId,
    this.departmentId,
    this.coverageId,
    this.documentKindId,
  });

  final String? organizationId;
  final String? zoneId;
  final String? siteId;
  final String? buildingId;
  final String? floorId;
  final String? areaId;
  final String? serviceTypeCode;
  final String? sectorId;
  final String? serviceClassId;
  final String? departmentId;
  final String? coverageId;
  final String? documentKindId;

  String? valueFor(LocationFilterDimension dimension) => switch (dimension) {
    LocationFilterDimension.organization => organizationId,
    LocationFilterDimension.zone => zoneId,
    LocationFilterDimension.site => siteId,
    LocationFilterDimension.building => buildingId,
    LocationFilterDimension.floor => floorId,
    LocationFilterDimension.area => areaId,
    LocationFilterDimension.checklistType => serviceTypeCode,
    LocationFilterDimension.sector => sectorId,
    LocationFilterDimension.serviceClass => serviceClassId,
    LocationFilterDimension.department => departmentId,
    LocationFilterDimension.coverage => coverageId,
    LocationFilterDimension.documentKind => documentKindId,
  };

  LocationFilterSelection withValue(
    LocationFilterDimension dimension,
    String? value,
  ) => LocationFilterSelection(
    organizationId: dimension == LocationFilterDimension.organization
        ? value
        : organizationId,
    zoneId: dimension == LocationFilterDimension.zone ? value : zoneId,
    siteId: dimension == LocationFilterDimension.site ? value : siteId,
    buildingId: dimension == LocationFilterDimension.building
        ? value
        : buildingId,
    floorId: dimension == LocationFilterDimension.floor ? value : floorId,
    areaId: dimension == LocationFilterDimension.area ? value : areaId,
    serviceTypeCode: dimension == LocationFilterDimension.checklistType
        ? value
        : serviceTypeCode,
    sectorId: dimension == LocationFilterDimension.sector ? value : sectorId,
    serviceClassId: dimension == LocationFilterDimension.serviceClass
        ? value
        : serviceClassId,
    departmentId: dimension == LocationFilterDimension.department
        ? value
        : departmentId,
    coverageId: dimension == LocationFilterDimension.coverage
        ? value
        : coverageId,
    documentKindId: dimension == LocationFilterDimension.documentKind
        ? value
        : documentKindId,
  );
}

class LocationScopeLeaf {
  const LocationScopeLeaf({
    required this.organizationId,
    required this.organizationNameEn,
    this.organizationNameAr,
    this.zoneId,
    this.zoneNameEn,
    this.zoneNameAr,
    required this.siteId,
    required this.siteNameEn,
    this.siteNameAr,
    required this.buildingId,
    required this.buildingCode,
    required this.buildingNameEn,
    this.buildingNameAr,
    required this.floorId,
    required this.floorCode,
    required this.floorNameEn,
    this.floorNameAr,
    required this.areaId,
    required this.areaCode,
    required this.areaNameEn,
    this.areaNameAr,
    required this.assignmentId,
    required this.checklistNameEn,
    this.checklistNameAr,
    required this.serviceTypeCode,
    required this.serviceTypeNameEn,
    required this.serviceTypeNameAr,
    this.legacySiteId,
    this.sectorId,
    this.sectorNameEn = 'Facilities Management',
    this.sectorNameAr = 'إدارة المرافق',
    this.serviceClassId,
    this.serviceClassNameEn = 'Hard Services',
    this.serviceClassNameAr = 'الخدمات الفنية',
    this.departmentId,
    this.departmentNameEn = 'General',
    this.departmentNameAr = 'عام',
    this.coverageId,
    this.coverageNameEn = 'Whole building / General',
    this.coverageNameAr = 'عام / كامل المبنى',
    this.documentKindId,
    this.documentKindNameEn = 'Daily Checklist',
    this.documentKindNameAr = 'قائمة فحص يومية',
  });

  final String organizationId;
  final String organizationNameEn;
  final String? organizationNameAr;
  final String? zoneId;
  final String? zoneNameEn;
  final String? zoneNameAr;
  final String siteId;
  final String siteNameEn;
  final String? siteNameAr;
  final String buildingId;
  final String buildingCode;
  final String buildingNameEn;
  final String? buildingNameAr;
  final String floorId;
  final String floorCode;
  final String floorNameEn;
  final String? floorNameAr;
  final String areaId;
  final String areaCode;
  final String areaNameEn;
  final String? areaNameAr;
  final String assignmentId;
  final String checklistNameEn;
  final String? checklistNameAr;
  final String serviceTypeCode;
  final String serviceTypeNameEn;
  final String serviceTypeNameAr;
  final String? legacySiteId;
  final String? sectorId,
      serviceClassId,
      departmentId,
      coverageId,
      documentKindId;
  final String sectorNameEn,
      sectorNameAr,
      serviceClassNameEn,
      serviceClassNameAr;
  final String departmentNameEn,
      departmentNameAr,
      coverageNameEn,
      coverageNameAr;
  final String documentKindNameEn, documentKindNameAr;

  factory LocationScopeLeaf.fromJson(
    Map<String, dynamic> json,
  ) => LocationScopeLeaf(
    organizationId: json['organization_id'] as String,
    organizationNameEn: (json['organization_name_en'] ?? '') as String,
    organizationNameAr: json['organization_name_ar'] as String?,
    zoneId: json['zone_id'] as String?,
    zoneNameEn: json['zone_name_en'] as String?,
    zoneNameAr: json['zone_name_ar'] as String?,
    siteId: json['site_id'] as String,
    siteNameEn: (json['site_name_en'] ?? '') as String,
    siteNameAr: json['site_name_ar'] as String?,
    buildingId: json['building_id'] as String,
    buildingCode: (json['building_code'] ?? '') as String,
    buildingNameEn: (json['building_name_en'] ?? '') as String,
    buildingNameAr: json['building_name_ar'] as String?,
    floorId: json['floor_id'] as String,
    floorCode: (json['floor_code'] ?? '') as String,
    floorNameEn: (json['floor_name_en'] ?? '') as String,
    floorNameAr: json['floor_name_ar'] as String?,
    areaId: json['area_id'] as String,
    areaCode: (json['area_code'] ?? '') as String,
    areaNameEn: (json['area_name_en'] ?? '') as String,
    areaNameAr: json['area_name_ar'] as String?,
    assignmentId: json['assignment_id'] as String,
    checklistNameEn: (json['checklist_name_en'] ?? '') as String,
    checklistNameAr: json['checklist_name_ar'] as String?,
    serviceTypeCode: (json['service_type_code'] ?? 'other') as String,
    serviceTypeNameEn: (json['service_type_name_en'] ?? 'Other') as String,
    serviceTypeNameAr: (json['service_type_name_ar'] ?? 'أخرى') as String,
    legacySiteId: json['legacy_site_id'] as String?,
    sectorId: json['sector_id'] as String?,
    sectorNameEn: (json['sector_name_en'] ?? 'Facilities Management') as String,
    sectorNameAr: (json['sector_name_ar'] ?? 'إدارة المرافق') as String,
    serviceClassId: json['service_class_id'] as String?,
    serviceClassNameEn:
        (json['service_class_name_en'] ?? 'Hard Services') as String,
    serviceClassNameAr:
        (json['service_class_name_ar'] ?? 'الخدمات الفنية') as String,
    departmentId: json['department_id'] as String?,
    departmentNameEn: (json['department_name_en'] ?? 'General') as String,
    departmentNameAr: (json['department_name_ar'] ?? 'عام') as String,
    coverageId: json['coverage_id'] as String?,
    coverageNameEn:
        (json['coverage_name_en'] ?? 'Whole building / General') as String,
    coverageNameAr: (json['coverage_name_ar'] ?? 'عام / كامل المبنى') as String,
    documentKindId: json['document_kind_id'] as String?,
    documentKindNameEn:
        (json['document_kind_name_en'] ?? 'Daily Checklist') as String,
    documentKindNameAr:
        (json['document_kind_name_ar'] ?? 'قائمة فحص يومية') as String,
  );

  String? valueFor(LocationFilterDimension dimension) => switch (dimension) {
    LocationFilterDimension.organization => organizationId,
    LocationFilterDimension.zone => zoneId,
    LocationFilterDimension.site => siteId,
    LocationFilterDimension.building => buildingId,
    LocationFilterDimension.floor => floorId,
    LocationFilterDimension.area => areaId,
    LocationFilterDimension.checklistType => serviceTypeCode,
    LocationFilterDimension.sector => sectorId,
    LocationFilterDimension.serviceClass => serviceClassId,
    LocationFilterDimension.department => departmentId,
    LocationFilterDimension.coverage => coverageId,
    LocationFilterDimension.documentKind => documentKindId,
  };

  LocationFilterOption? optionFor(LocationFilterDimension dimension) {
    return switch (dimension) {
      LocationFilterDimension.organization => LocationFilterOption(
        value: organizationId,
        nameEn: organizationNameEn,
        nameAr: organizationNameAr,
      ),
      LocationFilterDimension.zone =>
        zoneId == null
            ? null
            : LocationFilterOption(
                value: zoneId!,
                nameEn: zoneNameEn ?? '',
                nameAr: zoneNameAr,
              ),
      LocationFilterDimension.site => LocationFilterOption(
        value: siteId,
        nameEn: siteNameEn,
        nameAr: siteNameAr,
      ),
      LocationFilterDimension.building => LocationFilterOption(
        value: buildingId,
        nameEn: buildingNameEn,
        nameAr: buildingNameAr,
        code: buildingCode,
      ),
      LocationFilterDimension.floor => LocationFilterOption(
        value: floorId,
        nameEn: floorNameEn,
        nameAr: floorNameAr,
        code: floorCode,
      ),
      LocationFilterDimension.area => LocationFilterOption(
        value: areaId,
        nameEn: areaNameEn,
        nameAr: areaNameAr,
        code: areaCode,
      ),
      LocationFilterDimension.checklistType => LocationFilterOption(
        value: serviceTypeCode,
        nameEn: serviceTypeNameEn,
        nameAr: serviceTypeNameAr,
        code: serviceTypeCode,
      ),
      LocationFilterDimension.sector =>
        sectorId == null
            ? null
            : LocationFilterOption(
                value: sectorId!,
                nameEn: sectorNameEn,
                nameAr: sectorNameAr,
              ),
      LocationFilterDimension.serviceClass =>
        serviceClassId == null
            ? null
            : LocationFilterOption(
                value: serviceClassId!,
                nameEn: serviceClassNameEn,
                nameAr: serviceClassNameAr,
              ),
      LocationFilterDimension.department =>
        departmentId == null
            ? null
            : LocationFilterOption(
                value: departmentId!,
                nameEn: departmentNameEn,
                nameAr: departmentNameAr,
              ),
      LocationFilterDimension.coverage =>
        coverageId == null
            ? null
            : LocationFilterOption(
                value: coverageId!,
                nameEn: coverageNameEn,
                nameAr: coverageNameAr,
              ),
      LocationFilterDimension.documentKind =>
        documentKindId == null
            ? null
            : LocationFilterOption(
                value: documentKindId!,
                nameEn: documentKindNameEn,
                nameAr: documentKindNameAr,
              ),
    };
  }
}

class LocationFilterScope {
  const LocationFilterScope(this.leaves);

  final List<LocationScopeLeaf> leaves;

  static const hierarchyDimensions = <LocationFilterDimension>[
    LocationFilterDimension.organization,
    LocationFilterDimension.zone,
    LocationFilterDimension.site,
    LocationFilterDimension.building,
    LocationFilterDimension.floor,
    LocationFilterDimension.area,
    LocationFilterDimension.sector,
    LocationFilterDimension.serviceClass,
    LocationFilterDimension.department,
    LocationFilterDimension.coverage,
  ];

  List<LocationScopeLeaf> filteredLeaves(LocationFilterSelection selection) =>
      leaves.where((leaf) => _matches(leaf, selection)).toList(growable: false);

  List<LocationFilterOption> optionsFor(
    LocationFilterDimension dimension,
    LocationFilterSelection selection,
  ) {
    final options = <String, LocationFilterOption>{};
    for (final leaf in leaves) {
      if (!_matches(leaf, selection, ignore: dimension)) continue;
      final option = leaf.optionFor(dimension);
      if (option != null && option.value.isNotEmpty) {
        options[option.value] = option;
      }
    }
    final list = options.values.toList(
      growable: false,
    )..sort((a, b) => a.nameEn.toLowerCase().compareTo(b.nameEn.toLowerCase()));
    return list;
  }

  LocationFilterSelection normalize(LocationFilterSelection selection) {
    var result = selection;
    for (final dimension in hierarchyDimensions) {
      final options = optionsFor(dimension, result);
      final current = result.valueFor(dimension);
      if (current != null && options.any((o) => o.value == current)) continue;
      result = result.withValue(
        dimension,
        options.length == 1 ? options.single.value : null,
      );
    }
    final serviceOptions = optionsFor(
      LocationFilterDimension.checklistType,
      result,
    );
    if (result.serviceTypeCode != null &&
        !serviceOptions.any((o) => o.value == result.serviceTypeCode)) {
      result = result.withValue(LocationFilterDimension.checklistType, null);
    }
    final kindOptions = optionsFor(
      LocationFilterDimension.documentKind,
      result,
    );
    if (result.documentKindId != null &&
        !kindOptions.any((o) => o.value == result.documentKindId)) {
      result = result.withValue(LocationFilterDimension.documentKind, null);
    }
    return result;
  }

  bool shouldShow(
    LocationFilterDimension dimension,
    LocationFilterSelection selection,
  ) {
    final effective = normalize(selection);
    final options = optionsFor(dimension, effective);
    if (dimension == LocationFilterDimension.checklistType ||
        dimension == LocationFilterDimension.documentKind ||
        dimension == LocationFilterDimension.sector ||
        dimension == LocationFilterDimension.serviceClass ||
        dimension == LocationFilterDimension.department ||
        dimension == LocationFilterDimension.coverage) {
      return options.isNotEmpty;
    }
    return options.length > 1;
  }

  bool _matches(
    LocationScopeLeaf leaf,
    LocationFilterSelection selection, {
    LocationFilterDimension? ignore,
  }) {
    for (final dimension in LocationFilterDimension.values) {
      if (dimension == ignore) continue;
      final selected = selection.valueFor(dimension);
      if (selected == null || selected.isEmpty) continue;
      if (leaf.valueFor(dimension) != selected) return false;
    }
    return true;
  }
}

String accessRequirementDbValue(SiteAccessRequirement requirement) =>
    switch (requirement) {
      SiteAccessRequirement.none => 'read',
      SiteAccessRequirement.read => 'read',
      SiteAccessRequirement.write => 'write',
    };

class ManageableLocationScope {
  const ManageableLocationScope({
    required this.type,
    required this.id,
    required this.nameEn,
    this.nameAr,
    required this.pathEn,
    this.pathAr,
    required this.sortRank,
  });

  final String type;
  final String id;
  final String nameEn;
  final String? nameAr;
  final String pathEn;
  final String? pathAr;
  final int sortRank;

  String get key => '$type:$id';

  String labelFor(String language) {
    if (language == 'ar' && pathAr?.trim().isNotEmpty == true) {
      return pathAr!;
    }
    return pathEn;
  }

  factory ManageableLocationScope.fromJson(Map<String, dynamic> json) =>
      ManageableLocationScope(
        type: (json['scope_type'] ?? '') as String,
        id: (json['scope_id'] ?? '') as String,
        nameEn: (json['name_en'] ?? '') as String,
        nameAr: json['name_ar'] as String?,
        pathEn: (json['path_en'] ?? '') as String,
        pathAr: json['path_ar'] as String?,
        sortRank: (json['sort_rank'] as num?)?.toInt() ?? 0,
      );
}

class UserLocationGrant {
  const UserLocationGrant({
    required this.id,
    required this.scopeType,
    required this.scopeId,
    required this.role,
    required this.canRead,
    required this.canWrite,
    required this.canManage,
    this.validFrom,
    this.validUntil,
  });

  final String id;
  final String scopeType;
  final String scopeId;
  final UserRole role;
  final bool canRead;
  final bool canWrite;
  final bool canManage;
  final DateTime? validFrom;
  final DateTime? validUntil;

  String get key => '$scopeType:$scopeId';

  factory UserLocationGrant.fromJson(Map<String, dynamic> json) =>
      UserLocationGrant(
        id: (json['access_id'] ?? '') as String,
        scopeType: (json['scope_type'] ?? '') as String,
        scopeId: (json['scope_id'] ?? '') as String,
        role: UserRole.fromDb((json['role'] ?? 'viewer') as String),
        canRead: json['can_read'] as bool? ?? true,
        canWrite: json['can_write'] as bool? ?? false,
        canManage: json['can_manage'] as bool? ?? false,
        validFrom: json['valid_from'] == null
            ? null
            : DateTime.tryParse(json['valid_from'] as String),
        validUntil: json['valid_until'] == null
            ? null
            : DateTime.tryParse(json['valid_until'] as String),
      );
}
