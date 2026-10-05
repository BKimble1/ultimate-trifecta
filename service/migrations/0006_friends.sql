-- FINAL_RELEASE_SWEEP: Friends (mutual Game Center friends, in-game presence
-- and party invites).  service/src/friends.js; docs/final/friends.md.
--
-- Identity: the only Game Center identity the service trusts is the
-- verified teamPlayerID of a signed-in session (identities.subject).
-- A relationship exists only when two verified players each uploaded a
-- friend list containing the other ("mutual claim").
--
-- Data minimisation: a friend list contains people who may never have used
-- the service, so their IDs are never stored.  Each ID is replaced by a
-- keyed hash (HMAC-SHA256 with the FRIEND_HASH_KEY secret, environment-bound,
-- 128 bits as hex); without the key the hashes say nothing.  A player's own
-- hash (self_hash) is what other players' lists are matched against.
--
-- Retention: a friend set is replaced whole on every sync (a removed or
-- de-authorised friend disappears at once) and is deleted when it is not
-- refreshed for 30 days.  Presence rows live 60 s past their last
-- heartbeat; invites expire after 5 minutes and are deleted after 24 hours.
-- Everything here is deleted with the profile (DELETE /v1/me) and by the
-- cron sweep.  No history is kept.

CREATE TABLE friend_sets (
  profile_id TEXT PRIMARY KEY,        -- the player who uploaded the list
  self_hash TEXT NOT NULL,            -- keyed hash of their own verified teamPlayerID
  synced_at INTEGER NOT NULL,         -- last full replacement (ages out after 30 days)
  size INTEGER NOT NULL               -- how many friend hashes the set holds (<= 500)
);
CREATE UNIQUE INDEX friend_sets_self ON friend_sets(self_hash);
CREATE INDEX friend_sets_synced ON friend_sets(synced_at);

CREATE TABLE friend_claims (
  profile_id TEXT NOT NULL,           -- friend_sets.profile_id
  friend_hash TEXT NOT NULL,          -- keyed hash of one friend's teamPlayerID
  PRIMARY KEY (profile_id, friend_hash)
);
CREATE INDEX friend_claims_hash ON friend_claims(friend_hash);

-- One row per running game (an app launch on one device), never history.
-- The newest launch wins when a player has several (an obsolete device can
-- never overwrite a newer one); seq orders one launch's own heartbeats.
CREATE TABLE presence (
  profile_id TEXT NOT NULL,
  instance TEXT NOT NULL,             -- random per app launch, chosen by the game
  session_jti TEXT NOT NULL,          -- the session that last wrote it (sign-out clears it)
  status TEXT NOT NULL,               -- online | lobby | match
  room_id TEXT,                       -- verified membership only (never shown to friends)
  protocol INTEGER,
  build INTEGER,
  seq INTEGER NOT NULL,
  created_at INTEGER NOT NULL,        -- first heartbeat of this launch
  changed_at INTEGER NOT NULL,        -- last status change
  updated_at INTEGER NOT NULL,        -- last write
  expires_at INTEGER NOT NULL,        -- updated_at + 60 s
  PRIMARY KEY (profile_id, instance)
);
CREATE INDEX presence_expiry ON presence(expires_at);

CREATE TABLE invites (
  id TEXT PRIMARY KEY,
  from_id TEXT NOT NULL,              -- inviter (a verified member of the room)
  to_id TEXT NOT NULL,                -- invitee (a mutual friend)
  room_id TEXT NOT NULL,
  state TEXT NOT NULL,                -- pending | accepted | declined | expired | cancelled
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,        -- created_at + 5 min
  resolved_at INTEGER
);
CREATE INDEX invites_to ON invites(to_id, state, expires_at);
CREATE INDEX invites_from ON invites(from_id, state);
CREATE INDEX invites_created ON invites(created_at);
CREATE UNIQUE INDEX invites_pending ON invites(from_id, to_id, room_id) WHERE state = 'pending';
