import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses organization subscription RPC state', () {
    final sub = OrganizationSubscription.fromRpc('org-1', {
      'plan': 'professional',
      'status': 'active',
      'has_access': true,
      'max_users': 50,
      'max_sites': 25,
      'features': {'reports': true},
    });
    expect(sub.plan, SubscriptionPlan.professional);
    expect(sub.status, SubscriptionStatus.active);
    expect(sub.hasAccess, isTrue);
    expect(sub.hasFeature('reports'), isTrue);
  });

  test('maps database status names safely', () {
    final sub = OrganizationSubscription.fromRpc('org-1', {
      'plan': 'starter',
      'status': 'past_due',
      'has_access': false,
      'max_users': 10,
      'max_sites': 1,
    });
    expect(sub.status, SubscriptionStatus.pastDue);
    expect(sub.hasAccess, isFalse);
  });
}
