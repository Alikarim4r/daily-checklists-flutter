import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/organization.dart';

class OrganizationRepository {
  OrganizationRepository(this._client);
  final SupabaseClient _client;

  Future<List<Organization>> listOrganizations({
    bool activeOnly = false,
  }) async {
    var q = _client.from('organizations').select();
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('name_en');
    return (rows as List)
        .map((e) => Organization.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Organization?> getById(String id) async {
    final row = await _client
        .from('organizations')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Organization.fromJson(Map<String, dynamic>.from(row));
  }

  Future<String> createSelfServiceCompany({
    required String nameEn,
    String? nameAr,
    required String countryCode,
    required String defaultLanguage,
  }) async {
    final id = await _client.rpc(
      'create_self_service_company',
      params: {
        'p_name_en': nameEn.trim(),
        'p_name_ar': nameAr?.trim(),
        'p_country_code': countryCode.trim().toUpperCase(),
        'p_default_language': defaultLanguage.trim().toLowerCase(),
      },
    );
    return id as String;
  }

  Future<void> updateMyOrganizationProfile({
    required String nameEn,
    required String nameAr,
    required String countryCode,
    required String defaultLanguage,
  }) async {
    await _client.rpc(
      'update_my_organization_profile',
      params: {
        'p_name_en': nameEn.trim(),
        'p_name_ar': nameAr.trim(),
        'p_country_code': countryCode.trim().toUpperCase(),
        'p_default_language': defaultLanguage.trim().toLowerCase(),
      },
    );
  }

  Future<Map<String, dynamic>> completeInitialCompanySetup({
    required String siteNameEn,
    String siteNameAr = '',
    required String buildingCode,
    required String buildingNameEn,
    String buildingNameAr = '',
    required String floorCode,
    required String floorNameEn,
    String floorNameAr = '',
    int? floorLevel,
    required String areaCode,
    required String areaNameEn,
    String areaNameAr = '',
    String areaType = 'other',
    required String templateId,
    String checklistNameEn = '',
    String checklistNameAr = '',
    String serviceTypeCode = 'other',
  }) async {
    final raw = await _client.rpc(
      'complete_initial_company_setup_v15',
      params: {
        'p_site_name_en': siteNameEn.trim(),
        'p_site_name_ar': siteNameAr.trim(),
        'p_building_code': buildingCode.trim(),
        'p_building_name_en': buildingNameEn.trim(),
        'p_building_name_ar': buildingNameAr.trim(),
        'p_floor_code': floorCode.trim(),
        'p_floor_name_en': floorNameEn.trim(),
        'p_floor_name_ar': floorNameAr.trim(),
        'p_floor_level': floorLevel,
        'p_area_code': areaCode.trim(),
        'p_area_name_en': areaNameEn.trim(),
        'p_area_name_ar': areaNameAr.trim(),
        'p_area_type': areaType.trim().isEmpty ? 'other' : areaType.trim(),
        'p_template_id': templateId,
        'p_checklist_name_en': checklistNameEn.trim(),
        'p_checklist_name_ar': checklistNameAr.trim(),
        'p_service_type_code': serviceTypeCode.trim().isEmpty
            ? 'other'
            : serviceTypeCode.trim(),
      },
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, int>> companyUsageSummary() async {
    final raw = await _client.rpc('company_usage_summary');
    if (raw is! List || raw.isEmpty) return const {};
    final row = Map<String, dynamic>.from(raw.first as Map);
    int value(String key) => (row[key] as num?)?.toInt() ?? 0;
    return {
      'users': value('users_count'),
      'sites': value('sites_count'),
      'buildings': value('buildings_count'),
      'floors': value('floors_count'),
      'areas': value('areas_count'),
      'checklists': value('checklists_count'),
    };
  }

  Future<Organization> create(Organization org) async {
    final row = await _client
        .from('organizations')
        .insert(org.toInsertJson())
        .select()
        .single();
    // Ensure default policy row exists
    await _client.from('checklist_org_policies').upsert({
      'organization_id': row['id'],
    }, onConflict: 'organization_id');
    return Organization.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Organization> update(Organization org) async {
    final row = await _client
        .from('organizations')
        .update(org.toUpdateJson())
        .eq('id', org.id)
        .select()
        .single();
    return Organization.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> delete(String id) async {
    await _client.from('organizations').delete().eq('id', id);
  }

  Future<List<Zone>> listZones(String organizationId) async {
    final rows = await _client
        .from('zones')
        .select()
        .eq('organization_id', organizationId)
        .order('sort_order')
        .order('name_en');
    return (rows as List)
        .map((e) => Zone.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Zone>> listAllZones() async {
    final rows = await _client
        .from('zones')
        .select()
        .order('sort_order')
        .order('name_en');
    return (rows as List)
        .map((e) => Zone.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Zone> createZone(Zone zone) async {
    final row = await _client
        .from('zones')
        .insert(zone.toInsertJson())
        .select()
        .single();
    return Zone.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Zone> updateZone(Zone zone) async {
    final row = await _client
        .from('zones')
        .update(zone.toUpdateJson())
        .eq('id', zone.id)
        .select()
        .single();
    return Zone.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteZone(String id) async {
    await _client.from('zones').delete().eq('id', id);
  }

  Future<Organization> updateOrgLogos({
    required String id,
    String? logoEnPath,
    String? logoArPath,
  }) async {
    final row = await _client
        .from('organizations')
        .update({'logo_en_path': logoEnPath, 'logo_ar_path': logoArPath})
        .eq('id', id)
        .select()
        .single();
    return Organization.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Organization> updateOrganizationFormTheme({
    required String id,
    required String formTheme,
    String? formThemeAccent,
  }) async {
    final row = await _client
        .from('organizations')
        .update({'form_theme': formTheme, 'form_theme_accent': formThemeAccent})
        .eq('id', id)
        .select()
        .single();
    return Organization.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Zone> updateZoneLogo({
    required String id,
    String? reportLogoPath,
  }) async {
    final row = await _client
        .from('zones')
        .update({'report_logo_path': reportLogoPath})
        .eq('id', id)
        .select()
        .single();
    return Zone.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Zone> updateZoneFormTheme({
    required String id,
    required String formTheme,
    String? formThemeAccent,
  }) async {
    final row = await _client
        .from('zones')
        .update({'form_theme': formTheme, 'form_theme_accent': formThemeAccent})
        .eq('id', id)
        .select()
        .single();
    return Zone.fromJson(Map<String, dynamic>.from(row));
  }
}
