import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LocationScopeLeaf _leaf() => const LocationScopeLeaf(
  organizationId: 'org',
  organizationNameEn: 'Organization',
  siteId: 'site',
  siteNameEn: 'HQ',
  buildingId: 'building',
  buildingCode: 'B1',
  buildingNameEn: 'Building 1',
  floorId: 'floor',
  floorCode: 'GF',
  floorNameEn: 'Ground Floor',
  areaId: 'area',
  areaCode: 'A1',
  areaNameEn: 'Washroom',
  assignmentId: 'assignment',
  checklistNameEn: 'Washroom Checklist',
  serviceTypeCode: 'cleaning',
  serviceTypeNameEn: 'Cleaning',
  serviceTypeNameAr: 'النظافة',
  legacySiteId: 'legacy-site',
);

void main() {
  testWidgets('collapsed filters keep the date bar visible', (tester) async {
    var expanded = true;
    const selection = LocationFilterSelection();
    final scope = LocationFilterScope([_leaf()]);

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ChecklistLocationFilterPanel(
              scope: scope,
              selection: selection,
              onSelectionChanged: (_) {},
              date: DateTime(2026, 10, 6),
              onPreviousDate: () {},
              onNextDate: null,
              onPickDate: () {},
              expanded: expanded,
              onExpandedChanged: (value) => setState(() => expanded = value),
              language: 'en',
            ),
          ),
        ),
      ),
    );

    expect(find.text('2026-10-06'), findsOneWidget);
    expect(find.text('Checklist type'), findsOneWidget);
    // Unified CheckView / CheckAdmin both render authorized singleton filters.
    expect(find.text('Organization'), findsWidgets);

    await tester.drag(find.text('Filters'), const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(find.text('2026-10-06'), findsOneWidget);
    expect(find.text('Checklist type'), findsNothing);
  });

  testWidgets(
    'multiple A4 sheets share one parent scroll without layout errors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: const [
                A4PaperSheet(
                  scrollable: false,
                  child: SizedBox(height: 240, child: Text('Paper one')),
                ),
                A4PaperSheet(
                  scrollable: false,
                  child: SizedBox(height: 240, child: Text('Paper two')),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Paper one'), findsOneWidget);
      expect(find.text('Paper two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
