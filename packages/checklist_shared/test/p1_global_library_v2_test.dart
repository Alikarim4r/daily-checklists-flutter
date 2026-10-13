import 'package:checklist_shared/checklist_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> templateFixture({Object? industries, Object? domains}) => {
  'id': 'template-123',
  'category_id': 'cat-123',
  'category_slug': 'technical',
  'category_name_en': 'Technical Spaces',
  'category_name_ar': 'المرافق الفنية',
  'slug': 'chiller_plant',
  'version_number': 4,
  'name_en': 'Chiller Plant',
  'name_ar': 'محطة المبردات',
  'facility_tags': <String>['hvac'],
  'languages': <String>['en', 'ar', 'bn', 'hi', 'ml', 'tl', 'ta'],
  'access_model': 'premium',
  'minimum_plan_tier': 'professional',
  'item_count': 18,
  'can_access': false,
  'industries': industries,
  'domains': domains,
  'document_kind': 'checklist',
  'document_kind_name_en': 'Checklist',
  'document_kind_name_ar': 'قائمة فحص',
};

void main() {
  test('Global Library V2 parses 2 industries and multiple domains', () {
    final row = ChecklistLibraryTemplate.fromJson(
      templateFixture(
        industries: [
          {'slug': 'facilities', 'name_en': 'Facilities', 'name_ar': 'المرافق'},
          {'slug': 'energy', 'name_en': 'Energy', 'name_ar': 'الطاقة'},
        ],
        domains: [
          {'slug': 'hvac', 'name_en': 'HVAC', 'name_ar': 'التكييف'},
          {
            'slug': 'mechanical',
            'name_en': 'Mechanical',
            'name_ar': 'الميكانيكا',
          },
        ],
      ),
    );
    expect(row.industries.map((x) => x.slug), ['facilities', 'energy']);
    expect(row.industries[0].nameFor('ar'), 'المرافق');
    expect(row.domains.map((x) => x.slug), ['hvac', 'mechanical']);
    expect(row.documentKind, 'checklist');
    expect(row.validationStatus, 'unreviewed');
    expect(row.canAccess, isFalse);
    expect(row.languages, hasLength(7));
    expect(row.nameFor('ar'), 'محطة المبردات');
  });

  test(
    'Existing catalogue JSON remains compatible with optional V2 fields',
    () {
      final original = templateFixture()
        ..remove('industries')
        ..remove('domains')
        ..remove('document_kind')
        ..remove('document_kind_name_ar')
        ..remove('document_kind_name_en');
      final row = ChecklistLibraryTemplate.fromJson(original);
      expect(row.industries, isEmpty);
      expect(row.domains, isEmpty);
      expect(row.documentKind, 'checklist');
      expect(row.documentKindNameFor('ar'), 'قائمة فحص');
      expect(row.isPremium, isTrue);
    },
  );

  test('Global API falls back only if V2 migration is missing', () {
    expect(
      ChecklistLibraryRepository.isGlobalApiNotInstalled(
        const PostgrestException(message: 'Missing RPC', code: 'PGRST202'),
      ),
      isTrue,
    );
    expect(
      ChecklistLibraryRepository.isGlobalApiNotInstalled(
        const PostgrestException(message: 'Undefined function', code: '42883'),
      ),
      isTrue,
    );
    expect(
      ChecklistLibraryRepository.isGlobalApiNotInstalled(
        const PostgrestException(message: 'Unauthorized', code: '42501'),
      ),
      isFalse,
    );
    expect(
      ChecklistLibraryRepository.isGlobalApiNotInstalled(
        const PostgrestException(message: 'Bad state', code: 'XX000'),
      ),
      isFalse,
    );
    expect(
      ChecklistLibraryRepository.isGlobalApiNotInstalled(StateError('bad')),
      isFalse,
    );
  });

  test('facet metadata count is localized and parsed safely', () {
    final facet = GlobalLibraryFacet.fromJson({
      'slug': 'manufacturing',
      'name_en': 'Manufacturing',
      'name_ar': 'التصنيع',
      'template_count': 72,
    });
    expect(facet.count, 72);
    expect(facet.nameFor('en'), 'Manufacturing');
    expect(facet.nameFor('ar'), 'التصنيع');
  });
}
