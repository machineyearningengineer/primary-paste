import Stripe from "stripe";
import { signEntitlement, sha256, hmac, encrypt, decrypt, makeLicenseKey, randomToken, randomLetters, unixNow } from "./crypto";
import { RequestError, readBody, readText, requiredString, json, checkoutReturnPage } from "./http";

export type Env = Cloudflare.Env & {
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  LICENSE_KEY_PEPPER: string;
  CLAIM_ENCRYPTION_KEY: string;
  ENTITLEMENT_SIGNING_JWK: string;
};


const stripeVersion = "2026-06-24.dahlia" as Stripe.LatestApiVersion;


export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        return json({ ok: true });
      }
      if (request.method === "GET" && url.pathname === "/checkout/success") {
        return checkoutReturnPage(url.searchParams.get("session_id"));
      }
      if (request.method === "GET" && url.pathname === "/checkout/cancelled") {
        return new Response("Purchase cancelled. You can return to Primary Paste and try again.", { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
      }
      if (request.method === "POST" && url.pathname === "/webhooks/stripe") {
        return await handleWebhook(request, env);
      }
      if (request.method !== "POST") return json({ error: "not_found" }, 404);

      switch (url.pathname) {
        case "/v1/checkout-sessions": return await createCheckout(request, env);
        case "/v1/checkout/claim": return await claimCheckout(request, env);
        case "/v1/licenses/activate": return await activate(request, env);
        case "/v1/licenses/refresh": return await refresh(request, env);
        case "/v1/licenses/deactivate": return await deactivate(request, env);
        default: return json({ error: "not_found" }, 404);
      }
    } catch (error) {
      if (error instanceof RequestError) return json({ error: error.code }, error.status);
      console.error(JSON.stringify({ event: "request_failed", error: error instanceof Error ? error.name : "UnknownError" }));
      return json({ error: "request_failed" }, 500);
    }
  },
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    await env.DB.prepare("UPDATE checkout_claims SET encrypted_license_key = '' WHERE expires_at <= ? AND encrypted_license_key != ''")
      .bind(unixNow()).run();
  }
} satisfies ExportedHandler<Env>;

async function createCheckout(request: Request, env: Env): Promise<Response> {
  const body = await readBody(request);
  const installationID = requiredString(body, "installation_id", 128);
  const stripe = stripeClient(env);
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [{ price: env.STRIPE_PRICE_ID, quantity: 1 }],
    success_url: `${env.APP_ORIGIN}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${env.APP_ORIGIN}/checkout/cancelled`,
    client_reference_id: await sha256(installationID),
    metadata: { installation_id_hash: await sha256(installationID) },
    automatic_tax: { enabled: automaticTaxEnabled(env) },
    integration_identifier: `primary_paste_${randomLetters(8)}`
  });
  if (!session.url) throw new Error("checkout_url_missing");
  return json({ checkoutURL: session.url });
}

async function claimCheckout(request: Request, env: Env): Promise<Response> {
  const body = await readBody(request);
  const sessionID = requiredString(body, "session_id", 128);
  const installationHash = await sha256(requiredString(body, "installation_id", 128));
  await ensurePurchase(sessionID, installationHash, env);
  const claim = await env.DB.prepare(
    `SELECT checkout_claims.installation_id_hash, encrypted_license_key, claimed_at, expires_at
     FROM checkout_claims JOIN licenses USING (stripe_checkout_session_id)
     WHERE stripe_checkout_session_id = ? AND licenses.status = 'active'`
  ).bind(sessionID).first<{ installation_id_hash: string; encrypted_license_key: string; claimed_at: number | null; expires_at: number }>();
  if (!claim || claim.installation_id_hash !== installationHash || claim.expires_at <= unixNow()) {
    return json({ error: "claim_unavailable" }, 409);
  }
  const licenseKey = await decrypt(claim.encrypted_license_key, env.CLAIM_ENCRYPTION_KEY);
  // The installation-bound claim remains retryable until expiry so a lost
  // response cannot strand a completed purchase. Purge ciphertext after expiry.
  await env.DB.prepare(
    "UPDATE checkout_claims SET claimed_at = COALESCE(claimed_at, ?) WHERE stripe_checkout_session_id = ?"
  ).bind(unixNow(), sessionID).run();
  return json({ licenseKey });
}

