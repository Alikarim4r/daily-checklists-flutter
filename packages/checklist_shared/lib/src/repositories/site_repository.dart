import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/profile.dart';
import '../theme/form_theme_resolution.dart';
import '../utils/site_hierarchy.dart';

class SiteRepository {
  SiteRepository(this._client);

  final SupabaseClient _client;

  static const _siteSelect =
      'id, organization_id, zone_id, parent_site_id, name_en, name_ar, '
      'building_code, pin, checklist_type, location, is_active, report_logo_path, '
      'form_theme, form_theme_accent';

  Future<List<ChecklistSite>> _withEffectiveThemes(
    List<ChecklistSite> sites,
  ) async {
    if (sites.isEmpty) return sites;
    final resolved = <String, Map<String, dynamic>>{};
    try {
      final raw = await _client.rpc(
        'resolve_checklist_form_themes',
        params: {'p_site_ids': sites.map((site) => site.id).toList()},
      );
      for (final rawRow in raw as List) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        final siteId = row['site_id'] as String?;
        final theme = row['theme_key'] as String?;
        if (siteId == null ||
            theme == null ||
            theme.isEmpty ||
            theme == 'inherit') {
          continue;
        }
        resolved[siteId] = row;
      }
    } catch (_) {
      // The local hierarchy resolver below keeps themes working offline and
      // during staged database migrations.
    }

    final unresolved = sites.where((site) => !resolved.containsKey(site.id));
    if (unresolved.isEmpty) return _applyRpcThemes(sites, resolved);

    final allById = {for (final site in sites) site.id: site};
    final missingParentIds = unresolved
        .map((site) => site.parentSiteId)
        .whereType<String>()
        .where((id) => !allById.containsKey(id))
        .toSet();
    if (missingParentIds.isNotEmpty) {
      try {
        final rows = await _client
            .from('sites')
            .select(_siteSelect)
            .inFilter('id', missingParentIds.toList());
        for (final row in rows as List) {
          final parent = ChecklistSite.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          allById[parent.id] = parent;
        }
      } catch (_) {
        // Continue with the hierarchy levels the current role can read.
      }
    }

    final zoneIds = <String>{};
    final organizationIds = <String>{};
    final templateCodes = <String>{};
    for (final site in unresolved) {
      final parent = allById[site.parentSiteId];
      final zoneId = site.zoneId ?? parent?.zoneId;
      if (zoneId != null && zoneId.isNotEmpty) zoneIds.add(zoneId);
      if (site.organizationId.isNotEmpty) {
        organizationIds.add(site.organizationId);
      }
      if (site.checklistType.isNotEmpty) templateCodes.add(site.checklistType);
    }

    final zoneRows = await _safeThemeRows(
      table: 'zones',
      columns: 'id, form_theme, form_theme_accent',
      filterColumn: 'id',
      values: zoneIds,
    );
    final organizationRows = await _safeThemeRows(
      table: 'organizations',
      columns: 'id, form_theme, form_theme_accent',
      filterColumn: 'id',
      values: organizationIds,
    );
    final templateRows = await _safeThemeRows(
      table: 'checklist_templates',
      columns: 'code, form_theme, form_theme_accent',
      filterColumn: 'code',
      values: templateCodes,
    );
    final zonesById = {for (final row in zoneRows) row['id'] as String: row};
    final organizationsById = {
      for (final row in organizationRows) row['id'] as String: row,
    };
    final templatesByCode = {
      for (final row in templateRows) row['code'] as String: row,
    };

