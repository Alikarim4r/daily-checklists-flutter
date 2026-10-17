import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subscription catalog parses Google Play product mapping', () {
    final plan = SubscriptionPlanCatalogItem.fromJson({
      'plan': 'professional',
      'display_order': 2,
      'monthly_price_qar': 499,
      'annual_price_qar': 4990,
      'trial_days': 0,
      'max_users': 50,
      'max_sites': 5,
      'storage_gb': 25,
      'is_recommended': true,
      'features': <String, dynamic>{'reports': true},
      'google_play_product_id': 'daily_checklists_professional',
      'google_play_monthly_base_plan_id': 'monthly',
      'google_play_annual_base_plan_id': 'annual',
      'google_play_trial_offer_id': 'trial-30d',
    });

    expect(plan.plan, SubscriptionPlan.professional);
    expect(plan.googlePlayProductId, 'daily_checklists_professional');
    expect(plan.googlePlayMonthlyBasePlanId, 'monthly');
    expect(plan.googlePlayAnnualBasePlanId, 'annual');
    expect(plan.googlePlayTrialOfferId, 'trial-30d');
  });
}
