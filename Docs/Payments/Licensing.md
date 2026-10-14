# Payments and Licensing

Licensing is implemented, locally tested, and disabled. Production readiness remains unverified. `LicensingEnabled` and `LicensingEnforcementEnabled` are `false` in the app Info.plist, and the Worker configuration contains placeholder resource identifiers. The app has no payment secret and does not load a payment SDK. The enforcement path is already wired into paste and capture engines, but it allows product use while enforcement is off.

## Flow

1. The app asks the licensing API for a Stripe Checkout Session.
2. The API creates a hosted, one-time-payment Checkout Session. Payment details stay on Stripe-hosted pages.
3. Stripe sends a signed webhook to the Worker. The Worker verifies the raw request body before it provisions a license.
4. The success page opens `primarypaste://license/claim?session_id=...`.
5. The app claims the license key using its installation identifier, then activates it for its random installation identifier.
6. The Worker returns an opaque activation token and a signed ES256 entitlement.
7. The app stores the license key, activation token, and entitlement in Keychain. It verifies the entitlement offline with the embedded public key.
8. The app refreshes online after seven days and retries failed automatic refreshes at most hourly. The signed entitlement remains usable until its 30-day offline expiry. A verified revocation removes the cached entitlement.
9. Deactivation revokes one installation. Refund and dispute events revoke the license.

The server stores only a keyed hash of each license key and a hash of each activation token. A new license key is encrypted only for the short claim window and returned only to the originating installation during that 24-hour window. Claims remain retryable within that window so a lost response cannot strand a purchase. An hourly scheduled Worker handler purges expired ciphertext. Verify that schedule on the deployed Worker before public enablement.

## Backend

The private Worker is in `Backend/Licensing`. It uses Stripe Checkout, Cloudflare Workers, and D1. Its endpoints are:

- `POST /v1/checkout-sessions`
- `POST /v1/checkout/claim`
- `POST /v1/licenses/activate`
- `POST /v1/licenses/refresh`
- `POST /v1/licenses/deactivate`
- `POST /webhooks/stripe`

Run local checks with:

```sh
npm --prefix Backend/Licensing ci
npm --prefix Backend/Licensing run check
```

## Provisioning

Do these steps only when payments are ready to enable:

1. Create a D1 database named `primary-paste-licensing` (`cf d1 create`). Replace the placeholder `config.d1DatabaseId` in `Backend/Licensing/package.json` with its ID. `cloudflare.config.ts` and the migration scripts both read it.
2. Create a one-time Stripe Price and replace `REPLACE_WITH_STRIPE_PRICE_ID`.
3. Replace `APP_ORIGIN` with the HTTPS Worker or product site origin.
4. Generate a P-256 signing key. Store the private JWK only as a Worker secret. Put its X9.63 public-key bytes, Base64 encoded, in `LicensingPublicKey` in the app build configuration.
5. Generate independent high-entropy values for `LICENSE_KEY_PEPPER` and `CLAIM_ENCRYPTION_KEY`.
6. Use a dedicated [Stripe restricted API key](https://docs.stripe.com/keys/restricted-api-keys) with permissions verified against the test-mode calls. Store it under the existing `STRIPE_SECRET_KEY` secret name. Store all secrets with `cf workers secrets update <NAME> --worker primary-paste-licensing --body @/dev/stdin`: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `LICENSE_KEY_PEPPER`, `CLAIM_ENCRYPTION_KEY`, and `ENTITLEMENT_SIGNING_JWK`. Pipe a JSON object with `name`, `type: "secret_text"` and `text` over stdin, so the value never appears in command arguments or shell history. Never commit their values.
7. Apply D1 migrations with `npm --prefix Backend/Licensing run db:migrate:remote`.
8. Register the Worker webhook URL in Stripe and subscribe to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `charge.refunded`, and `charge.dispute.created`.
9. Complete an end-to-end test in Stripe test mode. Test success, repeat and concurrent webhook delivery, same-installation claim retries, wrong-installation/expired claims, activation limits including revoked-device reactivation, refresh, deactivation, refund, and dispute paths.
10. Set the real API URL and public key in the app. Set `LicensingEnabled` to `true` only for a release that passed those checks.
11. Keep `LicensingEnforcementEnabled` off during purchase testing. Turn it on only after activation, offline use, refresh, deactivation, refund, and recovery tests pass in a signed release build.

## Tax Safety

Automatic tax is off. Keep both `STRIPE_AUTOMATIC_TAX_ENABLED` and `TAX_REGISTRATION_CONFIRMED` set to `false` until the business has an active tax registration in every jurisdiction where Stripe Tax will collect. The Worker refuses to enable automatic tax unless both values are true.

## Operations

- Rotate the Stripe restricted key, webhook secret, claim encryption key, and license pepper through Cloudflare secrets. A pepper rotation needs an explicit key-reissue plan because stored license hashes depend on it.
- Keep the entitlement signing key stable across ordinary releases. To rotate it, ship the new public key before the Worker signs with the new private key.
- Do not log license keys, activation tokens, entitlement tokens, checkout customer data, selected text, clipboard contents, or file paths.
- D1 migrations are append-only after deployment. This repository is not deployed, so obsolete schema can still be replaced directly before first launch.

## Local regression evidence

`npm run check` includes integration tests against real SQLite using the production D1 statements. Tests generate real webhook signatures and ES256 entitlements and supply synthetic Stripe API responses. They cover malformed and oversized requests, duplicate fulfillment, matching claim/license keys, claim retries and installation binding, activation seat contention, refresh retries, deactivation, refund-before-fulfillment ordering, invalid signatures, and unexpected prices.

Fulfillment retrieves the current Checkout Session with expanded line items and verifies the configured price, quantity, payment status, mode, and installation binding. Refund/dispute identifiers persist before fulfillment, so out-of-order delivery cannot revive a revoked purchase. Claims and activation limits are enforced in the database. Refresh uses a stable opaque activation token, allowing retries after response loss; deactivation and license revocation still invalidate it.

These tests do not prove live Stripe configuration, Cloudflare D1 deployment, tax registration, payment-method acceptance, email delivery, or signed-app purchase recovery. Before public enablement, configure request rate limits, verify the expired-claim cleanup schedule, and set real resource IDs/secrets, webhook subscriptions, and the full test-mode journey above. No deployment or payment provisioning is performed by local checks.
