import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog.dart';

class PolicyRepository {
  PolicyRepository(this._client);
  final SupabaseClient _client;

  Future<ChecklistOrgPolicy?> getForOrganization(String organizationId) async {
    final row = await _client
        .from('checklist_org_policies')
        .select()
        .eq('organization_id', organizationId)
        .maybeSingle();
    if (row == null) return null;
    return ChecklistOrgPolicy.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ChecklistOrgPolicy> upsert(ChecklistOrgPolicy policy) async {
    final row = await _client
        .from('checklist_org_policies')
        .upsert(policy.toUpsertJson(), onConflict: 'organization_id')
        .select()
        .single();
    return ChecklistOrgPolicy.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ChecklistOrgPolicy> getOrCreate(String organizationId) async {
    final existing = await getForOrganization(organizationId);
    if (existing != null) return existing;
    return upsert(ChecklistOrgPolicy(organizationId: organizationId));
  }
}
