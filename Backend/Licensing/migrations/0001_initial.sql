CREATE TABLE licenses (
  id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK (status IN ('active', 'revoked', 'refunded', 'disputed')),
  stripe_customer_id TEXT,
  stripe_checkout_session_id TEXT NOT NULL UNIQUE,
  stripe_payment_intent_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE activations (
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
  device_hash TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  revoked_at INTEGER,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  UNIQUE (license_id, device_hash)
);

CREATE INDEX activations_license_id_idx ON activations(license_id);

CREATE TABLE checkout_claims (
  stripe_checkout_session_id TEXT PRIMARY KEY,
  installation_id_hash TEXT NOT NULL,
  encrypted_license_key TEXT NOT NULL,
  claimed_at INTEGER,
  expires_at INTEGER NOT NULL
);

CREATE TABLE webhook_events (
  stripe_event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  processed_at INTEGER
);