async function activate(request: Request, env: Env): Promise<Response> {
  const body = await readBody(request);
  const licenseKey = requiredString(body, "license_key", 128).toUpperCase();
  const deviceHash = requiredString(body, "device_hash", 64);
  if (!/^[a-f0-9]{64}$/.test(deviceHash)) throw new RequestError("invalid_device_hash", 400);
  const license = await env.DB.prepare("SELECT id, status FROM licenses WHERE key_hash = ?")
    .bind(await hmac(licenseKey, env.LICENSE_KEY_PEPPER)).first<{ id: string; status: string }>();
  if (!license || license.status !== "active") return json({ error: "license_invalid" }, 403);

  const limit = Number(env.MAX_ACTIVATIONS);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("invalid_activation_limit");
  const activationToken = randomToken();
  const now = unixNow();
  // The seat check and write share one SQLite statement. Reactivating a revoked
  // device uses a seat just like a new device; active devices keep their seat.
  const activation = await env.DB.prepare(
    `INSERT INTO activations (id, license_id, device_hash, token_hash, created_at, last_seen_at)
     SELECT ?, ?, ?, ?, ?, ?
     WHERE EXISTS (SELECT 1 FROM licenses WHERE id = ? AND status = 'active')
       AND ((SELECT COUNT(*) FROM activations WHERE license_id = ? AND revoked_at IS NULL) < ?
         OR EXISTS (SELECT 1 FROM activations WHERE license_id = ? AND device_hash = ? AND revoked_at IS NULL))
     ON CONFLICT (license_id, device_hash) DO UPDATE SET token_hash = excluded.token_hash,
       revoked_at = NULL, last_seen_at = excluded.last_seen_at
     RETURNING id`
  ).bind(crypto.randomUUID(), license.id, deviceHash, await sha256(activationToken), now, now,
    license.id, license.id, limit, license.id, deviceHash).first<{ id: string }>();
  if (!activation) return json({ error: "activation_limit" }, 409);
  return activationResponse(env, license.id, activation.id, deviceHash, activationToken);
}

async function refresh(request: Request, env: Env): Promise<Response> {
  const token = requiredString(await readBody(request), "activation_token", 256);
  const activation = await findActivation(token, env);
  if (!activation || activation.status !== "active" || activation.revoked_at) {
    return json({ error: "activation_invalid" }, 403);
  }
  // Refresh does not rotate the opaque token: the response may be lost and
  // retried. Deactivation and license revocation still invalidate it immediately.
  const update = await env.DB.prepare(
    `UPDATE activations SET last_seen_at = ? WHERE id = ? AND token_hash = ? AND revoked_at IS NULL
     AND EXISTS (SELECT 1 FROM licenses WHERE id = activations.license_id AND status = 'active')`
  ).bind(unixNow(), activation.id, await sha256(token)).run();
  if (update.meta.changes !== 1) return json({ error: "activation_invalid" }, 403);
  return activationResponse(env, activation.license_id, activation.id, activation.device_hash, token);
}

async function deactivate(request: Request, env: Env): Promise<Response> {
  const token = requiredString(await readBody(request), "activation_token", 256);
  await env.DB.prepare("UPDATE activations SET revoked_at = ? WHERE token_hash = ?")
    .bind(unixNow(), await sha256(token)).run();
  return json({});
}

