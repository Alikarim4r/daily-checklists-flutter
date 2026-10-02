import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subscription.dart';
import '../models/subscription_plan.dart';

class SubscriptionRepository {
  SubscriptionRepository(this._client);
  final SupabaseClient _client;

  Future<List<SubscriptionPlanCatalogItem>> listPlans() async {
    final rows = await _client
        .from('subscription_plan_catalog')
        .select()
        .eq('is_public', true)
        .order('display_order');
    return [
      for (final row in rows as List)
        SubscriptionPlanCatalogItem.fromJson(
          Map<String, dynamic>.from(row as Map),
        ),
    ];
  }

  Future<SubscriptionUsage> getUsage(String organizationId) async {
    final response = await _client.rpc(
      'subscription_usage',
      params: {'p_organization_id': organizationId},
    );
    final rows = response as List? ?? const [];
    if (rows.isEmpty) {
      return const SubscriptionUsage(activeUsers: 0, activeSites: 0);
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return SubscriptionUsage(
      activeUsers: (row['active_users'] as num?)?.toInt() ?? 0,
      activeSites: (row['active_sites'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> verifyGooglePlayPurchase({
    required String organizationId,
    required String packageName,
    required String productId,
    required String purchaseToken,
  }) async {
    final response = await _client.functions.invoke(
      'google-play-verify-purchase',
      body: {
        'organization_id': organizationId,
        'package_name': packageName,
        'product_id': productId,
        'purchase_token': purchaseToken,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Purchase verification failed (${response.status})');
    }
  }

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
