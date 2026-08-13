import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormPaperTheme', () {
    test('resolves every preset and a custom color', () {
      expect(
        FormPaperTheme.resolve(themeDb: 'forest').accent,
        FormPaperTheme.forest.accent,
      );

      final custom = FormPaperTheme.resolve(
        themeDb: 'custom',
        accentHex: '#112233',
      );
      expect(custom.key, FormThemeKey.custom);
      expect(FormPaperTheme.hexOf(custom.accent), '#112233');
      expect(custom.accentText, const Color(0xFFF8FAFC));
    });

    test('inspection inherits the campus preset and custom accent', () {
      final presetInspection = Inspection(
        id: 'inspection-1',
        siteId: 'site-1',
        buildingCode: 'B1',
        inspectionDate: DateTime(2026, 8, 9),
        formTheme: 'inherit',
        parentFormTheme: 'teal',
      );
      expect(presetInspection.paperTheme.accent, FormPaperTheme.teal.accent);

      final customInspection = Inspection(
        id: 'inspection-2',
        siteId: 'site-2',
        buildingCode: 'B2',
        inspectionDate: DateTime(2026, 8, 9),
        formTheme: 'inherit',
        parentFormTheme: 'custom',
        parentFormThemeAccent: '#6D28D9',
      );
      expect(customInspection.paperTheme.key, FormThemeKey.custom);
      expect(
        FormPaperTheme.hexOf(customInspection.paperTheme.accent),
        '#6D28D9',
      );
    });

    test('invalid recursive inheritance safely falls back to classic gold', () {
      final theme = FormPaperTheme.resolve(
        themeDb: 'inherit',
        parentThemeDb: 'inherit',
      );
      expect(theme, same(FormPaperTheme.classicGold));
    });

    test('resolved hierarchy overrides the raw inherited site value', () {
      final inspection = Inspection.fromJson({
        'id': 'inspection-3',
        'site_id': 'site-3',
        'building_code': 'B3',
        'inspection_date': '2026-08-09',
        '_resolved_form_theme': 'crimson',
        '_form_theme_source': 'zone',
        'sites': {'form_theme': 'inherit'},
      });

      expect(inspection.paperTheme.accent, FormPaperTheme.crimson.accent);
      expect(inspection.formThemeSource, 'zone');
    });

    test('site model exposes the effective hierarchy color', () {
      final site = ChecklistSite.fromJson({
        'id': 'site-4',
        'organization_id': 'org-1',
        'name_en': 'Building 4',
        'name_ar': 'المبنى 4',
        'building_code': 'B4',
        'form_theme': 'inherit',
        '_effective_form_theme': 'teal',
        '_form_theme_source': 'organization',
      });

      expect(site.paperTheme.accent, FormPaperTheme.teal.accent);
      expect(site.formThemeSource, 'organization');
    });

    test('offline hierarchy follows site to organization precedence', () {
      final resolved = resolveFormThemeHierarchy(
        site: const FormThemeScopeValue(theme: 'inherit', source: 'site'),
        campus: const FormThemeScopeValue(theme: 'inherit', source: 'campus'),
        zone: const FormThemeScopeValue(theme: 'forest', source: 'zone'),
        template: const FormThemeScopeValue(
          theme: 'crimson',
          source: 'template',
        ),
        organization: const FormThemeScopeValue(
          theme: 'navy_sand',
          source: 'organization',
        ),
      );

      expect(resolved.theme, 'forest');
      expect(resolved.source, 'zone');
    });

    test('list-type theme resolves when upper scopes inherit', () {
      final resolved = resolveFormThemeHierarchy(
        site: const FormThemeScopeValue(theme: 'inherit', source: 'site'),
        campus: const FormThemeScopeValue(theme: 'inherit', source: 'campus'),
        zone: const FormThemeScopeValue(theme: 'inherit', source: 'zone'),
        template: const FormThemeScopeValue(
          theme: 'custom',
          accent: '#2563EB',
          source: 'template',
        ),
      );

      expect(resolved.theme, 'custom');
      expect(resolved.accent, '#2563EB');
      expect(resolved.source, 'template');
    });
  });
}
