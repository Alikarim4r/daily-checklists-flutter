import 'package:checklist_shared/checklist_shared.dart';
import 'package:checklist_viewer/models/viewer_filter_distribution.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistFilterRow row(String id, String org, String category, String floor) =>
    ChecklistFilterRow(
      unit: ChecklistSite(
        id: id,
        organizationId: org,
        nameEn: id,
        nameAr: id,
        buildingCode: 'B1-WC-$floor-$id-CL',
        checklistCategory: category,
        floorScope: 'ground',
      ),
      options: {
        ChecklistFacet.organization: ChecklistFacetOption(org, org, org),
        ChecklistFacet.category: ChecklistFacetOption(
          category,
          category,
          category,
        ),
        ChecklistFacet.floor: ChecklistFacetOption(floor, floor, floor),
      },
    );

void main() {
  final scope = ChecklistScopeFilters([
    row('first', 'company', 'hygiene', 'GF'),
    row('second', 'company', 'facilities', 'GF'),
    row('third', 'company', 'hygiene', 'FF'),
  ]);
  test('Filters with only one authorized option are hidden', () {
    final visible = ViewerFilterDistribution.visibleFacets(
      scope,
      const ChecklistFilterSelection(),
    );
    expect(visible, [ChecklistFacet.category, ChecklistFacet.floor]);
  });
  test('Chosen facet remains visible, so All can be selected again', () {
    final chosen = const ChecklistFilterSelection().choose(
      ChecklistFacet.organization,
      'company',
    );
    expect(
      ViewerFilterDistribution.visibleFacets(scope, chosen),
      contains(ChecklistFacet.organization),
    );
  });
  test('Desktop has one row, and every visible field expands equally', () {
    for (final width in [1000.0, 1280.0, 1440.0, 1920.0]) {
      for (final count in [1, 2, 3, 4, 8]) {
        expect(ViewerFilterDistribution.columnsFor(width, count), count);
        final field = ViewerFilterDistribution.fieldWidth(width, count);
        expect(field * count + 16 + 8 * (count - 1), closeTo(width, 0.00001));
      }
    }
    expect(
      ViewerFilterDistribution.fieldWidth(1440, 3),
      greaterThan(ViewerFilterDistribution.fieldWidth(1440, 8)),
    );
  });
  test(
    'Mobile wraps Completion into visible row, never scrolls it offscreen',
    () {
      expect(ViewerFilterDistribution.columnsFor(320, 8), 2);
      expect(ViewerFilterDistribution.columnsFor(390, 8), 2);
      expect(ViewerFilterDistribution.columnsFor(600, 8), 3);
      expect(ViewerFilterDistribution.columnsFor(980, 8), 6);
      expect(ViewerFilterDistribution.fieldWidth(320, 2), 148);
      expect(ViewerFilterDistribution.fieldWidth(390, 2), 183);
      expect(ViewerFilterDistribution.fieldWidth(320, 1), 304);
    },
  );
}
