import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    as billing;
import 'play_subscription_catalog.dart';
import 'subscription_repository.dart';

class PlayBillingService {
  PlayBillingService({
    required this._packageName,
    InAppPurchase? store,
    SubscriptionRepository? repository,
    this.applicationUserName,
  }) : _store = store ?? InAppPurchase.instance,
       _repository = repository ?? SubscriptionRepository();
  final String _packageName;
  final InAppPurchase _store;
  final SubscriptionRepository _repository;
  final String? applicationUserName;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final Map<String, GooglePlayPurchaseDetails> _knownPurchases = {};
  final _verified = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get verifiedPurchases => _verified.stream;

  Future<bool> initialize() async {
    if (!await _store.isAvailable()) return false;
    _purchaseSub ??= _store.purchaseStream.listen(_handlePurchases);
    try {
      final addition = _store
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final past = await addition.queryPastPurchases(
        applicationUserName: applicationUserName,
      );
      if (past.error == null && past.pastPurchases.isNotEmpty) {
        await _handlePurchases(past.pastPurchases);
      }
    } catch (_) {
      // The normal purchase stream/Restore action remains available if Play
      // cannot query past purchases during screen initialization.
    }
    return true;
  }

  Future<ProductDetailsResponse> loadProducts() =>
      _store.queryProductDetails(PlaySubscriptionCatalog.productIds);

  Future<void> restore() => _store.restorePurchases();

  Future<void> buy(ProductDetails product, {String? currentProductId}) async {
    final PurchaseParam purchaseParam;
    if (product is GooglePlayProductDetails) {
      ChangeSubscriptionParam? change;
      if (currentProductId != null) {
        final previous = _knownPurchases[currentProductId];
        if (previous == null) {
          throw StateError(
            'Restore the current Google Play subscription before changing plans.',
          );
        }
        change = ChangeSubscriptionParam(
          oldPurchaseDetails: previous,
          replacementMode: billing.ReplacementMode.withTimeProration,
        );
      }
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
        offerToken: product.offerToken,
        changeSubscriptionParam: change,
      );
    } else {
      purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      );
    }

    final started = await _store.buyNonConsumable(purchaseParam: purchaseParam);
    if (!started) {
      throw StateError('Google Play did not start the purchase flow.');
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      try {
        final result = await _repository.verifyGooglePlayPurchase(
          productId: purchase.productID,
          purchaseToken: purchase.verificationData.serverVerificationData,
          packageName: _packageName,
        );
        if (purchase is GooglePlayPurchaseDetails) {
          _knownPurchases[purchase.productID] = purchase;
        }
        _verified.add(result);
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
      } catch (_) {
        // Fail closed: never acknowledge a purchase the backend did not verify.
      }
    }
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    await _verified.close();
  }
}
