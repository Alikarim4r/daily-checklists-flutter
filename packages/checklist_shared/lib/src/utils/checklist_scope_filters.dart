import '../models/location_hierarchy.dart';
import '../models/organization.dart';
import '../models/profile.dart';
import 'checklist_categories.dart';
import 'site_hierarchy.dart';

/// Single-choice, cascading filters. Null means *all accessible values*.
/// Order is fixed: organization, zone, site, category, building, floor, area.
enum ChecklistFacet {
  organization,
  zone,
  site,
  category,
  building,
  floor,
  area,
}

class ChecklistFacetOption {
  const ChecklistFacetOption(this.value, this.nameEn, this.nameAr);
  final String value;
  final String nameEn;
  final String nameAr;
  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;
}

class ChecklistFilterSelection {
  const ChecklistFilterSelection({
    this.organization,
    this.zone,
    this.site,
    this.category,
    this.building,
    this.floor,
    this.area,
  });
  final String? organization, zone, site, category, building, floor, area;
  bool get isAll => ChecklistFacet.values.every((f) => valueFor(f) == null);
  String? valueFor(ChecklistFacet facet) => switch (facet) {
    ChecklistFacet.organization => organization,
    ChecklistFacet.zone => zone,
    ChecklistFacet.site => site,
    ChecklistFacet.category => category,
    ChecklistFacet.building => building,
    ChecklistFacet.floor => floor,
    ChecklistFacet.area => area,
  };
  ChecklistFilterSelection choose(ChecklistFacet facet, String? value) {
    final values = [for (final f in ChecklistFacet.values) valueFor(f)];
    final index = ChecklistFacet.values.indexOf(facet);
    values[index] = value;
    for (var i = index + 1; i < values.length; i++) {
      values[i] = null;
    }
    return ChecklistFilterSelection(
      organization: values[0],
      zone: values[1],
      site: values[2],
      category: values[3],
      building: values[4],
      floor: values[5],
      area: values[6],
    );
  }
}

class ChecklistFilterRow {
  const ChecklistFilterRow({required this.unit, required this.options});
  final ChecklistSite unit;
  final Map<ChecklistFacet, ChecklistFacetOption> options;
  String? valueFor(ChecklistFacet facet) => options[facet]?.value;
}

class ChecklistScopeFilters {
  const ChecklistScopeFilters(this.rows);
  final List<ChecklistFilterRow> rows;

  factory ChecklistScopeFilters.fromSections(
    List<OrgBrowseSection> sections, {
    List<LocationScopeLeaf> locationLeaves = const [],
  }) {
    final leafByUnit = {
      for (final leaf in locationLeaves)
        if (leaf.legacySiteId != null) leaf.legacySiteId!: leaf,
    };
    return ChecklistScopeFilters([
      for (final org in sections)
        for (final zone in org.zones)
          for (final campus in zone.groups)
            for (final unit in campus.checklists)
              if (unit.isActive && unit.isChecklistUnit)
                _buildRow(
                  unit,
                  org.organization,
                  zone.zone,
                  campus.campus,
                  leafByUnit[unit.id],
                ),
    ]);
  }

  factory ChecklistScopeFilters.fromCatalog({
    required List<Organization> organizations,
    required List<Zone> zones,
    required List<ChecklistSite> sites,
    List<LocationScopeLeaf> locationLeaves = const [],
  }) {
    final leafByUnit = {
      for (final leaf in locationLeaves)
        if (leaf.legacySiteId != null) leaf.legacySiteId!: leaf,
    };
    final orgMap = {for (final org in organizations) org.id: org};
    final zoneMap = {for (final zone in zones) zone.id: zone};
    final byId = {for (final site in sites) site.id: site};
    return ChecklistScopeFilters([
      for (final unit in sites)
        if (unit.isChecklistUnit)
          _buildRow(
            unit,
            orgMap[unit.organizationId],
            zoneMap[unit.zoneId ?? byId[unit.parentSiteId]?.zoneId],
            byId[unit.parentSiteId],
            leafByUnit[unit.id],
          ),
    ]);
  }

