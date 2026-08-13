import '../models/organization.dart';
import '../models/profile.dart';

/// Groups checklist units under their parent campus site.
List<CampusChecklistGroup> groupChecklistsByCampus({
  required List<ChecklistSite> checklists,
  required List<ChecklistSite> allSites,
}) {
  final byId = {for (final s in allSites) s.id: s};
  final buckets = <String?, List<ChecklistSite>>{};
  for (final c in checklists.where((s) => s.isChecklistUnit)) {
    buckets.putIfAbsent(c.parentSiteId, () => []).add(c);
  }
  for (final list in buckets.values) {
    list.sort((a, b) => a.buildingCode.compareTo(b.buildingCode));
  }
  final keys = buckets.keys.toList()
    ..sort((a, b) {
      if (a == null) return 1;
      if (b == null) return -1;
      final an = byId[a]?.nameEn ?? a;
      final bn = byId[b]?.nameEn ?? b;
      return an.compareTo(bn);
    });
  return [
    for (final key in keys)
      CampusChecklistGroup(
        campus: key == null ? null : byId[key],
        checklists: buckets[key]!,
      ),
  ];
}

/// Ordered admin hierarchy: Zone → campus groups (unzoned last).
class ZoneHierarchySection {
  const ZoneHierarchySection({this.zone, required this.groups});

  /// Null = sites not assigned to a zone.
  final Zone? zone;
  final List<CampusChecklistGroup> groups;
}

String? _effectiveZoneId({
  required ChecklistSite site,
  required Map<String, ChecklistSite> byId,
}) {
  if (site.zoneId != null && site.zoneId!.isNotEmpty) return site.zoneId;
  final parentId = site.parentSiteId;
  if (parentId == null) return null;
  final parent = byId[parentId];
  return parent?.zoneId;
}

/// Build Zone → Campus → checklist tree for admin Structure.
List<ZoneHierarchySection> groupSitesByZoneThenCampus({
  required List<Zone> zones,
  required List<ChecklistSite> orgSites,
}) {
  final sortedZones = [...zones]
    ..sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.nameEn.compareTo(b.nameEn);
    });
  final byId = {for (final s in orgSites) s.id: s};

  final buckets = <String?, List<ChecklistSite>>{};
  for (final s in orgSites) {
    final zid = _effectiveZoneId(site: s, byId: byId);
    buckets.putIfAbsent(zid, () => []).add(s);
  }

  final sections = <ZoneHierarchySection>[];

  for (final z in sortedZones) {
    final inZone = buckets[z.id] ?? const <ChecklistSite>[];
    sections.add(
      ZoneHierarchySection(
        zone: z,
        groups: _campusGroupsForZoneSlice(inZone, orgSites),
      ),
    );
  }

  final unzoned = buckets[null] ?? const <ChecklistSite>[];
  if (unzoned.isNotEmpty || sortedZones.isEmpty) {
    sections.add(
      ZoneHierarchySection(
        zone: null,
        groups: _campusGroupsForZoneSlice(unzoned, orgSites),
      ),
    );
  }

  // Drop empty unzoned-only noise when every zone already listed and unzoned empty.
  return sections.where((s) {
    if (s.zone != null) return true;
    return s.groups.isNotEmpty;
  }).toList();
}

List<CampusChecklistGroup> _campusGroupsForZoneSlice(
  List<ChecklistSite> slice,
  List<ChecklistSite> allOrgSites,
) {
  final groups = groupChecklistsByCampus(
    checklists: slice.where((s) => s.isChecklistUnit).toList(),
    allSites: allOrgSites,
  );
  final shownCampus = {
    for (final g in groups)
      if (g.campus != null) g.campus!.id,
  };
  final emptyCampuses = slice.where(
    (s) => s.isCampus && !shownCampus.contains(s.id),
  );
  return [
    ...groups,
    for (final c in emptyCampuses)
      CampusChecklistGroup(campus: c, checklists: const []),
  ];
}

/// Organization bucket for Entry/Viewer drill-down.
class OrgBrowseSection {
  const OrgBrowseSection({required this.organization, required this.zones});

