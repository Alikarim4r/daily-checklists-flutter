# Google Play Billing setup — Daily Checklists

## Canonical product IDs (do not rename after activation)

| Tier | Subscription product ID | Monthly base plan | Annual base plan | Trial offer |
| --- | --- | --- | --- | --- |
| Starter | `daily_checklists_starter` | `monthly` — QAR 199 | `annual` — QAR 1,990 | `trial-30d` |
| Professional | `daily_checklists_professional` | `monthly` — QAR 499 | `annual` — QAR 4,990 | `trial-30d` |
| Business | `daily_checklists_business` | `monthly` — QAR 999 | `annual` — QAR 9,990 | `trial-30d` |

The purchase UI lives in **CheckAdmin** (`com.moehe.checklists.checklist_admin`). One organization subscription unlocks all three Daily Checklists apps through server-side entitlements.

## Play Console work that requires the account owner

1. Activate the merchant/payments profile for the developer account.
2. In CheckAdmin > Monetize > Products > Subscriptions, create the three product IDs above.
3. For each product create auto-renewing `monthly` and `annual` base plans with the approved Qatar prices. Let Play calculate/localize other-market pricing, then review it before activation.
4. Create a new-customer `trial-30d` offer with a 30-day free phase on the intended eligible base plans. Do not duplicate trials across tiers in a way that permits repeated free trials after plan switching.
5. Enable the Google Play Developer API and grant the backend service account the minimum permissions needed to view subscriptions/orders and acknowledge purchases.
6. Configure Real-time developer notifications (RTDN) to a Pub/Sub topic and push subscription that calls the deployed `google-play-rtdn` Edge Function URL including the generated shared-secret token.
7. Add license testers and Internal testing users. Install CheckAdmin from Google Play Internal Testing, not by sideloading the release APK.

## Supabase secrets (never commit values)

- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` — full JSON service-account credential stored as an Edge Function secret.
- `GOOGLE_PLAY_RTDN_SHARED_SECRET` — random high-entropy token used only by the Pub/Sub push endpoint.

## Server behavior

`google-play-verify-purchase` authenticates an approved organization admin, calls `purchases.subscriptionsv2.get`, maps the verified product to the organization plan, stores only a SHA-256 purchase-token hash in Postgres, updates entitlements, and acknowledges a valid unacknowledged purchase server-side.

`google-play-rtdn` accepts only requests with the shared secret, deduplicates Pub/Sub messages, re-fetches the current subscription from Google (RTDN itself is never trusted as entitlement truth), and updates the same organization entitlement.

## Upgrade / downgrade policy

- Upgrade to a higher tier: immediate `CHARGE_PRORATED_PRICE`.
- Downgrade to a lower tier: `DEFERRED` until the next renewal.
- Every replacement is re-verified server-side and the linked purchase token is used to preserve organization ownership.

## Acceptance test before production

1. New 30-day trial purchase.
2. New monthly paid purchase.
3. Annual purchase.
4. Starter -> Professional upgrade.
5. Business -> Professional downgrade and deferred entitlement transition.
6. Cancel in Play Store; access remains until paid period expiry.
7. Renewal.
8. Grace period / failed payment test.
9. Restore purchase after reinstall.
10. RTDN duplicate delivery is idempotent.
11. A purchase made for one organization cannot be attached to another organization.
12. No client can directly write billing tables or organization subscription state.
