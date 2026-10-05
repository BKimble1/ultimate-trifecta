// Friends (FINAL_RELEASE_SWEEP): mutual Game Center friends, ephemeral
// in-game presence and party invites.  Design, threat model and retention:
// docs/final/friends.md.  Schema: migrations/0006_friends.sql.
//
// Identity.  The service's Game Center subject is the verified teamPlayerID
// of the session (identities.subject; never a caller's claim).  The game
// uploads the teamPlayerIDs of its own authorised Game Center friends; only
// keyed hashes of them are stored (HMAC-SHA256, FRIEND_HASH_KEY), so a list
// says nothing about people who never used the service.
//
// Relationship = mutual claim.  A and B are friends here only while A's
// current list contains B's verified ID AND B's contains A's, both lists
// were refreshed within 30 days, neither has blocked the other (either
// direction) and neither is suspended or deleted.  A caller can never learn
// anything about an ID that isn't such a friend: presence lists only mutual
// friends, keyed by their teamPlayerID (an ID the caller itself submitted),
// and an invite to anyone else fails with the same generic error whether the
// ID is unknown, one-sided, blocked or suspended.  Room codes are never shown
// in presence; an invitee gets the code only by accepting a live invite.
//
// Presence.  The foreground game sends a heartbeat every 20 s with what it is
// actually doing (online in the menus, in a party lobby it is a verified
// member of, in a round).  A row expires 60 s after its last write; going to
// the background or signing out deletes that launch's row only.  Each app
// launch has its own row; friends see the newest launch (an obsolete device
// or a late request can never overwrite it), and `seq` orders one launch's
// heartbeats.  Exact location is never stored or shown, and there is no
// history.
//
// Invites.  A verified, connected member of a joinable room (forming, open
// or results, with space) may invite a mutual friend who is playing right
// now.  Any member may invite (the invite names the inviter and the host,
// never pretending to come from the host); capacity, version, blocks,
// removals, suspensions and reservations are then enforced by the normal
// join: accepting returns the room code, and the game joins through
// POST /v1/rooms/<code>/join exactly as for a typed code.
//
// Routes are registered in app.js; its helpers arrive as `deps`.
import { ApiError, json, str, int } from './http.js';
import { normalizeCode, randomId } from './ids.js';

const SEC = 1000;
const MIN = 60 * SEC;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

export const MAX_FRIENDS = 500;
export const FRIEND_SET_TTL_MS = 30 * DAY;
export const FRIEND_SYNC_RATE = { max: 30, windowMs: HOUR };
export const PRESENCE_INTERVAL_S = 20;
export const PRESENCE_TTL_MS = 60 * SEC;
// an unchanged heartbeat is written at most this often per launch, a change
// at most once a second (a flood can't turn into database writes)
export const PRESENCE_MIN_WRITE_MS = 4 * SEC;
export const PRESENCE_MIN_CHANGE_MS = 1 * SEC;
export const MAX_INSTANCES = 4;
export const PRESENCE_POLL_S = 10;
export const INVITE_TTL_MS = 5 * MIN;
export const INVITE_KEEP_MS = 24 * HOUR;
export const INVITE_RATE = { max: 20, windowMs: 10 * MIN };
export const INVITE_PAIR_RATE = { max: 3, windowMs: 10 * MIN };
export const STATUSES = ['online', 'lobby', 'match'];
const LIVE = "('forming','open','full','loading','in_match','results')";
const JOINABLE = ['forming', 'open', 'results'];
// (app.js: a room whose host stopped sending heartbeats has ended)
const ROOM_STALE_MS = 45 * SEC;
const BODY_MAX = 48 * 1024;
const ID_RE = /^[\x21-\x7e]{1,80}$/;
const INSTANCE_RE = /^[A-Za-z0-9_-]{8,40}$/;
const INVITE_ID_RE = /^inv_[a-z0-9]{8,32}$/;
const enc = new TextEncoder();

export function friendsConfigured(env) {
  return typeof env.FRIEND_HASH_KEY === 'string' && env.FRIEND_HASH_KEY.length >= 32;
}

function requireConfigured(env) {
  if (!friendsConfigured(env)) throw new ApiError(503, 'not_configured', "Friends aren't set up on this server.");
}

