import 'subscription.dart';

class SubscriptionPlanCatalogItem {
  const SubscriptionPlanCatalogItem({
    required this.plan,
    required this.displayOrder,
    required this.monthlyPriceQar,
    required this.annualPriceQar,
    required this.trialDays,
    required this.maxUsers,
    required this.maxSites,
    required this.storageGb,
    required this.isRecommended,
    required this.features,
  });

  final SubscriptionPlan plan;
  final int displayOrder;
  final int? monthlyPriceQar;
  final int? annualPriceQar;
  final int trialDays;
  final int maxUsers;
  final int maxSites;
  final int storageGb;
  final bool isRecommended;
  final Map<String, dynamic> features;

  factory SubscriptionPlanCatalogItem.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlanCatalogItem(
        plan: SubscriptionPlan.values.firstWhere(
          (value) => value.name == json['plan'],
          orElse: () => SubscriptionPlan.trial,
        ),
        displayOrder: json['display_order'] as int? ?? 0,
        monthlyPriceQar: json['monthly_price_qar'] as int?,
        annualPriceQar: json['annual_price_qar'] as int?,
        trialDays: json['trial_days'] as int? ?? 0,
        maxUsers: json['max_users'] as int? ?? 0,
        maxSites: json['max_sites'] as int? ?? 0,
        storageGb: json['storage_gb'] as int? ?? 0,
        isRecommended: json['is_recommended'] as bool? ?? false,
        features: Map<String, dynamic>.from(
          json['features'] as Map? ?? const {},
        ),
      );
}

class SubscriptionUsage {
  const SubscriptionUsage({
    required this.activeUsers,
    required this.activeSites,
  });
  final int activeUsers;
  final int activeSites;
}
