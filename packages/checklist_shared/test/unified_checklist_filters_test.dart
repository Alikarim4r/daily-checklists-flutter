import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

LocationScopeLeaf makeLeaf({
  required String assignment,
  required String service,
  required String department,
  required String coverage,
  String kind = 'daily',
  String org = 'org-a',
}) => LocationScopeLeaf.fromJson({
  'organization_id': org,
  'organization_name_en': 'Head Office',
  'site_id': 'site-1',
  'site_name_en': 'HQ',
  'building_id': 'building-3',
  'building_code': 'B3',
  'building_name_en': 'Building 3',
  'floor_id': 'floor-1',
  'floor_code': 'L1',
  'floor_name_en': 'First Floor',
  'area_id': 'area-$assignment',
  'area_code': 'A-$assignment',
  'area_name_en': 'Area',
  'assignment_id': assignment,
  'checklist_name_en': 'Checklist $assignment',
  'service_type_code': 'cleaning',
  'service_type_name_en': 'Cleaning',
  'service_type_name_ar': 'النظافة',
  'sector_id': 'facilities',
  'sector_name_en': 'Facilities Management',
  'sector_name_ar': 'إدارة المرافق',
  'service_class_id': service,
  'service_class_name_en': service == 'soft'
      ? 'Soft Services'
      : 'Hard Services',
  'service_class_name_ar': service == 'soft'
      ? 'الخدمات اللينة'
      : 'الخدمات الفنية',
  'department_id': department,
  'department_name_en': department == 'cleaning'
      ? 'Cleaning'
      : department == 'hospitality'
      ? 'Hospitality'
      : 'General',
  'department_name_ar': department == 'cleaning'
      ? 'النظافة'
      : department == 'hospitality'
      ? 'الضيافة'
      : 'عام',
  'coverage_id': coverage,
  'coverage_name_en': coverage.startsWith('wash')
      ? 'Washrooms'
      : coverage.startsWith('pantry')
      ? 'Pantries'
      : 'Whole building / General',
  'coverage_name_ar': coverage.startsWith('wash')
      ? 'الحمامات'
      : coverage.startsWith('pantry')
      ? 'البانتري'
      : 'عام / كامل المبنى',
  'document_kind_id': kind,
  'document_kind_name_en': kind == 'ppm' ? 'PPM' : 'Checklist',
  'document_kind_name_ar': kind == 'ppm'
      ? 'الصيانة الوقائية'
      : 'قائمة فحص يومية',
});

void main() {
  final scope = LocationFilterScope([
    makeLeaf(
      assignment: 'soft-clean',
      service: 'soft',
      department: 'cleaning',
      coverage: 'wash-soft',
    ),
    makeLeaf(
      assignment: 'soft-hosp',
      service: 'soft',
      department: 'hospitality',
      coverage: 'pantry-hosp',
    ),
    makeLeaf(
      assignment: 'hard-general',
      service: 'hard',
      department: 'general',
      coverage: 'wash-hard',
      kind: 'ppm',
    ),
  ]);
  test('Soft Services has Cleaning and Hospitality, hard only General', () {
    final soft = scope.optionsFor(
      LocationFilterDimension.department,
      const LocationFilterSelection(serviceClassId: 'soft'),
    );
    expect(soft.map((x) => x.value).toSet(), {'cleaning', 'hospitality'});
    final hard = scope.optionsFor(
      LocationFilterDimension.department,
      const LocationFilterSelection(serviceClassId: 'hard'),
    );
    expect(hard.map((x) => x.nameEn), ['General']);
  });
  test('Washrooms in hard and soft are independent scoped options', () {
    final soft = scope.optionsFor(
      LocationFilterDimension.coverage,
      const LocationFilterSelection(
        serviceClassId: 'soft',
        departmentId: 'cleaning',
      ),
    );
    expect(soft.single.value, 'wash-soft');
    final hard = scope.optionsFor(
      LocationFilterDimension.coverage,
      const LocationFilterSelection(
        serviceClassId: 'hard',
        departmentId: 'general',
      ),
    );
    expect(hard.single.value, 'wash-hard');
  });
  test('Building, class and PPM can be combined', () {
    final result = scope.filteredLeaves(
      const LocationFilterSelection(
        buildingId: 'building-3',
        serviceClassId: 'hard',
        documentKindId: 'ppm',
      ),
    );
    expect(result.map((x) => x.assignmentId), ['hard-general']);
  });
  test('One section still stays visible even without subdepartments', () {
    expect(
      scope.shouldShow(
        LocationFilterDimension.department,
        const LocationFilterSelection(serviceClassId: 'hard'),
      ),
      isTrue,
    );
  });
  test(
    'Different organizations cannot leak options through a scoped leaf set',
    () {
      final limited = LocationFilterScope([
        makeLeaf(
          assignment: 'visible',
          org: 'org-a',
          service: 'soft',
          department: 'cleaning',
          coverage: 'wash-soft',
        ),
      ]);
      expect(
        limited
            .optionsFor(
              LocationFilterDimension.organization,
              const LocationFilterSelection(),
            )
            .single
            .value,
        'org-a',
      );
      expect(
        limited.filteredLeaves(
          const LocationFilterSelection(organizationId: 'org-b'),
        ),
        isEmpty,
      );
    },
  );
  test('Metadata can be omitted on legacy rows without throwing', () {
    final raw = makeLeaf(
      assignment: 'fallback',
      service: 'soft',
      department: 'cleaning',
      coverage: 'wash-soft',
    );
    expect(raw.sectorNameAr, 'إدارة المرافق');
    expect(raw.valueFor(LocationFilterDimension.documentKind), 'daily');
  });
}
