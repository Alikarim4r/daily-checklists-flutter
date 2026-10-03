class PlaySubscriptionCatalog {
  static const starter = 'daily_checklists_starter';
  static const professional = 'daily_checklists_professional';
  static const business = 'daily_checklists_business';

  static const productIds = <String>{starter, professional, business};
  static const orderedProductIds = <String>[starter, professional, business];

  static String labelForTier(String tier, String language) {
    final ar = language == 'ar';
    return switch (tier) {
      'starter' => ar ? 'أساسية' : 'Starter',
      'professional' => ar ? 'احترافية' : 'Professional',
      'business' => ar ? 'أعمال' : 'Business',
      _ => tier,
    };
  }

  static String tierForProduct(String productId) => switch (productId) {
    starter => 'starter',
    professional => 'professional',
    business => 'business',
    _ => throw ArgumentError.value(
      productId,
      'productId',
      'Unknown subscription',
    ),
  };
}
