import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/google_play_billing_service.dart';

class GooglePlaySubscriptionScreen extends ConsumerStatefulWidget {
  const GooglePlaySubscriptionScreen({
    super.key,
    required this.profile,
    required this.language,
  });
  final Profile profile;
  final String language;
  @override
  ConsumerState<GooglePlaySubscriptionScreen> createState() =>
      _GooglePlaySubscriptionScreenState();
}

class _GooglePlaySubscriptionScreenState
    extends ConsumerState<GooglePlaySubscriptionScreen> {
  GooglePlayBillingService? _billing;
  List<SubscriptionPlanCatalogItem> _plans = const [];
  List<PlayOffer> _offers = const [];
  OrganizationSubscription? _subscription;
  SubscriptionUsage _usage = const SubscriptionUsage(
    activeUsers: 0,
    activeSites: 0,
  );
  bool _loading = true;
  String? _error;

  bool get ar => widget.language == 'ar';
  String get orgId => widget.profile.homeOrganizationId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(subscriptionRepositoryProvider);
      final billing = GooglePlayBillingService(repository: repo);
      await billing.start(organizationId: orgId);
      final plans = await repo.listPlans();
      final values = await Future.wait([
        repo.getForOrganization(orgId),
        repo.getUsage(orgId),
      ]);
      final offers = await billing.loadOffers(plans);
      if (!mounted) {
        return;
      }
      setState(() {
        _billing = billing;
        _plans = plans;
        _subscription = values[0] as OrganizationSubscription?;
        _usage = values[1] as SubscriptionUsage;
        _offers = offers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _billing?.dispose();
    super.dispose();
  }

  PlayOffer? _offer(SubscriptionPlanCatalogItem plan, BillingPeriod period) {
    final product = plan.googlePlayProductId;
    final base = period == BillingPeriod.monthly
        ? plan.googlePlayMonthlyBasePlanId
        : plan.googlePlayAnnualBasePlanId;
    for (final offer in _offers) {
      if (offer.details.id == product &&
          offer.basePlanId == base &&
          offer.offerId == null) {
        return offer;
      }
    }
    for (final offer in _offers) {
      if (offer.details.id == product && offer.basePlanId == base) {
        return offer;
      }
    }
    return null;
  }

  Future<void> _buy(
    SubscriptionPlanCatalogItem plan,
    BillingPeriod period,
  ) async {
    final billing = _billing;
    final offer = _offer(plan, period);
    if (billing == null || offer == null) {
      return;
    }
    try {
      final owned = await billing.ownedSubscriptions();
      GooglePlayPurchaseDetails? existing;
      for (final purchase in owned) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          existing = purchase;
          break;
        }
      }
      ReplacementMode? mode;
      if (existing != null) {
        final currentRank = _subscription?.plan.index ?? 0;
        final nextRank = plan.plan.index;
        mode = nextRank >= currentRank
            ? ReplacementMode.chargeProratedPrice
            : ReplacementMode.deferred;
      }
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw StateError('Authentication required');
      }
      await billing.buy(
        offer: offer,
        userId: userId,
        existing: existing,
        replacementMode: mode,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ar ? 'تعذر بدء عملية الشراء.' : 'Could not start purchase.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'الاشتراك والفوترة' : 'Subscription & billing'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                ar
                    ? 'تعذر الاتصال بخدمة الاشتراكات.'
                    : 'Subscription service is unavailable.',
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_subscription != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(
                          '${_subscription!.plan.name.toUpperCase()} • ${_subscription!.status.name}',
                        ),
                        subtitle: Text(
                          '${ar ? 'المستخدمون' : 'Users'} ${_usage.activeUsers}/${_subscription!.maxUsers}  •  ${ar ? 'المواقع' : 'Sites'} ${_usage.activeSites}/${_subscription!.maxSites}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    ar ? 'اختر الباقة' : 'Choose a plan',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    ar
                        ? 'السعر النهائي والعملة يعرضهما Google Play قبل تأكيد الدفع.'
                        : 'Google Play shows the final localized price and currency before confirmation.',
                  ),
                  const SizedBox(height: 12),
                  for (final plan in _plans.where(
                    (p) => p.googlePlayProductId != null,
                  ))
                    _planCard(plan),
                  OutlinedButton.icon(
                    onPressed: () => _billing?.restore(),
                    icon: const Icon(Icons.restore),
                    label: Text(ar ? 'استعادة المشتريات' : 'Restore purchases'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _planCard(SubscriptionPlanCatalogItem plan) {
    final monthly = _offer(plan, BillingPeriod.monthly);
    final annual = _offer(plan, BillingPeriod.annual);
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
                    plan.plan.name.toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (plan.isRecommended)
                  Chip(label: Text(ar ? 'الأكثر شيوعًا' : 'Most popular')),
              ],
            ),
            Text(
              '${ar ? 'المستخدمون' : 'Users'}: ${plan.maxUsers} • ${ar ? 'المواقع' : 'Sites'}: ${plan.maxSites} • ${plan.storageGb} GB',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: monthly == null
                        ? null
                        : () => _buy(plan, BillingPeriod.monthly),
                    child: Text(
                      monthly?.details.price ??
                          '${plan.monthlyPriceQar} QAR / ${ar ? 'شهر' : 'month'}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: annual == null
                        ? null
                        : () => _buy(plan, BillingPeriod.annual),
                    child: Text(
                      annual?.details.price ??
                          '${plan.annualPriceQar} QAR / ${ar ? 'سنة' : 'year'}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
