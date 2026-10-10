import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistSite site(String id, String category, {bool active = true}) =>
    ChecklistSite(
      id: id,
      organizationId: 'org',
      nameEn: id,
      nameAr: id,
      buildingCode: id,
      checklistCategory: category,
      isActive: active,
    );

void main() {
  test('only categories with active lists appear in the site', () {
    final groups = ChecklistCategories.groupAvailable([
      site('B1', 'hygiene'),
      site('B2', 'facilities'),
      site('B3', 'hygiene'),
      site('B4', 'pantry', active: false),
    ]);
    expect(groups.keys.toList(), ['facilities', 'hygiene']);
    expect(groups['hygiene']!.length, 2);
    expect(groups.containsKey('pantry'), false);
    expect(groups.containsKey('irrigation'), false);
  });

  test(
    'legacy unspecified categories are not lost and admin sees inactive',
    () {
      final general = site('B5', 'unknown_old_value');
      final disabled = site('B6', 'pantry', active: false);
      final groups = ChecklistCategories.groupAvailable([general, disabled]);
      expect(groups.keys.toList(), ['general']);
      final adminGroups = ChecklistCategories.groupAvailable([
        general,
        disabled,
      ], includeInactive: true);
      expect(adminGroups.keys.toList(), ['pantry', 'general']);
      expect(ChecklistCategories.title('pantry', 'ar'), 'البانتري');
      expect(
        ChecklistCategories.title('facilities', 'en'),
        'Facilities Management',
      );
    },
  );
}
