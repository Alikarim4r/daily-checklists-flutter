import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildDailyRecordId', () {
    expect(buildDailyRecordId('B1', '2026-07-28'), 'B1__2026-07-28');
  });

  test('buildings loaded', () {
    expect(BuildingConfig.all.length, 10);
    expect(BuildingConfig.byId('B1')?.type, 'DEFAULT');
  });

  test('checklist lists loaded', () {
    expect(ChecklistItem.forBuilding('B1').length, 18);
    expect(ChecklistItem.forBuilding('B2-DC').length, 12);
    expect(ChecklistItem.forBuilding('B7-BMS').length, 36);
  });
}
