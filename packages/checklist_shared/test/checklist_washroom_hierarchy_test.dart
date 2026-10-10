import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistSite washroom(String code, String category, String subcategory,
    String floor) => ChecklistSite(
      id: code, organizationId: 'ministry', nameEn: 'Washroom $code',
      nameAr: 'حمام $code', buildingCode: code,
      pin: 'A/66170852/01-0013', checklistCategory: category,
      checklistSubcategory: subcategory, floorScope: floor,
    );

void main() {
  test('Facilities washrooms display a nonempty child folder', () {
    final facility = washroom('B1-WC-LGF-13-FM', 'facilities', 'washrooms',
        'floor_number:-1');
    final cleaning = washroom('B1-WC-LGF-13-CL', 'hygiene', '',
        'floor_number:-1');
    final facilities = ChecklistCategories.groupAvailable([facility, cleaning]);
    expect(facilities.keys, containsAll(['facilities', 'hygiene']));
    final folder = ChecklistSubcategories.available(facilities['facilities']!);
    expect(folder.keys, ['washrooms']);
    expect(ChecklistSubcategories.title('washrooms', 'ar'), 'قوائم فحص الحمامات');
    expect(ChecklistSubcategories.available(facilities['hygiene']!).keys, ['']);
    expect(facility.reportFloor, 'LGF');
    expect(cleaning.reportFloor, 'LGF');
    expect(facility.pin, 'A/66170852/01-0013');
  });

  test('GF and FF render correctly and no empty subcategories appear', () {
    final siteGF = washroom('B3-WC-GF-03-FM','facilities','washrooms','ground');
    final siteFF = washroom('B5-WC-FF-70-FM','facilities','washrooms','first');
    expect(siteGF.reportFloor, 'GF');
    expect(siteFF.reportFloor, 'FF');
    expect(ChecklistSubcategories.available([]), isEmpty);
  });
}
