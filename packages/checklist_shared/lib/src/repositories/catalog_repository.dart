import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/checklist_lists.dart';
import '../models/catalog.dart';
import '../models/inspection.dart';
import '../models/profile.dart';

class ChecklistCatalogRepository {
  ChecklistCatalogRepository(this._client);
  final SupabaseClient _client;

  /// Retry transient gateway timeouts once; permission or schema errors
  /// still propagate, preventing silently incomplete site checklists.
  Future<T> _retryTransientRead<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error) {
      final message = '$error'.toLowerCase();
      if (!message.contains('504') &&
          !message.contains('timeout') &&
          !message.contains('timed out')) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 220));
      return operation();
    }
  }

  Future<List<ChecklistTemplate>> listTemplates({
    bool activeOnly = true,
  }) async {
    var q = _client.from('checklist_templates').select();
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('code');
    return (rows as List)
        .map(
          (e) =>
              ChecklistTemplate.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<ChecklistTemplate?> getTemplateByCode(String code) async {
    final row = await _client
        .from('checklist_templates')
        .select()
        .eq('code', code)
        .maybeSingle();
    if (row == null) return null;
    final items = await listTemplateItems(row['id'] as String);
    return ChecklistTemplate.fromJson(
      Map<String, dynamic>.from(row),
      items: items,
    );
  }

  Future<ChecklistTemplate?> getTemplateById(String id) async {
    final row = await _client
        .from('checklist_templates')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final items = await listTemplateItems(id);
    return ChecklistTemplate.fromJson(
      Map<String, dynamic>.from(row),
      items: items,
    );
  }

  Future<List<CatalogItem>> listTemplateItems(String templateId) async {
    final rows = await _client
        .from('checklist_template_items')
        .select()
        .eq('template_id', templateId)
        .eq('is_active', true)
        .order('sort_order')
        .order('item_index');
    return (rows as List)
        .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ChecklistTemplate> createTemplate({
    required String code,
    required String nameEn,
    required String nameAr,
  }) async {
    final row = await _client
        .from('checklist_templates')
        .insert({'code': code, 'name_en': nameEn, 'name_ar': nameAr})
        .select()
        .single();
    return ChecklistTemplate.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ChecklistTemplate> updateTemplate(ChecklistTemplate t) async {
    final row = await _client
        .from('checklist_templates')
        .update(t.toUpdateJson())
        .eq('id', t.id)
        .select()
        .single();
    return ChecklistTemplate.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ChecklistTemplate> updateTemplateFormTheme({
    required String id,
    required String formTheme,
    String? formThemeAccent,
  }) async {
    final row = await _client
        .from('checklist_templates')
        .update({'form_theme': formTheme, 'form_theme_accent': formThemeAccent})
        .eq('id', id)
        .select()
        .single();
    return ChecklistTemplate.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteTemplate(String id) async {
    await _client.from('checklist_templates').delete().eq('id', id);
  }

  Future<String> cloneTemplateVersion({
    required String sourceTemplateId,
    required String reason,
  }) async =>
      await _client.rpc(
            'clone_checklist_template_version',
            params: {
              'p_source_template_id': sourceTemplateId,
              'p_reason': reason,
            },
          )
          as String;

  Future<void> publishTemplateVersion({
    required String templateId,
    required String reason,
  }) => _client.rpc(
    'publish_checklist_template_version',
    params: {'p_template_id': templateId, 'p_reason': reason},
  );

  Future<CatalogItem> upsertTemplateItem({
    required String templateId,
    required CatalogItem item,
  }) async {
    if (item.id == null) {
      final row = await _client
          .from('checklist_template_items')
          .insert(item.toTemplateInsertJson(templateId))
          .select()
          .single();
      return CatalogItem.fromJson(Map<String, dynamic>.from(row));
    }
    final row = await _client
        .from('checklist_template_items')
        .update(item.toTemplateUpdateJson())
        .eq('id', item.id!)
        .select()
        .single();
    return CatalogItem.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteTemplateItem(String id) async {
    await _client.from('checklist_template_items').delete().eq('id', id);
  }

  Future<List<CatalogItem>> listSiteExtraItems(String siteId) async {
    final rows = await _client
        .from('site_checklist_items')
        .select()
        .eq('site_id', siteId)
        .eq('is_active', true)
        .order('sort_order')
        .order('item_index');
    return (rows as List)
        .map(
          (e) => CatalogItem.fromJson({
            ...Map<String, dynamic>.from(e as Map),
            'is_custom': true,
          }),
        )
        .toList();
  }

  Future<CatalogItem> upsertSiteExtraItem({
    required String siteId,
    required CatalogItem item,
  }) async {
    if (item.id == null) {
      final row = await _client
          .from('site_checklist_items')
          .insert(item.toSiteInsertJson(siteId))
          .select()
          .single();
      return CatalogItem.fromJson({
        ...Map<String, dynamic>.from(row),
        'is_custom': true,
      });
    }
    final row = await _client
        .from('site_checklist_items')
        .update({
          'item_index': item.itemIndex,
          'default_answer': item.defaultAnswer,
          'description_en': item.descriptionEn,
          'description_ar': item.descriptionAr,
          for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
            'description_$language': item.localizedDescriptions[language],
          'sort_order': item.sortOrder,
          'is_active': item.isActive,
          'overdue_after_days': item.overdueAfterDays,
        })
        .eq('id', item.id!)
        .select()
        .single();
    return CatalogItem.fromJson({
      ...Map<String, dynamic>.from(row),
      'is_custom': true,
    });
  }

  Future<void> deleteSiteExtraItem(String id) async {
    await _client.from('site_checklist_items').delete().eq('id', id);
  }

  /// Resolve inspection items for a site: template + site extras.
  /// Falls back to embedded Dart catalog if DB template missing.
  Future<List<InspectionItem>> resolveItemsForSite({
    required String checklistType,
    required String siteId,
    String language = 'en',
  }) async {
    final key = checklistType.isEmpty ? 'DEFAULT' : checklistType;
    final template = await getTemplateByCode(key);
    final extras = await listSiteExtraItems(siteId);

    List<CatalogItem> catalog;
    if (template != null && template.items.isNotEmpty) {
      catalog = [...template.items];
    } else {
      final rawList =
          kChecklistLists[key] ?? kChecklistLists['DEFAULT'] ?? const [];
      catalog = [
        for (final raw in rawList)
          CatalogItem(
            itemIndex: raw['id'] as int,
            defaultAnswer: '${raw['default'] ?? 'Y'}',
            descriptionEn: (raw['en'] ?? '') as String,
            descriptionAr: raw['ar'] as String?,
            localizedDescriptions: {
              for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
                if ((raw[language] as String?)?.trim().isNotEmpty == true)
                  language: (raw[language] as String).trim(),
            },
            sortOrder: raw['id'] as int,
            overdueAfterDays: (raw['overdue_days'] as num?)?.toInt() ?? 3,
          ),
      ];
    }

    final maxIndex = catalog.isEmpty
        ? 0
        : catalog.map((e) => e.itemIndex).reduce((a, b) => a > b ? a : b);

    final merged = <CatalogItem>[
      ...catalog,
      for (var i = 0; i < extras.length; i++)
        CatalogItem(
          id: extras[i].id,
          itemIndex: maxIndex + i + 1,
          defaultAnswer: extras[i].defaultAnswer,
          descriptionEn: extras[i].descriptionEn,
          descriptionAr: extras[i].descriptionAr,
          localizedDescriptions: extras[i].localizedDescriptions,
          sortOrder: extras[i].sortOrder,
          isCustom: true,
          overdueAfterDays: extras[i].overdueAfterDays,
        ),
    ]..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));

    return [
      for (final c in merged)
        InspectionItem(
          itemIndex: c.itemIndex,
          description: c.descriptionEn,
          descriptionAr: c.descriptionAr,
          localizedDescriptions: c.localizedDescriptions,
          defaultAnswer: c.defaultAnswer,
          response: null,
          isCustom: c.isCustom,
          overdueAfterDays: c.overdueAfterDays,
        ),
    ];
  }

  /// Bulk preview loading for the read-only stacked viewer. A small number
  /// of template types may be reused across hundreds of washroom checklists.
  /// Fetch each template only once; fetch all site extras in bounded chunks.
  /// Never mix the custom items of different sites.
  Future<Map<String, List<CatalogItem>>> listEffectiveCatalogForSites(
    Iterable<ChecklistSite> accessibleSites,
  ) async {
    final sitesById = {
      for (final site in accessibleSites)
        if (site.id.isNotEmpty) site.id: site,
    };
    if (sitesById.isEmpty) return {};
    final types = {
      for (final site in sitesById.values)
        site.checklistType.trim().isEmpty ? 'DEFAULT' : site.checklistType,
    }.toList();
    final templates = await Future.wait([
      for (final type in types)
        _retryTransientRead(() => getTemplateByCode(type)),
    ]);
    final baseByType = <String, List<CatalogItem>>{};
    for (var i = 0; i < types.length; i++) {
      final type = types[i];
      final template = templates[i];
      if (template != null && template.items.isNotEmpty) {
        baseByType[type] = [
          for (final item in template.items)
            CatalogItem(
              id: item.id,
              itemIndex: item.itemIndex,
              defaultAnswer: item.defaultAnswer,
              descriptionEn: item.descriptionEn,
              descriptionAr: item.descriptionAr,
              localizedDescriptions: item.localizedDescriptions,
              sortOrder: item.sortOrder,
              overdueAfterDays: item.overdueAfterDays,
            ),
        ];
      } else {
        final embedded =
            kChecklistLists[type] ?? kChecklistLists['DEFAULT'] ?? const [];
        baseByType[type] = [
          for (final raw in embedded)
            CatalogItem(
              itemIndex: raw['id'] as int,
              defaultAnswer: '${raw['default'] ?? 'Y'}',
              descriptionEn: (raw['en'] ?? '') as String,
              descriptionAr: raw['ar'] as String?,
              localizedDescriptions: {
                for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
                  if ((raw[language] as String?)?.trim().isNotEmpty == true)
                    language: (raw[language] as String).trim(),
              },
              sortOrder: raw['id'] as int,
              overdueAfterDays: (raw['overdue_days'] as num?)?.toInt() ?? 3,
            ),
        ];
      }
    }
    final extrasBySite = <String, List<CatalogItem>>{};
    final ids = sitesById.keys.toList();
    const batchSize = 35;
    for (var offset = 0; offset < ids.length; offset += batchSize) {
      final batch = ids.skip(offset).take(batchSize).toList();
      final rows = await _retryTransientRead(
        () => _client
            .from('site_checklist_items')
            .select()
            .inFilter('site_id', batch)
            .eq('is_active', true)
            .order('site_id')
            .order('sort_order')
            .order('item_index'),
      );
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final id = row['site_id'] as String;
        extrasBySite
            .putIfAbsent(id, () => [])
            .add(CatalogItem.fromJson({...row, 'is_custom': true}));
      }
    }
    return {
      for (final site in sitesById.values)
        site.id: mergeSiteCatalog(
          baseByType[site.checklistType.trim().isEmpty
                  ? 'DEFAULT'
                  : site.checklistType] ??
              const [],
          extrasBySite[site.id] ?? const [],
        ),
    };
  }

  /// Keeps the exact old numbering: extra items follow the last template item.
  static List<CatalogItem> mergeSiteCatalog(
    List<CatalogItem> base,
    List<CatalogItem> extras,
  ) {
    final maxIndex = base.isEmpty
        ? 0
        : base.map((item) => item.itemIndex).reduce((a, b) => a > b ? a : b);
    return [
      ...base,
      for (var i = 0; i < extras.length; i++)
        CatalogItem(
          id: extras[i].id,
          itemIndex: maxIndex + i + 1,
          defaultAnswer: extras[i].defaultAnswer,
          descriptionEn: extras[i].descriptionEn,
          descriptionAr: extras[i].descriptionAr,
          localizedDescriptions: extras[i].localizedDescriptions,
          sortOrder: extras[i].sortOrder,
          isCustom: true,
          overdueAfterDays: extras[i].overdueAfterDays,
        ),
    ]..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
  }

  /// Same merge as [resolveItemsForSite] but keeps [CatalogItem] metadata
  /// (for Admin “effective list” preview).
  Future<List<CatalogItem>> listEffectiveCatalogForSite({
    required String checklistType,
    required String siteId,
  }) async {
    final key = checklistType.isEmpty ? 'DEFAULT' : checklistType;
    final template = await getTemplateByCode(key);
    final extras = await listSiteExtraItems(siteId);

    List<CatalogItem> catalog;
    if (template != null && template.items.isNotEmpty) {
      catalog = [
        for (final c in template.items)
          CatalogItem(
            id: c.id,
            itemIndex: c.itemIndex,
            defaultAnswer: c.defaultAnswer,
            descriptionEn: c.descriptionEn,
            descriptionAr: c.descriptionAr,
            localizedDescriptions: c.localizedDescriptions,
            sortOrder: c.sortOrder,
            isCustom: false,
            overdueAfterDays: c.overdueAfterDays,
          ),
      ];
    } else {
      final rawList =
          kChecklistLists[key] ?? kChecklistLists['DEFAULT'] ?? const [];
      catalog = [
        for (final raw in rawList)
          CatalogItem(
            itemIndex: raw['id'] as int,
            defaultAnswer: '${raw['default'] ?? 'Y'}',
            descriptionEn: (raw['en'] ?? '') as String,
            descriptionAr: raw['ar'] as String?,
            localizedDescriptions: {
              for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
                if ((raw[language] as String?)?.trim().isNotEmpty == true)
                  language: (raw[language] as String).trim(),
            },
            sortOrder: raw['id'] as int,
            isCustom: false,
            overdueAfterDays: (raw['overdue_days'] as num?)?.toInt() ?? 3,
          ),
      ];
    }

    final maxIndex = catalog.isEmpty
        ? 0
        : catalog.map((e) => e.itemIndex).reduce((a, b) => a > b ? a : b);

    return [
      ...catalog,
      for (var i = 0; i < extras.length; i++)
        CatalogItem(
          id: extras[i].id,
          itemIndex: maxIndex + i + 1,
          defaultAnswer: extras[i].defaultAnswer,
          descriptionEn: extras[i].descriptionEn,
          descriptionAr: extras[i].descriptionAr,
          localizedDescriptions: extras[i].localizedDescriptions,
          sortOrder: extras[i].sortOrder,
          isCustom: true,
          overdueAfterDays: extras[i].overdueAfterDays,
        ),
    ]..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
  }
}
