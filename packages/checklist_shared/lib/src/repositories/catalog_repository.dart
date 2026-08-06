import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/checklist_lists.dart';
import '../models/catalog.dart';
import '../models/inspection.dart';

class ChecklistCatalogRepository {
  ChecklistCatalogRepository(this._client);
  final SupabaseClient _client;

  Future<List<ChecklistTemplate>> listTemplates({bool activeOnly = true}) async {
    var q = _client.from('checklist_templates').select();
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('code');
    return (rows as List)
        .map(
          (e) => ChecklistTemplate.fromJson(Map<String, dynamic>.from(e as Map)),
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
        .insert({
          'code': code,
          'name_en': nameEn,
          'name_ar': nameAr,
        })
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

  Future<void> deleteTemplate(String id) async {
    await _client.from('checklist_templates').delete().eq('id', id);
  }

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
            sortOrder: raw['id'] as int,
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
          itemIndex: extras[i].itemIndex > maxIndex
              ? extras[i].itemIndex
              : maxIndex + i + 1,
          defaultAnswer: extras[i].defaultAnswer,
          descriptionEn: extras[i].descriptionEn,
          descriptionAr: extras[i].descriptionAr,
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
          defaultAnswer: c.defaultAnswer,
          response: null,
          isCustom: c.isCustom,
          overdueAfterDays: c.overdueAfterDays,
        ),
    ];
  }
}
