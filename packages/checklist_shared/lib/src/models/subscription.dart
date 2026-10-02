enum SubscriptionPlan { trial, starter, professional, enterprise }

enum SubscriptionStatus {
  trialing,
  active,
  pastDue,
  gracePeriod,
  canceled,
  expired,
}

class SubscriptionPlanInfo {
  const SubscriptionPlanInfo({
    required this.plan,
    required this.maxUsers,
    required this.maxSites,
  });
  final SubscriptionPlan plan;
  final int maxUsers;
  final int maxSites;

  static const starter = SubscriptionPlanInfo(
    plan: SubscriptionPlan.starter,
    maxUsers: 10,
    maxSites: 1,
  );
  static const professional = SubscriptionPlanInfo(
    plan: SubscriptionPlan.professional,
    maxUsers: 50,
    maxSites: 25,
  );
  static const enterprise = SubscriptionPlanInfo(
    plan: SubscriptionPlan.enterprise,
    maxUsers: 1000000,
    maxSites: 1000000,
  );
}

class OrganizationSubscription {
  const OrganizationSubscription({
    required this.organizationId,
    required this.plan,
    required this.status,
    required this.hasAccess,
    required this.maxUsers,
    required this.maxSites,
    this.currentPeriodEnd,
    this.gracePeriodEnd,
    this.features = const {},
  });

  final String organizationId;
  final SubscriptionPlan plan;
  final SubscriptionStatus status;
  final bool hasAccess;
  final int maxUsers;
  final int maxSites;
  final DateTime? currentPeriodEnd;
  final DateTime? gracePeriodEnd;
  final Map<String, dynamic> features;

  bool hasFeature(String key) => features[key] == true;

  factory OrganizationSubscription.fromRpc(
    String organizationId,
    Map<String, dynamic> json,
  ) {
    return OrganizationSubscription(
      organizationId: organizationId,
      plan: SubscriptionPlan.values.firstWhere(
        (v) => v.name == json['plan'],
        orElse: () => SubscriptionPlan.trial,
      ),
      status: _statusFromDb(json['status'] as String?),
      hasAccess: json['has_access'] as bool? ?? false,
      maxUsers: json['max_users'] as int? ?? 0,
      maxSites: json['max_sites'] as int? ?? 0,
      currentPeriodEnd: DateTime.tryParse(
        '${json['current_period_end'] ?? ''}',
      ),
      gracePeriodEnd: DateTime.tryParse('${json['grace_period_end'] ?? ''}'),
      features: Map<String, dynamic>.from(json['features'] as Map? ?? const {}),
    );
  }

  static SubscriptionStatus _statusFromDb(String? value) => switch (value) {
    'active' => SubscriptionStatus.active,
    'past_due' => SubscriptionStatus.pastDue,
    'grace_period' => SubscriptionStatus.gracePeriod,
    'canceled' => SubscriptionStatus.canceled,
    'expired' => SubscriptionStatus.expired,
    _ => SubscriptionStatus.trialing,
  };
}
