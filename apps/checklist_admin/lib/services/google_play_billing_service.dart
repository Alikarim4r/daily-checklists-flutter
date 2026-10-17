import 'dart:async';
import 'dart:convert';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

const _adminPackage = 'com.moehe.checklists.checklist_admin';

enum BillingPeriod { monthly, annual }

class PlayOffer {
  const PlayOffer({
    required this.details,
    required this.basePlanId,
    required this.offerId,
  });
  final GooglePlayProductDetails details;
  final String basePlanId;
  final String? offerId;
}

class GooglePlayBillingService {
  GooglePlayBillingService({required this.repository, InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance;
  final SubscriptionRepository repository;
  final InAppPurchase _store;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  String? _organizationId;
  bool _processing = false;

  Future<bool> isAvailable() => _store.isAvailable();

  Future<List<PlayOffer>> loadOffers(
    List<SubscriptionPlanCatalogItem> plans,
  ) async {
    if (!await _store.isAvailable()) {
      return const [];
    }
    final ids = plans
        .map((p) => p.googlePlayProductId)
        .whereType<String>()
        .toSet();
    if (ids.isEmpty) {
      return const [];
    }
    final response = await _store.queryProductDetails(ids);
    if (response.error != null) throw StateError(response.error!.message);
    final result = <PlayOffer>[];
    for (final details
        in response.productDetails.whereType<GooglePlayProductDetails>()) {
      final index = details.subscriptionIndex;
      final offers = details.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index >= offers.length) continue;
      final offer = offers[index];
      result.add(
        PlayOffer(
          details: details,
          basePlanId: offer.basePlanId,
          offerId: offer.offerId,
        ),
      );
    }
    return result;
  }

  Future<void> start({required String organizationId}) async {
    _organizationId = organizationId;
    await _subscription?.cancel();
    _subscription = _store.purchaseStream.listen(_handlePurchases);
  }

  Future<void> dispose() async => _subscription?.cancel();

  Future<void> buy({
    required PlayOffer offer,
    required String userId,
    GooglePlayPurchaseDetails? existing,
    ReplacementMode? replacementMode,
  }) async {
    final account = sha256.convert(utf8.encode(userId)).toString();
    final org = _organizationId;
    if (org == null) throw StateError('Billing service has not been started');
    final profile = sha256.convert(utf8.encode(org)).toString();
    final param = GooglePlayPurchaseParam(
      productDetails: offer.details,
      offerToken: offer.details.offerToken,
      applicationUserName: account,
      obfuscatedProfileId: profile,
      changeSubscriptionParam: existing == null
          ? null
          : ChangeSubscriptionParam(
              oldPurchaseDetails: existing,
              replacementMode: replacementMode,
            ),
    );
    final launched = await _store.buyNonConsumable(purchaseParam: param);
    if (!launched) {
      throw StateError('Google Play did not launch the purchase flow');
    }
  }

  Future<List<GooglePlayPurchaseDetails>> ownedSubscriptions() async {
    final addition = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    return response.pastPurchases;
  }

  Future<void> restore() => _store.restorePurchases();

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    if (_processing) return;
    _processing = true;
    try {
      for (final purchase in purchases) {
        if (purchase.status != PurchaseStatus.purchased &&
            purchase.status != PurchaseStatus.restored) {
          continue;
        }
        if (purchase is! GooglePlayPurchaseDetails) {
          continue;
        }
        final org = _organizationId;
        if (org == null) {
          continue;
        }
        await repository.verifyGooglePlayPurchase(
          organizationId: org,
          packageName: purchase.billingClientPurchase.packageName.isEmpty
              ? _adminPackage
              : purchase.billingClientPurchase.packageName,
          productId: purchase.productID,
          purchaseToken: purchase.verificationData.serverVerificationData,
        );
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
      }
    } finally {
      _processing = false;
    }
  }
}
