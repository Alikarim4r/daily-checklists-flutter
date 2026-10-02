import { tokenHash, entitlementState, getSubscriptionV2, acknowledgeSubscription } from "./google_play.ts";

export async function syncPurchase(admin: any, args: { packageName: string; purchaseToken: string; organizationId?: string; purchasedBy?: string | null; expectedProductId?: string | null; }) {
  const play = await getSubscriptionV2(args.packageName, args.purchaseToken);
  const ent = entitlementState(play);
  if (!ent.productId) throw new Error("Google response contains no subscription product");
  if (args.expectedProductId && ent.productId !== args.expectedProductId) throw new Error("Verified product does not match requested product");

  let organizationId = args.organizationId ?? null;
  if (!organizationId && ent.linkedPurchaseToken) {
    const { data } = await admin.from("google_play_subscription_purchases").select("organization_id").eq("purchase_token_hash", tokenHash(ent.linkedPurchaseToken)).maybeSingle();
    organizationId = data?.organization_id ?? null;
  }
  if (!organizationId) {
    const { data } = await admin.from("google_play_subscription_purchases").select("organization_id").eq("purchase_token_hash", tokenHash(args.purchaseToken)).maybeSingle();
    organizationId = data?.organization_id ?? null;
  }
  if (!organizationId) throw new Error("Purchase is not linked to an organization");

  const { data: catalog, error: catalogError } = await admin.from("subscription_plan_catalog")
    .select("plan,max_users,max_sites,storage_gb,features")
    .eq("google_play_product_id", ent.productId).maybeSingle();
  if (catalogError || !catalog) throw new Error("Google Play product is not mapped to a subscription plan");

  if (ent.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING" && ["active", "grace_period", "canceled"].includes(ent.status)) {
    await acknowledgeSubscription(args.packageName, ent.productId, args.purchaseToken);
  }

  const hash = tokenHash(args.purchaseToken);
  const linkedHash = ent.linkedPurchaseToken ? tokenHash(ent.linkedPurchaseToken) : null;
  const { error: purchaseError } = await admin.from("google_play_subscription_purchases").upsert({
    purchase_token_hash: hash, organization_id: organizationId, purchased_by: args.purchasedBy ?? null,
    package_name: args.packageName, product_id: ent.productId, base_plan_id: ent.basePlanId,
    offer_id: ent.offerId, order_id: ent.orderId, linked_purchase_token_hash: linkedHash,
    subscription_state: ent.state, acknowledgement_state: ent.acknowledgementState,
    region_code: ent.regionCode, is_test_purchase: ent.isTestPurchase, start_time: ent.startTime,
    expiry_time: ent.expiryTime, auto_renewing: ent.autoRenewing, cancel_at_period_end: ent.cancelAtPeriodEnd,
    raw_response: play, last_verified_at: new Date().toISOString(),
  }, { onConflict: "purchase_token_hash" });
  if (purchaseError) throw purchaseError;

  const graceEnd = ent.status === "grace_period" ? ent.expiryTime : null;
  const { error: subError } = await admin.from("organization_subscriptions").upsert({
    organization_id: organizationId, plan: catalog.plan, status: ent.status, provider: "google_play",
    provider_subscription_ref: hash, current_period_start: ent.startTime, current_period_end: ent.expiryTime,
    grace_period_end: graceEnd, cancel_at_period_end: ent.cancelAtPeriodEnd,
    max_users: catalog.max_users, max_sites: catalog.max_sites, storage_gb: catalog.storage_gb, features: catalog.features,
  }, { onConflict: "organization_id" });
  if (subError) throw subError;
  return { organizationId, plan: catalog.plan, status: ent.status, productId: ent.productId, expiryTime: ent.expiryTime };
}