  static ChecklistFilterRow _buildRow(
    ChecklistSite unit,
    Organization? org,
    Zone? zone,
    ChecklistSite? campus,
    LocationScopeLeaf? leaf,
  ) {
    final buildingMatch = RegExp(
      r'^B([0-9]+)',
      caseSensitive: false,
    ).firstMatch(unit.buildingCode.trim());
    final numericMatch = RegExp(
      r'^0*([0-9]{1,2})$',
    ).firstMatch(unit.buildingCode.trim());
    final building = buildingMatch != null
        ? 'B${int.parse(buildingMatch.group(1)!)}'
        : numericMatch != null
        ? 'B${int.parse(numericMatch.group(1)!)}'
        : null;
    final floor = switch (unit.floorScope) {
      'floor_number:-1' => 'LGF',
      'ground' => 'GF',
      'first' => 'FF',
      'basement' => 'B',
      'parking' => 'P',
      'roof' => 'ROOF',
      _ => null,
    };
    // Existing room identifiers are valid areas for legacy checklist units.
    // Units without area information keep the Area filter on All; never guess.
    final room = RegExp(
      r'\bRoom\s+([0-9]+[A-Za-z]?)\b',
      caseSensitive: false,
    ).firstMatch(unit.nameEn);
    final area = room == null ? null : 'Room ${room.group(1)!.toUpperCase()}';
    final category = ChecklistCategories.normalize(unit.checklistCategory);
    // Canonical facility mappings take precedence when assigned.
    final mappedBuilding = leaf?.buildingCode.trim();
    final mappedFloor = leaf?.floorCode.trim();
    final mappedArea = leaf?.areaCode.trim();
    return ChecklistFilterRow(
      unit: unit,
      options: {
        ChecklistFacet.organization: ChecklistFacetOption(
          unit.organizationId,
          org?.nameEn ?? unit.organizationId,
          org?.nameAr ?? org?.nameEn ?? unit.organizationId,
        ),
        if (zone != null)
          ChecklistFacet.zone: ChecklistFacetOption(
            zone.id,
            zone.nameEn,
            zone.nameAr ?? zone.nameEn,
          ),
        ChecklistFacet.site: ChecklistFacetOption(
          campus?.id ?? unit.parentSiteId ?? unit.id,
          campus?.nameEn ?? unit.nameEn,
          campus?.nameAr ?? unit.nameAr,
        ),
        ChecklistFacet.category: ChecklistFacetOption(
          category,
          ChecklistCategories.title(category, 'en'),
          ChecklistCategories.title(category, 'ar'),
        ),
        if (mappedBuilding != null && mappedBuilding.isNotEmpty)
          ChecklistFacet.building: ChecklistFacetOption(
            mappedBuilding,
            leaf!.buildingNameEn,
            leaf.buildingNameAr ?? leaf.buildingNameEn,
          )
        else if (building != null)
          ChecklistFacet.building: ChecklistFacetOption(
            building,
            building,
            building,
          ),
        if (mappedFloor != null && mappedFloor.isNotEmpty)
          ChecklistFacet.floor: ChecklistFacetOption(
            mappedFloor,
            leaf!.floorNameEn,
            leaf.floorNameAr ?? leaf.floorNameEn,
          )
        else if (floor != null)
          ChecklistFacet.floor: ChecklistFacetOption(floor, floor, floor),
        if (mappedArea != null && mappedArea.isNotEmpty)
          ChecklistFacet.area: ChecklistFacetOption(
            mappedArea,
            leaf!.areaNameEn,
            leaf.areaNameAr ?? leaf.areaNameEn,
          )
        else if (area != null)
          ChecklistFacet.area: ChecklistFacetOption(area, area, area),
      },
    );
  }

  bool matches(ChecklistFilterRow row, ChecklistFilterSelection selection) {
    for (final facet in ChecklistFacet.values) {
      final selected = selection.valueFor(facet);
      if (selected != null && row.valueFor(facet) != selected) return false;
    }
    return true;
  }

  List<ChecklistFacetOption> optionsFor(
    ChecklistFacet facet,
    ChecklistFilterSelection selection,
  ) {
    final index = ChecklistFacet.values.indexOf(facet);
    final options = <String, ChecklistFacetOption>{};
    for (final row in rows) {
      var matchesEarlier = true;
      for (var i = 0; i < index; i++) {
        final before = ChecklistFacet.values[i];
        final value = selection.valueFor(before);
        if (value != null && row.valueFor(before) != value) {
          matchesEarlier = false;
          break;
        }
      }
      if (!matchesEarlier) continue;
      final option = row.options[facet];
      if (option != null) options[option.value] = option;
    }
    return options.values.toList()
      ..sort((a, b) => a.nameEn.compareTo(b.nameEn));
  }

  Set<String> matchingSiteIds(ChecklistFilterSelection selection) => {
    for (final row in rows)
      if (matches(row, selection)) row.unit.id,
  };

  List<OrgBrowseSection> filteredSections(
    List<OrgBrowseSection> sections,
    ChecklistFilterSelection selection,
  ) {
    if (selection.isAll) return sections;
    final allowed = matchingSiteIds(selection);
    return [
      for (final org in sections)
        if (org.zones.any(
          (z) => z.groups.any(
            (g) => g.checklists.any((s) => allowed.contains(s.id)),
          ),
        ))
          OrgBrowseSection(
            organization: org.organization,
            zones: [
              for (final zone in org.zones)
                if (zone.groups.any(
                  (g) => g.checklists.any((s) => allowed.contains(s.id)),
                ))
                  ZoneBrowseSection(
                    zone: zone.zone,
                    groups: [
                      for (final group in zone.groups)
                        if (group.checklists.any((s) => allowed.contains(s.id)))
                          CampusChecklistGroup(
                            campus: group.campus,
                            checklists: [
                              for (final site in group.checklists)
                                if (allowed.contains(site.id)) site,
                            ],
                          ),
                    ],
                  ),
            ],
          ),
    ];
  }
}
