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
      ('AWQAF_MEN_PRAYER', 1, 'Y'),
      ('AWQAF_WUDU', 24, 'Y'),
      ('AWQAF_IMAM_HOUSE', 14, 'Y'),
    ];

    for (final (type, id, expected) in cases) {
      final raw = kChecklistLists[type]!.firstWhere((e) => e['id'] == id);
      expect(raw['default'], expected, reason: '$type#$id');
      final response = ChecklistResponse.fromDb('${raw['default']}');
      expect(response?.shortCode, expected);
    }
  });

  test('Awqaf catalog has 24 atomic items in all supported languages', () {
    const languages = ['en', 'ar', 'bn', 'hi', 'ml', 'tl', 'ta'];
    for (final type in const [
      'AWQAF_MEN_PRAYER',
      'AWQAF_WUDU',
      'AWQAF_IMAM_HOUSE',
    ]) {
      final items = kChecklistLists[type];
      expect(items, isNotNull, reason: type);
      expect(items, hasLength(24), reason: type);
      expect(
        [for (final item in items!) item['id']],
        List<int>.generate(24, (index) => index + 1),
        reason: '$type item numbering',
      );
      for (final item in items) {
        expect(item['default'], 'Y', reason: '$type#${item['id']}');
        expect(item['overdue_days'], isA<int>());
        for (final language in languages) {
          expect(
            (item[language] as String?)?.trim(),
            isNotEmpty,
            reason: '$type#${item['id']} $language',
          );
        }
      }
    }
  });

  test('B7-M plant-room catalog has 22 complete multilingual items', () {
    const languages = ['en', 'ar', 'bn', 'hi', 'ml', 'tl', 'ta'];
    final items = kChecklistLists['B7_MECH'];
    expect(items, isNotNull);
    expect(items, hasLength(22));
    expect([
      for (final item in items!) item['id'],
    ], List<int>.generate(22, (index) => index + 1));
    for (final item in items) {
      expect(item['default'], 'Y', reason: 'B7_MECH#${item['id']}');
      expect(item['overdue_days'], 1);
      for (final language in languages) {
        expect(
          (item[language] as String?)?.trim(),
          isNotEmpty,
          reason: 'B7_MECH#${item['id']} $language',
        );
      }
    }
  });
}
