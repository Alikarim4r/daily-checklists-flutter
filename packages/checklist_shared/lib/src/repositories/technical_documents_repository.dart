import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/technical_documents.dart';

/// All P3 writes are tenant-scoped, audited server RPCs.
/// The client has SELECT only on document/version/evidence tables.
class TechnicalDocumentsRepository {
  const TechnicalDocumentsRepository(this._client);
  final SupabaseClient _client;

  Future<List<TechnicalDocument>> listDocuments(
    String orgId, {
    String? kind,
    String? status,
    int limit = 500,
  }) async {
    var q = _client
        .from('technical_documents')
        .select()
        .eq('organization_id', orgId);
    if (kind != null && kind != 'all') q = q.eq('document_kind', kind);
    if (status != null && status != 'all') q = q.eq('status', status);
    final rows = await q
        .order('updated_at', ascending: false)
        .limit(limit.clamp(1, 1000));
    return [
      for (final row in rows)
        TechnicalDocument.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<List<TechnicalVersion>> versions(String docId) async {
    final rows = await _client
        .from('technical_document_versions')
        .select()
        .eq('document_id', docId)
        .order('version_no', ascending: false);
    return [
      for (final row in rows)
        TechnicalVersion.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<List<TechnicalDecision>> decisions(String docId) async {
    final rows = await _client
        .from('technical_document_decisions')
        .select()
        .eq('document_id', docId)
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        TechnicalDecision.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<List<Map<String, dynamic>>> links(String docId) async {
    final rows = await _client
        .from('technical_document_links')
        .select()
        .eq('source_id', docId);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> permits(String orgId) async {
    final rows = await _client
        .from('technical_permit_issues')
        .select()
        .eq('organization_id', orgId)
        .order('issued_at', ascending: false);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> permitEvents(String permitId) async {
    final rows = await _client
        .from('technical_permit_events')
        .select()
        .eq('permit_id', permitId)
        .order('happened_at', ascending: false);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> itpResults(String docId) async {
    final rows = await _client
        .from('technical_itp_results')
        .select()
        .eq('document_id', docId)
        .order('signed_at', ascending: false);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> ncrClosures(String docId) async {
    final rows = await _client
        .from('technical_ncr_closures')
        .select()
        .eq('document_id', docId);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<String> create({
    required String organizationId,
    required String kind,
    required String code,
    required String title,
    String? siteId,
    String? assetId,
    String? ppmJobId,
    String? country,
    String? standard,
    String? edition,
    String language = 'en',
  }) async {
    final result = await _client.rpc(
      'technical_create_document',
      params: {
        'p_org': organizationId,
        'p_kind': kind,
        'p_code': code.trim(),
        'p_title': title.trim(),
        'p_site': siteId,
        'p_asset': assetId,
        'p_job': ppmJobId,
        'p_country': country,
        'p_standard': standard,
        'p_edition': edition,
        'p_language': language,
      },
    );
    return result as String;
  }

  Future<int> saveVersion(
    String docId,
    Map<String, dynamic> payload, {
    String changeNote = '',
  }) async {
    final result = await _client.rpc(
      'technical_save_revision',
      params: {
        'p_document': docId,
        'p_content': payload,
        'p_change_note': changeNote,
      },
    );
    return (result as num).toInt();
  }

  Future<void> submit(String id) async {
    await _client.rpc('technical_submit_review', params: {'p_document': id});
  }

  Future<void> decide(
    String id, {
    required bool approve,
    String? remarks,
  }) async {
    await _client.rpc(
      'technical_decide_review',
      params: {'p_document': id, 'p_approve': approve, 'p_remarks': remarks},
    );
  }

  Future<void> link(
    String source,
    String target, {
    String relation = 'related',
  }) async {
    await _client.rpc(
      'technical_link_document',
      params: {
        'p_source': source,
        'p_target': target,
        'p_relationship': relation,
      },
    );
  }

  Future<String> issuePermit({
    required String ptwId,
    required String raId,
    required DateTime from,
    required DateTime until,
  }) async =>
      (await _client.rpc(
            'technical_issue_permit',
            params: {
              'p_ptw': ptwId,
              'p_ra': raId,
              'p_from': from.toUtc().toIso8601String(),
              'p_until': until.toUtc().toIso8601String(),
            },
          ))
          as String;
  Future<void> transitionPermit(
    String permitId,
    String action, {
    String? note,
  }) async {
    await _client.rpc(
      'technical_transition_permit',
      params: {'p_permit': permitId, 'p_action': action, 'p_note': note},
    );
  }

  Future<String> signItp({
    required String docId,
    required String checkpoint,
    required String result,
    required String evidenceNote,
    String? inspectionId,
  }) async =>
      (await _client.rpc(
            'technical_sign_itp',
            params: {
              'p_document': docId,
              'p_checkpoint': checkpoint,
              'p_result': result,
              'p_note': evidenceNote,
              'p_inspection': inspectionId,
            },
          ))
          as String;
  Future<void> supersede(
    String oldId,
    String replacementId,
    String reason,
  ) async {
    await _client.rpc(
      'technical_supersede_document',
      params: {
        'p_old': oldId,
        'p_new': replacementId,
        'p_reason': reason.trim(),
      },
    );
  }

  Future<void> closeNcr({
    required String docId,
    required String disposition,
    required String verification,
    String? inspectionId,
  }) async {
    await _client.rpc(
      'technical_close_ncr',
      params: {
        'p_document': docId,
        'p_disposition': disposition,
        'p_notes': verification,
        'p_inspection': inspectionId,
      },
    );
  }
}
