import '../models/location_hierarchy.dart';
import '../utils/site_hierarchy.dart';

/// Preserves the established read-grant based location selectors for legacy
/// checklist units that have not been mapped to new facility assignments.
/// Never imports unscoped/other tenant sites: input sections MUST come from
/// listAccessibleCampusGroups, not listAllSites.
LocationFilterScope combineAuthorizedLegacyChecklistScope({
  required LocationFilterScope mapped,
  required List<OrgBrowseSection> authorizedSections,
}) {
  final alreadyMapped = <String>{
    for (final leaf in mapped.leaves)
      if (leaf.legacySiteId != null) leaf.legacySiteId!,
  };
  final merged = <LocationScopeLeaf>[...mapped.leaves];
  for (final org in authorizedSections) {
    for (final zone in org.zones) {
      for (final campus in zone.groups) {
        for (final unit in campus.checklists) {
          if (!unit.isActive ||
              !unit.isChecklistUnit ||
              !alreadyMapped.add(unit.id)) {
            continue;
          }
          final parent = campus.campus;
          final logicalSiteId = parent?.id ?? unit.id;
          final buildingCode = unit.buildingCode.trim();
          final floorCode = unit.reportFloor;
          merged.add(
            LocationScopeLeaf(
              organizationId: unit.organizationId,
              organizationNameEn: org.organization.nameEn,
              organizationNameAr: org.organization.nameAr,
              zoneId: zone.zone?.id,
              zoneNameEn: zone.zone?.nameEn,
              zoneNameAr: zone.zone?.nameAr,
              siteId: logicalSiteId,
              siteNameEn: parent?.nameEn ?? unit.location,
              siteNameAr: parent?.nameAr ?? unit.location,
              buildingId:
                  'legacy-building:${unit.organizationId}:$logicalSiteId:$buildingCode',
              buildingCode: buildingCode,
              buildingNameEn: buildingCode,
              buildingNameAr: buildingCode,
              floorId:
                  'legacy-floor:${unit.organizationId}:$logicalSiteId:$buildingCode:$floorCode',
              floorCode: floorCode,
              floorNameEn: floorCode,
              floorNameAr: floorCode,
              areaId: 'legacy-area:${unit.id}',
              areaCode: unit.nameEn,
              areaNameEn: unit.nameEn,
              areaNameAr: unit.nameAr,
              assignmentId: 'legacy-authorized:${unit.id}',
              checklistNameEn: unit.nameEn,
              checklistNameAr: unit.nameAr,
              serviceTypeCode: unit.checklistType,
              serviceTypeNameEn: unit.checklistCategory,
              serviceTypeNameAr: unit.checklistCategory,
              legacySiteId: unit.id,
            ),
          );
        }
      }
    }
  }
  return LocationFilterScope(merged);
}