  final Organization organization;
  final List<ZoneBrowseSection> zones;

  int get campusCount => zones.fold(0, (n, z) => n + z.groups.length);

  int get checklistCount => zones.fold(
    0,
    (n, z) => n + z.groups.fold(0, (m, g) => m + g.checklists.length),
  );
}

/// Zone bucket under an organization (null zone = unassigned).
class ZoneBrowseSection {
  const ZoneBrowseSection({this.zone, required this.groups});

  final Zone? zone;
  final List<CampusChecklistGroup> groups;

  String titleFor(String language) {
    if (zone != null) return zone!.nameFor(language);
    return language == 'ar' ? 'بدون منطقة' : 'Unassigned zone';
  }
}

String? _groupOrganizationId(CampusChecklistGroup group) {
  final campus = group.campus;
  if (campus != null && campus.organizationId.isNotEmpty) {
    return campus.organizationId;
  }
  if (group.checklists.isNotEmpty) {
    return group.checklists.first.organizationId;
  }
  return null;
}

String? _groupZoneId(CampusChecklistGroup group) {
  final campus = group.campus;
  if (campus?.zoneId != null && campus!.zoneId!.isNotEmpty) {
    return campus.zoneId;
  }
  for (final c in group.checklists) {
    if (c.zoneId != null && c.zoneId!.isNotEmpty) return c.zoneId;
  }
  return null;
}

/// Org → Zone → Campus groups for Entry/Viewer sequential browse.
List<OrgBrowseSection> groupCampusGroupsByOrgThenZone({
  required List<Organization> organizations,
  required List<Zone> zones,
  required List<CampusChecklistGroup> groups,
}) {
  final orgById = {for (final o in organizations) o.id: o};
  final zonesByOrg = <String, List<Zone>>{};
  for (final z in zones) {
    zonesByOrg.putIfAbsent(z.organizationId, () => []).add(z);
  }
  for (final list in zonesByOrg.values) {
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.nameEn.compareTo(b.nameEn);
    });
  }

  final byOrg = <String, List<CampusChecklistGroup>>{};
  for (final g in groups) {
    final oid = _groupOrganizationId(g);
    if (oid == null || oid.isEmpty) continue;
    byOrg.putIfAbsent(oid, () => []).add(g);
  }

  final orgIds =
      <String>{...organizations.map((o) => o.id), ...byOrg.keys}.toList()
        ..sort((a, b) {
          final an = orgById[a]?.nameEn ?? a;
          final bn = orgById[b]?.nameEn ?? b;
          return an.compareTo(bn);
        });

  final sections = <OrgBrowseSection>[];
  for (final oid in orgIds) {
    final orgGroups = byOrg[oid];
    if (orgGroups == null || orgGroups.isEmpty) continue;
    final org = orgById[oid] ?? Organization(id: oid, nameEn: oid, nameAr: oid);
    final zoneList = zonesByOrg[oid] ?? const <Zone>[];
    sections.add(
      OrgBrowseSection(
        organization: org,
        zones: _buildZoneSections(zoneList: zoneList, orgGroups: orgGroups),
      ),
    );
  }
  return sections;
}

List<ZoneBrowseSection> _buildZoneSections({
  required List<Zone> zoneList,
  required List<CampusChecklistGroup> orgGroups,
}) {
  final byZone = <String?, List<CampusChecklistGroup>>{};
  for (final g in orgGroups) {
    byZone.putIfAbsent(_groupZoneId(g), () => []).add(g);
  }
  final out = <ZoneBrowseSection>[];
  for (final z in zoneList) {
    final gz = byZone.remove(z.id);
    if (gz == null || gz.isEmpty) continue;
    gz.sort((a, b) => a.titleFor('en').compareTo(b.titleFor('en')));
    out.add(ZoneBrowseSection(zone: z, groups: gz));
  }
  // Remaining (null or unknown zone ids)
  for (final entry in byZone.entries) {
    if (entry.value.isEmpty) continue;
    entry.value.sort((a, b) => a.titleFor('en').compareTo(b.titleFor('en')));
    out.add(ZoneBrowseSection(zone: null, groups: entry.value));
  }
  return out;
}