async function handleWebhook(request: Request, env: Env): Promise<Response> {
  const rawBody = await readText(request, 1_048_576);
  const signature = request.headers.get("stripe-signature");
  if (!signature) return json({ error: "signature_missing" }, 400);
  let event: Stripe.Event;
  try {
    event = await stripeClient(env).webhooks.constructEventAsync(rawBody, signature, env.STRIPE_WEBHOOK_SECRET);
  } catch {
    return json({ error: "signature_invalid" }, 400);
  }
  const insert = await env.DB.prepare(
    "INSERT OR IGNORE INTO webhook_events (stripe_event_id, event_type, received_at) VALUES (?, ?, ?)"
  ).bind(event.id, event.type, unixNow()).run();
  if (insert.meta.changes === 0) {
    const previous = await env.DB.prepare("SELECT processed_at FROM webhook_events WHERE stripe_event_id = ?")
      .bind(event.id).first<{ processed_at: number | null }>();
    if (previous?.processed_at) return json({ received: true });
  }

  if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
    const session = await stripeClient(env).checkout.sessions.retrieve(event.data.object.id, { expand: ["line_items"] });
    await provisionPurchase(session, env);
  } else if (event.type === "charge.refunded" || event.type === "charge.dispute.created") {
    const object = event.data.object as Stripe.Charge | Stripe.Dispute;
    let paymentIntentID = resourceID(object.payment_intent);
    if (!paymentIntentID && event.type === "charge.dispute.created") {
      const chargeID = resourceID((object as Stripe.Dispute).charge);
      if (chargeID) paymentIntentID = resourceID((await stripeClient(env).charges.retrieve(chargeID)).payment_intent);
    }
    if (!paymentIntentID) throw new Error("payment_intent_missing");
    const status = event.type === "charge.refunded" ? "refunded" : "disputed";
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO payment_revocations (payment_intent_id, status) VALUES (?, ?)
        ON CONFLICT (payment_intent_id) DO UPDATE SET status = excluded.status`).bind(paymentIntentID, status),
      env.DB.prepare("UPDATE licenses SET status = ?, updated_at = ? WHERE stripe_payment_intent_id = ?")
        .bind(status, unixNow(), paymentIntentID)
    ]);
  }
  await env.DB.prepare("UPDATE webhook_events SET processed_at = ? WHERE stripe_event_id = ?")
    .bind(unixNow(), event.id).run();
  return json({ received: true });
}

async function ensurePurchase(sessionID: string, installationHash: string, env: Env): Promise<void> {
  const existing = await env.DB.prepare(
    "SELECT stripe_checkout_session_id FROM checkout_claims WHERE stripe_checkout_session_id = ?"
  ).bind(sessionID).first();
  if (existing) return;
  const session = await stripeClient(env).checkout.sessions.retrieve(sessionID, { expand: ["line_items"] });
  if (session.metadata?.installation_id_hash !== installationHash) throw new RequestError("claim_unavailable", 409);
  if (session.payment_status !== "paid") throw new RequestError("checkout_not_paid", 409);
  await provisionPurchase(session, env);
}

async function provisionPurchase(session: Stripe.Checkout.Session, env: Env): Promise<void> {
  if (session.payment_status !== "paid") return;
  const lines = session.line_items;
  if (session.mode !== "payment" || !lines || lines.has_more || lines.data.length !== 1
    || lines.data[0].price?.id !== env.STRIPE_PRICE_ID || lines.data[0].quantity !== 1) {
    throw new Error("unexpected_checkout_product");
  }
  const installationHash = session.metadata?.installation_id_hash;
  if (!installationHash || session.client_reference_id !== installationHash) throw new Error("installation_hash_missing");
  const paymentIntentID = resourceID(session.payment_intent);
  if (!paymentIntentID) throw new Error("payment_intent_missing");
  const licenseKey = makeLicenseKey();
  const licenseID = crypto.randomUUID();
  const now = unixNow();
  const encryptedKey = await encrypt(licenseKey, env.CLAIM_ENCRYPTION_KEY);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT OR IGNORE INTO licenses
       (id, key_hash, status, stripe_customer_id, stripe_checkout_session_id, stripe_payment_intent_id, created_at, updated_at)
       VALUES (?, ?, COALESCE((SELECT status FROM payment_revocations WHERE payment_intent_id = ?), 'active'), ?, ?, ?, ?, ?)`
    ).bind(licenseID, await hmac(licenseKey, env.LICENSE_KEY_PEPPER), paymentIntentID, resourceID(session.customer), session.id, paymentIntentID, now, now),
    env.DB.prepare(
      `INSERT OR IGNORE INTO checkout_claims
       (stripe_checkout_session_id, installation_id_hash, encrypted_license_key, expires_at)
       SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM licenses WHERE id = ? AND stripe_checkout_session_id = ?)`
    ).bind(session.id, installationHash, encryptedKey, now + 86_400, licenseID, session.id)
  ]);
}

async function activationResponse(
  env: Env,
  licenseID: string,
  activationID: string,
  deviceHash: string,
  activationToken: string
): Promise<Response> {
  const now = unixNow();
  const entitlementToken = await signEntitlement({
    iss: "primary-paste-licensing",
    aud: "com.abel.primarypaste",
    license_id: licenseID,
    activation_id: activationID,
    device_hash: deviceHash,
    entitlement: "primary-paste",
    iat: now,
    refresh_after: now + 7 * 86_400,
    exp: now + 30 * 86_400
  }, env.ENTITLEMENT_SIGNING_JWK);
  return json({ activationToken, entitlementToken });
}

async function findActivation(token: string, env: Env) {
  return env.DB.prepare(
    `SELECT activations.id, activations.license_id, activations.device_hash, activations.revoked_at, licenses.status
     FROM activations JOIN licenses ON licenses.id = activations.license_id
     WHERE activations.token_hash = ?`
  ).bind(await sha256(token)).first<{
    id: string; license_id: string; device_hash: string; revoked_at: number | null; status: string;
  }>();
}

function stripeClient(env: Env): Stripe {
  return new Stripe(env.STRIPE_SECRET_KEY, { apiVersion: stripeVersion, httpClient: Stripe.createFetchHttpClient() });
}

function automaticTaxEnabled(env: Env): boolean {
  const requested = env.STRIPE_AUTOMATIC_TAX_ENABLED === "true";
  const confirmed = env.TAX_REGISTRATION_CONFIRMED === "true";
  if (requested && !confirmed) throw new Error("tax_registration_not_confirmed");
  return requested && confirmed;
}


function resourceID(value: string | { id: string } | null | undefined): string {
  return typeof value === "string" ? value : value?.id ?? "";
}
