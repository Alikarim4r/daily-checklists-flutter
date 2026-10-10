import 'package:checklist_shared/checklist_shared.dart';
import 'package:checklist_viewer/models/stacked_checklist_filtering.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistSite unit(String id, String category, String room, String building) =>
    ChecklistSite(
      id: id,
      organizationId: 'ministry',
      parentSiteId: 'hq',
      nameEn: 'Building $building - LGF - Room $room',
      nameAr: 'المبنى $building - LGF - غرفة $room',
      buildingCode: 'B$building-WC-LGF-$room-FM',
      checklistCategory: category,
      floorScope: 'floor_number:-1',
    );

Inspection record(
  ChecklistSite site, {
  bool oneAnswer = false,
  bool allAnswers = false,
  bool submitted = false,
}) => Inspection(
  id: 'record-${site.id}',
  siteId: site.id,
  buildingCode: site.buildingCode,
  inspectionDate: DateTime(2026, 10, 10),
  status: submitted ? InspectionStatus.submitted : InspectionStatus.draft,
  reviewStatus: submitted ? ReviewStatus.submitted : ReviewStatus.draft,
  items: [
    InspectionItem(
      itemIndex: 1,
      description: 'Clean? ',
      response: oneAnswer || allAnswers ? ChecklistResponse.yes : null,
    ),
    InspectionItem(
      itemIndex: 2,
      description: 'Safe?',
      response: allAnswers ? ChecklistResponse.yes : null,
    ),
  ],
);

void main() {
  final a = unit('f1', 'facilities', '13', '1');
  final b = unit('h1', 'hygiene', '13', '1');
  final c = unit('f2', 'facilities', '09', '2');
  final org = Organization(
    id: 'ministry',
    nameEn: 'MOEHE HQ',
    nameAr: 'الوزارة',
  );
  final campus = ChecklistSite(
    id: 'hq',
    organizationId: 'ministry',
    nameEn: 'HQ',
    nameAr: 'المقر',
    buildingCode: '',
  );
  final scope = ChecklistScopeFilters.fromCatalog(
    organizations: [org],
    zones: [],
    sites: [campus, a, b, c],
  );
  final completed = record(a, allAnswers: true);
  final partial = record(b, oneAnswer: true);
  test('All shows every accessible checklist, even when never filled', () {
    final selected = StackedChecklistFiltering.select(
      scope: scope,
      selection: const ChecklistFilterSelection(),
      fill: ChecklistFillFilter.all,
      records: [completed, partial],
    );
    expect(selected.map((r) => r.unit.id).toSet(), {'f1', 'h1', 'f2'});
  });
  test('Filled selects completed, not partially answered', () {
    final selected = StackedChecklistFiltering.select(
      scope: scope,
      selection: const ChecklistFilterSelection(),
      fill: ChecklistFillFilter.filled,
      records: [completed, partial],
    );
    expect(selected.map((r) => r.unit.id).toList(), ['f1']);
    expect(StackedChecklistFiltering.isFilled(partial), isFalse);
  });
  test('Unfilled includes incomplete draft and untouched site', () {
    final selected = StackedChecklistFiltering.select(
      scope: scope,
      selection: const ChecklistFilterSelection(),
      fill: ChecklistFillFilter.unfilled,
      records: [completed, partial],
    );
    expect(selected.map((r) => r.unit.id).toSet(), {'h1', 'f2'});
  });
  test('Building, category, floor and area filter actual displayed papers', () {
    final selected = const ChecklistFilterSelection()
        .choose(ChecklistFacet.organization, 'ministry')
        .choose(ChecklistFacet.site, 'hq')
        .choose(ChecklistFacet.category, 'facilities')
        .choose(ChecklistFacet.building, 'B1')
        .choose(ChecklistFacet.floor, 'LGF')
        .choose(ChecklistFacet.area, 'Room 13');
    final result = StackedChecklistFiltering.select(
      scope: scope,
      selection: selected,
      fill: ChecklistFillFilter.all,
      records: [],
    );
    expect(result.map((r) => r.unit.id).toList(), ['f1']);
    final allCategories = selected.choose(ChecklistFacet.category, null);
    expect(
      StackedChecklistFiltering.select(
        scope: scope,
        selection: allCategories,
        fill: ChecklistFillFilter.all,
        records: [],
      ).map((r) => r.unit.id).toSet(),
      {'f1', 'h1', 'f2'},
    );
  });
  test(
    'Database submitted status counts filled even when old item answers incomplete',
    () {
      expect(
        StackedChecklistFiltering.isFilled(record(c, submitted: true)),
        isTrue,
      );
    },
  );
}
