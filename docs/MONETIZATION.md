# Daily Checklists monetization architecture

## Commercial model
Daily Checklists is sold as one B2B SaaS subscription per organization. CheckIn, CheckView and CheckAdmin share the same entitlement.

## Approved pricing
| Plan | Monthly | Annual | Users | Sites | Storage |
| --- | ---: | ---: | ---: | ---: | ---: |
| Trial | Free for 30 days | — | 10 | 1 | 5 GB |
| Starter | QAR 199 | QAR 1,990 | 10 | 1 | 5 GB |
| Professional | QAR 499 | QAR 4,990 | 50 | 5 | 25 GB |
| Business | QAR 999 | QAR 9,990 | 200 | 20 | 100 GB |
| Enterprise | Custom | From QAR 20,000 | Contract | Contract | Contract |

Professional is the recommended/default commercial tier. Annual pricing gives the equivalent of two months free.

## Enforcement
Plan catalog and organization entitlements are server-owned. Authenticated clients may read them but cannot change billing state. Active user and site limits are enforced in PostgreSQL triggers, not only in Flutter. Expired, canceled, or unpaid organizations cannot activate additional users/sites. Platform billing recovery remains server-controlled.

## Billing channels
The entitlement ledger supports `google_play`, `external_contract`, and `manual`. Provider receipts/tokens must be verified by a trusted server before changing `organization_subscriptions`.

For Google Play distribution, do not add a web checkout link inside Android unless the applicable Play program/market rules permit it. If a subscription is purchased in-app, use Google Play Billing and verify purchases server-side. Existing B2B contract customers can sign in to a consumption-only deployment without an in-app checkout.

## Google Play product mapping
Create monthly and annual Play base plans for Starter, Professional, and Business. Store Play product/base-plan IDs in trusted server configuration, never in entitlement logic. Enterprise remains sales/contract led unless a later Play-supported purchase flow is deliberately added.

## Production activation checklist
1. Create Play Console subscription products/base plans.
2. Configure Google Play Developer API service credentials on the server.
3. Implement server-side purchase-token verification and idempotent billing events.
4. Configure Real-time Developer Notifications for renewals, cancellations, grace periods and revocations.
5. Map verified provider state to `organization_subscriptions`.
6. Test purchase, renewal, cancellation, grace, restore and refund in Internal Testing before production.
