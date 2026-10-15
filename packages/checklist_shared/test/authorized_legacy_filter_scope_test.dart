import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

const org = Organization(
  id: 'org-a',
  nameEn: 'Authorized Org',
  nameAr: 'جهة مصرح بها',
);
const other = Organization(
  id: 'org-b',
  nameEn: 'Denied Org',
  nameAr: 'غير مصرح بها',
);

ChecklistSite oldUnit(String id, String orgId) => ChecklistSite(
  id: id,
  organizationId: orgId,
  nameEn: 'Washroom $id',
  nameAr: 'حمام $id',
  buildingCode: 'B1',
  checklistType: 'HYGIENE',
);
LocationScopeLeaf newer() => const LocationScopeLeaf(
  organizationId: 'org-a',
  organizationNameEn: 'Authorized Org',
  siteId: 'site-mapped',
  siteNameEn: 'Headquarters',
  buildingId: 'building-mapped',
  buildingCode: 'B2',
  buildingNameEn: 'Building Two',
  floorId: 'floor-mapped',
  floorCode: 'GF',
  floorNameEn: 'Ground Floor',
  areaId: 'area-mapped',
  areaCode: 'A1',
  areaNameEn: 'Washrooms',
  assignmentId: 'assigned-new',
  checklistNameEn: 'Cleaning',
  serviceTypeCode: 'cleaning',
  serviceTypeNameEn: 'Cleaning',
  serviceTypeNameAr: 'النظافة',
  sectorId: 'facilities',
  serviceClassId: 'soft',
  departmentId: 'cleaning',
  coverageId: 'washrooms',
  documentKindId: 'checklist',
  legacySiteId: 'mapped-unit',
);

void main() {
  final authorized = [
    OrgBrowseSection(
      organization: org,
      zones: [
        ZoneBrowseSection(
          groups: [
            CampusChecklistGroup(
              checklists: [
                oldUnit('legacy-a', 'org-a'),
                oldUnit('mapped-unit', 'org-a'),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
  test(
    'Restore legacy site filters without duplicates for already mapped units',
    () {
      final result = combineAuthorizedLegacyChecklistScope(
        mapped: LocationFilterScope([newer()]),
        authorizedSections: authorized,
      );
      expect(result.leaves.length, 2);
      expect(
        result.leaves.where((x) => x.legacySiteId == 'legacy-a').length,
        1,
      );
      expect(
        result.leaves.where((x) => x.legacySiteId == 'mapped-unit').length,
        1,
      );
      expect(
        result
            .optionsFor(
              LocationFilterDimension.building,
              const LocationFilterSelection(),
            )
            .length,
        2,
      );
      expect(
        result
            .optionsFor(
              LocationFilterDimension.area,
              const LocationFilterSelection(),
            )
            .length,
        2,
      );
    },
  );
  test(
    'Single classified service must not hide unclassified historical lists',
    () {
      final result = combineAuthorizedLegacyChecklistScope(
        mapped: LocationFilterScope([newer()]),
        authorizedSections: authorized,
      );
      final normalized = result.normalize(const LocationFilterSelection());
      expect(normalized.sectorId, isNull);
      expect(normalized.serviceClassId, isNull);
      expect(normalized.departmentId, isNull);
      expect(result.filteredLeaves(normalized).length, 2);
    },
  );
  test('Only explicitly authorized groups provide legacy filter values', () {
    final denied = [
      OrgBrowseSection(
        organization: other,
        zones: [
          ZoneBrowseSection(
            groups: [
              CampusChecklistGroup(
                checklists: [oldUnit('denied-unit', 'org-b')],
              ),
            ],
          ),
        ],
      ),
    ];
    final result = combineAuthorizedLegacyChecklistScope(
      mapped: const LocationFilterScope([]),
      authorizedSections: authorized,
    );
    expect(
      result.leaves.map((e) => e.legacySiteId),
      isNot(contains('denied-unit')),
    );
    expect(result.leaves.map((e) => e.organizationId).toSet(), {'org-a'});
    expect(denied.single.organization.id, 'org-b');
  });
  test(
    'Existing location filters remain available even with no mapped assignments',
    () {
      final result = combineAuthorizedLegacyChecklistScope(
        mapped: const LocationFilterScope([]),
        authorizedSections: authorized,
      );
      expect(result.leaves.length, 2);
      expect(
        result
            .optionsFor(
              LocationFilterDimension.organization,
              const LocationFilterSelection(),
            )
            .single
            .nameEn,
        'Authorized Org',
      );
      expect(
        result
            .optionsFor(
              LocationFilterDimension.checklistType,
              const LocationFilterSelection(),
            )
            .single
            .value,
        'HYGIENE',
      );
    },
  );
}
