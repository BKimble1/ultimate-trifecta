-- V6 commerce: wallets, an append-only ledger, entitlements, App Store
-- transactions, Season 1 progress and claims, verified round settlement.
-- Every row carries the deployment's environment ('sandbox' | 'production'):
-- TestFlight builds use the sandbox deployment and database, App Store
-- builds production; the column is a second guard so a sandbox credit can
-- never be read as a production balance.  Times are ms since the epoch.

CREATE TABLE wallets (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),   -- never negative: an overdraw fails the whole batch
  debt INTEGER NOT NULL DEFAULT 0 CHECK (debt >= 0),          -- refunded Coins that were already spent
  revision INTEGER NOT NULL DEFAULT 0,                        -- bumped by every change (coins, items, season)
  app_account_token TEXT NOT NULL,                            -- UUID passed to StoreKit (appAccountToken)
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, environment)
);
CREATE UNIQUE INDEX wallets_token ON wallets(app_account_token);

-- Append-only: rows are never updated or deleted (profile deletion only
-- clears profile_id).  idem_key makes every grant/spend happen once.
CREATE TABLE ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  profile_id TEXT,
  environment TEXT NOT NULL,
  idem_key TEXT NOT NULL,
  kind TEXT NOT NULL,             -- grant | spend | revoke
  source TEXT NOT NULL,           -- round | apple | season_claim | legacy_beta | coin_purchase | refund | admin
  amount INTEGER NOT NULL,        -- signed Coins (+grant, -spend); 0 for item-only rows
  balance_after INTEGER NOT NULL,
  revision INTEGER NOT NULL,
  ref TEXT,                       -- match id, transaction id, item id, claim
  catalogue_version INTEGER NOT NULL,
  at INTEGER NOT NULL
);
CREATE UNIQUE INDEX ledger_idem ON ledger(environment, idem_key);
CREATE INDEX ledger_profile ON ledger(profile_id, environment, id);

CREATE TABLE entitlements (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  item_id TEXT NOT NULL,
  source TEXT NOT NULL,           -- coin_purchase | apple | season | legacy_beta | admin
  ref TEXT,
  granted_at INTEGER NOT NULL,
  revoked_at INTEGER,             -- an App Store refund of a direct skin
  PRIMARY KEY (profile_id, environment, item_id)
);

CREATE TABLE apple_transactions (
  environment TEXT NOT NULL,      -- deployment environment
  transaction_id TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  kind TEXT NOT NULL,             -- coin_pack | apple_skin
  coins INTEGER NOT NULL DEFAULT 0,
  profile_id TEXT,                -- who received it (NULL after profile deletion)
  app_account_token TEXT,
  apple_environment TEXT NOT NULL,-- Sandbox | Production (from the signed transaction)
  purchase_date INTEGER,
  state TEXT NOT NULL,            -- delivered | revoked | refused
  delivered_at INTEGER NOT NULL,
  revoked_at INTEGER,
  PRIMARY KEY (environment, transaction_id)
);
CREATE INDEX apple_original ON apple_transactions(environment, original_transaction_id);

CREATE TABLE season_progress (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  season TEXT NOT NULL,
  xp INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
  premium INTEGER NOT NULL DEFAULT 0,
  premium_at INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, environment, season)
);

CREATE TABLE season_claims (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  season TEXT NOT NULL,
  tier INTEGER NOT NULL,
  track TEXT NOT NULL,            -- free | premium
  reward TEXT NOT NULL,           -- item id or coins:N
  result TEXT NOT NULL,           -- granted | already_owned
  at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, environment, season, tier, track)
);

-- Rounds registered by a room host at start and reported at the end.
CREATE TABLE rounds (
  environment TEXT NOT NULL,
  match_id TEXT NOT NULL,
  room_id TEXT NOT NULL,
  host_profile_id TEXT NOT NULL,
  state TEXT NOT NULL,            -- started | reported | cancelled | rejected
  started_at INTEGER NOT NULL,
  reported_at INTEGER,
  outcome INTEGER,
  round_time_s INTEGER,
  coin_spawns INTEGER,
  reject_reason TEXT,
  PRIMARY KEY (environment, match_id)
);
CREATE INDEX rounds_room ON rounds(room_id, started_at);

CREATE TABLE round_players (
  environment TEXT NOT NULL,
  match_id TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  slot INTEGER NOT NULL,
  report TEXT,                    -- the host's row (bounded JSON)
  ack_digest TEXT,                -- the player's own digest of the row it received
  ack_at INTEGER,
  state TEXT NOT NULL,            -- registered | settled | ineligible | mismatch | capped | cancelled | rejected
  reason TEXT,
  coins INTEGER NOT NULL DEFAULT 0,
  xp INTEGER NOT NULL DEFAULT 0,
  settled_at INTEGER,
  PRIMARY KEY (environment, match_id, profile_id)
);
CREATE INDEX round_players_profile ON round_players(profile_id, environment, settled_at);

-- Rewarded rounds per profile per UTC day (the CHECK is the hard cap: a
-- settlement that would pass it fails its batch and is recorded as capped).
CREATE TABLE daily_rounds (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  day TEXT NOT NULL,
  rounds INTEGER NOT NULL DEFAULT 0 CHECK (rounds <= 40),
  PRIMARY KEY (profile_id, environment, day)
);

-- The one-time import of a pre-V6 device balance (source legacy_beta).
CREATE TABLE legacy_imports (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  claimed_coins INTEGER NOT NULL,
  imported_coins INTEGER NOT NULL,
  items TEXT NOT NULL,
  subject_hash TEXT,              -- salted hash of the Game Center player: one import per player, even after a profile is deleted and recreated
  at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, environment)
);
CREATE UNIQUE INDEX legacy_subject ON legacy_imports(environment, subject_hash) WHERE subject_hash IS NOT NULL;

-- App Store Server Notifications V2 seen (idempotent by notificationUUID).
CREATE TABLE apple_notifications (
  uuid TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  subtype TEXT,
  transaction_id TEXT,
  at INTEGER NOT NULL
);
