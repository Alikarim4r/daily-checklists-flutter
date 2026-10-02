# Daily Checklists monetization architecture

## Commercial model

Daily Checklists is sold as one B2B SaaS subscription per organization. CheckIn, CheckView and CheckAdmin are clients of the same entitlement; customers do not buy three separate subscriptions.

### Plans

- Starter: up to 10 users and 1 site.
- Professional: up to 50 users and 25 sites; recommended default for facilities teams.
- Enterprise: contract-defined users/sites, onboarding and commercial terms.
- Trial: temporary entitlement for evaluation; duration is set server-side.

Prices are intentionally not hard-coded in the apps. The commercial price can change without an app release and Play-facing prices must come from the configured billing product where an in-app Play purchase is offered.

## Billing channels

The entitlement ledger supports `google_play`, `external_contract`, and `manual`. Provider receipts/tokens must be verified by a trusted server before changing `organization_subscriptions`. Mobile clients have SELECT-only access to subscription state.

For Google Play distribution, do not add a web checkout link inside the Android apps unless the relevant Google Play program/market rules explicitly permit it. If digital SaaS is purchased in-app, integrate Google Play Billing and verify purchases server-side. A consumption-only B2B deployment can allow existing contracted customers to sign in without offering an in-app purchase flow.

## Access policy

Billing is organization-scoped. Expired/past-due state must be enforced server-side for paid capabilities; UI gating alone is not security. Platform owners retain an operational recovery path. Existing production organizations receive a launch-period Professional entitlement during migration so deployment cannot accidentally lock out the current tenant.

## Next provider step

Before accepting real money: create the commercial products in Play Console (if using in-app Play subscriptions), configure server credentials/notifications, implement verified purchase lifecycle handling, then map provider product IDs to Starter/Professional/Enterprise without storing secret credentials in Flutter.
