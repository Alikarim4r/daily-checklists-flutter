import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report header keeps site PIN as fallback for earlier inspections', () {
    final inspection = Inspection.fromJson({
      'id': '00000000-0000-4000-8000-000000000001',
      'site_id': '00000000-0000-4000-8000-000000000002',
      'building_code': 'B1',
      'location_label': 'Headquarters',
      'inspection_date': '2026-10-10',
      'sites': {'pin': '0042'},
    });
    expect(inspection.pin, '0042');
    expect(inspection.pinOverride, isNull);
    expect(inspection.bldgNo, '1');
  });

  test('saved header override wins over site PIN after reload', () {
    final inspection = Inspection.fromJson({
      'id': '00000000-0000-4000-8000-000000000003',
      'site_id': '00000000-0000-4000-8000-000000000004',
      'building_code': '07',
      'location_label': 'West Bay, GF',
      'pin_override': '0008',
      'inspection_date': '2026-10-10',
      'sites': {'pin': '0042'},
    });
    expect(inspection.pin, '0008');
    expect(inspection.pinOverride, '0008');
    expect(inspection.bldgNo, '07');
    expect(inspection.locationLabel, 'West Bay, GF');
  });

  test('empty PIN override intentionally replaces the site PIN', () {
    final inspection = Inspection.fromJson({
      'id': '00000000-0000-4000-8000-000000000005',
      'site_id': '00000000-0000-4000-8000-000000000006',
      'building_code': 'B5',
      'pin_override': '',
      'inspection_date': '2026-10-10',
      'sites': {'pin': '0012'},
    });
    expect(inspection.pin, '');
  });
}
