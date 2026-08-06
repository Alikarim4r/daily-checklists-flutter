import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/profile.dart';
import '../utils/site_hierarchy.dart';

class SiteRepository {
  SiteRepository(this._client);

  final SupabaseClient _client;

  static const _siteSelect =
      'id, organization_id, zone_id, parent_site_id, name_en, name_ar, '
      'building_code, pin, checklist_type, location, is_active';

  /// Checklist units only (rows with a building_code).
  Future<List<ChecklistSite>> listChecklistSites({bool activeOnly = true}) async {
    var q = _client.from('sites').select(_siteSelect).not('building_code', 'is', null);
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('building_code');
    return (rows as List)
        .map((e) => ChecklistSite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Campus / container sites (no building_code).
  Future<List<ChecklistSite>> listCampusSites({bool activeOnly = true}) async {
    var q = _client.from('sites').select(_siteSelect).isFilter('building_code', null);
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('name_en');
    return (rows as List)
        .map((e) => ChecklistSite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ChecklistSite>> listSitesByIds(Iterable<String> ids) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return [];
    final rows =
        await _client.from('sites').select(_siteSelect).inFilter('id', idList);
    return (rows as List)
        .map((e) => ChecklistSite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ChecklistSite>> _expandChecklistAccess({
    required Set<String> grantedIds,
  }) async {
    if (grantedIds.isEmpty) return [];
    final all = await listAllSites(activeOnly: true);
    final parentGrants = all
        .where((s) => s.isCampus && grantedIds.contains(s.id))
        .map((s) => s.id)
        .toSet();
    final units = all.where((s) => s.isChecklistUnit).where((s) {
      if (grantedIds.contains(s.id)) return true;
      final p = s.parentSiteId;
      return p != null && parentGrants.contains(p);
    }).toList()
      ..sort((a, b) => a.buildingCode.compareTo(b.buildingCode));
    return units;
  }

  /// Sites the current user can read (RLS + optional client filter).
  Future<List<ChecklistSite>> listAccessibleSites({
    Profile? profile,
  }) async {
    if (profile != null &&
        (profile.isPlatformOwner || profile.role == UserRole.superAdmin)) {
      return listChecklistSites();
    }
    final access = await listMySiteAccess();
    final ids = access.where((a) => a.canRead).map((a) => a.siteId).toSet();
    return _expandChecklistAccess(grantedIds: ids);
  }

  /// Sites the current user can write inspections for.
  Future<List<ChecklistSite>> listWritableSites({Profile? profile}) async {
    if (profile != null &&
        (profile.isPlatformOwner || profile.role == UserRole.superAdmin)) {
      return listChecklistSites();
    }
    final access = await listMySiteAccess();
    final ids = access.where((a) => a.canWrite).map((a) => a.siteId).toSet();
    return _expandChecklistAccess(grantedIds: ids);
  }

  /// Writable checklist units grouped under campus sites for Entry UI.
  Future<List<CampusChecklistGroup>> listWritableCampusGroups({
    Profile? profile,
  }) async {
    final checklists = await listWritableSites(profile: profile);
    final parentIds = checklists
        .map((c) => c.parentSiteId)
        .whereType<String>()
        .toSet();
    final parents = await listSitesByIds(parentIds);
    final orphanIds = checklists
        .where((c) => c.parentSiteId == null)
        .map((c) => c.id);
    final extra = await listSitesByIds([...parentIds, ...orphanIds]);
    final all = {...parents, ...extra, ...checklists}.toList();
    return groupChecklistsByCampus(checklists: checklists, allSites: all);
  }

  /// Accessible checklist units grouped under campus sites.
  Future<List<CampusChecklistGroup>> listAccessibleCampusGroups({
    Profile? profile,
  }) async {
    final checklists = await listAccessibleSites(profile: profile);
    final parentIds = checklists
        .map((c) => c.parentSiteId)
        .whereType<String>()
        .toSet();
    final parents = await listSitesByIds(parentIds);
    return groupChecklistsByCampus(
      checklists: checklists,
      allSites: [...parents, ...checklists],
    );
  }

  Future<List<UserSiteAccess>> listMySiteAccess() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    return listUserSiteAccess(uid);
  }

  Future<bool> canWriteSite(String siteId, {Profile? profile}) async {
    if (profile != null &&
        (profile.isPlatformOwner || profile.role == UserRole.superAdmin)) {
      return true;
    }
    final access = await listMySiteAccess();
    if (access.any((a) => a.siteId == siteId && a.canWrite)) return true;
    // Parent campus write expands to children
    final sites = await listSitesByIds([siteId]);
    final parentId = sites.isEmpty ? null : sites.first.parentSiteId;
    if (parentId == null) return false;
    return access.any((a) => a.siteId == parentId && a.canWrite);
  }

  Future<bool> canManageSite(String siteId, {Profile? profile}) async {
    if (profile != null &&
        (profile.isPlatformOwner || profile.role == UserRole.superAdmin)) {
      return true;
    }
    final access = await listMySiteAccess();
    if (access.any((a) => a.siteId == siteId && a.canManage)) return true;
    final sites = await listSitesByIds([siteId]);
    final parentId = sites.isEmpty ? null : sites.first.parentSiteId;
    if (parentId == null) return false;
    return access.any((a) => a.siteId == parentId && a.canManage);
  }

  Future<void> grantSiteAccess({
    required String userId,
    required String siteId,
    bool canRead = true,
    bool canWrite = false,
    bool canManage = false,
    String role = 'technician',
  }) async {
    await _client.from('user_site_access').upsert({
      'user_id': userId,
      'site_id': siteId,
      'can_read': canRead,
      'can_write': canWrite,
      'can_manage': canManage,
      'role': role,
    }, onConflict: 'user_id,site_id');
  }

  Future<void> updateSiteAccessFlags({
    required String userId,
    required String siteId,
    required bool canRead,
    required bool canWrite,
    required bool canManage,
  }) async {
    await _client
        .from('user_site_access')
        .update({
          'can_read': canRead,
          'can_write': canWrite,
          'can_manage': canManage,
        })
        .eq('user_id', userId)
        .eq('site_id', siteId);
  }

  Future<List<UserSiteAccess>> listUserSiteAccess(String userId) async {
    final rows = await _client
        .from('user_site_access')
        .select(
          'id, user_id, site_id, role, can_read, can_write, can_manage, '
          'sites(id, organization_id, zone_id, parent_site_id, name_en, name_ar, '
          'building_code, pin, checklist_type, location, is_active)',
        )
        .eq('user_id', userId);
    return (rows as List)
        .map((e) => UserSiteAccess.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> revokeSiteAccess({
    required String userId,
    required String siteId,
  }) async {
    await _client
        .from('user_site_access')
        .delete()
        .eq('user_id', userId)
        .eq('site_id', siteId);
  }

  Future<List<ChecklistSite>> listAllSites({bool activeOnly = false}) async {
    var q = _client.from('sites').select(_siteSelect);
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('building_code').order('name_en');
    return (rows as List)
        .map((e) => ChecklistSite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ChecklistSite> createSite({
    required String organizationId,
    String? zoneId,
    String? parentSiteId,
    required String nameEn,
    required String nameAr,
    String? buildingCode,
    String pin = '',
    String checklistType = 'DEFAULT',
    String location = 'MOEHE Permanent Headquarters',
    String siteType = 'other',
  }) async {
    final code = buildingCode?.trim();
    final row = await _client
        .from('sites')
        .insert({
          'organization_id': organizationId,
          if (zoneId != null) 'zone_id': zoneId,
          if (parentSiteId != null) 'parent_site_id': parentSiteId,
          'name_en': nameEn,
          'name_ar': nameAr,
          'building_code': (code == null || code.isEmpty) ? null : code,
          'pin': pin,
          'checklist_type': checklistType,
          'location': location,
          'site_type': siteType,
          'is_active': true,
        })
        .select(_siteSelect)
        .single();
    return ChecklistSite.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ChecklistSite> updateSite({
    required String id,
    String? zoneId,
    String? parentSiteId,
    required String nameEn,
    required String nameAr,
    String? buildingCode,
    String pin = '',
    String checklistType = 'DEFAULT',
    String location = 'MOEHE Permanent Headquarters',
    bool isActive = true,
  }) async {
    final code = buildingCode?.trim();
    final row = await _client
        .from('sites')
        .update({
          'zone_id': zoneId,
          'parent_site_id': parentSiteId,
          'name_en': nameEn,
          'name_ar': nameAr,
          'building_code': (code == null || code.isEmpty) ? null : code,
          'pin': pin,
          'checklist_type': checklistType,
          'location': location,
          'is_active': isActive,
        })
        .eq('id', id)
        .select(_siteSelect)
        .single();
    return ChecklistSite.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ChecklistSite> updateChecklistType({
    required ChecklistSite site,
    required String checklistType,
  }) {
    return updateSite(
      id: site.id,
      zoneId: site.zoneId,
      parentSiteId: site.parentSiteId,
      nameEn: site.nameEn,
      nameAr: site.nameAr,
      buildingCode: site.buildingCode,
      pin: site.pin,
      checklistType: checklistType,
      location: site.location,
      isActive: site.isActive,
    );
  }

  Future<void> deleteSite(String id) async {
    await _client.from('sites').delete().eq('id', id);
  }

  Future<int> countMyAccess({required SiteAccessRequirement requirement}) async {
    final access = await listMySiteAccess();
    switch (requirement) {
      case SiteAccessRequirement.none:
        return access.length;
      case SiteAccessRequirement.read:
        return access.where((a) => a.canRead).length;
      case SiteAccessRequirement.write:
        return access.where((a) => a.canWrite).length;
    }
  }
}
