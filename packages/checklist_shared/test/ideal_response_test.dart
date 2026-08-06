import 'package:checklist_shared/src/data/checklist_lists.dart';
import 'package:checklist_shared/src/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog ideals map to the correct Yes/No column', () {
    final cases = <(String, int, String)>[
      ('B2_DC', 1, 'Y'),
      ('B2_DC', 3, 'N'),
      ('B2_DC', 12, 'N'),
      ('DEFAULT', 14, 'N'),
      ('DEFAULT', 1, 'Y'),
      ('B4', 14, 'N'),
      ('B7_BMS', 14, 'Y'),
      ('B7_MECH', 1, 'Y'),
    ];

    for (final (type, id, expected) in cases) {
      final raw = kChecklistLists[type]!.firstWhere((e) => e['id'] == id);
      expect(raw['default'], expected, reason: '$type#$id');
      final response = ChecklistResponse.fromDb('${raw['default']}');
      expect(response?.shortCode, expected);
    }
  });
}
