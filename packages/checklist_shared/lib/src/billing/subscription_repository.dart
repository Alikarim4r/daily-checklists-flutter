import 'package:supabase_flutter/supabase_flutter.dart';

import 'subscription_entitlement.dart';

class SubscriptionRepository {
  SubscriptionRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<SubscriptionEntitlement?> currentEntitlement() async {
    final response = await _client.rpc('current_subscription_entitlement');
    if (response is! List || response.isEmpty) return null;
    final row = Map<String, dynamic>.from(response.first as Map);
    return SubscriptionEntitlement.fromJson(row);
  }

  Future<Map<String, dynamic>> verifyGooglePlayPurchase({
    required String productId,
    required String purchaseToken,
    required String packageName,
  }) async {
    final response = await _client.functions.invoke(
      'verify-google-play-subscription',
      body: <String, dynamic>{
        'product_id': productId,
        'purchase_token': purchaseToken,
        'package_name': packageName,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'Subscription verification failed (${response.status}).',
      );
    }
    if (response.data is! Map) {
      throw StateError(
        'Subscription verification returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
