-- Pass 8: Coin purchases made through a scheduled rotating Shop offer
-- (service/src/offers.js).  One row per accepted purchase, written in the
-- same batch as the debit, the ledger row and the permanent entitlement: the
-- record of which offer was bought, at what price, under which schedule
-- revision, and the service time at which it was accepted.  The CHECK makes
-- "accepted while the offer was on sale" part of the schema, so an
-- acceptance outside the offer's window fails the whole batch (nothing is
-- charged).  A replay of the same idempotency key returns this row.
CREATE TABLE offer_sales (
  environment TEXT NOT NULL,
  idem_key TEXT NOT NULL,          -- the ledger's key (spend:<profile>:<client key>)
  profile_id TEXT,                 -- NULL after profile deletion (kept for reconciliation)
  offer_id TEXT NOT NULL,
  item_id TEXT NOT NULL,           -- the permanent entitlement it granted
  price INTEGER NOT NULL,
  schedule_revision INTEGER NOT NULL,
  offer_starts_at INTEGER NOT NULL,
  offer_ends_at INTEGER NOT NULL,
  accepted_at INTEGER NOT NULL,
  CONSTRAINT offer_window CHECK (accepted_at >= offer_starts_at AND accepted_at < offer_ends_at),
  PRIMARY KEY (environment, idem_key)
);
CREATE INDEX offer_sales_profile ON offer_sales(profile_id, environment);
CREATE INDEX offer_sales_offer ON offer_sales(environment, offer_id);