let _key = null;
let _keySrc = '';
async function hashKey(env) {
  if (_key && _keySrc === env.FRIEND_HASH_KEY) return _key;
  _key = await crypto.subtle.importKey('raw', enc.encode(env.FRIEND_HASH_KEY), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  _keySrc = env.FRIEND_HASH_KEY;
  return _key;
}

// The keyed hash of one Game Center teamPlayerID in this environment.
export async function friendHash(env, teamPlayerId) {
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', await hashKey(env), enc.encode(`gc-team:${env.ENVIRONMENT || 'development'}:${teamPlayerId}`)));
  let s = '';
  for (let i = 0; i < 16; i++) s += mac[i].toString(16).padStart(2, '0');
  return s;
}

async function readBody(req) {
  const len = Number(req.headers.get('content-length') || '0');
  if (len > BODY_MAX) throw new ApiError(413, 'too_large', 'Request too large.');
  const text = await req.text();
  if (text.length > BODY_MAX) throw new ApiError(413, 'too_large', 'Request too large.');
  if (!text) return {};
  try {
    const v = JSON.parse(text);
    if (v === null || typeof v !== 'object' || Array.isArray(v)) throw new Error('not an object');
    return v;
  } catch {
    throw new ApiError(400, 'bad_json', 'Request body must be a JSON object.');
  }
}

function envName(env) {
  return env.ENVIRONMENT || 'development';
}

async function subjectOf(D, env, profileId) {
  const r = await D.db(env).one('SELECT subject FROM identities WHERE profile_id = ? AND provider = ? AND environment = ?',
    profileId, 'gamecenter', envName(env));
  if (!r) throw new ApiError(403, 'no_game_center', 'Sign in to Game Center to play online.');
  return r.subject;
}

function shown(name, forced) {
  return name && !forced ? name : null;
}

function disc(d) {
  return d ? String(d).padStart(4, '0') : null;
}

// SQL: the profile `?` (an active or lapsed-suspension profile) is a mutual,
// unblocked friend of profile `?`, with both friend sets fresh.  Parameters:
// a, b, freshSince, now.
const MUTUAL_SQL = `EXISTS (
    SELECT 1 FROM friend_sets sa JOIN friend_sets sb
      ON sb.profile_id = ?2 AND sa.profile_id = ?1
    WHERE sa.synced_at > ?3 AND sb.synced_at > ?3
      AND EXISTS (SELECT 1 FROM friend_claims ca WHERE ca.profile_id = sa.profile_id AND ca.friend_hash = sb.self_hash)
      AND EXISTS (SELECT 1 FROM friend_claims cb WHERE cb.profile_id = sb.profile_id AND cb.friend_hash = sa.self_hash)
      AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.blocker_id = sa.profile_id AND bl.blocked_id = sb.profile_id)
                                                OR (bl.blocker_id = sb.profile_id AND bl.blocked_id = sa.profile_id))
      AND EXISTS (SELECT 1 FROM profiles pa WHERE pa.id = sa.profile_id AND ${activeSql('pa', '?4')})
      AND EXISTS (SELECT 1 FROM profiles pb WHERE pb.id = sb.profile_id AND ${activeSql('pb', '?4')}))`;

function activeSql(alias, nowParam) {
  return `(${alias}.status = 'active' OR (${alias}.status = 'suspended' AND ${alias}.suspended_until IS NOT NULL AND ${alias}.suspended_until <= ${nowParam}))`;
}

async function isMutual(D, env, a, b, t) {
  const r = await D.db(env).one(`SELECT ${MUTUAL_SQL} AS ok`, a, b, t - FRIEND_SET_TTL_MS, t);
  return !!(r && r.ok);
}

// The newest live presence row of a profile (the newest launch wins).
async function livePresence(D, env, pid, t) {
  return D.db(env).one('SELECT status, room_id, protocol, build FROM presence WHERE profile_id = ? AND expires_at > ? ORDER BY created_at DESC, updated_at DESC LIMIT 1',
    pid, t);
}

// The live room this profile is a member of (newest), with its active count.
async function myRoom(D, env, pid, t) {
  const q = D.db(env);
  const r = await q.one(`SELECT r.id, r.code, r.state, r.capacity, r.protocol, r.host_profile_id, m.state AS member_state
      FROM room_members m JOIN rooms r ON r.id = m.room_id
      WHERE m.profile_id = ? AND m.state != 'left' AND r.state IN ${LIVE} AND r.heartbeat_at > ?
      ORDER BY m.joined_at DESC LIMIT 1`, pid, t - ROOM_STALE_MS);
  if (!r) return null;
  // (as app.js activeCount: reservations that never connected lapse)
  const n = await q.one(`SELECT COUNT(*) AS n FROM room_members WHERE room_id = ? AND (state = 'connected' OR (state = 'reserved' AND last_seen >= ?))`,
    r.id, t - 90 * SEC);
  r.members = n ? n.n : 0;
  return r;
}

function roomWhyNot(r) {
  if (!r) return 'no_party';
  if (['loading', 'in_match'].includes(r.state)) return 'party_busy';
  if (r.members >= r.capacity || r.state === 'full') return 'party_full';
  if (!JOINABLE.includes(r.state)) return 'party_busy';
  return null;
}

// ------------------------------------------------------------ friend list
// PUT /v1/friends {ids: [teamPlayerID, ...]}: replace this player's whole
// friend set (the game's authorised Game Center friends).
async function putFriends(req, env, D) {
  requireConfigured(env);
  const { profile: p } = await D.requireUser(req, env);
  const body = await readBody(req);
  if (!Array.isArray(body.ids)) throw new ApiError(400, 'bad_request', 'ids must be a list.');
  if (body.ids.length > MAX_FRIENDS) throw new ApiError(413, 'too_many_friends', `Up to ${MAX_FRIENDS} friends are shared.`);
  await D.rateLimit(env, `friends_sync:${p.id}`, FRIEND_SYNC_RATE.max, FRIEND_SYNC_RATE.windowMs, 'Friends were refreshed a lot just now. Try again later.');
  const self = await subjectOf(D, env, p.id);
  const ids = new Set();
  for (const v of body.ids) {
    if (typeof v !== 'string' || !ID_RE.test(v)) throw new ApiError(400, 'bad_request', 'A friend ID has the wrong format.');
    if (v !== self) ids.add(v);
  }
  const selfHash = await friendHash(env, self);
  const hashes = [];
  for (const id of ids) hashes.push(await friendHash(env, id));
  const q = D.db(env);
  const t = D.clock(env);
  await q.batch([
    // (a stale set under the same verified ID, e.g. from a deleted profile)
    q.stmt('DELETE FROM friend_claims WHERE profile_id IN (SELECT profile_id FROM friend_sets WHERE self_hash = ? AND profile_id != ?)', selfHash, p.id),
    q.stmt('DELETE FROM friend_sets WHERE self_hash = ? AND profile_id != ?', selfHash, p.id),
    q.stmt('DELETE FROM friend_claims WHERE profile_id = ?', p.id),
    q.stmt(`INSERT INTO friend_sets (profile_id, self_hash, synced_at, size) VALUES (?, ?, ?, ?)
      ON CONFLICT(profile_id) DO UPDATE SET self_hash = excluded.self_hash, synced_at = excluded.synced_at, size = excluded.size`,
    p.id, selfHash, t, hashes.length),
    q.stmt('INSERT OR IGNORE INTO friend_claims (profile_id, friend_hash) SELECT ?, value FROM json_each(?)', p.id, JSON.stringify(hashes)),
  ]);
  return json({ ok: true, count: hashes.length, synced_at: t, ttl_s: FRIEND_SET_TTL_MS / 1000 });
}

// DELETE /v1/friends: friend access was revoked (or the player turned
// Friends off): forget the set, this player's presence and their invites.
async function deleteFriends(req, env, D) {
  const { profile: p } = await D.requireUser(req, env, { allowSuspended: true });
  const q = D.db(env);
  const t = D.clock(env);
  await q.batch([
    q.stmt('DELETE FROM friend_claims WHERE profile_id = ?', p.id),
    q.stmt('DELETE FROM friend_sets WHERE profile_id = ?', p.id),
    q.stmt('DELETE FROM presence WHERE profile_id = ?', p.id),
    q.stmt("UPDATE invites SET state = 'cancelled', resolved_at = ? WHERE state = 'pending' AND (from_id = ? OR to_id = ?)", t, p.id, p.id),
  ]);
  return json({ ok: true });
}

// GET /v1/friends/presence: the caller's mutual friends and what they are
// doing in the game right now.  Nobody else is ever listed.
async function getPresence(req, env, D) {
  requireConfigured(env);
  const { profile: p } = await D.requireUser(req, env);
  const q = D.db(env);
  const t = D.clock(env);
  const fresh = t - FRIEND_SET_TTL_MS;
  const rows = await q.all(`SELECT s.profile_id AS pid, i.subject AS tid, pr.display_name, pr.discriminator, pr.forced_rename,
        (SELECT x.status || '|' || COALESCE(x.room_id, '') || '|' || COALESCE(x.protocol, 0) FROM presence x
          WHERE x.profile_id = s.profile_id AND x.expires_at > ?3 ORDER BY x.created_at DESC, x.updated_at DESC LIMIT 1) AS live
      FROM friend_sets me
      JOIN friend_claims a ON a.profile_id = me.profile_id
      JOIN friend_sets s ON s.self_hash = a.friend_hash
      JOIN friend_claims b ON b.profile_id = s.profile_id AND b.friend_hash = me.self_hash
      JOIN profiles pr ON pr.id = s.profile_id
      JOIN identities i ON i.profile_id = s.profile_id AND i.provider = 'gamecenter' AND i.environment = ?4
      WHERE me.profile_id = ?1 AND me.synced_at > ?2 AND s.synced_at > ?2 AND s.profile_id != ?1
        AND ${activeSql('pr', '?3')}
        AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.blocker_id = ?1 AND bl.blocked_id = s.profile_id)
                                                  OR (bl.blocker_id = s.profile_id AND bl.blocked_id = ?1))
      LIMIT ${MAX_FRIENDS}`, p.id, fresh, t, envName(env));
  const set = await q.one('SELECT synced_at, size FROM friend_sets WHERE profile_id = ?', p.id);
  const room = await myRoom(D, env, p.id, t);
  const mine = await livePresence(D, env, p.id, t);
  const myProtocol = room ? room.protocol : (mine ? mine.protocol : null);
  const pending = new Set();
  if (room) {
    for (const r of await q.all("SELECT to_id FROM invites WHERE from_id = ? AND room_id = ? AND state = 'pending' AND expires_at > ?", p.id, room.id, t)) {
      pending.add(r.to_id);
    }
  }
  const roomWhy = roomWhyNot(room);
  const friends = rows.map((r) => {
    let status = 'offline';
    let roomId = '';
    let protocol = 0;
    if (r.live) {
      const parts = String(r.live).split('|');
      status = STATUSES.includes(parts[0]) ? parts[0] : 'online';
      roomId = parts[1] || '';
      protocol = Number(parts[2] || 0);
    }
    const inYourParty = !!(room && roomId && roomId === room.id);
    const invited = pending.has(r.pid);
    let why = null;
    if (inYourParty) why = 'in_your_party';
    else if (status === 'offline') why = 'offline';
    else if (invited) why = 'invited';
    else if (roomWhy && roomWhy !== 'no_party') why = roomWhy;
    else if (myProtocol && protocol && protocol !== myProtocol) why = 'update';
    return {
      id: r.tid, profile_id: r.pid, name: shown(r.display_name, r.forced_rename), discriminator: shown(r.display_name, r.forced_rename) ? disc(r.discriminator) : null,
      status, in_your_party: inYourParty, invited, can_invite: why === null, why,
    };
  });
  return json({
    ok: true, server_time: t, poll_s: PRESENCE_POLL_S,
    shared: !!(set && set.synced_at > fresh), synced_at: set ? set.synced_at : null,
    party: room ? { joinable: roomWhy === null, why: roomWhy, members: room.members, capacity: room.capacity, host: room.host_profile_id === p.id } : null,
    friends,
  });
}

// ------------------------------------------------------------ presence
// POST /v1/presence {instance, seq, state, room?, protocol, build}
async function heartbeat(req, env, D) {
  requireConfigured(env);
  const { profile: p, session } = await D.requireUser(req, env);
  const body = await readBody(req);
  const instance = str(body.instance, 'instance', { max: 40 });
  if (!INSTANCE_RE.test(instance)) throw new ApiError(400, 'bad_request', 'instance has the wrong format.');
  const seq = int(body.seq, 'seq', { min: 0, max: 2 ** 31 });
  const want = str(body.state, 'state', { max: 8 });
  if (!STATUSES.includes(want)) throw new ApiError(400, 'bad_request', 'state must be online, lobby or match.');
  const protocol = int(body.protocol ?? null, 'protocol', { min: 1, max: 1000, optional: true });
  const build = int(body.build ?? null, 'build', { min: 1, max: 1e9, optional: true });
  const q = D.db(env);
  const t = D.clock(env);
  // a lobby or round only counts for a room this profile is a verified member of
  let roomId = null;
  let status = want;
  if (body.room !== undefined && body.room !== null && body.room !== '') {
    const n = normalizeCode(String(body.room));
    if (n.ok) {
      const r = await q.one(`SELECT r.id FROM rooms r JOIN room_members m ON m.room_id = r.id
          WHERE r.code = ? AND r.state IN ${LIVE} AND r.heartbeat_at > ? AND m.profile_id = ? AND m.state != 'left'`, n.code, t - ROOM_STALE_MS, p.id);
      if (r) roomId = r.id;
    }
  }
  if (status === 'lobby' && !roomId) status = 'online';
  const row = await q.one('SELECT * FROM presence WHERE profile_id = ? AND instance = ?', p.id, instance);
  let stale = false;
  let written = false;
  if (row && seq <= row.seq) {
    stale = true;   // an older heartbeat of this launch arrived late: ignored
    status = row.status;
  } else {
    const changed = !row || row.status !== status || (row.room_id || null) !== roomId;
    const since = row ? t - row.updated_at : Infinity;
    if (!row || (changed && since >= PRESENCE_MIN_CHANGE_MS) || since >= PRESENCE_MIN_WRITE_MS) {
      if (!row) {
        // a new launch: drop this player's expired rows, keep at most MAX_INSTANCES
        await q.run('DELETE FROM presence WHERE profile_id = ? AND expires_at <= ?', p.id, t);
        const others = await q.all('SELECT instance FROM presence WHERE profile_id = ? ORDER BY updated_at DESC', p.id);
        for (const o of others.slice(MAX_INSTANCES - 1)) await q.run('DELETE FROM presence WHERE profile_id = ? AND instance = ?', p.id, o.instance);
      }
      await q.run(`INSERT INTO presence (profile_id, instance, session_jti, status, room_id, protocol, build, seq, created_at, changed_at, updated_at, expires_at)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9, ?9, ?10)
        ON CONFLICT(profile_id, instance) DO UPDATE SET session_jti = excluded.session_jti, status = excluded.status, room_id = excluded.room_id,
          protocol = excluded.protocol, build = excluded.build, seq = excluded.seq,
          changed_at = CASE WHEN presence.status != excluded.status OR COALESCE(presence.room_id, '') != COALESCE(excluded.room_id, '') THEN excluded.updated_at ELSE presence.changed_at END,
          updated_at = excluded.updated_at, expires_at = excluded.expires_at`,
      p.id, instance, session.jti, status, roomId, protocol, build, seq, t, t + PRESENCE_TTL_MS);
      written = true;
    } else {
      status = row.status;
      if (changed) stale = true;   // too soon after the last change: sent again with the next heartbeat
    }
  }
  return json({ ok: true, status, room_verified: !!roomId, stale, written, interval_s: PRESENCE_INTERVAL_S, ttl_s: PRESENCE_TTL_MS / 1000,
    server_time: t, invites: await incomingInvites(D, env, p.id, t) });
}

// DELETE /v1/presence {instance}: this launch went to the background or
// signed out.  Only that launch's row goes.
async function clearPresence(req, env, D) {
  const { profile: p } = await D.requireUser(req, env, { allowSuspended: true });
  const body = await readBody(req);
  const instance = str(body.instance, 'instance', { max: 40 });
  await D.db(env).run('DELETE FROM presence WHERE profile_id = ? AND instance = ?', p.id, instance);
  return json({ ok: true });
}

// ------------------------------------------------------------ invites
async function incomingInvites(D, env, pid, t) {
  const q = D.db(env);
  const rows = await q.all(`SELECT iv.id, iv.created_at, iv.expires_at, iv.from_id, r.host_profile_id, r.capacity,
        fp.display_name AS from_name, fp.forced_rename AS from_fr, fi.subject AS from_tid,
        hp.display_name AS host_name, hp.forced_rename AS host_fr
      FROM invites iv
      JOIN rooms r ON r.id = iv.room_id
      JOIN room_members m ON m.room_id = iv.room_id AND m.profile_id = iv.from_id AND m.state != 'left'
      JOIN profiles fp ON fp.id = iv.from_id
      JOIN identities fi ON fi.profile_id = iv.from_id AND fi.provider = 'gamecenter' AND fi.environment = ?4
      LEFT JOIN profiles hp ON hp.id = r.host_profile_id
      WHERE iv.to_id = ?1 AND iv.state = 'pending' AND iv.expires_at > ?2
        AND r.state IN ${LIVE} AND r.heartbeat_at > ?3
      ORDER BY iv.created_at DESC LIMIT 10`, pid, t, t - ROOM_STALE_MS, envName(env));
  const out = [];
  for (const r of rows) {
    // still friends, unblocked, not suspended (checked per invite: at most 10)
    if (!(await isMutual(D, env, pid, r.from_id, t))) continue;
    out.push({
      id: r.id, created_at: r.created_at, expires_at: r.expires_at,
      from: { id: r.from_tid, profile_id: r.from_id, name: shown(r.from_name, r.from_fr) },
      from_host: r.from_id === r.host_profile_id,
      host_name: shown(r.host_name, r.host_fr),
    });
  }
  return out;
}

const NOT_FRIEND = () => new ApiError(404, 'not_friend', 'You can invite Game Center friends who also play Ultimate Trifecta and have Friends turned on.');

// POST /v1/invites {to: teamPlayerID}
async function sendInvite(req, env, D) {
  requireConfigured(env);
  const { profile: p } = await D.requireUser(req, env);
  const body = await readBody(req);
  const to = str(body.to, 'to', { max: 80 });
  if (!ID_RE.test(to)) throw new ApiError(400, 'bad_request', 'to has the wrong format.');
  const q = D.db(env);
  const t = D.clock(env);
  await D.rateLimit(env, `invite:${p.id}`, INVITE_RATE.max, INVITE_RATE.windowMs, "You've sent a lot of invites. Try again in a few minutes.");
  // who is that?  Only a mutual, unblocked, active friend; anything else gets
  // the same answer (no way to probe IDs)
  const target = await q.one('SELECT profile_id FROM friend_sets WHERE self_hash = ?', await friendHash(env, to));
  if (!target || target.profile_id === p.id || !(await isMutual(D, env, p.id, target.profile_id, t))) throw NOT_FRIEND();
  const tid = target.profile_id;
  const tp = await q.one('SELECT display_name, forced_rename FROM profiles WHERE id = ?', tid);
  const who = shown(tp && tp.display_name, tp && tp.forced_rename) || 'Your friend';
  // the room the inviter is in right now, as a verified, connected member
  const room = await myRoom(D, env, p.id, t);
  if (!room) throw new ApiError(409, 'no_party', 'Start a party first, then invite.');
  if (room.member_state !== 'connected') throw new ApiError(409, 'not_ready', "You're still joining this party. Invite in a moment.");
  const why = roomWhyNot(room);
  if (why === 'party_busy') throw new ApiError(409, 'party_busy', 'Your party is in a round. Invite when it ends.');
  if (why === 'party_full') throw new ApiError(409, 'party_full', 'Your party is full.');
  const member = await q.one("SELECT 1 AS x FROM room_members WHERE room_id = ? AND profile_id = ? AND state != 'left'", room.id, tid);
  if (member) throw new ApiError(409, 'already_in_party', `${who} is already in your party.`);
  // a repeated tap: the same pending invite, nothing new
  const dup = await q.one("SELECT id, expires_at FROM invites WHERE from_id = ? AND to_id = ? AND room_id = ? AND state = 'pending' AND expires_at > ?",
    p.id, tid, room.id, t);
  if (dup) return json({ ok: true, duplicate: true, invite: { id: dup.id, to, expires_at: dup.expires_at } });
  const live = await livePresence(D, env, tid, t);
  if (!live) throw new ApiError(409, 'offline', `${who} isn't playing right now.`);
  if (live.protocol && live.protocol !== room.protocol) {
    throw new ApiError(409, 'version_mismatch', live.protocol < room.protocol ? `${who} needs to update the game first.` : 'Update the game to invite this friend.');
  }
  await D.rateLimit(env, `invite_pair:${p.id}:${tid}`, INVITE_PAIR_RATE.max, INVITE_PAIR_RATE.windowMs, `You've invited ${who} a few times. Try again in a few minutes.`);
  const id = randomId('inv', 16);
  await q.batch([
    // an older pending invite from you for another party is replaced
    q.stmt("UPDATE invites SET state = 'cancelled', resolved_at = ? WHERE from_id = ? AND to_id = ? AND state = 'pending'", t, p.id, tid),
    q.stmt("INSERT INTO invites (id, from_id, to_id, room_id, state, created_at, expires_at) VALUES (?, ?, ?, ?, 'pending', ?, ?)",
      id, p.id, tid, room.id, t, t + INVITE_TTL_MS),
  ]);
  return json({ ok: true, invite: { id, to, expires_at: t + INVITE_TTL_MS } }, 201);
}

// GET /v1/invites: invites waiting for me (the heartbeat returns them too)
async function listInvites(req, env, D) {
  requireConfigured(env);
  const { profile: p } = await D.requireUser(req, env);
  const t = D.clock(env);
  return json({ ok: true, server_time: t, invites: await incomingInvites(D, env, p.id, t) });
}

async function loadInvite(D, env, id, pid) {
  if (!INVITE_ID_RE.test(id)) throw new ApiError(404, 'not_found', "That invite isn't available any more.");
  const iv = await D.db(env).one('SELECT * FROM invites WHERE id = ? AND to_id = ?', id, pid);
  if (!iv) throw new ApiError(404, 'not_found', "That invite isn't available any more.");
  return iv;
}

// POST /v1/invites/<id>/accept {build, protocol}: every check again, then the
// room code for the normal join (POST /v1/rooms/<code>/join does admission).
async function acceptInvite(req, env, D, id) {
  requireConfigured(env);
  const { profile: p } = await D.requireUser(req, env);
  const body = await readBody(req);
  const protocol = int(body.protocol, 'protocol', { min: 1, max: 1000 });
  const q = D.db(env);
  const t = D.clock(env);
  await D.rateLimit(env, `invite_accept:${p.id}`, 20, MIN, 'Too many tries. Please wait a moment.');
  const iv = await loadInvite(D, env, id, p.id);
  if (!['pending', 'accepted'].includes(iv.state)) throw new ApiError(410, 'expired', 'That invite has ended.');
  if (iv.expires_at <= t) {
    await q.run("UPDATE invites SET state = 'expired', resolved_at = ? WHERE id = ? AND state = 'pending'", t, iv.id);
    throw new ApiError(410, 'expired', 'That invite has expired. Ask for a new one.');
  }
  const fp = await q.one('SELECT display_name, forced_rename FROM profiles WHERE id = ?', iv.from_id);
  const from = shown(fp && fp.display_name, fp && fp.forced_rename) || 'Your friend';
  if (!(await isMutual(D, env, p.id, iv.from_id, t))) {
    await q.run("UPDATE invites SET state = 'cancelled', resolved_at = ? WHERE id = ?", t, iv.id);
    throw new ApiError(410, 'expired', 'That invite has ended.');
  }
  const r = await q.one(`SELECT * FROM rooms WHERE id = ? AND state IN ${LIVE}`, iv.room_id);
  if (!r || t - r.heartbeat_at > ROOM_STALE_MS) throw new ApiError(410, 'expired', 'That party has ended.');
  const inviter = await q.one("SELECT 1 AS x FROM room_members WHERE room_id = ? AND profile_id = ? AND state != 'left'", r.id, iv.from_id);
  if (!inviter) throw new ApiError(410, 'inviter_left', `${from} has left that party.`);
  // the same rules as POST /v1/rooms/<code>/join, checked early for a clear
  // answer; the join itself decides again
  if (protocol !== r.protocol) {
    throw new ApiError(409, 'version_mismatch', protocol < r.protocol ? 'Update the game to join this party.' : 'Your host needs to update the game.',
      { host_protocol: r.protocol });
  }
  const mine = await q.one('SELECT * FROM room_members WHERE room_id = ? AND profile_id = ?', r.id, p.id);
  const blocked = await q.one(`SELECT 1 AS x FROM room_members m JOIN blocks b ON
      ((b.blocker_id = m.profile_id AND b.blocked_id = ?1) OR (b.blocker_id = ?1 AND b.blocked_id = m.profile_id))
    WHERE m.room_id = ?2 AND (m.state != 'left' OR m.profile_id = ?3)`, p.id, r.id, r.host_profile_id);
  if (blocked || (mine && mine.kicked)) throw new ApiError(403, 'not_allowed', "You can't join this party.");
  const already = mine && mine.state !== 'left';
  if (!already) {
    if (r.state === 'forming') throw new ApiError(409, 'not_ready', 'The host is still setting up. Try again in a moment.');
    if (['loading', 'in_match'].includes(r.state)) throw new ApiError(409, 'in_match', 'That party is in a round. Try again when it ends.');
    const n = await q.one(`SELECT COUNT(*) AS n FROM room_members WHERE room_id = ? AND (state = 'connected' OR (state = 'reserved' AND last_seen >= ?))`,
      r.id, t - 90 * SEC);
    if (n.n >= r.capacity) throw new ApiError(409, 'full', 'That party is full.');
  }
  await q.batch([
    q.stmt("UPDATE invites SET state = 'accepted', resolved_at = COALESCE(resolved_at, ?) WHERE id = ?", t, iv.id),
    q.stmt("UPDATE invites SET state = 'cancelled', resolved_at = ? WHERE to_id = ? AND room_id = ? AND state = 'pending' AND id != ?", t, p.id, r.id, iv.id),
  ]);
  const host = await q.one('SELECT display_name, forced_rename FROM profiles WHERE id = ?', r.host_profile_id);
  return json({ ok: true, code: r.code, host_name: shown(host && host.display_name, host && host.forced_rename), from_name: from, invite_id: iv.id });
}

// POST /v1/invites/<id>/decline
async function declineInvite(req, env, D, id) {
  const { profile: p } = await D.requireUser(req, env, { allowSuspended: true });
  const t = D.clock(env);
  const iv = await loadInvite(D, env, id, p.id);
  if (iv.state === 'pending') {
    await D.db(env).run("UPDATE invites SET state = ?, resolved_at = ? WHERE id = ? AND state = 'pending'",
      iv.expires_at <= t ? 'expired' : 'declined', t, iv.id);
  }
  return json({ ok: true });
}

// ------------------------------------------------------------ hooks
// DELETE /v1/me: everything Friends kept about the player.  (Other players'
// lists keep their own hashes; without this player's self_hash nothing can
// match them.)
export function deletionStmts(q, pid) {
  return [
    q.stmt('DELETE FROM friend_claims WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM friend_sets WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM presence WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM invites WHERE from_id = ? OR to_id = ?', pid, pid),
  ];
}

// POST /v1/auth/signout: only the presence written by that session goes.
export function signOutStmts(q, pid, jti) {
  return [q.stmt('DELETE FROM presence WHERE profile_id = ? AND session_jti = ?', pid, jti)];
}

// Cron: presence past its expiry, invites past theirs (recorded as
// expired), resolved invites after a day, friend sets not refreshed for 30
// days.
export async function sweepFriends(q, t) {
  await q.run('DELETE FROM presence WHERE expires_at <= ?', t);
  await q.run("UPDATE invites SET state = 'expired', resolved_at = ? WHERE state = 'pending' AND expires_at <= ?", t, t);
  await q.run('DELETE FROM invites WHERE created_at < ?', t - INVITE_KEEP_MS);
  await q.run('DELETE FROM friend_claims WHERE profile_id IN (SELECT profile_id FROM friend_sets WHERE synced_at <= ?)', t - FRIEND_SET_TTL_MS);
  await q.run('DELETE FROM friend_sets WHERE synced_at <= ?', t - FRIEND_SET_TTL_MS);
}

// ------------------------------------------------------------ router
export async function routeFriends(req, env, path, m, D) {
  let k;
  if (path === '/v1/friends') {
    if (m === 'PUT') return putFriends(req, env, D);
    if (m === 'DELETE') return deleteFriends(req, env, D);
  }
  if (m === 'GET' && path === '/v1/friends/presence') return getPresence(req, env, D);
  if (path === '/v1/presence') {
    if (m === 'POST') return heartbeat(req, env, D);
    if (m === 'DELETE') return clearPresence(req, env, D);
  }
  if (path === '/v1/invites') {
    if (m === 'POST') return sendInvite(req, env, D);
    if (m === 'GET') return listInvites(req, env, D);
  }
  if (m === 'POST' && (k = path.match(/^\/v1\/invites\/([A-Za-z0-9_]{3,48})\/(accept|decline)$/))) {
    return k[2] === 'accept' ? acceptInvite(req, env, D, k[1]) : declineInvite(req, env, D, k[1]);
  }
  return null;
}
