import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/checklist_lists.dart';
import '../models/enums.dart';
import '../models/inspection.dart';
import '../models/profile.dart';

class InspectionRepository {
  InspectionRepository(this._client);

  final SupabaseClient _client;
  static const bucket = 'checklist-media';

  Future<List<Inspection>> listInspections({
    String? siteId,
    DateTime? date,
    InspectionStatus? status,
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
    final rows = await q.order('inspection_date', ascending: false);
    return (rows as List)
        .map((e) => Inspection.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Inspection?> getById(String id) async {
    final row = await _client
        .from('checklist_inspections')
        .select('*, sites(name_en, name_ar, pin, organization_id)')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final items = await listItems(id);
    return Inspection.fromJson(
      Map<String, dynamic>.from(row),
      items: items,
    );
  }

  Future<List<InspectionItem>> listItems(String inspectionId) async {
    final rows = await _client
        .from('checklist_inspection_items')
        .select()
        .eq('inspection_id', inspectionId)
        .order('item_index');
    return (rows as List)
        .map(
          (e) => InspectionItem.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<Inspection?> getForSiteDate({
    required String siteId,
    required DateTime date,
  }) async {
    final iso =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final row = await _client
        .from('checklist_inspections')
        .select('*, sites(name_en, name_ar, pin, organization_id)')
        .eq('site_id', siteId)
        .eq('inspection_date', iso)
        .maybeSingle();
    if (row == null) return null;
    final id = row['id'] as String;
    final items = await listItems(id);
    return Inspection.fromJson(Map<String, dynamic>.from(row), items: items);
  }

  List<InspectionItem> templateItemsFor(String checklistType, String language) {
    final key = checklistType.isEmpty ? 'DEFAULT' : checklistType;
    final list = kChecklistLists[key] ?? kChecklistLists['DEFAULT'] ?? const [];
    return [
      for (final raw in list)
        InspectionItem(
          itemIndex: raw['id'] as int,
          description: (raw['en'] ?? '') as String,
          descriptionAr: raw['ar'] as String?,
          defaultAnswer: '${raw['default'] ?? 'Y'}',
          // Start empty like HTML — technician must answer.
          response: null,
        ),
    ];
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
        })
        .select('*, sites(name_en, name_ar, pin, organization_id)')
        .single();

    final inspectionId = inserted['id'] as String;
    final items = templateItemsFor(site.checklistType, language);
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

  Future<void> submit(String inspectionId) async {
    final userId = _client.auth.currentUser?.id;
    await _client.from('checklist_inspections').update({
      'status': InspectionStatus.submitted.dbValue,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'submitted_by': userId,
    }).eq('id', inspectionId);
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

  Future<String?> signedUrl(String path, {int expiresIn = 3600}) async {
    try {
      return await _client.storage.from(bucket).createSignedUrl(path, expiresIn);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> downloadBytes(String path) async {
    try {
      return await _client.storage.from(bucket).download(path);
    } catch (_) {
      return null;
    }
  }
}
