import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/checklist_lists.dart';
import '../models/enums.dart';
import '../models/inspection.dart';
import '../models/profile.dart';
import '../theme/form_theme_resolution.dart';
import '../utils/storage_path_list.dart';
import 'catalog_repository.dart';

class InspectionRepository {
  InspectionRepository(this._client);

  final SupabaseClient _client;
  static const bucket = 'checklist-media';

  ChecklistCatalogRepository get _catalog =>
      ChecklistCatalogRepository(_client);

  /// Adds the resolved organization/zone/campus/site/template theme in one
  /// batch so list screens never issue one request per inspection.
  Future<void> _attachResolvedThemeData(
    List<Map<String, dynamic>> inspectionRows,
  ) async {
    final rowsBySiteId = <String, List<Map<String, dynamic>>>{};
    for (final row in inspectionRows) {
      final siteId = row['site_id'] as String?;
      if (siteId == null || siteId.isEmpty) continue;
      rowsBySiteId.putIfAbsent(siteId, () => []).add(row);
    }
    if (rowsBySiteId.isEmpty) return;
    final unresolvedSiteIds = rowsBySiteId.keys.toSet();

    try {
      final raw = await _client.rpc(
        'resolve_checklist_form_themes',
        params: {'p_site_ids': rowsBySiteId.keys.toList()},
      );
      for (final value in raw as List) {
        final resolved = Map<String, dynamic>.from(value as Map);
        final siteId = resolved['site_id'] as String?;
        if (siteId == null) continue;
        final theme = resolved['theme_key'] as String?;
        if (theme == null || theme.trim().isEmpty || theme == 'inherit') {
          continue;
        }
        for (final row in rowsBySiteId[siteId] ?? const []) {
          row['_resolved_form_theme'] = theme;
          row['_resolved_form_theme_accent'] = resolved['accent_hex'];
          row['_form_theme_source'] = resolved['source_scope'];
        }
        unresolvedSiteIds.remove(siteId);
      }
      if (unresolvedSiteIds.isEmpty) return;
    } catch (_) {
      // Resolve locally below if the RPC is unavailable during a rollout.
    }

    await _attachLocallyResolvedThemeData(rowsBySiteId, unresolvedSiteIds);
  }

