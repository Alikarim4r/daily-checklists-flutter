import { createHash } from "node:crypto";

export const PLAY_PACKAGE = "com.moehe.checklists.checklist_admin";

export function tokenHash(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function base64Url(input: Uint8Array): string {
  return btoa(String.fromCharCode(...input))
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function importServiceAccountKey() {
  const raw = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not configured");
  const account = JSON.parse(raw);
  const pem = String(account.private_key ?? "");
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  return { key, clientEmail: String(account.client_email ?? "") };
}

export async function googleAccessToken(): Promise<string> {
  const { key, clientEmail } = await importServiceAccountKey();
  if (!clientEmail) throw new Error("Google service account email is missing");
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = base64Url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = base64Url(enc.encode(JSON.stringify({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const unsigned = `${header}.${claim}`;
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(unsigned)));
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error(`Google OAuth failed: ${response.status}`);
  const json = await response.json();
  if (!json.access_token) throw new Error("Google OAuth returned no access token");
  return String(json.access_token);
}

export async function getSubscriptionV2(packageName: string, purchaseToken: string) {
  const accessToken = await googleAccessToken();
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const response = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(`Google subscription verification failed: ${response.status}`);
  return await response.json();
}

export async function acknowledgeSubscription(packageName: string, productId: string, purchaseToken: string) {
  const accessToken = await googleAccessToken();
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const response = await fetch(url, { method: "POST", headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" }, body: "{}" });
  if (!response.ok && response.status !== 409) throw new Error(`Google acknowledgement failed: ${response.status}`);
}

export function entitlementState(play: any) {
  const state = String(play.subscriptionState ?? "");
  const lineItems = Array.isArray(play.lineItems) ? play.lineItems : [];
  const activeLine = [...lineItems].sort((a, b) => String(b.expiryTime ?? "").localeCompare(String(a.expiryTime ?? "")))[0] ?? {};
  const productId = String(activeLine.productId ?? "");
  const offer = activeLine.offerDetails ?? {};
  const auto = activeLine.autoRenewingPlan ?? null;
  const expiry = activeLine.expiryTime ? new Date(activeLine.expiryTime) : null;
  let status = "expired";
  if (state === "SUBSCRIPTION_STATE_ACTIVE") status = "active";
  else if (state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD") status = "grace_period";
  else if (state === "SUBSCRIPTION_STATE_CANCELED") status = expiry && expiry > new Date() ? "canceled" : "expired";
  else if (state === "SUBSCRIPTION_STATE_ON_HOLD" || state === "SUBSCRIPTION_STATE_PAUSED") status = "past_due";
  else if (state === "SUBSCRIPTION_STATE_PENDING" || state === "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED") status = "past_due";
  return {
    state, status, productId,
    basePlanId: offer.basePlanId ? String(offer.basePlanId) : null,
    offerId: offer.offerId ? String(offer.offerId) : null,
    expiryTime: expiry?.toISOString() ?? null,
    startTime: play.startTime ? new Date(play.startTime).toISOString() : null,
    orderId: play.latestOrderId ? String(play.latestOrderId) : null,
    linkedPurchaseToken: play.linkedPurchaseToken ? String(play.linkedPurchaseToken) : null,
    acknowledgementState: play.acknowledgementState ? String(play.acknowledgementState) : null,
    regionCode: play.regionCode ? String(play.regionCode) : null,
    isTestPurchase: play.testPurchase != null,
    autoRenewing: auto?.autoRenewEnabled === true,
    cancelAtPeriodEnd: status === "canceled" || auto?.autoRenewEnabled === false,
  };
}
