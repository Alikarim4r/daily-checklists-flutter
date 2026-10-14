// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../repositories/checklist_library_repository.dart';

class LibraryPurchaseService {
  LibraryPurchaseService({
    required this.organizationId,
    required this.productIds,
    required this.applicationUserName,
    required this.packageName,
    InAppPurchase? store,
    required ChecklistLibraryRepository repository,
  }) : _store = store ?? InAppPurchase.instance,
       _repository = repository;

  final String organizationId;
  final Set<String> productIds;
  final String applicationUserName;
  final String packageName;
  final InAppPurchase _store;
  final ChecklistLibraryRepository _repository;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final _verified = StreamController<String>.broadcast();

  Stream<String> get verifiedProductIds => _verified.stream;

  Future<bool> initialize() async {
    if (!await _store.isAvailable()) return false;
    _subscription ??= _store.purchaseStream.listen(_handlePurchases);
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
      // Restore remains available through the normal store flow.
    }
    return true;
  }

  Future<ProductDetailsResponse> loadProducts() =>
      _store.queryProductDetails(productIds);

  Future<void> restore() => _store.restorePurchases();

  Future<void> buy(ProductDetails product) async {
    final started = await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      ),
    );
    if (!started) throw StateError('library_purchase_not_started');
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!productIds.contains(purchase.productID)) continue;
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      try {
        await _repository.verifyGooglePlayPurchase(
          productId: purchase.productID,
          purchaseToken: purchase.verificationData.serverVerificationData,
          packageName: packageName,
          organizationId: organizationId,
        );
        _verified.add(purchase.productID);
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
      } catch (_) {
        // Fail closed. A purchase is never unlocked before backend verification.
      }
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _verified.close();
  }
}
