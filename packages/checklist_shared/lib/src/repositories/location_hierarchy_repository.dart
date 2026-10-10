import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/location_hierarchy.dart';

class LocationHierarchyRepository {
  LocationHierarchyRepository(this._client);

  final SupabaseClient _client;

  Future<List<FacilityBuilding>> listBuildings({
    required String siteId,
    bool activeOnly = true,
  }) async {
    var query = _client
        .from('facility_buildings')
        .select(
          'id, site_id, legacy_site_id, code, name_en, name_ar, '
          'is_active, sort_order',
        )
        .eq('site_id', siteId);
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('name_en');
    return [
      for (final row in rows as List)
        FacilityBuilding.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<FacilityFloor>> listFloors({
    required String buildingId,
    bool activeOnly = true,
  }) async {
    var query = _client
        .from('facility_floors')
        .select(
          'id, building_id, code, name_en, name_ar, level_number, '
          'is_active, sort_order',
        )
        .eq('building_id', buildingId);
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('level_number');
    return [
      for (final row in rows as List)
        FacilityFloor.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<FacilityArea>> listAreas({
    required String floorId,
    bool activeOnly = true,
  }) async {
    var query = _client
        .from('facility_areas')
        .select(
          'id, floor_id, code, name_en, name_ar, area_type, '
          'is_active, sort_order',
        )
        .eq('floor_id', floorId);
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('name_en');
    return [
      for (final row in rows as List)
        FacilityArea.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<FacilityBuilding> createBuilding({
    required String siteId,
    required String code,
    required String nameEn,
    String? nameAr,
    int sortOrder = 0,
  }) async {
    final row = await _client
        .from('facility_buildings')
        .insert({
          'site_id': siteId,
          'code': code.trim(),
          'name_en': nameEn.trim(),
          'name_ar': nameAr?.trim(),
          'sort_order': sortOrder,
          'is_active': true,
        })
        .select()
        .single();
    return FacilityBuilding.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FacilityBuilding> updateBuilding({
    required FacilityBuilding building,
    required String code,
    required String nameEn,
    String? nameAr,
    required bool isActive,
  }) async {
    final row = await _client
        .from('facility_buildings')
        .update({
          'code': code.trim(),
          'name_en': nameEn.trim(),
          'name_ar': nameAr?.trim(),
          'is_active': isActive,
          'sort_order': building.sortOrder,
        })
        .eq('id', building.id)
        .select()
        .single();
    return FacilityBuilding.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FacilityFloor> createFloor({
    required String buildingId,
    required String code,
    required String nameEn,
    String? nameAr,
    int? levelNumber,
    int sortOrder = 0,
  }) async {
    final row = await _client
        .from('facility_floors')
        .insert({
          'building_id': buildingId,
          'code': code.trim(),
          'name_en': nameEn.trim(),
          'name_ar': nameAr?.trim(),
          'level_number': levelNumber,
          'sort_order': sortOrder,
          'is_active': true,
        })
        .select()
        .single();
    return FacilityFloor.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FacilityFloor> updateFloor({
    required FacilityFloor floor,
    required String code,
    required String nameEn,
    String? nameAr,
    int? levelNumber,
    required bool isActive,
  }) async {
    final row = await _client
        .from('facility_floors')
        .update({
          'code': code.trim(),
          'name_en': nameEn.trim(),
          'name_ar': nameAr?.trim(),
          'level_number': levelNumber,
          'is_active': isActive,
          'sort_order': floor.sortOrder,
        })
        .eq('id', floor.id)
        .select()
        .single();
    return FacilityFloor.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FacilityArea> createArea({
    required String floorId,
    required String code,
    required String nameEn,
    String? nameAr,
    String areaType = 'other',
    int sortOrder = 0,
  }) async {
    final row = await _client
        .from('facility_areas')
        .insert({
          'floor_id': floorId,
          'code': code.trim(),
          'name_en': nameEn.trim(),
          'name_ar': nameAr?.trim(),
          'area_type': areaType.trim().isEmpty ? 'other' : areaType.trim(),
          'sort_order': sortOrder,
          'is_active': true,
        })
        .select()
        .single();
    return FacilityArea.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FacilityArea> updateArea({
    required FacilityArea area,
    required String code,
    required String nameEn,
    String? nameAr,
    required String areaType,
    required bool isActive,
  }) async {
    final row = await _client
        .from('facility_areas')
        .update({
          'code': code.trim(),
          'name_en': nameEn.trim(),
          'name_ar': nameAr?.trim(),
          'area_type': areaType.trim().isEmpty ? 'other' : areaType.trim(),
          'is_active': isActive,
          'sort_order': area.sortOrder,
        })
        .eq('id', area.id)
        .select()
        .single();
    return FacilityArea.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<ChecklistAssignment>> listAssignments({
    required String areaId,
    bool activeOnly = true,
  }) async {
    var query = _client
        .from('checklist_assignments')
        .select(
          'id, organization_id, site_id, building_id, floor_id, area_id, '
          'name_en, name_ar, template_id, template_code_snapshot, '
          'service_type_code, legacy_site_id, is_active, sort_order',
        )
        .eq('area_id', areaId);
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('name_en');
    return [
      for (final row in rows as List)
        ChecklistAssignment.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<ChecklistServiceType>> listServiceTypes({
    bool activeOnly = true,
  }) async {
    var query = _client
        .from('checklist_service_types')
        .select('code, name_en, name_ar, is_active, sort_order');
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('name_en');
    return [
      for (final row in rows as List)
        ChecklistServiceType.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<LocationFilterScope> listMyChecklistLocationScope({
    SiteAccessRequirement requirement = SiteAccessRequirement.read,
  }) async {
    final raw = await _client.rpc(
      'list_my_checklist_location_scope',
      params: {'p_requirement': accessRequirementDbValue(requirement)},
    );
    final leaves = [
      for (final row in raw as List)
        LocationScopeLeaf.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    return LocationFilterScope(leaves);
  }

  Future<List<ManageableLocationScope>> listManageableLocationScopes({
    String? organizationId,
  }) async {
    final raw = await _client.rpc(
      'list_manageable_location_scopes',
      params: {'p_organization_id': organizationId},
    );
    return [
      for (final row in raw as List)
        ManageableLocationScope.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<UserLocationGrant>> listUserLocationAccess({
    required String userId,
    String? organizationId,
  }) async {
    final raw = await _client.rpc(
      'list_user_location_access_v15',
      params: {'p_user_id': userId, 'p_organization_id': organizationId},
    );
    return [
      for (final row in raw as List)
        UserLocationGrant.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<void> replaceUserLocationAccess({
    required String userId,
    required UserRole role,
    required List<ManageableLocationScope> scopes,
    String? organizationId,
  }) async {
    await _client.rpc(
      'replace_user_location_access_v15',
      params: {
        'p_user_id': userId,
        'p_role': role.dbValue,
        'p_scopes': [
          for (final scope in scopes) {'type': scope.type, 'id': scope.id},
        ],
        'p_organization_id': organizationId,
      },
    );
  }
}
