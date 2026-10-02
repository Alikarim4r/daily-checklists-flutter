import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subscription.dart';

class SubscriptionRepository {
  SubscriptionRepository(this._client);
  final SupabaseClient _client;

  Future<OrganizationSubscription?> getForOrganization(
    String organizationId,
  ) async {
    final response = await _client.rpc(
      'subscription_access_state',
      params: {'p_organization_id': organizationId},
    );
    final rows = response as List? ?? const [];
    if (rows.isEmpty) return null;
    return OrganizationSubscription.fromRpc(
      organizationId,
      Map<String, dynamic>.from(rows.first as Map),
    );
  }
}
