import 'package:checklist_shared/checklist_shared.dart';
import 'package:checklist_viewer/design/checkview_filter_panel.dart';
import 'package:checklist_viewer/design/checkview_location_match.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LocationScopeLeaf leaf(String id, String area, {String type = 'cleaning'}) =>
    LocationScopeLeaf(
      organizationId: 'org',
      organizationNameEn: 'Ministry',
      zoneId: 'z',
      zoneNameEn: 'West Bay',
      siteId: 'hq',
      siteNameEn: 'HQ',
      buildingId: 'b',
      buildingCode: 'B1',
      buildingNameEn: 'Building One',
      floorId: 'f',
      floorCode: 'GF',
      floorNameEn: 'Ground Floor',
      areaId: id,
      areaCode: id,
      areaNameEn: area,
      assignmentId: 'check-$id',
      checklistNameEn: 'Hygiene $area',
      serviceTypeCode: type,
      serviceTypeNameEn: type == 'cleaning' ? 'Cleaning' : 'Maintenance',
      serviceTypeNameAr: 'نظافة',
      legacySiteId: 'legacy',
    );

final testScope = LocationFilterScope([
  leaf('a1', 'Washrooms'),
  leaf('a2', 'Corridors'),
]);

Inspection inspection({String? areaId, String siteId = 'legacy'}) => Inspection(
  id: 'insp',
  siteId: siteId,
  buildingCode: 'B1',
  inspectionDate: DateTime(2026, 10, 13),
  organizationId: 'org',
  buildingId: 'b',
  floorId: 'f',
  areaId: areaId,
);

void main() {
  group('authorized location filtering', () {
    test('precise area filtering excludes sibling areas', () {
      const areaA = LocationFilterSelection(areaId: 'a1');
      expect(
        cvMatchesAuthorizedLocation(
          inspection: inspection(areaId: 'a1'),
          scope: testScope,
          selection: areaA,
        ),
        isTrue,
      );
      expect(
        cvMatchesAuthorizedLocation(
          inspection: inspection(areaId: 'a2'),
          scope: testScope,
          selection: areaA,
        ),
        isFalse,
      );
    });

    test('old inspections do not get misassigned to an arbitrary area', () {
      expect(
        cvMatchesAuthorizedLocation(
          inspection: inspection(),
          scope: testScope,
          selection: const LocationFilterSelection(areaId: 'a1'),
        ),
        isFalse,
      );
      expect(
        cvMatchesAuthorizedLocation(
          inspection: inspection(),
          scope: testScope,
          selection: const LocationFilterSelection(),
        ),
        isTrue,
      );
    });

    test('records outside authorization are always excluded', () {
      expect(
        cvMatchesAuthorizedLocation(
          inspection: inspection(siteId: 'unauthorized'),
          scope: testScope,
          selection: const LocationFilterSelection(),
        ),
        isFalse,
      );
    });
  });

  testWidgets(
    'singleton permission facets disappear and one filter fills desktop',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1160, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CvLocationFilterPanel(
              scope: testScope,
              selection: const LocationFilterSelection(),
              onSelectionChanged: (_) {},
              date: DateTime(2026, 10, 13),
              onPreviousDate: () {},
              onNextDate: () {},
              onPickDate: () {},
              expanded: true,
              onExpandedChanged: (_) {},
              language: 'en',
              search: '',
              onSearchChanged: (_) {},
              onReset: () {},
              resultsCount: 14,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Historic CheckView contract: only authorized dimensions containing
      // useful choices occupy room; empty/singleton controls never show.
      for (final label in [
        'Organization (1)',
        'Zone (1)',
        'Site (1)',
        'Building (1)',
        'Floor (1)',
        'Checklist type (1)',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text('Area (2)'), findsOneWidget);
      final areaWidth = tester
          .getSize(find.byKey(const ValueKey(LocationFilterDimension.area)))
          .width;
      // The sole available filter stretches across the desktop browser, not
      // 25% of a fixed grid with an unused margin.
      expect(areaWidth, greaterThan(1000));
      expect(find.textContaining('1 filters'), findsOneWidget);
      expect(find.textContaining('14 records'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('two permitted dropdowns divide the full desktop width evenly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scope = LocationFilterScope([
      leaf('a1', 'Washrooms'),
      leaf('a2', 'Corridors', type: 'maintenance'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CvLocationFilterPanel(
            scope: scope,
            selection: const LocationFilterSelection(),
            onSelectionChanged: (_) {},
            date: DateTime(2026, 10, 13),
            onPreviousDate: () {},
            onNextDate: () {},
            onPickDate: () {},
            expanded: true,
            onExpandedChanged: (_) {},
            language: 'en',
            search: '',
            onSearchChanged: (_) {},
            onReset: () {},
            resultsCount: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final area = tester.getSize(
      find.byKey(const ValueKey(LocationFilterDimension.area)),
    );
    final type = tester.getSize(
      find.byKey(const ValueKey(LocationFilterDimension.checklistType)),
    );
    expect(find.text('Area (2)'), findsOneWidget);
    expect(find.text('Checklist type (2)'), findsOneWidget);
    expect((area.width - type.width).abs(), lessThan(2));
    expect(area.width, greaterThan(560));
    expect(area.width + type.width, greaterThan(1200));
    expect(find.text('Organization (1)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic RTL compact panel expands without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool expanded = false;
    Widget app() => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              CvLocationFilterPanel(
                scope: testScope,
                selection: const LocationFilterSelection(),
                onSelectionChanged: (_) {},
                date: DateTime(2026, 10, 13),
                onPreviousDate: () {},
                onNextDate: () {},
                onPickDate: () {},
                expanded: expanded,
                onExpandedChanged: (value) => expanded = value,
                language: 'ar',
                search: '',
                onSearchChanged: (_) {},
                onReset: () {},
                resultsCount: 5,
              ),
              const Expanded(child: Placeholder()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    expect(find.textContaining('البحث والفلاتر'), findsOneWidget);
    await tester.tap(find.textContaining('البحث والفلاتر'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(expanded, isTrue);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('المساحة'), findsWidgets);
  });
}
