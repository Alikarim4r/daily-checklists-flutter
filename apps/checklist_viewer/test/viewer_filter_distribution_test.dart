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
  test('Filters without alternatives are hidden but completion stays', () {
    final visible = ViewerFilterDistribution.visibleFacets(
      scope,
      const ChecklistFilterSelection(),
    );
    expect(visible, [ChecklistFacet.category, ChecklistFacet.floor]);
  });
  test('Chosen facet remains visible to allow selecting All', () {
    final chosen = const ChecklistFilterSelection().choose(
      ChecklistFacet.organization,
      'company',
    );
    expect(
      ViewerFilterDistribution.visibleFacets(scope, chosen),
      contains(ChecklistFacet.organization),
    );
  });
  test('Fewer permission filters divide viewport equally and grow', () {
    final many = ViewerFilterDistribution.fieldWidth(1280, 8);
    final few = ViewerFilterDistribution.fieldWidth(1280, 3);
    expect(many, greaterThan(142));
    expect(few, greaterThan(many));
    // 3 fields include the completion filter; no separate far-right gap.
    expect(few * 3 + 16 + 16, 1280);
    expect(ViewerFilterDistribution.fieldWidth(320, 2), 148);
    expect(ViewerFilterDistribution.fieldWidth(320, 6), 142);
  });
}
