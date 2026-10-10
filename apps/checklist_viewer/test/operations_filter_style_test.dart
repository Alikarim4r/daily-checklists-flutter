import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Operations-styled drop-down expands below and selects specific or All',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: OperationsStyleDropdown<String>(
                  label: 'Buildings',
                  valueLabel: 'All',
                  choices: const [
                    OperationsFilterChoice(value: '', label: 'All'),
                    OperationsFilterChoice(value: 'B1', label: 'Building 1'),
                    OperationsFilterChoice(value: 'B2', label: 'Building 2'),
                  ],
                  onSelected: (s) => chosen = s,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buildings'));
      await tester.pumpAndSettle();
      expect(find.text('Building 1'), findsOneWidget);
      await tester.tap(find.text('Building 1'));
      await tester.pumpAndSettle();
      expect(chosen, 'B1');
      await tester.tap(find.text('Buildings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();
      expect(chosen, '');
    },
  );
  testWidgets('The hidden reset icon is not built in the viewer filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChecklistScopeFilterBar(
            scope: const ChecklistScopeFilters([]),
            selection: const ChecklistFilterSelection(),
            language: 'en',
            onChanged: (_) {},
            operationsStyle: true,
            showResetButton: false,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.filter_alt_off_outlined), findsNothing);
  });
}
