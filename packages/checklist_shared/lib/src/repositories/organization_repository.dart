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
