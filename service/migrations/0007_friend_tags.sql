-- Friend tags and in-game friends (no Game Center friendship needed).
-- service/src/friend_tags.js; docs/final/friends.md.
--
-- Every named profile has one friend tag: its approved display name without
-- spaces plus a 4-digit number, e.g. ComfyFrog#4821.  The name part always
-- follows the current display name (so it is always a moderated name); the
-- number stays when the name changes unless that tag is taken.  A tag is
-- unique per environment (each deployment has its own database).
--
-- A player adds a friend by typing that friend's tag (a friend request).
-- The other player accepts (or declines).  When both have requested each
-- other, the second request accepts at once.  An accepted pair is a row in
-- friend_links; presence, status and party invites then treat the pair
-- exactly like mutual Game Center friends.  Blocks (either direction),
-- suspensions and deletion are checked on every read, as for Game Center
-- friends.
--
-- Retention: requests that were answered are deleted after 30 days, and
-- unanswered ones after 30 days too.  Everything here goes with the profile
-- (DELETE /v1/me).  Blocking a player ends the friendship and any request
-- between the two.

CREATE TABLE friend_tags (
  profile_id TEXT PRIMARY KEY,
  tag_key TEXT NOT NULL,              -- lowercase display name without spaces
  disc INTEGER NOT NULL,              -- 1..9999, shown as 4 digits
  updated_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX friend_tags_unique ON friend_tags(tag_key, disc);

CREATE TABLE friend_links (
  a_id TEXT NOT NULL,                 -- the smaller profile id of the pair
  b_id TEXT NOT NULL,                 -- the larger one
  created_at INTEGER NOT NULL,
  PRIMARY KEY (a_id, b_id)
);
CREATE INDEX friend_links_b ON friend_links(b_id);

CREATE TABLE friend_requests (
  id TEXT PRIMARY KEY,
  from_id TEXT NOT NULL,
  to_id TEXT NOT NULL,
  state TEXT NOT NULL,                -- pending | accepted | declined | cancelled
  created_at INTEGER NOT NULL,
  resolved_at INTEGER
);
CREATE UNIQUE INDEX friend_requests_pending ON friend_requests(from_id, to_id) WHERE state = 'pending';
CREATE INDEX friend_requests_to ON friend_requests(to_id, state);
CREATE INDEX friend_requests_from ON friend_requests(from_id, state);
CREATE INDEX friend_requests_created ON friend_requests(created_at);