  Future<List<Map<String, dynamic>>> _safeThemeRows({
    required String table,
    required String columns,
    required String filterColumn,
    required Iterable<String> values,
  }) async {
    final ids = values.where((value) => value.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const [];
    try {
      final rows = await _client
          .from(table)
          .select(columns)
          .inFilter(filterColumn, ids);
      return [
        for (final row in rows as List) Map<String, dynamic>.from(row as Map),
      ];
    } catch (_) {
      return const [];
    }
  }

  FormThemeScopeValue? _themeCandidate(
    Map<String, dynamic>? row,
    String source,
  ) {
    final theme = (row?['form_theme'] as String?)?.trim();
    if (theme == null || theme.isEmpty || theme == 'inherit') return null;
    return FormThemeScopeValue(
      theme: theme,
      accent: row?['form_theme_accent'] as String?,
      source: source,
    );
  }

  Future<void> _attachLocallyResolvedThemeData(
    Map<String, List<Map<String, dynamic>>> rowsBySiteId,
    Set<String> unresolvedSiteIds,
  ) async {
    final parentIds = <String>{};
    final organizationIds = <String>{};
    final templateCodes = <String>{};
    for (final siteId in unresolvedSiteIds) {
      final row = rowsBySiteId[siteId]?.firstOrNull;
      final site = row?['sites'];
      if (site is! Map) continue;
      final parentId = site['parent_site_id'] as String?;
      if (parentId != null && parentId.isNotEmpty) parentIds.add(parentId);
      final organizationId = site['organization_id'] as String?;
      if (organizationId != null && organizationId.isNotEmpty) {
        organizationIds.add(organizationId);
      }
      final checklistType = site['checklist_type'] as String?;
      if (checklistType != null && checklistType.isNotEmpty) {
        templateCodes.add(checklistType);
      }
    }
    final parentRows = await _safeThemeRows(
      table: 'sites',
      columns: 'id, zone_id, form_theme, form_theme_accent',
      filterColumn: 'id',
      values: parentIds,
    );
    final parentsById = <String, Map<String, dynamic>>{
      for (final row in parentRows)
        if (row['id'] is String) row['id'] as String: row,
    };

    final zoneIds = <String>{};
    for (final siteId in unresolvedSiteIds) {
      final site = rowsBySiteId[siteId]?.firstOrNull?['sites'];
      if (site is! Map) continue;
      final directZoneId = site['zone_id'] as String?;
      final parent = parentsById[site['parent_site_id'] as String?];
      final effectiveZoneId = directZoneId ?? parent?['zone_id'] as String?;
      if (effectiveZoneId != null && effectiveZoneId.isNotEmpty) {
        zoneIds.add(effectiveZoneId);
      }
    }

    final zoneRows = await _safeThemeRows(
      table: 'zones',
      columns: 'id, form_theme, form_theme_accent',
      filterColumn: 'id',
      values: zoneIds,
    );
    final organizationRows = await _safeThemeRows(
      table: 'organizations',
      columns: 'id, form_theme, form_theme_accent',
      filterColumn: 'id',
      values: organizationIds,
    );
    final templateRows = await _safeThemeRows(
      table: 'checklist_templates',
      columns: 'code, form_theme, form_theme_accent',
      filterColumn: 'code',
      values: templateCodes,
    );
    final zonesById = <String, Map<String, dynamic>>{
      for (final row in zoneRows)
        if (row['id'] is String) row['id'] as String: row,
    };
    final organizationsById = <String, Map<String, dynamic>>{
      for (final row in organizationRows)
        if (row['id'] is String) row['id'] as String: row,
    };
    final templatesByCode = <String, Map<String, dynamic>>{
      for (final row in templateRows)
        if (row['code'] is String) row['code'] as String: row,
    };

    for (final siteId in unresolvedSiteIds) {
      final rows = rowsBySiteId[siteId] ?? const [];
      if (rows.isEmpty) continue;
      final siteValue = rows.first['sites'];
      if (siteValue is! Map) continue;
      final site = Map<String, dynamic>.from(siteValue);
      final parent = parentsById[site['parent_site_id'] as String?];
      final zoneId =
          site['zone_id'] as String? ?? parent?['zone_id'] as String?;
      final templateCode = site['checklist_type'] as String?;
      final organizationId = site['organization_id'] as String?;
      final resolved = resolveFormThemeHierarchy(
        site: _themeCandidate(site, 'site'),
        campus: _themeCandidate(parent, 'campus'),
        zone: _themeCandidate(zonesById[zoneId], 'zone'),
        template: _themeCandidate(templatesByCode[templateCode], 'template'),
        organization: _themeCandidate(
          organizationsById[organizationId],
          'organization',
        ),
      );

      for (final row in rows) {
        row['_resolved_form_theme'] = resolved.theme;
        row['_resolved_form_theme_accent'] = resolved.accent;
        row['_form_theme_source'] = resolved.source;
        if (parent != null) {
          row['_parent_form_theme'] = parent['form_theme'];
          row['_parent_form_theme_accent'] = parent['form_theme_accent'];
        }
      }
    }
  }

  Future<List<Inspection>> listInspections({
    String? siteId,
    DateTime? date,
    InspectionStatus? status,
    ReviewStatus? reviewStatus,
    List<ReviewStatus>? reviewStatuses,
  }) async {
    var q = _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type, parent_site_id, zone_id, form_theme, form_theme_accent)',
        );
    if (siteId != null && siteId.isNotEmpty) q = q.eq('site_id', siteId);
    if (date != null) {
      final iso =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      q = q.eq('inspection_date', iso);
    }
    if (status != null) q = q.eq('status', status.dbValue);
    if (reviewStatus != null) {
      q = q.eq('review_status', reviewStatus.dbValue);
    } else if (reviewStatuses != null && reviewStatuses.isNotEmpty) {
      q = q.inFilter(
        'review_status',
        reviewStatuses.map((e) => e.dbValue).toList(),
      );
    }
    final rows = await q.order('inspection_date', ascending: false);
    final maps = [
      for (final row in rows as List) Map<String, dynamic>.from(row as Map),
    ];
    await _attachResolvedThemeData(maps);
    return maps.map(Inspection.fromJson).toList();
  }

  /// Recent inspections for a site (with items) used for overdue streak calc.
  Future<List<Inspection>> listRecentForSite({
    required String siteId,
    required DateTime asOfDate,
    int lookbackDays = 30,
  }) async {
    final from = asOfDate.subtract(Duration(days: lookbackDays));
    final fromIso =
        '${from.year.toString().padLeft(4, '0')}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final toIso =
        '${asOfDate.year.toString().padLeft(4, '0')}-${asOfDate.month.toString().padLeft(2, '0')}-${asOfDate.day.toString().padLeft(2, '0')}';
    final rows = await _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type, parent_site_id, zone_id, form_theme, form_theme_accent)',
        )
        .eq('site_id', siteId)
        .gte('inspection_date', fromIso)
        .lte('inspection_date', toIso)
        .order('inspection_date', ascending: false)
        .order('created_at', ascending: false);
    final maps = [
      for (final row in rows as List) Map<String, dynamic>.from(row as Map),
    ];
    await _attachResolvedThemeData(maps);
    final list = <Inspection>[];
    for (final map in maps) {
      final site = map['sites'] as Map<String, dynamic>?;
      final checklistType =
          (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
          ? site!['checklist_type'] as String
          : 'DEFAULT';
      final items = await listItems(
        map['id'] as String,
        checklistType: checklistType,
      );
      list.add(Inspection.fromJson(map, items: items));
    }
    return list;
  }

  Future<Inspection?> getById(String id) async {
    final row = await _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type, parent_site_id, zone_id, form_theme, form_theme_accent)',
        )
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final map = Map<String, dynamic>.from(row);
    await _attachResolvedThemeData([map]);
    final site = map['sites'] as Map<String, dynamic>?;
    final checklistType =
        (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
        ? site!['checklist_type'] as String
        : 'DEFAULT';
    final items = await listItems(id, checklistType: checklistType);
    return Inspection.fromJson(map, items: items);
  }

  Future<List<InspectionItem>> listItems(
    String inspectionId, {
    String? checklistType,
    bool forceIdealResponse = false,
  }) async {
    final rows = await _client
        .from('checklist_inspection_items')
        .select()
        .eq('inspection_id', inspectionId)
        .order('item_index', ascending: true);
    final items =
        (rows as List)
            .map(
              (e) =>
                  InspectionItem.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList()
          ..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
    _applyCatalogIdeals(
      items,
      checklistType,
      forceIdealResponse: forceIdealResponse,
    );
    return items;
  }

  /// Loads item snapshots for a list screen in one database round-trip.
  ///
  /// The viewer previously called [getById] for every visible inspection,
  /// producing an N+1 request pattern and a noticeable pause on desktop.
  Future<Map<String, List<InspectionItem>>> listItemsForInspections({
    required Iterable<String> inspectionIds,
    Map<String, String> checklistTypeByInspectionId = const {},
  }) async {
    final ids = inspectionIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    final rows = await _client
        .from('checklist_inspection_items')
        .select()
        .inFilter('inspection_id', ids)
        .order('inspection_id')
        .order('item_index');
    final grouped = <String, List<InspectionItem>>{
      for (final id in ids) id: <InspectionItem>[],
    };
    for (final value in rows as List) {
      final row = Map<String, dynamic>.from(value as Map);
      final inspectionId = row['inspection_id'] as String?;
      if (inspectionId == null) continue;
      grouped
          .putIfAbsent(inspectionId, () => <InspectionItem>[])
          .add(InspectionItem.fromJson(row));
    }
    for (final entry in grouped.entries) {
      entry.value.sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
      _applyCatalogIdeals(entry.value, checklistTypeByInspectionId[entry.key]);
    }
    return grouped;
  }

  /// Align stored rows with catalog ideals.
  ///
  /// Catalog `default` is the healthy-state answer:
  /// - most items → Y (blue ✓ under Yes)
  /// - "is there a leak/alarm?" items → N (blue ✓ under No)
  ///
  /// Never fall back to DEFAULT when [checklistType] is null — overlapping
  /// item indexes across lists would assign the wrong ideal column.
  void _applyCatalogIdeals(
    List<InspectionItem> items,
    String? checklistType, {
    bool forceIdealResponse = false,
  }) {
    final type = checklistType?.trim();
    final Map<int, InspectionItem> templates;
    if (type != null && type.isNotEmpty && kChecklistLists.containsKey(type)) {
      templates = {
        for (final t in templateItemsFor(type, 'en')) t.itemIndex: t,
      };
    } else {
      templates = const {};
    }

    for (final item in items) {
      final template = templates[item.itemIndex];
      final sameCatalogText =
          template != null &&
          item.description.trim() == template.description.trim() &&
          ((item.descriptionAr ?? '').trim().isEmpty ||
              (template.descriptionAr ?? '').trim().isEmpty ||
              (item.descriptionAr ?? '').trim() ==
                  (template.descriptionAr ?? '').trim());
      if (template != null && (forceIdealResponse || sameCatalogText)) {
        item.defaultAnswer = template.defaultAnswer.toUpperCase();
        item.localizedDescriptions.addAll(template.localizedDescriptions);
      } else {
        item.defaultAnswer = item.defaultAnswer.toUpperCase();
      }
      // Keep response as stored (may be null) — Yes/No/NA stay empty until answered.
    }
  }

  Future<Inspection?> getForSiteDate({
    required String siteId,
    required DateTime date,
  }) async {
    final iso =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final rows = await _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type, parent_site_id, zone_id, form_theme, form_theme_accent)',
        )
        .eq('site_id', siteId)
        .eq('inspection_date', iso)
        .order('created_at', ascending: false);
    final list = [
      for (final row in rows as List) Map<String, dynamic>.from(row as Map),
    ];
    if (list.isEmpty) return null;
    await _attachResolvedThemeData(list);
    // Prefer an open draft, then most recent submitted/approved.
    Map<String, dynamic> row = list.first;
    for (final r in list) {
      final status =
          (r['review_status'] as String?) ?? (r['status'] as String?);
      if (status == 'draft' || status == 'returned') {
        row = r;
        break;
      }
    }
    final id = row['id'] as String;
    final site = row['sites'] as Map<String, dynamic>?;
    final checklistType =
        (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
        ? site!['checklist_type'] as String
        : 'DEFAULT';
    final items = await listItems(id, checklistType: checklistType);
    return Inspection.fromJson(row, items: items);
  }

  /// Most recent inspection for [siteId] strictly before [beforeDate].
  Future<Inspection?> getPreviousForSite({
    required String siteId,
    required DateTime beforeDate,
  }) async {
    final beforeIso =
        '${beforeDate.year.toString().padLeft(4, '0')}-${beforeDate.month.toString().padLeft(2, '0')}-${beforeDate.day.toString().padLeft(2, '0')}';
    final row = await _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type, parent_site_id, zone_id, form_theme, form_theme_accent)',
        )
        .eq('site_id', siteId)
        .lt('inspection_date', beforeIso)
        .order('inspection_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final map = Map<String, dynamic>.from(row);
    await _attachResolvedThemeData([map]);
    final site = map['sites'] as Map<String, dynamic>?;
    final checklistType =
        (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
        ? site!['checklist_type'] as String
        : 'DEFAULT';
    final items = await listItems(
      map['id'] as String,
      checklistType: checklistType,
    );
    return Inspection.fromJson(map, items: items);
  }

  /// Latest inspection for [siteId] other than [excludeInspectionId]
  /// (includes same calendar day — used to carry open WOs into a new list).
  Future<Inspection?> getLatestOtherForSite({
    required String siteId,
    required String excludeInspectionId,
  }) async {
    final row = await _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type, parent_site_id, zone_id, form_theme, form_theme_accent)',
        )
        .eq('site_id', siteId)
        .neq('id', excludeInspectionId)
        .order('inspection_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final map = Map<String, dynamic>.from(row);
    await _attachResolvedThemeData([map]);
    final site = map['sites'] as Map<String, dynamic>?;
    final checklistType =
        (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
        ? site!['checklist_type'] as String
        : 'DEFAULT';
    final items = await listItems(
      map['id'] as String,
      checklistType: checklistType,
    );
    return Inspection.fromJson(map, items: items);
  }

  List<InspectionItem> templateItemsFor(String checklistType, String language) {
    // Sync fallback for callers that cannot await; prefer resolveItemsForSite.
    final key = checklistType.isEmpty ? 'DEFAULT' : checklistType;
    final list = kChecklistLists[key] ?? kChecklistLists['DEFAULT'] ?? const [];
    return [
      for (final raw in list)
        InspectionItem(
          itemIndex: raw['id'] as int,
          description: (raw['en'] ?? '') as String,
          descriptionAr: raw['ar'] as String?,
          localizedDescriptions: {
            for (final code in const ['bn', 'hi', 'ml', 'tl', 'ta'])
              if ((raw[code] as String?)?.trim().isNotEmpty == true)
                code: (raw[code] as String).trim(),
          },
          defaultAnswer: '${raw['default'] ?? 'Y'}',
          response: null,
          overdueAfterDays: (raw['overdue_days'] as num?)?.toInt() ?? 3,
        ),
    ];
  }

  Future<List<InspectionItem>> resolveItemsForSite({
    required ChecklistSite site,
    String language = 'en',
  }) {
    return _catalog.resolveItemsForSite(
      checklistType: site.checklistType,
      siteId: site.id,
      language: language,
    );
  }

  Future<Inspection> createDraft({
    required ChecklistSite site,
    required DateTime date,
    required String inspectorName,
    required String inspectionTime,
    String floorLabel = 'ALL',
    String language = 'en',
    String? clientReference,
    String? reinspectionReason,
  }) async {
    final iso =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final params = {
      'p_site_id': site.id,
      'p_inspection_date': iso,
      'p_inspector_name': inspectorName,
      'p_inspection_time': inspectionTime,
      'p_floor_label': floorLabel,
      // Migration 020 resolves immutable item metadata from the
      // server catalog. Keep this parameter for RPC compatibility.
      'p_items': const <Map<String, dynamic>>[],
      'p_client_reference': clientReference,
      'p_reinspection_reason': ?reinspectionReason,
    };
    final inspectionId =
        await _client.rpc(
              reinspectionReason == null
                  ? 'create_checklist_inspection_draft'
                  : 'create_checklist_reinspection_draft',
              params: params,
            )
            as String;
    return (await getById(inspectionId))!;
  }

  Future<void> saveItems(Inspection inspection) async {
    final nextVersion = await _client.rpc(
      'save_checklist_inspection',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
        'p_header': {
          'inspector_name': inspection.inspectorName,
          'inspection_time': inspection.inspectionTime,
          'floor_label': inspection.floorLabel,
          'signature_path': inspection.signaturePath,
        },
        'p_items': [for (final item in inspection.items) item.toRpcJson()],
      },
    );
    inspection.version = (nextVersion as num).toInt();
  }

  Future<void> deleteInspectionItem(
    Inspection inspection,
    String itemId,
  ) async {
    final nextVersion = await _client.rpc(
      'delete_checklist_inspection_item',
      params: {'p_item_id': itemId, 'p_expected_version': inspection.version},
    );
    inspection.version = (nextVersion as num).toInt();
  }

  Future<void> submit(Inspection inspection) async {
    final nextVersion = await _client.rpc(
      'submit_checklist_inspection',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
      },
    );
    inspection.version = (nextVersion as num).toInt();
  }

  Future<void> approveInspection(Inspection inspection) async {
    final nextVersion = await _client.rpc(
      'admin_approve_inspection',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
      },
    );
    inspection.version = (nextVersion as num).toInt();
  }

  Future<void> returnInspection({
    required Inspection inspection,
    required String reason,
  }) async {
    final nextVersion = await _client.rpc(
      'manager_return_checklist_inspection',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
        'p_reason': reason,
      },
    );
    inspection.version = (nextVersion as num).toInt();
  }

  Future<void> rejectInspection({
    required Inspection inspection,
    required String reason,
  }) async {
    final nextVersion = await _client.rpc(
      'manager_reject_checklist_inspection',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
        'p_reason': reason,
      },
    );
    inspection.version = (nextVersion as num).toInt();
  }

  Future<void> cancelInspectionAsOwner({
    required Inspection inspection,
    required String reason,
  }) async {
    final nextVersion = await _client.rpc(
      'owner_cancel_checklist_inspection',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
        'p_reason': reason,
      },
    );
    inspection.version = (nextVersion as num).toInt();
  }

  /// Corrects a draft/submitted inspection date through the owner-only RPC.
  /// The caller should reload the inspection afterward because its date field
  /// is immutable in the local model by design.
  Future<int> changeInspectionDateAsOwner({
    required Inspection inspection,
    required DateTime newDate,
    required String reason,
  }) async {
    final iso =
        '${newDate.year.toString().padLeft(4, '0')}-'
        '${newDate.month.toString().padLeft(2, '0')}-'
        '${newDate.day.toString().padLeft(2, '0')}';
    final nextVersion = await _client.rpc(
      'owner_change_inspection_date',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
        'p_new_date': iso,
        'p_reason': reason,
      },
    );
    inspection.version = (nextVersion as num).toInt();
    return inspection.version;
  }

  Future<List<Inspection>> listPendingReview({String? siteId}) async {
    var q = _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type, parent_site_id, zone_id, form_theme, form_theme_accent)',
        );
    q = q.eq('review_status', ReviewStatus.submitted.dbValue);
    if (siteId != null && siteId.isNotEmpty) q = q.eq('site_id', siteId);
    final rows = await q.order('inspection_date', ascending: false);
    final maps = [
      for (final row in rows as List) Map<String, dynamic>.from(row as Map),
    ];
    await _attachResolvedThemeData(maps);
    final list = <Inspection>[];
    for (final map in maps) {
      final id = map['id'] as String;
      final items = await listItems(id);
      list.add(Inspection.fromJson(map, items: items));
    }
    return list;
  }

  Future<void> deleteInspection(Inspection inspection) async {
    final result = await _client.rpc(
      'delete_checklist_inspection_with_cleanup',
      params: {
        'p_inspection_id': inspection.id,
        'p_expected_version': inspection.version,
      },
    );

    final paths = <String>{
      if (result is List)
        for (final path in result)
          if (path != null) storagePathOf('$path'),
      if ((inspection.signaturePath ?? '').isNotEmpty)
        storagePathOf(inspection.signaturePath!),
      for (final item in inspection.items)
        for (final photo in item.remarkPhotos) storagePathOf(photo.path),
    }..removeWhere((path) => path.isEmpty);
    try {
      await _completeMediaCleanup(paths);
    } catch (error) {
      throw StateError(
        'Inspection was deleted, but its protected media cleanup is pending: '
        '$error',
      );
    }
  }

  Future<void> _completeMediaCleanup(Iterable<String> rawPaths) async {
    final paths = rawPaths
        .map(storagePathOf)
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList();
    if (paths.isEmpty) return;
    await _client.storage.from(bucket).remove(paths);
    await _client.rpc(
      'complete_checklist_media_cleanup',
      params: {'p_paths': paths},
    );
    for (final path in paths) {
      _downloadByteFutures.remove(path);
      _signedUrlFutures.remove(path);
    }
  }

  /// Finishes protected object cleanup after a previous network interruption.
  /// The server returns only short-lived paths requested by the current user.
  Future<int> retryPendingMediaCleanup() async {
    final result = await _client.rpc('list_my_pending_checklist_media_cleanup');
    final paths = <String>{
      if (result is List)
        for (final value in result)
          if (value != null) storagePathOf('$value'),
    }..removeWhere((path) => path.isEmpty);
    await _completeMediaCleanup(paths);
    return paths.length;
  }

  String _contentAddressedFileName(String fileName, String contentHash) {
    final slash = fileName.lastIndexOf('/');
    final directory = slash < 0 ? '' : fileName.substring(0, slash + 1);
    final name = slash < 0 ? fileName : fileName.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final extension = dot <= 0 ? '' : name.substring(dot);
    return '$directory${stem}_${contentHash.substring(0, 16)}$extension';
  }

  bool _isDuplicateObjectError(Object error) {
    final value = '$error'.toLowerCase();
    return value.contains('already exists') ||
        value.contains('duplicate') ||
        value.contains('statuscode: 409') ||
        value.contains('status code: 409');
  }

  Future<String> uploadBytes({
    required String organizationId,
    required String siteId,
    required String inspectionId,
    required String fileName,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    String? evidenceItemId,
    String? evidenceKind,
  }) async {
    final contentHash = sha256.convert(bytes).toString();
    final immutableName = _contentAddressedFileName(fileName, contentHash);
    final path = '$organizationId/$siteId/$inspectionId/$immutableName';
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } catch (error) {
      if (!_isDuplicateObjectError(error)) rethrow;
      final existing = await _client.storage.from(bucket).download(path);
      if (sha256.convert(existing).toString() != contentHash) {
        throw StateError(
          'Immutable media path already contains different bytes: $path',
        );
      }
    }
    if (evidenceKind != null && evidenceKind.isNotEmpty) {
      try {
        await _client.rpc(
          'register_checklist_media_evidence',
          params: {
            'p_inspection_id': inspectionId,
            'p_item_id': evidenceItemId,
            'p_storage_path': path,
            'p_media_kind': evidenceKind,
          },
        );
      } catch (_) {
        // Do not leave evidence in storage without its authoritative metadata
        // relationship. A retry can safely upload the same deterministic path.
        try {
          await _client.storage.from(bucket).remove([path]);
        } catch (_) {}
        rethrow;
      }
    }
    _downloadByteFutures.remove(path);
    _signedUrlFutures.remove(path);
    return path;
  }

  Future<void> deleteMedia(String path) async {
    final storagePath = storagePathOf(path);
    if (storagePath.isEmpty || storagePath.startsWith('offline://')) return;
    await _client.storage.from(bucket).remove([storagePath]);
    _downloadByteFutures.remove(storagePath);
    clearSignedUrlCache();
  }

  final Map<String, ({Future<String?> future, DateTime expiresAt})>
  _signedUrlFutures = {};

  Future<String?> signedUrl(String path, {int expiresIn = 3600}) {
    final storagePath = storagePathOf(path);
    if (storagePath.isEmpty || storagePath.startsWith('offline://')) {
      return Future.value(null);
    }
    final hit = _signedUrlFutures[storagePath];
    if (hit != null && hit.expiresAt.isAfter(DateTime.now())) {
      return hit.future;
    }
    final keepFor = Duration(seconds: math.max(60, expiresIn - 120));
    late final Future<String?> future;
    future = () async {
      try {
        return await _client.storage
            .from(bucket)
            .createSignedUrl(storagePath, expiresIn);
      } catch (_) {
        // A transient network/RLS failure must not hide media for the full
        // cache lifetime. Let the next frame/reload retry immediately.
        if (_signedUrlFutures[storagePath]?.future == future) {
          _signedUrlFutures.remove(storagePath);
        }
        return null;
      }
    }();
    _signedUrlFutures[storagePath] = (
      future: future,
      expiresAt: DateTime.now().add(keepFor),
    );
    return future;
  }

  void clearSignedUrlCache() => _signedUrlFutures.clear();

  final Map<String, ({Future<Uint8List?> future, DateTime expiresAt})>
  _downloadByteFutures = {};

  Future<Uint8List?> downloadBytes(String path, {bool forceRefresh = false}) {
    final storagePath = storagePathOf(path);
    if (storagePath.isEmpty || storagePath.startsWith('offline://')) {
      return Future.value(null);
    }
    if (forceRefresh) _downloadByteFutures.remove(storagePath);
    final hit = _downloadByteFutures[storagePath];
    if (hit != null && hit.expiresAt.isAfter(DateTime.now())) {
      return hit.future;
    }
    late final Future<Uint8List?> future;
    future = () async {
      try {
        return await _client.storage.from(bucket).download(storagePath);
      } catch (_) {
        if (_downloadByteFutures[storagePath]?.future == future) {
          _downloadByteFutures.remove(storagePath);
        }
        return null;
      }
    }();
    _downloadByteFutures[storagePath] = (
      future: future,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    return future;
  }
}
