import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import Stripe from "stripe";
import worker, { type Env } from "../src/index";
import { decrypt, hmac, sha256 } from "../src/crypto";

// Exercise production SQL against real SQLite, with atomic D1-style batches.
class LocalD1 {
  readonly db = new DatabaseSync(":memory:");
  private batchTail: Promise<unknown> = Promise.resolve();
  constructor() {
    this.db.exec(readFileSync("migrations/0001_initial.sql", "utf8"));
    this.db.exec(readFileSync("migrations/0002_payment_revocations.sql", "utf8"));
  }
  prepare(sql: string) {
    const db = this.db;
    let values: (string | number | null)[] = [];
    const query = {
      bind(...parameters: (string | number | null)[]) { values = parameters; return query; },
      async first() { return db.prepare(sql).get(...values) ?? null; },
      async run() { return { meta: { changes: Number(db.prepare(sql).run(...values).changes) } }; }
    };
    return query;
  }
  batch(statements: { run(): Promise<unknown> }[]) {
    const operation = this.batchTail.then(async () => {
      this.db.exec("BEGIN");
      try {
        const results = [];
        for (const statement of statements) results.push(await statement.run());
        this.db.exec("COMMIT");
        return results;
      } catch (error) { this.db.exec("ROLLBACK"); throw error; }
    });
    this.batchTail = operation.catch(() => {});
    return operation;
  }

}

async function environment() {
  const database = new LocalD1();
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const env = {
    DB: database, MAX_ACTIVATIONS: "1", STRIPE_PRICE_ID: "price_primary",
    APP_ORIGIN: "https://primarypaste.example", STRIPE_AUTOMATIC_TAX_ENABLED: "false", TAX_REGISTRATION_CONFIRMED: "false",
    STRIPE_SECRET_KEY: "test-only-key", STRIPE_WEBHOOK_SECRET: "test-only-signature-secret",
    LICENSE_KEY_PEPPER: crypto.randomUUID(), CLAIM_ENCRYPTION_KEY: crypto.randomUUID(),
    ENTITLEMENT_SIGNING_JWK: JSON.stringify(await crypto.subtle.exportKey("jwk", keys.privateKey))
  } as unknown as Env;
  return { env, database, keys };
}

