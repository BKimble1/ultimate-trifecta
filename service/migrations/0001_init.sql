-- Ultimate Trifecta service schema (Cloudflare D1 / SQLite).
-- Times are milliseconds since the Unix epoch.  Profile IDs are opaque
-- ("p_..."), never the Game Center player ID.

CREATE TABLE profiles (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  display_name TEXT,                 -- approved name as shown
  name_norm TEXT,                    -- lowercase form (duplicates get discriminators)
  discriminator INTEGER,             -- 1..9999, unique per name_norm
  name_set_at INTEGER,               -- last successful rename (cooldown)
  appearance TEXT,                   -- schema-2 appearance (JSON)
  status TEXT NOT NULL DEFAULT 'active',   -- active | suspended
  suspended_until INTEGER,
  forced_rename INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX profiles_name ON profiles(name_norm, discriminator) WHERE name_norm IS NOT NULL;

-- Verified sign-in identities (Game Center teamPlayerID per environment).
CREATE TABLE identities (
  provider TEXT NOT NULL,            -- 'gamecenter'
  subject TEXT NOT NULL,             -- teamPlayerID (verified)
  environment TEXT NOT NULL,         -- production | sandbox | development
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  PRIMARY KEY (provider, subject, environment)
);
CREATE INDEX identities_profile ON identities(profile_id);

-- Revoked session tokens (sign-out) until they would have expired anyway.
CREATE TABLE revoked_sessions (
  jti TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
);

-- Sliding-window rate limits.
CREATE TABLE rate_events (
  key TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX rate_events_key ON rate_events(key, at);

CREATE TABLE name_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  profile_id TEXT NOT NULL,
  attempted TEXT NOT NULL,
  decision TEXT NOT NULL,            -- approved | rejected
  reason TEXT,
  at INTEGER NOT NULL
);
CREATE INDEX name_history_profile ON name_history(profile_id, at);

CREATE TABLE reserved_names (
  name_norm TEXT PRIMARY KEY,
  note TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE blocks (
  blocker_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);
CREATE INDEX blocks_blocked ON blocks(blocked_id);

CREATE TABLE reports (
  id TEXT PRIMARY KEY,               -- receipt shown to the reporter
  reporter_id TEXT,                  -- NULL once the reporter deletes their profile
  target_id TEXT NOT NULL,
  target_name TEXT,                  -- name at the time of the report
  reason TEXT NOT NULL,              -- name | harassment | cheating | inappropriate | other
  details TEXT,
  context TEXT,                      -- JSON: room code, match id, client build
  status TEXT NOT NULL DEFAULT 'open',     -- open | actioned | dismissed
  created_at INTEGER NOT NULL,
  resolved_at INTEGER,
  resolution TEXT,
  resolver TEXT
);
CREATE INDEX reports_status ON reports(status, created_at);
CREATE INDEX reports_target ON reports(target_id);

CREATE TABLE audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER NOT NULL,
  actor TEXT NOT NULL,               -- 'system', 'admin', or a profile id
  action TEXT NOT NULL,
  target TEXT,
  detail TEXT
);
CREATE INDEX audit_at ON audit(at);

-- Party rooms (directory + admission).  Game Center carries the match; the
-- host simulates; this table decides who may join which room.
CREATE TABLE rooms (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL,
  host_profile_id TEXT NOT NULL,
  host_gc_player TEXT NOT NULL,      -- verified teamPlayerID of the host
  state TEXT NOT NULL,               -- forming | open | full | loading | in_match | results | closing | expired
  capacity INTEGER NOT NULL,
  client_build INTEGER NOT NULL,
  protocol INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  heartbeat_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX rooms_code_live ON rooms(code) WHERE state NOT IN ('closing', 'expired');
CREATE INDEX rooms_host ON rooms(host_profile_id);

CREATE TABLE room_members (
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  profile_id TEXT NOT NULL,
  gc_player TEXT NOT NULL,
  slot INTEGER NOT NULL,
  state TEXT NOT NULL,               -- reserved | connected | left
  kicked INTEGER NOT NULL DEFAULT 0, -- removed by the host: may not rejoin this room
  admission_jti TEXT,
  joined_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  PRIMARY KEY (room_id, profile_id)
);
CREATE UNIQUE INDEX room_members_slot ON room_members(room_id, slot) WHERE state != 'left';
