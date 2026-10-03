import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/profile.dart';
import 'play_billing_service.dart';
import 'play_subscription_catalog.dart';
import 'subscription_entitlement.dart';
import 'subscription_repository.dart';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({
    super.key,
    required this.profile,
    required this.language,
  });

  final Profile profile;
  final String language;

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  final SubscriptionRepository _repository = SubscriptionRepository();
  PlayBillingService? _billing;
  StreamSubscription<Map<String, dynamic>>? _verifiedSubscription;
  SubscriptionEntitlement? _entitlement;
  List<ProductDetails> _products = const [];
  bool _loading = true;
  bool _storeAvailable = false;
  bool _restoring = false;
  String? _busyProductId;
  String? _message;

  bool get _ar => widget.language == 'ar';
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _entitlement = await _repository.currentEntitlement();
      if (!_android) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final info = await PackageInfo.fromPlatform();
      final billing = PlayBillingService(
        packageName: info.packageName,
        applicationUserName: widget.profile.id,
      );
      _billing = billing;
      _verifiedSubscription = billing.verifiedPurchases.listen((_) async {
        await _reloadEntitlement();
        if (mounted) {
          setState(() {
            _busyProductId = null;
            _restoring = false;
            _message = _ar
                ? 'تم التحقق من الاشتراك وتحديث الحساب.'
                : 'Subscription verified and account updated.';
          });
        }
      });

      _storeAvailable = await billing.initialize();
      if (_storeAvailable) {
        final response = await billing.loadProducts();
        final productOrder = <String, int>{
          for (
            var i = 0;
            i < PlaySubscriptionCatalog.orderedProductIds.length;
            i++
          )
            PlaySubscriptionCatalog.orderedProductIds[i]: i,
        };
        _products = [...response.productDetails]
          ..sort((a, b) {
            final byProduct = (productOrder[a.id] ?? 999).compareTo(
              productOrder[b.id] ?? 999,
            );
            if (byProduct != 0) return byProduct;
            final aIndex = a is GooglePlayProductDetails
                ? (a.subscriptionIndex ?? 0)
                : 0;
            final bIndex = b is GooglePlayProductDetails
                ? (b.subscriptionIndex ?? 0)
                : 0;
            return aIndex.compareTo(bIndex);
          });
        if (response.error != null) {
          _message = response.error!.message;
        } else if (response.notFoundIDs.isNotEmpty) {
          _message = _ar
              ? 'بعض خطط الاشتراك غير متاحة بعد في Google Play.'
              : 'Some subscription plans are not available in Google Play yet.';
        }
      }
    } catch (error) {
      _message = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('restore the current google play')) {
      return _ar
          ? 'استعد الاشتراك الحالي أولًا ثم أعد محاولة تغيير الخطة.'
          : 'Restore the current subscription first, then try changing plans again.';
    }
    if (raw.contains('billing') || raw.contains('google play')) {
      return _ar
          ? 'تعذر بدء عملية الشراء عبر Google Play. تأكد من أن التطبيق مثبت من متجر Google Play وحاول مرة أخرى.'
          : 'Google Play could not start the purchase. Make sure this app was installed from Google Play and try again.';
    }
    if (raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('timeout')) {
      return _ar
          ? 'تعذر الاتصال بالخدمة. تحقق من اتصال الإنترنت ثم حاول مرة أخرى.'
          : 'Could not reach the service. Check your internet connection and try again.';
    }
    if (raw.contains('verification') || raw.contains('subscription')) {
      return _ar
          ? 'تعذر التحقق من الاشتراك الآن. لم يتم تفعيل أي اشتراك غير متحقق منه.'
          : 'The subscription could not be verified right now. No unverified subscription was activated.';
    }
    return _ar
        ? 'حدث خطأ غير متوقع. حاول مرة أخرى، وإذا استمرت المشكلة تواصل مع الدعم.'
        : 'Something went wrong. Try again, and contact support if the problem continues.';
  }

  Future<void> _reloadEntitlement() async {
    try {
      final current = await _repository.currentEntitlement();
      if (mounted) setState(() => _entitlement = current);
    } catch (_) {
      // Keep the last server-verified entitlement visible.
    }
  }

  Future<void> _buy(ProductDetails product) async {
    final billing = _billing;
    if (billing == null || _busyProductId != null) return;
    setState(() {
      _busyProductId = product.id;
      _message = null;
    });
    try {
      final current = _entitlement;
      await billing.buy(
        product,
        currentProductId: current?.isActive == true ? current!.productId : null,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busyProductId = null;
          _message = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _restore() async {
    final billing = _billing;
    if (billing == null || _restoring) return;
    setState(() {
      _restoring = true;
      _message = _ar ? 'جارٍ استعادة المشتريات…' : 'Restoring purchases…';
    });
    try {
      await billing.restore();
    } catch (error) {
      if (mounted) {
        setState(() {
          _restoring = false;
          _message = _friendlyError(error);
        });
      }
    }
  }

  @override
  void dispose() {
    _verifiedSubscription?.cancel();
    _billing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = _entitlement;
    return Scaffold(
      appBar: AppBar(title: Text(_ar ? 'الاشتراك' : 'Subscription')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reloadEntitlement,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _CurrentPlanCard(
                    entitlement: entitlement,
                    language: widget.language,
                  ),
                  const SizedBox(height: 16),
                  if (!_android)
                    _InfoCard(
                      icon: Icons.android_outlined,
                      text: _ar
                          ? 'إدارة الاشتراك والشراء متاحة داخل نسخة Android المثبتة من Google Play.'
                          : 'Subscription purchase and management are available in the Android app installed from Google Play.',
                    )
                  else if (!_storeAvailable)
                    _InfoCard(
                      icon: Icons.store_mall_directory_outlined,
                      text: _ar
                          ? 'Google Play Billing غير متاح على هذا الجهاز أو هذه النسخة.'
                          : 'Google Play Billing is not available on this device or build.',
                    )
                  else ...[
                    Text(
                      _ar ? 'الخطط المتاحة' : 'Available plans',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final product in _products)
                      _PlanCard(
                        product: product,
                        language: widget.language,
                        currentEntitlement: entitlement,
                        busy: _busyProductId == product.id,
                        disabled: _busyProductId != null,
                        onBuy: () => _buy(product),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _restoring ? null : _restore,
                      icon: _restoring
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restore_outlined),
                      label: Text(
                        _ar ? 'استعادة المشتريات' : 'Restore purchases',
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    _InfoCard(icon: Icons.info_outline, text: _message!),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.entitlement, required this.language});
  final SubscriptionEntitlement? entitlement;
  final String language;

  @override
  Widget build(BuildContext context) {
    final ar = language == 'ar';
    final current = entitlement;
    final active = current?.isActive == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              active
                  ? Icons.verified_outlined
                  : Icons.workspace_premium_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active
                        ? '${ar ? 'الخطة الحالية' : 'Current plan'}: ${PlaySubscriptionCatalog.labelForTier(current!.planTier, language)}'
                        : (ar
                              ? 'لا يوجد اشتراك نشط'
                              : 'No active subscription'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (current?.expiresAt != null)
                    Text(
                      '${ar ? 'صالح حتى' : 'Valid until'} ${current!.expiresAt!.toLocal().toString().split('.').first}',
                    ),
                  if (active && current!.autoRenewing)
                    Text(
                      ar ? 'التجديد التلقائي مفعل' : 'Auto-renewal is enabled',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AndroidPlanMeta {
  const _AndroidPlanMeta({
    required this.basePlanId,
    required this.offerId,
    required this.price,
    required this.period,
    required this.trialPeriod,
  });

  final String basePlanId;
  final String? offerId;
  final String price;
  final String period;
  final String? trialPeriod;

  static _AndroidPlanMeta? from(ProductDetails product) {
    if (product is! GooglePlayProductDetails ||
        product.subscriptionIndex == null ||
        product.productDetails.subscriptionOfferDetails == null) {
      return null;
    }
    final offer = product
        .productDetails
        .subscriptionOfferDetails![product.subscriptionIndex!];
    if (offer.pricingPhases.isEmpty) return null;
    final recurring = offer.pricingPhases.last;
    String? trial;
    for (final phase in offer.pricingPhases) {
      if (phase.priceAmountMicros == 0) {
        trial = phase.billingPeriod;
        break;
      }
    }
    return _AndroidPlanMeta(
      basePlanId: offer.basePlanId,
      offerId: offer.offerId,
      price: recurring.formattedPrice,
      period: recurring.billingPeriod,
      trialPeriod: trial,
    );
  }

  String cadenceLabel(bool ar) {
    final id = basePlanId.toLowerCase();
    if (id.contains('month')) return ar ? 'شهري' : 'Monthly';
    if (id.contains('annual') || id.contains('year')) {
      return ar ? 'سنوي' : 'Annual';
    }
    if (period == 'P1M') return ar ? 'شهري' : 'Monthly';
    if (period == 'P1Y') return ar ? 'سنوي' : 'Annual';
    return basePlanId;
  }

  String priceLabel(bool ar) {
    final suffix = switch (period) {
      'P1M' => ar ? ' / شهر' : ' / month',
      'P1Y' => ar ? ' / سنة' : ' / year',
      _ => '',
    };
    return '$price$suffix';
  }

  String? trialLabel(bool ar) {
    final p = trialPeriod;
    if (p == null) return null;
    final label = switch (p) {
      'P3D' => ar ? 'تجربة مجانية 3 أيام' : '3-day free trial',
      'P7D' => ar ? 'تجربة مجانية 7 أيام' : '7-day free trial',
      'P30D' => ar ? 'تجربة مجانية 30 يومًا' : '30-day free trial',
      _ => ar ? 'تجربة مجانية متاحة' : 'Free trial available',
    };
    return label;
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.language,
    required this.currentEntitlement,
    required this.busy,
    required this.disabled,
    required this.onBuy,
  });

  final ProductDetails product;
  final String language;
  final SubscriptionEntitlement? currentEntitlement;
  final bool busy;
  final bool disabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final ar = language == 'ar';
    final tier = PlaySubscriptionCatalog.tierForProduct(product.id);
    final meta = _AndroidPlanMeta.from(product);
    final entitlement = currentEntitlement;
    final current =
        entitlement?.isActive == true &&
        entitlement!.productId == product.id &&
        (entitlement.basePlanId == null ||
            entitlement.basePlanId == meta?.basePlanId) &&
        (entitlement.offerId == null || entitlement.offerId == meta?.offerId);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PlaySubscriptionCatalog.labelForTier(tier, language),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Builder(
                    builder: (context) {
                      if (meta == null) return Text(product.price);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meta.cadenceLabel(ar),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(meta.priceLabel(ar)),
                          if (meta.trialLabel(ar) case final trial?)
                            Text(
                              trial,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  if (product.description.trim().isNotEmpty)
                    Text(
                      product.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: current || disabled ? null : onBuy,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      current
                          ? (ar ? 'الحالية' : 'Current')
                          : (ar ? 'اختيار' : 'Choose'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
