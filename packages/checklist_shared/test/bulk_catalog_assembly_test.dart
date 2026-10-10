import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogItem item(int index, String desc, {String ideal = 'Y'}) => CatalogItem(
  itemIndex: index,
  defaultAnswer: ideal,
  descriptionEn: desc,
  sortOrder: index,
);

void main() {
  test(
    '104 washrooms can share one 14-point catalog without altered items',
    () {
      final base = [for (var n = 1; n <= 14; n++) item(n, 'Cleaning item $n')];
      final siteA = ChecklistCatalogRepository.mergeSiteCatalog(base, []);
      final siteB = ChecklistCatalogRepository.mergeSiteCatalog(base, [
        item(1, 'Site B only extra', ideal: 'N'),
      ]);
      expect(siteA.length, 14);
      expect(siteB.length, 15);
      expect(siteB.last.itemIndex, 15);
      expect(
        siteA.any((e) => e.descriptionEn.contains('Site B only')),
        isFalse,
      );
      expect(siteB.last.defaultAnswer, 'N');
    },
  );
  test('facility technical template stays separate from cleaning', () {
    final facilities = [
      for (var n = 1; n <= 24; n++) item(n, 'Technical item $n'),
    ];
    final cleaning = [
      for (var n = 1; n <= 14; n++) item(n, 'Cleaning item $n'),
    ];
    expect(
      ChecklistCatalogRepository.mergeSiteCatalog(facilities, []).length,
      24,
    );
    expect(
      ChecklistCatalogRepository.mergeSiteCatalog(cleaning, []).length,
      14,
    );
  });
}
