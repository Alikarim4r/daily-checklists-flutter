import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/checklist_library.dart';

class ChecklistLibraryRepository {
  ChecklistLibraryRepository(this._client);

  final SupabaseClient _client;

  Future<List<ChecklistLibraryTemplate>> listTemplates({
    required String organizationId,
  }) async {
    final response = await _client.rpc(
      'list_checklist_library',
      params: {'p_organization_id': organizationId},
    );
    if (response is! List) return const [];
    return [
      for (final row in response)
        ChecklistLibraryTemplate.fromJson(
          Map<String, dynamic>.from(row as Map),
        ),
    ];
  }

  /// New, scoped and paginated Global Library 2.0 API. The old catalog RPC
  /// remains available for installed clients and for pre-migration fallback.
  Future<List<ChecklistLibraryTemplate>> listGlobalTemplatesV2({
    required String organizationId,
    String? industry,
    String? domain,
    String? documentKind,
    String? category,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _client.rpc(
      'list_global_library_v2',
      params: {
        'p_organization_id': organizationId,
        'p_sector': industry,
        'p_domain': domain,
        'p_kind': documentKind,
        'p_category': category,
        'p_search': search?.trim(),
        'p_limit': limit.clamp(1, 100),
        'p_offset': offset < 0 ? 0 : offset,
      },
    );
    if (response is! List) {
      throw StateError('invalid_global_library_response');
    }
    return [
      for (final row in response)
        ChecklistLibraryTemplate.fromJson(
          Map<String, dynamic>.from(row as Map),
        ),
    ];
  }

  Future<Map<String, List<GlobalLibraryFacet>>> listGlobalFacetsV2({
    required String organizationId,
  }) async {
    final response = await _client.rpc(
      'list_global_library_facets_v2',
      params: {'p_organization_id': organizationId},
    );
    if (response is! List) throw StateError('invalid_library_facets_response');
    final facets = <String, List<GlobalLibraryFacet>>{
      'industry': [],
      'domain': [],
      'subdomain': [],
      'category': [],
    };
    for (final row in response) {
      final json = Map<String, dynamic>.from(row as Map);
      final dimension = json['dimension'] as String?;
      if (dimension != null && facets.containsKey(dimension)) {
        facets[dimension]!.add(GlobalLibraryFacet.fromJson(json));
      }
    }
    return facets;
  }

  /// Read-only taxonomy dictionary; table RLS requires an approved user.
  Future<Map<String, List<GlobalLibraryFacet>>>
  listGlobalTaxonomyTerms() async {
    final result = await _client
        .from('library_taxonomy_terms')
        .select('dimension,slug,name_en,name_ar')
        .eq('is_active', true)
        .order('sort_order');
    final grouped = <String, List<GlobalLibraryFacet>>{
      'industry': [],
      'domain': [],
      'subdomain': [],
    };
    for (final item in result) {
      final dimension = item['dimension'] as String?;
      if (dimension == null || !grouped.containsKey(dimension)) continue;
      grouped[dimension]!.add(GlobalLibraryFacet.fromJson(item));
    }
    return grouped;
  }

  Future<void> assignGlobalTaxonomyV2({
    required String templateId,
    required List<String> industries,
    required List<String> domains,
  }) async {
    await _client.rpc(
      'assign_global_library_taxonomy_v2',
      params: {
        'p_template_id': templateId,
        'p_industries': industries,
        'p_domains': domains,
      },
    );
  }

  /// Undefined V2 RPC is the only reason to fall back. A permission error
  /// must NEVER trigger a less restrictive API.
  static bool isGlobalApiNotInstalled(Object error) =>
      error is PostgrestException &&
      (error.code == 'PGRST202' || error.code == '42883');

  Future<String> installTemplate({
    required String libraryTemplateId,
    required String organizationId,
  }) async {
    final response = await _client.rpc(
      'install_checklist_library_template',
      params: {
        'p_library_template_id': libraryTemplateId,
        'p_organization_id': organizationId,
      },
    );
    if (response is! String || response.isEmpty) {
      throw StateError('library_install_failed');
    }
    return response;
  }

  Future<Map<String, dynamic>> verifyGooglePlayPurchase({
    required String productId,
    required String purchaseToken,
    required String packageName,
    required String organizationId,
  }) async {
    final response = await _client.functions.invoke(
      'verify-google-play-library-purchase',
      body: {
        'product_id': productId,
        'purchase_token': purchaseToken,
        'package_name': packageName,
        'organization_id': organizationId,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('library_purchase_verification_failed');
    }
    if (response.data is! Map) {
      throw StateError('library_purchase_verification_invalid');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
