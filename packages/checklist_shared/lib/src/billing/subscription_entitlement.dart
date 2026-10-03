class SubscriptionEntitlement {
  const SubscriptionEntitlement({
    required this.organizationId,
    required this.planTier,
    required this.productId,
    required this.basePlanId,
    required this.offerId,
    required this.subscriptionState,
    required this.expiresAt,
    required this.autoRenewing,
  });

  final String organizationId;
  final String planTier;
  final String productId;
  final String? basePlanId;
  final String? offerId;
  final String subscriptionState;
  final DateTime? expiresAt;
  final bool autoRenewing;

  bool get isActive {
    const activeStates = {'active', 'grace_period'};
    if (!activeStates.contains(subscriptionState)) return false;
    return expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc());
  }

  factory SubscriptionEntitlement.fromJson(Map<String, dynamic> json) {
    return SubscriptionEntitlement(
      organizationId: json['organization_id'] as String,
      planTier: json['plan_tier'] as String,
      productId: json['product_id'] as String,
      basePlanId: json['base_plan_id'] as String?,
      offerId: json['offer_id'] as String?,
      subscriptionState: json['subscription_state'] as String,
      expiresAt: DateTime.tryParse(
        json['expires_at']?.toString() ?? '',
      )?.toUtc(),
      autoRenewing: json['auto_renewing'] == true,
    );
  }
}
