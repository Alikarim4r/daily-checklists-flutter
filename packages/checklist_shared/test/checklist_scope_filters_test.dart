import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistSite bathroom({
  required String id,
  required String name,
  required String category,
  required String floor,
  required String code,
  required String organization,
  String? parent,
}) => ChecklistSite(
  id: id,
  organizationId: organization,
  parentSiteId: parent,
  nameEn: name,
  nameAr: name,
  buildingCode: code,
  checklistType: 'DEFAULT',
  checklistCategory: category,
  floorScope: floor,
);

void main() {
  final a1 = bathroom(
    id: 'A1',
    name: 'Building 1 - LGF - Room 13',
    category: 'facilities',
    floor: 'floor_number:-1',
    code: 'B1-WC-LGF-13-FM',
    organization: 'org1',
    parent: 'hq1',
  );
  final a2 = bathroom(
    id: 'A2',
    name: 'Building 1 - LGF - Room 13',
    category: 'hygiene',
    floor: 'floor_number:-1',
    code: 'B1-WC-LGF-13-CL',
    organization: 'org1',
    parent: 'hq1',
  );
  final b1 = bathroom(
    id: 'B1',
    name: 'Building 2 - GF - Room 09',
    category: 'hygiene',
    floor: 'ground',
    code: 'B2-WC-GF-09-CL',
    organization: 'org2',
    parent: 'hq2',
  );
  final orgs = [
    Organization(
      id: 'org1',
      nameEn: 'First Ministry',
      nameAr: 'الوزارة الأولى',
    ),
    Organization(
      id: 'org2',
      nameEn: 'Second Ministry',
      nameAr: 'الوزارة الثانية',
    ),
  ];
  final scope = ChecklistScopeFilters.fromCatalog(
    organizations: orgs,
    zones: [],
    sites: [a1, a2, b1],
  );

  test('seven facets are ordered exactly as requested', () {
    expect(ChecklistFacet.values, [
      ChecklistFacet.organization,
      ChecklistFacet.zone,
      ChecklistFacet.site,
      ChecklistFacet.category,
      ChecklistFacet.building,
      ChecklistFacet.floor,
      ChecklistFacet.area,
    ]);
  });
  test('All in each facet means no constraint, including one-item choices', () {
    const all = ChecklistFilterSelection();
    expect(all.isAll, isTrue);
    expect(scope.matchingSiteIds(all), {'A1', 'A2', 'B1'});
    for (final facet in ChecklistFacet.values) {
      expect(all.choose(facet, null).isAll, isTrue);
    }
  });
  test('cascading organization, site, category, building, floor and area', () {
    var selected = const ChecklistFilterSelection()
        .choose(ChecklistFacet.organization, 'org1')
        .choose(ChecklistFacet.site, 'hq1')
        .choose(ChecklistFacet.category, 'facilities')
        .choose(ChecklistFacet.building, 'B1')
        .choose(ChecklistFacet.floor, 'LGF')
        .choose(ChecklistFacet.area, 'Room 13');
    expect(scope.matchingSiteIds(selected), {'A1'});
    expect(
      scope.optionsFor(ChecklistFacet.area, selected).single.value,
      'Room 13',
    );
    selected = selected.choose(ChecklistFacet.category, null);
    expect(selected.area, isNull);
    expect(selected.floor, isNull);
    expect(scope.matchingSiteIds(selected), {'A1', 'A2'});
    selected = selected.choose(ChecklistFacet.organization, null);
    expect(selected.isAll, isTrue);
    expect(
      scope.optionsFor(ChecklistFacet.building, selected).map((o) => o.value),
      containsAll(['B1', 'B2']),
    );
  });
  test('selector shows only the authorized provided site rows', () {
    final restricted = ChecklistScopeFilters.fromCatalog(
      organizations: orgs,
      zones: [],
      sites: [a1],
    );
    expect(
      restricted
          .optionsFor(
            ChecklistFacet.organization,
            const ChecklistFilterSelection(),
          )
          .single
          .value,
      'org1',
    );
    expect(restricted.matchingSiteIds(const ChecklistFilterSelection()), {
      'A1',
    });
    expect(
      restricted
          .optionsFor(ChecklistFacet.area, const ChecklistFilterSelection())
          .single
          .value,
      'Room 13',
    );
  });
  testWidgets('toolbar keeps all seven dropdowns on 320px viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChecklistScopeFilterBar(
            scope: scope,
            selection: const ChecklistFilterSelection(),
            onChanged: (_) {},
            language: 'en',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('scope-organization-null')),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(-2500, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scope-area-null')), findsOneWidget);
  });
}
