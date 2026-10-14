import 'package:supabase_flutter/supabase_flutter.dart';

/// A taxonomy term is owned by exactly one organization. Only authorized
/// managers may enumerate unassigned terms; viewers get authorized leaf labels.
class ChecklistFilterTerm {
  const ChecklistFilterTerm({
    required this.id,
    required this.organizationId,
    required this.dimension,
    required this.code,
    required this.nameEn,
    required this.nameAr,
    required this.active,
    this.parentId,
  });
  final String id, organizationId, dimension, code, nameEn, nameAr;
  final String? parentId;
  final bool active;
  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;
  factory ChecklistFilterTerm.fromJson(Map<String, dynamic> j) =>
      ChecklistFilterTerm(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        dimension: j['dimension'] as String,
        code: j['code'] as String,
        nameEn: j['name_en'] as String,
        nameAr: j['name_ar'] as String,
        parentId: j['parent_id'] as String?,
        active: j['is_active'] as bool? ?? true,
      );
}

class ChecklistFilterRepository {
  const ChecklistFilterRepository(this._client);
  final SupabaseClient _client;

  Future<List<ChecklistFilterTerm>> listTerms(String organizationId) async {
    final result = await _client.rpc(
      'list_org_checklist_filter_terms',
      params: {'p_org': organizationId},
    );
    return [
      for (final row in result as List)
        ChecklistFilterTerm.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<String> addTerm({
    required String organizationId,
    required String dimension,
    required String code,
    required String nameEn,
    required String nameAr,
    String? parentId,
  }) async {
    return (await _client.rpc(
          'manage_checklist_filter_term',
          params: {
            'p_org': organizationId,
            'p_dimension': dimension,
            'p_parent': parentId,
            'p_code': code,
            'p_name_en': nameEn,
            'p_name_ar': nameAr,
            'p_archive_id': null,
          },
        ))
        as String;
  }

  Future<void> archiveTerm(ChecklistFilterTerm term) async {
    await _client.rpc(
      'manage_checklist_filter_term',
      params: {
        'p_org': term.organizationId,
        'p_dimension': term.dimension,
        'p_parent': term.parentId,
        'p_code': term.code,
        'p_name_en': term.nameEn,
        'p_name_ar': term.nameAr,
        'p_archive_id': term.id,
      },
    );
  }

  Future<void> assign({
    required String assignmentId,
    required String sectorId,
    required String serviceClassId,
    required String departmentId,
    required String coverageId,
    required String documentKindId,
  }) async {
    await _client.rpc(
      'set_checklist_assignment_facets',
      params: {
        'p_assignment': assignmentId,
        'p_sector': sectorId,
        'p_service_class': serviceClassId,
        'p_department': departmentId,
        'p_coverage': coverageId,
        'p_document_kind': documentKindId,
      },
    );
  }
}
