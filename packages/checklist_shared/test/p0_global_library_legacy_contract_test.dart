import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

/// GLOB-001 / P0 regression fixtures: the proposed global taxonomy must not
/// rewrite pre-existing FM records, categories, purchased-library metadata or
/// organization visibility. No database or network calls are performed.
void main() {
  ChecklistSite legacyUnit({
    required String id,
    required String organization,
    required String category,
    required String name,
  }) => ChecklistSite(
    id: id,
    organizationId: organization,
    parentSiteId: 'hq-$organization',
    nameEn: name,
    nameAr: 'حمامات الدور الأرضي',
    buildingCode: 'B1-WC-GF-01-CL',
    checklistCategory: category,
    floorScope: 'ground',
    checklistType: 'DEFAULT',
  );

  group('P0 legacy FM contract', () {
    test('known legacy category slugs and semantics remain stable', () {
      expect(ChecklistCategories.normalize('  HYGIENE '), 'hygiene');
      expect(ChecklistCategories.normalize('irrigation'), 'irrigation');
      expect(ChecklistCategories.normalize('facilities'), 'facilities');
      expect(ChecklistCategories.normalize('maintenance'), 'maintenance');
      expect(
        ChecklistCategories.normalize('future-global-industry'),
        'general',
      );
      expect(ChecklistCategories.title('hygiene', 'ar'), 'النظافة');
    });

    test(
      'sector-neutral library metadata round trips via current JSON API',
      () {
        final fixture = <String, dynamic>{
          'id': 'library-1',
          'category_id': 'cat-1',
          'category_slug': 'technical',
          'category_name_en': 'Technical & MEP Spaces',
          'category_name_ar': 'المرافق الفنية',
          'slug': 'chiller_plant',
          'version_number': 7,
          'name_en': 'Chiller Plant',
          'name_ar': 'محطة المبردات',
          'facility_tags': <String>['hvac', 'facilities', 'education'],
          'languages': <String>['en', 'ar', 'bn', 'hi', 'ml', 'tl', 'ta'],
          'access_model': 'premium',
          'minimum_plan_tier': 'professional',
          'google_play_product_id': 'checklib_chiller_plant',
          'list_price_minor': 3900,
          'list_price_currency': 'QAR',
          'item_count': 18,
          'can_access': false,
          'installed_template_id': 'installed-copy-1',
          'installed_library_version': 6,
        };
        final row = ChecklistLibraryTemplate.fromJson(fixture);
        expect(row.slug, 'chiller_plant');
        expect(row.nameFor('ar'), 'محطة المبردات');
        expect(row.categoryNameFor('en'), 'Technical & MEP Spaces');
        expect(row.languages, hasLength(7));
        expect(row.facilityTags, containsAll(['hvac', 'education']));
        expect(row.isPremium, isTrue);
        expect(row.canAccess, isFalse);
        expect(row.isInstalled, isTrue);
        expect(row.hasUpdate, isTrue);
        expect(row.versionNumber, 7);
        expect(row.installedLibraryVersion, 6);
        expect(row.listPriceMinor, 3900);
        expect(row.listPriceCurrency, 'QAR');
      },
    );

    test(
      'installation state and update detection preserve current semantics',
      () {
        ChecklistLibraryTemplate fixture({required int? installedVersion}) =>
            ChecklistLibraryTemplate.fromJson({
              'id': 'lib-1',
              'category_id': 'cat-1',
              'slug': 'washroom_hygiene_safety',
              'version_number': 3,
              'name_en': 'Washroom Hygiene',
              'name_ar': 'نظافة دورات المياه',
              'facility_tags': <String>['hygiene'],
              'languages': <String>['en', 'ar'],
              'access_model': 'starter_included',
              'minimum_plan_tier': 'starter',
              'item_count': 12,
              'can_access': true,
              if (installedVersion != null) ...{
                'installed_template_id': 'copy-1',
                'installed_library_version': installedVersion,
              },
            });
        expect(fixture(installedVersion: null).isInstalled, isFalse);
        expect(fixture(installedVersion: null).hasUpdate, isFalse);
        expect(fixture(installedVersion: 3).hasUpdate, isFalse);
        expect(fixture(installedVersion: 2).hasUpdate, isTrue);
        expect(fixture(installedVersion: 4).hasUpdate, isFalse);
        expect(fixture(installedVersion: 3).isPremium, isFalse);
      },
    );

    test('legacy category grouping never merges two roles for one room', () {
      final fm = legacyUnit(
        id: 'fm-room',
        organization: 'org-a',
        category: 'facilities',
        name: 'B1 - GF - Room 01 (maintenance)',
      );
      final cleaning = legacyUnit(
        id: 'clean-room',
        organization: 'org-a',
        category: 'hygiene',
        name: 'B1 - GF - Room 01 (cleaning)',
      );
      final grouped = ChecklistCategories.groupAvailable([fm, cleaning]);
      expect(grouped['facilities']!.single.id, 'fm-room');
      expect(grouped['hygiene']!.single.id, 'clean-room');
    });

    test('organization boundaries and cascading choices stay intact', () {
      final rows = [
        legacyUnit(
          id: 'o-a-clean',
          organization: 'org-a',
          category: 'hygiene',
          name: 'HQ B1 Ground Room 01',
        ),
        legacyUnit(
          id: 'o-a-ppm',
          organization: 'org-a',
          category: 'maintenance',
          name: 'HQ Chiller Room',
        ),
        legacyUnit(
          id: 'o-b-clean',
          organization: 'org-b',
          category: 'hygiene',
          name: 'Hotel Ground Washroom',
        ),
      ];
      final scope = ChecklistScopeFilters.fromCatalog(
        organizations: [
          Organization(id: 'org-a', nameEn: 'Education', nameAr: 'التعليم'),
          Organization(id: 'org-b', nameEn: 'Hotel', nameAr: 'الفندق'),
        ],
        zones: [],
        sites: rows,
      );

      final selection = const ChecklistFilterSelection()
          .choose(ChecklistFacet.organization, 'org-a')
          .choose(ChecklistFacet.category, 'hygiene');
      expect(scope.matchingSiteIds(selection), {'o-a-clean'});
      expect(
        scope
            .optionsFor(ChecklistFacet.category, selection)
            .map((e) => e.value),
        containsAll(['hygiene', 'maintenance']),
      );
      final all = selection.choose(ChecklistFacet.organization, null);
      expect(all.isAll, isTrue);
      expect(scope.matchingSiteIds(all), hasLength(3));
    });
  });
}
