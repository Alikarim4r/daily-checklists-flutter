import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

Inspection washroom({
  required String type,
  required String code,
  String name = 'Building 1 - LGF - Female Toilet/Ablution - Room 0013',
  String? snapshot,
}) => Inspection(
  id: 'preview-test',
  siteId: 'wc-1',
  buildingCode: code,
  inspectionDate: DateTime(2026, 10, 10),
  siteNameEn: name,
  siteChecklistType: type,
  templateCodeSnapshot: snapshot,
);

void main() {
  test('104 facilities washroom cards use ONLY exact maintenance headline', () {
    final inspection = washroom(
      type: 'LIB_WASHROOM_HYGIENE_SAFETY_A0000000_V3',
      code: '1',
    );
    expect(
      washroomPaperSecondLine(inspection),
      'Facilities Daily Checklists - Toilet Maintenance',
    );
    expect(washroomPaperSecondLine(inspection), isNot(contains('Building')));
    expect(washroomPaperSecondLine(inspection), isNot(contains('LGF')));
    expect(washroomPaperSecondLine(inspection), isNot(contains('0013')));
  });
  test('104 cleaning washroom cards use ONLY exact cleaning headline', () {
    final inspection = washroom(type: 'MOEHE_WC_CLEANING_V1', code: '1');
    expect(
      washroomPaperSecondLine(inspection),
      'Facilities Daily Checklists - Toilet Cleaning',
    );
  });
  test('persisted inspection without template code still uses site code', () {
    final cleaning = washroom(type: '', code: 'B2-WC-FF-04A-CL');
    final maintenance = washroom(type: '', code: 'B2-WC-FF-04A-FM');
    expect(
      washroomPaperSecondLine(cleaning),
      'Facilities Daily Checklists - Toilet Cleaning',
    );
    expect(
      washroomPaperSecondLine(maintenance),
      'Facilities Daily Checklists - Toilet Maintenance',
    );
  });
  test('template snapshot works for legacy inspection', () {
    final legacy = washroom(
      type: '',
      code: '1',
      snapshot: 'LIB_WASHROOM_HYGIENE_SAFETY_A0000000_V3',
    );
    expect(
      washroomPaperSecondLine(legacy),
      'Facilities Daily Checklists - Toilet Maintenance',
    );
  });
  test('all unrelated checklists retain their original title', () {
    final pump = washroom(
      type: 'DEFAULT',
      code: 'B1-CHWP-02',
      name: 'Building 1 - Chilled Water Pumps',
    );
    final unrelated = washroom(
      type: 'MOEHE_WC_CLEANING_V1',
      code: 'B1-CLEAN',
      name: 'Building 1 - Pantry',
    );
    expect(washroomPaperSecondLine(pump), isNull);
    expect(washroomPaperSecondLine(unrelated), isNull);
  });
}