function request(path: string, body: unknown) {
  return new Request(`https://licensing.example${path}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
}

async function webhook(env: Env, id: string, type: string, object: object) {
  const payload = JSON.stringify({ id, type, data: { object } });
  const signature = Stripe.webhooks.generateTestHeaderString({ payload, secret: env.STRIPE_WEBHOOK_SECRET });
  return worker.fetch(new Request("https://licensing.example/webhooks/stripe", {
    method: "POST", headers: { "stripe-signature": signature }, body: payload
  }), env);
}

async function checkout(installationID = "installation") {
  const hash = await sha256(installationID);
  return { id: "cs_primary", mode: "payment", payment_status: "paid", metadata: { installation_id_hash: hash },
    client_reference_id: hash, payment_intent: "pi_primary", customer: { id: "cus_primary" },
    line_items: { has_more: false, data: [{ price: { id: "price_primary" }, quantity: 1 }] } };
}

async function seedLicense(env: Env, database: LocalD1, key = "PP-TEST-KEY") {
  database.db.prepare(`INSERT INTO licenses (id, key_hash, status, stripe_checkout_session_id, created_at, updated_at)
    VALUES ('license', ?, 'active', 'cs_seed', 1, 1)`).run(await hmac(key, env.LICENSE_KEY_PEPPER));
  return key;
}

test("malformed JSON, empty fields, content type, and streamed size produce client errors", async () => {
  const { env, database } = await environment();
  try {
    for (const [body, status] of [["{", 400], ["[]", 400], ['{"installation_id":"   "}', 400], ["x".repeat(17_000), 413]] as const) {
      const response = await worker.fetch(new Request("https://licensing.example/v1/checkout-sessions", {
        method: "POST", headers: { "content-type": "application/json" }, body
      }), env);
      assert.equal(response.status, status);
      assert.equal(response.headers.get("cache-control"), "no-store");
    }
    const response = await worker.fetch(new Request("https://licensing.example/v1/checkout-sessions", { method: "POST", body: "{}" }), env);
    assert.equal(response.status, 415);
    assert.equal((await worker.fetch(new Request("https://licensing.example/checkout/success?session_id=%22bad"), env)).status, 400);
    assert.equal((await worker.fetch(new Request("https://licensing.example/checkout/cancelled"), env)).status, 200);
  } finally { database.db.close(); }
});

test("duplicate fulfillment produces one license and matching claim; lost claim responses can be retried", async t => {
  const { env, database } = await environment();
  const session = await checkout();
  t.mock.method(globalThis, "fetch", async () => Response.json(session));
  try {
    const results = await Promise.all([
      webhook(env, "evt_first", "checkout.session.completed", session),
      webhook(env, "evt_second", "checkout.session.async_payment_succeeded", session)
    ]);
    assert.deepEqual(results.map(result => result.status), [200, 200]);
    assert.equal((await webhook(env, "evt_first", "checkout.session.completed", session)).status, 200);
    const licenses = database.db.prepare("SELECT * FROM licenses").all();
    assert.equal(licenses.length, 1);
    const claim = database.db.prepare("SELECT * FROM checkout_claims").get()!;
    const key = await decrypt(String(claim.encrypted_license_key), env.CLAIM_ENCRYPTION_KEY);
    assert.equal(licenses[0].key_hash, await hmac(key, env.LICENSE_KEY_PEPPER));
    for (let i = 0; i < 2; i++) {
      const response = await worker.fetch(request("/v1/checkout/claim", { session_id: session.id, installation_id: "installation" }), env);
      assert.equal(response.status, 200);
      assert.equal((await response.json() as { licenseKey: string }).licenseKey, key);
    }
    assert.equal((await worker.fetch(request("/v1/checkout/claim", { session_id: session.id, installation_id: "other" }), env)).status, 409);
    database.db.prepare("UPDATE checkout_claims SET expires_at = 1").run();
    await worker.scheduled({} as ScheduledController, env);
    assert.equal(database.db.prepare("SELECT encrypted_license_key FROM checkout_claims").get()?.encrypted_license_key, "");
    assert.equal((await worker.fetch(request("/v1/checkout/claim", { session_id: session.id, installation_id: "installation" }), env)).status, 409);
  } finally { database.db.close(); }
});

test("activation seats are atomic, revoked devices cannot bypass the limit, and refresh is retryable", async () => {
  const { env, database, keys } = await environment();
  try {
    const key = await seedLicense(env, database);
    const [first, second] = await Promise.all(["a", "b"].map(device => worker.fetch(request("/v1/licenses/activate", {
      license_key: key, device_hash: device.repeat(64)
    }), env)));
    assert.deepEqual([first.status, second.status].sort(), [200, 409]);
    const active = first.status === 200 ? first : second;
    const device = first.status === 200 ? "a" : "b";
    const body = await active.json() as { activationToken: string; entitlementToken: string };
    const [header, payload, signature] = body.entitlementToken.split(".");
    assert.equal(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, keys.publicKey,
      Buffer.from(signature, "base64url"), new TextEncoder().encode(`${header}.${payload}`)), true);
    assert.equal(JSON.parse(Buffer.from(payload, "base64url").toString()).device_hash, device.repeat(64));
    for (let i = 0; i < 2; i++) {
      const response = await worker.fetch(request("/v1/licenses/refresh", { activation_token: body.activationToken }), env);
      assert.equal(response.status, 200);
      assert.equal((await response.json() as { activationToken: string }).activationToken, body.activationToken);
    }
    assert.equal((await worker.fetch(request("/v1/licenses/deactivate", { activation_token: body.activationToken }), env)).status, 200);
    assert.equal((await worker.fetch(request("/v1/licenses/refresh", { activation_token: body.activationToken }), env)).status, 403);
    assert.equal((await worker.fetch(request("/v1/licenses/activate", { license_key: key, device_hash: "c".repeat(64) }), env)).status, 200);
    assert.equal((await worker.fetch(request("/v1/licenses/activate", { license_key: key, device_hash: device.repeat(64) }), env)).status, 409);
  } finally { database.db.close(); }
});

test("refunds and disputes arriving before fulfillment stay revoked after fulfillment", async t => {
  const { env, database } = await environment();
  const session = await checkout();
  t.mock.method(globalThis, "fetch", async () => Response.json(session));
  try {
    assert.equal((await webhook(env, "evt_refund", "charge.refunded", { payment_intent: { id: "pi_primary" } })).status, 200);
    assert.equal((await webhook(env, "evt_paid", "checkout.session.completed", session)).status, 200);
    assert.equal(database.db.prepare("SELECT status FROM licenses").get()?.status, "refunded");
    assert.equal((await worker.fetch(request("/v1/checkout/claim", { session_id: session.id, installation_id: "installation" }), env)).status, 409);
    assert.equal((await webhook(env, "evt_dispute", "charge.dispute.created", { payment_intent: "pi_primary" })).status, 200);
    assert.equal(database.db.prepare("SELECT status FROM licenses").get()?.status, "disputed");
  } finally { database.db.close(); }
});

test("invalid webhook signatures and wrong products never provision licenses", async t => {
  const { env, database } = await environment();
  const session = await checkout();
  session.line_items.data[0].price.id = "price_wrong";
  t.mock.method(globalThis, "fetch", async () => Response.json(session));
  t.mock.method(console, "error", () => {});
  try {
    const invalid = new Request("https://licensing.example/webhooks/stripe", {
      method: "POST", headers: { "stripe-signature": "invalid" }, body: "{}"
    });
    assert.equal((await worker.fetch(invalid, env)).status, 400);
    assert.equal((await webhook(env, "evt_wrong", "checkout.session.completed", session)).status, 500);
    assert.equal(database.db.prepare("SELECT COUNT(*) AS count FROM licenses").get()?.count, 0);
    assert.equal(database.db.prepare("SELECT processed_at FROM webhook_events").get()?.processed_at, null);
  } finally { database.db.close(); }
});
