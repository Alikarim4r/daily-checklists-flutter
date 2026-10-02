import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../models/subscription.dart';
import '../providers/providers.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({
    super.key,
    required this.profile,
    required this.language,
  });
  final Profile profile;
  final String language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    final orgId = profile.homeOrganizationId;
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'الاشتراك' : 'Subscription')),
      body: orgId == null
          ? Center(
              child: Text(
                ar
                    ? 'لا توجد مؤسسة مرتبطة بالحساب.'
                    : 'No organization is linked to this account.',
              ),
            )
          : FutureBuilder<OrganizationSubscription?>(
              future: ref
                  .read(subscriptionRepositoryProvider)
                  .getForOrganization(orgId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      ar
                          ? 'تعذر تحميل حالة الاشتراك.'
                          : 'Could not load subscription status.',
                    ),
                  );
                }
                final sub = snapshot.data;
                if (sub == null) {
                  return Center(
                    child: Text(
                      ar
                          ? 'لم يتم إعداد اشتراك لهذه المؤسسة.'
                          : 'No subscription is configured for this organization.',
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _StatusCard(subscription: sub, ar: ar),
                    const SizedBox(height: 20),
                    Text(
                      ar ? 'الباقات' : 'Plans',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _PlanCard(
                      title: 'Starter',
                      detail: ar
                          ? 'حتى 10 مستخدمين • موقع واحد'
                          : 'Up to 10 users • 1 site',
                    ),
                    _PlanCard(
                      title: 'Professional',
                      detail: ar
                          ? 'حتى 50 مستخدمًا • 25 موقعًا'
                          : 'Up to 50 users • 25 sites',
                      recommended: true,
                    ),
                    _PlanCard(
                      title: 'Enterprise',
                      detail: ar
                          ? 'مؤسسات كبيرة • حدود واتفاقية مخصصة'
                          : 'Large organizations • custom limits and agreement',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ar
                          ? 'إدارة الفوترة تتم على مستوى المؤسسة. لا يتم تغيير حالة الاشتراك من جهاز المستخدم.'
                          : 'Billing is managed at organization level. Subscription state cannot be changed from a user device.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.subscription, required this.ar});
  final OrganizationSubscription subscription;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ar ? 'الاشتراك الحالي' : 'Current subscription',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              subscription.plan.name.toUpperCase(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('${ar ? 'الحالة' : 'Status'}: ${subscription.status.name}'),
            Text('${ar ? 'المستخدمون' : 'Users'}: ${subscription.maxUsers}'),
            Text('${ar ? 'المواقع' : 'Sites'}: ${subscription.maxSites}'),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.detail,
    this.recommended = false,
  });
  final String title;
  final String detail;
  final bool recommended;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        recommended
            ? Icons.workspace_premium_outlined
            : Icons.business_outlined,
      ),
      title: Text(title),
      subtitle: Text(detail),
      trailing: recommended ? const Icon(Icons.check_circle_outline) : null,
    ),
  );
}
