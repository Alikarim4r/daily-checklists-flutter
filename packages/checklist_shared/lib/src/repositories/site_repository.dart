import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/profile.dart';

class SiteRepository {
  SiteRepository(this._client);

  final SupabaseClient _client;

  Future<List<ChecklistSite>> listChecklistSites({bool activeOnly = true}) async {
    var q = _client.from('sites').select().not('building_code', 'is', null);
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('building_code');
    return (rows as List)
        .map((e) => ChecklistSite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Sites the current user can read (RLS + optional client filter).
  Future<List<ChecklistSite>> listAccessibleSites({
    Profile? profile,
  }) async {
    if (profile != null &&
        (profile.isPlatformOwner || profile.role == UserRole.superAdmin)) {
      return listChecklistSites();
    }
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final access = await listMySiteAccess();
    final ids = access.where((a) => a.canRead).map((a) => a.siteId).toSet();
    if (ids.isEmpty) return [];
    final all = await listChecklistSites();
    return all.where((s) => ids.contains(s.id)).toList();
  }

  /// Sites the current user can write inspections for.
  Future<List<ChecklistSite>> listWritableSites({Profile? profile}) async {
    if (profile != null &&
        (profile.isPlatformOwner || profile.role == UserRole.superAdmin)) {
      return listChecklistSites();
    }
    final access = await listMySiteAccess();
    final ids = access.where((a) => a.canWrite).map((a) => a.siteId).toSet();
    if (ids.isEmpty) return [];
    final all = await listChecklistSites();
    return all.where((s) => ids.contains(s.id)).toList();
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
    return access.any((a) => a.siteId == siteId && a.canWrite);
  }

  Future<bool> canManageSite(String siteId, {Profile? profile}) async {
    if (profile != null &&
        (profile.isPlatformOwner || profile.role == UserRole.superAdmin)) {
      return true;
    }
    final access = await listMySiteAccess();
    return access.any((a) => a.siteId == siteId && a.canManage);
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
          'sites(id, organization_id, name_en, name_ar, building_code, pin, '
          'checklist_type, location, is_active)',
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
