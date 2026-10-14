-- Retain refunds/disputes even if their webhook arrives before fulfillment.
CREATE TABLE payment_revocations (
  payment_intent_id TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK (status IN ('refunded', 'disputed'))
);
CREATE INDEX licenses_payment_intent_idx ON licenses(stripe_payment_intent_id);