    return [
      for (final site in sites)
        if (resolved[site.id] case final rpcTheme?)
          _applyResolvedTheme(
            site,
            theme: rpcTheme['theme_key'] as String,
            accent: rpcTheme['accent_hex'] as String?,
            source: rpcTheme['source_scope'] as String? ?? 'database',
          )
        else
          () {
            final parent = allById[site.parentSiteId];
            final zoneId = site.zoneId ?? parent?.zoneId;
            final local = resolveFormThemeHierarchy(
              site: _siteScope(site, 'site'),
              campus: parent == null ? null : _siteScope(parent, 'campus'),
              zone: _mapScope(zonesById[zoneId], 'zone'),
              template: _mapScope(
                templatesByCode[site.checklistType],
                'template',
              ),
              organization: _mapScope(
                organizationsById[site.organizationId],
                'organization',
              ),
            );
            return _applyResolvedTheme(
              site,
              theme: local.theme,
              accent: local.accent,
              source: local.source,
            );
          }(),
    ];
  }

  List<ChecklistSite> _applyRpcThemes(
    List<ChecklistSite> sites,
    Map<String, Map<String, dynamic>> resolved,
  ) => [
    for (final site in sites)
      if (resolved[site.id] case final theme?)
        _applyResolvedTheme(
          site,
          theme: theme['theme_key'] as String,
          accent: theme['accent_hex'] as String?,
          source: theme['source_scope'] as String? ?? 'database',
        )
      else
        site,
  ];

  ChecklistSite _applyResolvedTheme(
    ChecklistSite site, {
    required String theme,
    required String? accent,
    required String source,
  }) => site.copyWith(
    effectiveFormTheme: theme,
    effectiveFormThemeAccent: accent,
    clearEffectiveThemeAccent: accent == null,
    formThemeSource: source,
  );

  FormThemeScopeValue _siteScope(ChecklistSite site, String source) =>
      FormThemeScopeValue(
        theme: site.formTheme,
        accent: site.formThemeAccent,
        source: source,
      );

  FormThemeScopeValue? _mapScope(Map<String, dynamic>? row, String source) =>
      row == null
      ? null
      : FormThemeScopeValue(
          theme: row['form_theme'] as String?,
          accent: row['form_theme_accent'] as String?,
          source: source,
        );

  Future<List<Map<String, dynamic>>> _safeThemeRows({
    required String table,
    required String columns,
    required String filterColumn,
    required Iterable<String> values,
  }) async {
    final ids = values.where((value) => value.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const [];
    try {
      final rows = await _client
          .from(table)
          .select(columns)
          .inFilter(filterColumn, ids);
      return [
        for (final row in rows as List) Map<String, dynamic>.from(row as Map),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<ChecklistSite>> _decodeSites(Object? rows) async {
    final sites = [
      for (final row in rows as List)
        ChecklistSite.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    return _withEffectiveThemes(sites);
  }

  /// Checklist units only (rows with a building_code).
  Future<List<ChecklistSite>> listChecklistSites({
    bool activeOnly = true,
  }) async {
    var q = _client
        .from('sites')
        .select(_siteSelect)
        .not('building_code', 'is', null);
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('building_code');
    return _decodeSites(rows);
  }

  /// Campus / container sites (no building_code).
  Future<List<ChecklistSite>> listCampusSites({bool activeOnly = true}) async {
    var q = _client
        .from('sites')
        .select(_siteSelect)
        .isFilter('building_code', null);
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('name_en');
    return _decodeSites(rows);
  }

  Future<List<ChecklistSite>> listSitesByIds(Iterable<String> ids) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return [];
    final rows = await _client
        .from('sites')
        .select(_siteSelect)
        .inFilter('id', idList);
    return _decodeSites(rows);
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
    }).toList()..sort((a, b) => a.buildingCode.compareTo(b.buildingCode));
    return units;
  }

  bool _bypassesSiteGrants(Profile? profile) {
    if (profile == null) return false;
    // Owner: all orgs. Org super_admin: RLS already limits to home org.
    return profile.isPlatformOwner || profile.role == UserRole.superAdmin;
  }

  /// Sites the current user can read (RLS + optional client filter).
  Future<List<ChecklistSite>> listAccessibleSites({Profile? profile}) async {
    if (_bypassesSiteGrants(profile)) {
      return listChecklistSites();
    }
    final access = await listMySiteAccess();
    final ids = access.where((a) => a.canRead).map((a) => a.siteId).toSet();
    return _expandChecklistAccess(grantedIds: ids);
  }

  /// Sites the current user can write inspections for.
  Future<List<ChecklistSite>> listWritableSites({Profile? profile}) async {
    if (_bypassesSiteGrants(profile)) {
      return listChecklistSites();
    }
    final access = await listMySiteAccess();
    final ids = access.where((a) => a.canWrite).map((a) => a.siteId).toSet();
    return _expandChecklistAccess(grantedIds: ids);
  }

  /// Writable checklist units grouped under campus sites for Entry UI.
  Future<List<CampusChecklistGroup>> listWritableCampusGroups({
    Profile? profile,
  }) => _listCampusGroups(
    profile: profile,
    accessFlag: (access) => access.canWrite,
  );

  /// Accessible checklist units grouped under campus sites.
  Future<List<CampusChecklistGroup>> listAccessibleCampusGroups({
    Profile? profile,
  }) => _listCampusGroups(
    profile: profile,
    accessFlag: (access) => access.canRead,
  );

  /// Fetch the hierarchy once, then filter checklist units in memory.
  /// This replaces repeated checklist/parent/theme queries on every home load.
  Future<List<CampusChecklistGroup>> _listCampusGroups({
    required Profile? profile,
    required bool Function(UserSiteAccess access) accessFlag,
  }) async {
    late final List<ChecklistSite> all;
    Set<String>? grantedIds;
    if (_bypassesSiteGrants(profile)) {
      all = await listAllSites(activeOnly: true);
    } else {
      final loaded = await Future.wait<Object>([
        listAllSites(activeOnly: true),
        listMySiteAccess(),
      ]);
      all = loaded[0] as List<ChecklistSite>;
      final access = loaded[1] as List<UserSiteAccess>;
      grantedIds = access.where(accessFlag).map((a) => a.siteId).toSet();
    }

    final parentGrants = grantedIds == null
        ? const <String>{}
        : all
              .where((site) => site.isCampus && grantedIds!.contains(site.id))
              .map((site) => site.id)
              .toSet();
    final checklists = all.where((site) {
      if (!site.isChecklistUnit) return false;
      if (grantedIds == null) return true;
      if (grantedIds.contains(site.id)) return true;
      final parentId = site.parentSiteId;
      return parentId != null && parentGrants.contains(parentId);
    }).toList()..sort((a, b) => a.buildingCode.compareTo(b.buildingCode));

    return groupChecklistsByCampus(checklists: checklists, allSites: all);
  }

  Future<List<UserSiteAccess>> listMySiteAccess() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    return listUserSiteAccess(uid);
  }

  Future<bool> _siteInHomeOrg(String siteId, Profile profile) async {
    final home = profile.homeOrganizationId;
    if (home == null) return false;
    final sites = await listSitesByIds([siteId]);
    if (sites.isEmpty) return false;
    return sites.first.organizationId == home;
  }

  Future<bool> canWriteSite(String siteId, {Profile? profile}) async {
    if (profile != null && profile.isPlatformOwner) return true;
    if (profile != null && profile.role == UserRole.superAdmin) {
      return _siteInHomeOrg(siteId, profile);
    }
    final access = await listMySiteAccess();
    if (access.any(
      (a) => a.siteId == siteId && a.canWrite && a.isCurrentlyValid,
    )) {
      return true;
    }
    // Parent campus write expands to children
    final sites = await listSitesByIds([siteId]);
    final parentId = sites.isEmpty ? null : sites.first.parentSiteId;
    if (parentId == null) return false;
    return access.any(
      (a) => a.siteId == parentId && a.canWrite && a.isCurrentlyValid,
    );
  }

  Future<bool> canManageSite(String siteId, {Profile? profile}) async {
    if (profile != null && profile.isPlatformOwner) return true;
    if (profile != null && profile.role == UserRole.superAdmin) {
      return _siteInHomeOrg(siteId, profile);
    }
    final access = await listMySiteAccess();
    if (access.any(
      (a) => a.siteId == siteId && a.canManage && a.isCurrentlyValid,
    )) {
      return true;
    }
    final sites = await listSitesByIds([siteId]);
    final parentId = sites.isEmpty ? null : sites.first.parentSiteId;
    if (parentId == null) return false;
    return access.any(
      (a) => a.siteId == parentId && a.canManage && a.isCurrentlyValid,
    );
  }

  Future<void> grantSiteAccess({
    required String userId,
    required String siteId,
    bool canRead = true,
    bool canWrite = false,
    bool canManage = false,
    String role = 'technician',
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    await _client.from('user_site_access').upsert({
      'user_id': userId,
      'site_id': siteId,
      'can_read': canRead,
      'can_write': canWrite,
      'can_manage': canManage,
      'role': role,
      'valid_from': validFrom?.toUtc().toIso8601String(),
      'valid_until': validUntil?.toUtc().toIso8601String(),
    }, onConflict: 'user_id,site_id');
  }

  Future<void> updateSiteAccessFlags({
    required String userId,
    required String siteId,
    required bool canRead,
    required bool canWrite,
    required bool canManage,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    await _client
        .from('user_site_access')
        .update({
          'can_read': canRead,
          'can_write': canWrite,
          'can_manage': canManage,
          'valid_from': validFrom?.toUtc().toIso8601String(),
          'valid_until': validUntil?.toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('site_id', siteId);
  }

  Future<List<UserSiteAccess>> listUserSiteAccess(String userId) async {
    final rows = await _client
        .from('user_site_access')
        .select(
          'id, user_id, site_id, role, can_read, can_write, can_manage, '
          'valid_from, valid_until, '
          'sites(id, organization_id, zone_id, parent_site_id, name_en, name_ar, '
          'building_code, pin, checklist_type, location, is_active, '
          'report_logo_path, form_theme, form_theme_accent)',
        )
        .eq('user_id', userId);
    return (rows as List)
        .map(
          (e) => UserSiteAccess.fromJson(Map<String, dynamic>.from(e as Map)),
        )
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
    return _decodeSites(rows);
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
    String location = 'Government HQ Demo',
    String siteType = 'other',
  }) async {
    final code = buildingCode?.trim();
    final row = await _client
        .from('sites')
        .insert({
          'organization_id': organizationId,
          'zone_id': ?zoneId,
          'parent_site_id': ?parentSiteId,
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
    return (await _decodeSites([row])).single;
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
    String location = 'Government HQ Demo',
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
    return (await _decodeSites([row])).single;
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

  Future<ChecklistSite> updateFormTheme({
    required String id,
    required String formTheme,
    String? formThemeAccent,
  }) async {
    final row = await _client
        .from('sites')
        .update({'form_theme': formTheme, 'form_theme_accent': formThemeAccent})
        .eq('id', id)
        .select(_siteSelect)
        .single();
    return (await _decodeSites([row])).single;
  }

  Future<ChecklistSite> updateReportLogo({
    required String id,
    String? reportLogoPath,
  }) async {
    final row = await _client
        .from('sites')
        .update({'report_logo_path': reportLogoPath})
        .eq('id', id)
        .select(_siteSelect)
        .single();
    return (await _decodeSites([row])).single;
  }

  Future<int> countMyAccess({
    required SiteAccessRequirement requirement,
  }) async {
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
