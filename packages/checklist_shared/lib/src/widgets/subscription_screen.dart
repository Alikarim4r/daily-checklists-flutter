import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../models/subscription.dart';
import '../models/subscription_plan.dart';
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
      appBar: AppBar(
        title: Text(ar ? 'الاشتراك والفوترة' : 'Subscription & billing'),
      ),
      body: orgId == null
          ? Center(
              child: Text(
                ar
                    ? 'لا توجد مؤسسة مرتبطة بالحساب.'
                    : 'No organization is linked to this account.',
              ),
            )
          : FutureBuilder<_SubscriptionViewData>(
              future: _load(ref, orgId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      ar
                          ? 'تعذر تحميل بيانات الاشتراك.'
                          : 'Could not load subscription data.',
                    ),
                  );
                }
                final data = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (data.subscription != null)
                      _StatusCard(
                        subscription: data.subscription!,
                        usage: data.usage,
                        ar: ar,
                      ),
                    const SizedBox(height: 24),
                    Text(
                      ar ? 'الباقات' : 'Plans',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ar
                          ? 'اشتراك واحد للمؤسسة يفتح التطبيقات الثلاثة.'
                          : 'One organization subscription covers all three apps.',
                    ),
                    const SizedBox(height: 12),
                    for (final plan in data.plans)
                      _PlanCard(plan: plan, ar: ar),
                    const SizedBox(height: 16),
                    Text(
                      ar
                          ? 'الأسعار بالريال القطري. الاشتراك السنوي يعادل خصم شهرين. Enterprise يبدأ من 20,000 ر.ق سنويًا ويحدد بالعقد.'
                          : 'Prices are in Qatari riyals. Annual billing includes the equivalent of two months free. Enterprise starts at QAR 20,000/year and is contract-defined.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
    );
  }

  Future<_SubscriptionViewData> _load(WidgetRef ref, String orgId) async {
    final repo = ref.read(subscriptionRepositoryProvider);
    final values = await Future.wait([
      repo.getForOrganization(orgId),
      repo.getUsage(orgId),
      repo.listPlans(),
    ]);
    return _SubscriptionViewData(
      subscription: values[0] as OrganizationSubscription?,
      usage: values[1] as SubscriptionUsage,
      plans: values[2] as List<SubscriptionPlanCatalogItem>,
    );
  }
}

class _SubscriptionViewData {
  const _SubscriptionViewData({
    required this.subscription,
    required this.usage,
    required this.plans,
  });
  final OrganizationSubscription? subscription;
  final SubscriptionUsage usage;
  final List<SubscriptionPlanCatalogItem> plans;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.subscription,
    required this.usage,
    required this.ar,
  });
  final OrganizationSubscription subscription;
  final SubscriptionUsage usage;
  final bool ar;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ar ? 'الاشتراك الحالي' : 'Current subscription',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            subscription.plan.name.toUpperCase(),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          _usage(
            context,
            ar ? 'المستخدمون' : 'Users',
            usage.activeUsers,
            subscription.maxUsers,
          ),
          const SizedBox(height: 8),
          _usage(
            context,
            ar ? 'المواقع' : 'Sites',
            usage.activeSites,
            subscription.maxSites,
          ),
          const SizedBox(height: 8),
          Text('${ar ? 'الحالة' : 'Status'}: ${subscription.status.name}'),
        ],
      ),
    ),
  );

  Widget _usage(BuildContext context, String label, int used, int max) {
    final ratio = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $used / $max'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: ratio),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.ar});
  final SubscriptionPlanCatalogItem plan;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final monthly = plan.monthlyPriceQar;
    final annual = plan.annualPriceQar;
    final price = monthly == null
        ? (ar ? 'حسب العرض' : 'Custom quote')
        : '$monthly QAR/${ar ? 'شهر' : 'month'}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title(plan.plan),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (plan.isRecommended)
                  Chip(label: Text(ar ? 'الأكثر شيوعًا' : 'Most popular')),
              ],
            ),
            Text(price, style: Theme.of(context).textTheme.headlineSmall),
            if (annual != null && annual > 0)
              Text('$annual QAR/${ar ? 'سنة' : 'year'}'),
            const SizedBox(height: 8),
            Text(
              '${ar ? 'المستخدمون' : 'Users'}: ${_limit(plan.maxUsers)}  •  ${ar ? 'المواقع' : 'Sites'}: ${_limit(plan.maxSites)}',
            ),
            Text('${ar ? 'التخزين' : 'Storage'}: ${plan.storageGb} GB'),
          ],
        ),
      ),
    );
  }

  String _title(SubscriptionPlan value) => switch (value) {
    SubscriptionPlan.starter => 'Starter',
    SubscriptionPlan.professional => 'Professional',
    SubscriptionPlan.business => 'Business',
    SubscriptionPlan.enterprise => 'Enterprise',
    SubscriptionPlan.trial => 'Trial',
  };

  String _limit(int value) =>
      value >= 1000000 ? (ar ? 'حسب العقد' : 'Custom') : '$value';
}
