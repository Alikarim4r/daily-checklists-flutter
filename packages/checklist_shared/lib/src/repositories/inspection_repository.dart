import 'dart:math' as math;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/checklist_lists.dart';
import '../models/enums.dart';
import '../models/inspection.dart';
import '../models/profile.dart';
import '../utils/storage_path_list.dart';
import 'catalog_repository.dart';

class InspectionRepository {
  InspectionRepository(this._client);

  final SupabaseClient _client;
  static const bucket = 'checklist-media';

  ChecklistCatalogRepository get _catalog => ChecklistCatalogRepository(_client);

  Future<List<Inspection>> listInspections({
    String? siteId,
    DateTime? date,
    InspectionStatus? status,
    ReviewStatus? reviewStatus,
    List<ReviewStatus>? reviewStatuses,
  }) async {
    var q = _client.from('checklist_inspections').select(
          '*, sites(name_en, name_ar, pin, organization_id)',
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
    return (rows as List)
        .map((e) => Inspection.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
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
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type)',
        )
        .eq('site_id', siteId)
        .gte('inspection_date', fromIso)
        .lte('inspection_date', toIso)
        .order('inspection_date', ascending: false);
    final list = <Inspection>[];
    for (final e in rows as List) {
      final map = Map<String, dynamic>.from(e as Map);
      final site = map['sites'] as Map<String, dynamic>?;
      final checklistType =
          (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
              ? site!['checklist_type'] as String
              : 'DEFAULT';
      final items = await listItems(map['id'] as String,
          checklistType: checklistType);
      list.add(Inspection.fromJson(map, items: items));
    }
    return list;
  }

  Future<Inspection?> getById(String id) async {
    final row = await _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type)',
        )
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final site = row['sites'] as Map<String, dynamic>?;
    final checklistType =
        (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
            ? site!['checklist_type'] as String
            : 'DEFAULT';
    final items = await listItems(id, checklistType: checklistType);
    return Inspection.fromJson(
      Map<String, dynamic>.from(row),
      items: items,
    );
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
    final items = (rows as List)
        .map(
          (e) => InspectionItem.fromJson(Map<String, dynamic>.from(e as Map)),
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
    if (type != null &&
        type.isNotEmpty &&
        kChecklistLists.containsKey(type)) {
      templates = {
        for (final t in templateItemsFor(type, 'en')) t.itemIndex: t,
      };
    } else {
      templates = const {};
    }

    for (final item in items) {
      final template = templates[item.itemIndex];
      if (template != null) {
        item.defaultAnswer = template.defaultAnswer.toUpperCase();
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
    final row = await _client
        .from('checklist_inspections')
        .select(
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type)',
        )
        .eq('site_id', siteId)
        .eq('inspection_date', iso)
        .maybeSingle();
    if (row == null) return null;
    final id = row['id'] as String;
    final site = row['sites'] as Map<String, dynamic>?;
    final checklistType =
        (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
            ? site!['checklist_type'] as String
            : 'DEFAULT';
    final items = await listItems(id, checklistType: checklistType);
    return Inspection.fromJson(Map<String, dynamic>.from(row), items: items);
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
          '*, sites(name_en, name_ar, pin, organization_id, checklist_type)',
        )
        .eq('site_id', siteId)
        .lt('inspection_date', beforeIso)
        .order('inspection_date', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final site = row['sites'] as Map<String, dynamic>?;
    final checklistType =
        (site?['checklist_type'] as String?)?.trim().isNotEmpty == true
            ? site!['checklist_type'] as String
            : 'DEFAULT';
    final items =
        await listItems(row['id'] as String, checklistType: checklistType);
    return Inspection.fromJson(Map<String, dynamic>.from(row), items: items);
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
          defaultAnswer: '${raw['default'] ?? 'Y'}',
          response: null,
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
  }) async {
    final userId = _client.auth.currentUser?.id;
    final iso =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final inserted = await _client
        .from('checklist_inspections')
        .insert({
          'site_id': site.id,
          'building_code': site.buildingCode,
          'inspection_date': iso,
          'inspection_time': inspectionTime,
          'floor_label': floorLabel,
          'location_label': site.location,
          'inspector_name': inspectorName,
          'inspector_user_id': userId,
          'status': InspectionStatus.draft.dbValue,
          'review_status': ReviewStatus.draft.dbValue,
        })
        .select('*, sites(name_en, name_ar, pin, organization_id)')
        .single();

    final inspectionId = inserted['id'] as String;
    final items = await resolveItemsForSite(site: site, language: language);
    if (items.isNotEmpty) {
      await _client.from('checklist_inspection_items').insert([
        for (final item in items) item.toInsertJson(inspectionId),
      ]);
    }
    return (await getById(inspectionId))!;
  }

  Future<void> saveItems(Inspection inspection) async {
    for (final item in inspection.items) {
      if (item.id == null) {
        await _client
            .from('checklist_inspection_items')
            .insert(item.toInsertJson(inspection.id));
      } else {
        await _client
            .from('checklist_inspection_items')
            .update(item.toUpdateJson())
            .eq('id', item.id!);
      }
    }
    await _client.from('checklist_inspections').update({
      'inspector_name': inspection.inspectorName,
      'inspection_time': inspection.inspectionTime,
      'floor_label': inspection.floorLabel,
      'signature_path': inspection.signaturePath,
    }).eq('id', inspection.id);
  }

  Future<void> deleteInspectionItem(String itemId) async {
    await _client
        .from('checklist_inspection_items')
        .delete()
        .eq('id', itemId);
  }

  Future<void> submit(String inspectionId) async {
    final userId = _client.auth.currentUser?.id;
    await _client.from('checklist_inspections').update({
      'status': InspectionStatus.submitted.dbValue,
      'review_status': ReviewStatus.submitted.dbValue,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'submitted_by': userId,
    }).eq('id', inspectionId);
  }

  Future<void> approveInspection(String inspectionId) async {
    await _client.rpc(
      'admin_approve_inspection',
      params: {'p_inspection_id': inspectionId},
    );
  }

  Future<List<Inspection>> listPendingReview({String? siteId}) async {
    var q = _client.from('checklist_inspections').select(
          '*, sites(name_en, name_ar, pin, organization_id)',
        );
    q = q.eq('review_status', ReviewStatus.submitted.dbValue);
    if (siteId != null && siteId.isNotEmpty) q = q.eq('site_id', siteId);
    final rows = await q.order('inspection_date', ascending: false);
    final list = <Inspection>[];
    for (final e in rows as List) {
      final map = Map<String, dynamic>.from(e as Map);
      final id = map['id'] as String;
      final items = await listItems(id);
      list.add(Inspection.fromJson(map, items: items));
    }
    return list;
  }

  Future<void> deleteInspection(String id) async {
    await _client.from('checklist_inspections').delete().eq('id', id);
  }

  Future<String> uploadBytes({
    required String organizationId,
    required String siteId,
    required String inspectionId,
    required String fileName,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final path = '$organizationId/$siteId/$inspectionId/$fileName';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  final Map<String, ({Future<String?> future, DateTime expiresAt})>
      _signedUrlFutures = {};

  Future<String?> signedUrl(String path, {int expiresIn = 3600}) {
    final storagePath = storagePathOf(path);
    final hit = _signedUrlFutures[storagePath];
    if (hit != null && hit.expiresAt.isAfter(DateTime.now())) {
      return hit.future;
    }
    final keepFor = Duration(seconds: math.max(60, expiresIn - 120));
    final future = () async {
      try {
        return await _client.storage
            .from(bucket)
            .createSignedUrl(storagePath, expiresIn);
      } catch (_) {
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

  Future<Uint8List?> downloadBytes(String path) async {
    try {
      return await _client.storage.from(bucket).download(storagePathOf(path));
    } catch (_) {
      return null;
    }
  }
}
