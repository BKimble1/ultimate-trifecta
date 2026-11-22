// Friend tags and in-game friends: add a friend by typing their tag
// (ComfyFrog#4821), no Game Center friendship needed.  Schema and retention:
// migrations/0007_friend_tags.sql; design: docs/final/friends.md.
//
// Tag.  The approved display name without spaces, '#', and a number shown
// as 4 digits.  The name part always follows the current display name, so a
// tag is only ever a name that passed moderation; a player whose name was
// hidden by moderation (forced rename) has no tag and can't be found until
// they choose a new name.  The number is the profile's discriminator where
// that is free for the tag (it is, for every name approved since tags
// exist: POST /v1/me/name picks a number free in both places) and stays when
// the name changes unless the new tag is taken.  (tag_key, disc) is unique.
//
// Requests.  POST /v1/friends/requests {tag} finds an active, named player
// by tag (case-insensitive, a leading '@' and spaces ignored).  An unknown
// tag, a blocked player (either direction) and a suspended one all get the
// same "No player with that tag" answer, so blocks can't be probed.  Adding
// someone who already asked you accepts at once; asking twice returns the
// same request.  The other player sees it in Friends and accepts or
// declines.  Rate limits: 20 tries per 10 minutes and 60 a day per player
// (unknown tags count, so tags can't be guessed in bulk).  Caps: 200
// in-game friends, 50 requests waiting from you, 100 waiting for someone.
//
// Friendship.  An accepted pair (friend_links) counts like mutual Game
// Center friends for presence, status and invites (friends.js: isMutual,
// getPresence), always re-checked against blocks and suspensions.  DELETE
// /v1/friends/<profile> ends it; blocking ends it too.
import { ApiError, json, readJson } from './http.js';
import { randomId } from './ids.js';

const MIN = 60 * 1000;
const DAY = 24 * 60 * MIN;

export const MAX_TAG_FRIENDS = 200;
export const MAX_PENDING_OUT = 50;
export const MAX_PENDING_IN = 100;
export const REQUEST_RATE = { max: 20, windowMs: 10 * MIN };
export const REQUEST_DAY_RATE = { max: 60, windowMs: DAY };
export const REQUEST_KEEP_MS = 30 * DAY;
const REQ_ID_RE = /^frq_[a-z0-9]{8,32}$/;
export const PROFILE_ID_RE = /^p_[a-z0-9]{8,40}$/;
const TAG_EXAMPLE = 'ComfyFrog#4821';

// ------------------------------------------------------------ tag text
export function tagName(displayName) {
  return String(displayName || '').replace(/\s+/g, '');
}

export function tagKey(displayName) {
  return tagName(displayName).toLowerCase();
}

export function formatTag(displayName, disc) {
  return `${tagName(displayName)}#${String(disc).padStart(4, '0')}`;
}

// What a player typed into "Add friend": {ok, key, disc} or {ok:false,
// error, message}.  Case, spaces, a leading '@' and full-width characters
// (NFKC) are forgiven; anything else is a clear error.
export function parseTag(raw) {
  const bad = (message) => ({ ok: false, error: 'bad_tag', message });
  if (typeof raw !== 'string') return bad(`Type your friend's tag, like ${TAG_EXAMPLE}.`);
  let s = raw.normalize('NFKC').trim();
  if (s.startsWith('@')) s = s.slice(1).trim();
  if (s === '') return bad(`Type your friend's tag, like ${TAG_EXAMPLE}.`);
  const i = s.lastIndexOf('#');
  if (i < 0) return bad(`Add the # and number, like ${TAG_EXAMPLE}.`);
  const name = s.slice(0, i).replace(/\s+/g, '');
  const num = s.slice(i + 1).trim();
  if (!/^[A-Za-z0-9_]{2,16}$/.test(name)) return bad(`That isn't a tag. Tags look like ${TAG_EXAMPLE}.`);
  if (!/^[0-9]{1,4}$/.test(num) || Number(num) < 1) return bad('The number after # has 4 digits, like #4821.');
  return { ok: true, key: name.toLowerCase(), disc: Number(num) };
}

function activeSql(alias, nowParam) {
  return `(${alias}.status = 'active' OR (${alias}.status = 'suspended' AND ${alias}.suspended_until IS NOT NULL AND ${alias}.suspended_until <= ${nowParam}))`;
}

const pair = (a, b) => (a < b ? [a, b] : [b, a]);

// ------------------------------------------------------------ tags
// The numbers already used by other players for this tag key.
export async function takenDiscs(q, key, pid) {
  return new Set((await q.all('SELECT disc FROM friend_tags WHERE tag_key = ? AND profile_id != ?', key, pid)).map((r) => r.disc));
}

// The profile's tag row, created or moved to its current name.  {key, disc}
// or null (no shown name, or all 9999 numbers taken for that name).
export async function assignTag(q, p, t) {
  if (!p || !p.display_name) return null;
  const key = tagKey(p.display_name);
  const cur = await q.one('SELECT tag_key, disc FROM friend_tags WHERE profile_id = ?', p.id);
  if (cur && cur.tag_key === key) return { key, disc: cur.disc };
  const prefs = [];
  if (p.discriminator) prefs.push(Number(p.discriminator));
  if (cur) prefs.push(Number(cur.disc));
  for (let attempt = 0; attempt < 4; attempt++) {
    const taken = await takenDiscs(q, key, p.id);
    let disc = prefs.find((d) => d >= 1 && d <= 9999 && !taken.has(d)) ?? null;
    for (let i = 0; i < 40 && disc === null; i++) {
      const d = 1 + Math.floor(Math.random() * 9999);
      if (!taken.has(d)) disc = d;
    }
    for (let d = 1; d <= 9999 && disc === null; d++) if (!taken.has(d)) disc = d;
    if (disc === null) return null;
    try {
      await q.run(`INSERT INTO friend_tags (profile_id, tag_key, disc, updated_at) VALUES (?, ?, ?, ?)
        ON CONFLICT(profile_id) DO UPDATE SET tag_key = excluded.tag_key, disc = excluded.disc, updated_at = excluded.updated_at`,
      p.id, key, disc, t);
      return { key, disc };
    } catch (e) {
      if (!String(e && e.message).includes('UNIQUE')) throw e;   // (someone took it just now: pick again)
    }
  }
  return null;
}

// The tag to show for this profile (null while it has no shown name).
export async function myTag(q, p, t) {
  if (!p || !p.display_name || p.forced_rename) return null;
  const a = await assignTag(q, p, t);
  return a ? formatTag(p.display_name, a.disc) : null;
}

// A shown tag from a joined row (display_name, forced_rename, tag_key, disc).
export function shownTag(r) {
  if (!r || !r.display_name || r.forced_rename || !r.disc || r.tag_key !== tagKey(r.display_name)) return null;
  return formatTag(r.display_name, r.disc);
}

function person(r, idCol = 'pid') {
  const name = r.display_name && !r.forced_rename ? r.display_name : null;
  return { profile_id: r[idCol], name, tag: shownTag(r) };
}

// ------------------------------------------------------------ friendship
// An accepted in-game friendship between a and b, with no block either way
// and both active (the same conditions as a mutual Game Center pair).
export async function isLinked(q, a, b, t) {
  if (!a || !b || a === b) return false;
  const [x, y] = pair(a, b);
  const r = await q.one(`SELECT 1 AS ok FROM friend_links l
      JOIN profiles pa ON pa.id = l.a_id JOIN profiles pb ON pb.id = l.b_id
    WHERE l.a_id = ?1 AND l.b_id = ?2 AND ${activeSql('pa', '?3')} AND ${activeSql('pb', '?3')}
      AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.blocker_id = ?1 AND bl.blocked_id = ?2) OR (bl.blocker_id = ?2 AND bl.blocked_id = ?1))`,
  x, y, t);
  return !!(r && r.ok);
}

async function friendCount(q, pid) {
  const r = await q.one('SELECT COUNT(*) AS n FROM friend_links WHERE a_id = ? OR b_id = ?', pid, pid);
  return r ? r.n : 0;
}

// Requests waiting for this player (from active, unblocked, named players).
export async function incomingCount(q, pid, t) {
  const r = await q.one(`SELECT COUNT(*) AS n FROM friend_requests fr JOIN profiles pr ON pr.id = fr.from_id
    WHERE fr.to_id = ?1 AND fr.state = 'pending' AND ${activeSql('pr', '?2')} AND pr.display_name IS NOT NULL AND pr.forced_rename = 0
      AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.blocker_id = ?1 AND bl.blocked_id = fr.from_id) OR (bl.blocker_id = fr.from_id AND bl.blocked_id = ?1))`,
  pid, t);
  return r ? r.n : 0;
}

const NO_PLAYER = () => new ApiError(404, 'no_player', 'No player with that tag.');

function link(q, a, b, t) {
  const [x, y] = pair(a, b);
  return q.stmt('INSERT OR IGNORE INTO friend_links (a_id, b_id, created_at) VALUES (?, ?, ?)', x, y, t);
}

async function capsAllow(q, me, other) {
  if (await friendCount(q, me) >= MAX_TAG_FRIENDS) throw new ApiError(409, 'friends_full', 'Your friends list is full. Remove someone first.');
  if (await friendCount(q, other) >= MAX_TAG_FRIENDS) throw new ApiError(409, 'their_friends_full', 'Their friends list is full.');
}

async function summary(q, pid) {
  const r = await q.one(`SELECT pr.id AS pid, pr.display_name, pr.forced_rename, ft.tag_key, ft.disc
    FROM profiles pr LEFT JOIN friend_tags ft ON ft.profile_id = pr.id WHERE pr.id = ?`, pid);
  return r ? person(r) : { profile_id: pid, name: null, tag: null };
}

// GET /v1/friends/me/tag
async function getTag(req, env, D) {
  const { profile: p } = await D.requireUser(req, env, { allowSuspended: true });
  const tag = await myTag(D.db(env), p, D.clock(env));
  return json({ ok: true, tag, needs_name: !p.display_name || !!p.forced_rename });
}

// GET /v1/friends/requests: my tag, requests both ways, my in-game friends.
async function listRequests(req, env, D) {
  const { profile: p } = await D.requireUser(req, env);
  const q = D.db(env);
  const t = D.clock(env);
  const tag = await myTag(q, p, t);
  const cols = 'pr.display_name, pr.forced_rename, ft.tag_key, ft.disc';
  const ok = (col) => `${activeSql('pr', '?2')} AND pr.display_name IS NOT NULL AND pr.forced_rename = 0
      AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.blocker_id = ?1 AND bl.blocked_id = ${col}) OR (bl.blocker_id = ${col} AND bl.blocked_id = ?1))`;
  const incoming = await q.all(`SELECT fr.id, fr.created_at, fr.from_id AS pid, ${cols} FROM friend_requests fr
      JOIN profiles pr ON pr.id = fr.from_id LEFT JOIN friend_tags ft ON ft.profile_id = fr.from_id
    WHERE fr.to_id = ?1 AND fr.state = 'pending' AND ${ok('fr.from_id')} ORDER BY fr.created_at DESC LIMIT ${MAX_PENDING_IN}`, p.id, t);
  const outgoing = await q.all(`SELECT fr.id, fr.created_at, fr.to_id AS pid, ${cols} FROM friend_requests fr
      JOIN profiles pr ON pr.id = fr.to_id LEFT JOIN friend_tags ft ON ft.profile_id = fr.to_id
    WHERE fr.from_id = ?1 AND fr.state = 'pending' AND ${ok('fr.to_id')} ORDER BY fr.created_at DESC LIMIT ${MAX_PENDING_OUT}`, p.id, t);
  const friends = await q.all(`SELECT pr.id AS pid, l.created_at, ${cols} FROM friend_links l
      JOIN profiles pr ON pr.id = CASE WHEN l.a_id = ?1 THEN l.b_id ELSE l.a_id END
      LEFT JOIN friend_tags ft ON ft.profile_id = pr.id
    WHERE (l.a_id = ?1 OR l.b_id = ?1) AND ${activeSql('pr', '?2')}
      AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.blocker_id = ?1 AND bl.blocked_id = pr.id) OR (bl.blocker_id = pr.id AND bl.blocked_id = ?1))
    ORDER BY l.created_at DESC LIMIT ${MAX_TAG_FRIENDS}`, p.id, t);
  return json({
    ok: true, server_time: t, tag, needs_name: !p.display_name || !!p.forced_rename, max_friends: MAX_TAG_FRIENDS,
    incoming: incoming.map((r) => ({ id: r.id, created_at: r.created_at, from: person(r) })),
    outgoing: outgoing.map((r) => ({ id: r.id, created_at: r.created_at, to: person(r) })),
    friends: friends.map((r) => ({ ...person(r), since: r.created_at })),
  });
}

// POST /v1/friends/requests {tag}
async function sendRequest(req, env, D) {
  const { profile: p } = await D.requireUser(req, env);
  const body = await readJson(req);
  const q = D.db(env);
  const t = D.clock(env);
  if (!p.display_name || p.forced_rename) throw new ApiError(409, 'needs_name', 'Choose a player name first.');
  const parsed = parseTag(body.tag);
  if (!parsed.ok) throw new ApiError(400, parsed.error, parsed.message);
  // every lookup counts (an unknown tag too): tags can't be guessed in bulk
  await D.rateLimit(env, `friend_req:${p.id}`, REQUEST_RATE.max, REQUEST_RATE.windowMs, "You've added a lot of friends just now. Try again in a few minutes.");
  await D.rateLimit(env, `friend_req_day:${p.id}`, REQUEST_DAY_RATE.max, REQUEST_DAY_RATE.windowMs, "You've added a lot of friends today. Try again tomorrow.");
  const target = await q.one(`SELECT pr.id AS pid, pr.display_name, pr.forced_rename, ft.tag_key, ft.disc FROM friend_tags ft JOIN profiles pr ON pr.id = ft.profile_id
    WHERE ft.tag_key = ?1 AND ft.disc = ?2 AND ${activeSql('pr', '?3')} AND pr.display_name IS NOT NULL AND pr.forced_rename = 0`,
  parsed.key, parsed.disc, t);
  // (a tag row left behind by an old name never matches: the name part must be the current one)
  if (!target || target.tag_key !== tagKey(target.display_name)) throw NO_PLAYER();
  if (target.pid === p.id) throw new ApiError(400, 'self', "That's your own tag.");
  const blocked = await q.one('SELECT 1 AS x FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)',
    p.id, target.pid, target.pid, p.id);
  if (blocked) throw NO_PLAYER();     // (the same answer: a block can't be probed)
  const who = person(target);
  const [x, y] = pair(p.id, target.pid);
  if (await q.one('SELECT 1 AS x FROM friend_links WHERE a_id = ? AND b_id = ?', x, y)) {
    throw new ApiError(409, 'already_friends', `You're already friends with ${target.display_name}.`, { friend: who });
  }
  // they asked you already: that's a yes from both sides
  const theirs = await q.one("SELECT id FROM friend_requests WHERE from_id = ? AND to_id = ? AND state = 'pending'", target.pid, p.id);
  if (theirs) {
    await capsAllow(q, p.id, target.pid);
    await q.batch([
      link(q, p.id, target.pid, t),
      q.stmt("UPDATE friend_requests SET state = 'accepted', resolved_at = ? WHERE id = ?", t, theirs.id),
    ]);
    return json({ ok: true, state: 'accepted', friend: who });
  }
  const mine = await q.one("SELECT id, created_at FROM friend_requests WHERE from_id = ? AND to_id = ? AND state = 'pending'", p.id, target.pid);
  if (mine) return json({ ok: true, state: 'pending', duplicate: true, request: { id: mine.id, created_at: mine.created_at, to: who } });
  await capsAllow(q, p.id, target.pid);
  const out = await q.one("SELECT COUNT(*) AS n FROM friend_requests WHERE from_id = ? AND state = 'pending'", p.id);
  if (out.n >= MAX_PENDING_OUT) throw new ApiError(409, 'too_many_requests', 'Lots of your requests are still waiting. Try again later.');
  const inc = await q.one("SELECT COUNT(*) AS n FROM friend_requests WHERE to_id = ? AND state = 'pending'", target.pid);
  if (inc.n >= MAX_PENDING_IN) throw new ApiError(409, 'their_requests_full', "They can't take more requests right now.");
  const id = randomId('frq', 16);
  try {
    await q.run("INSERT INTO friend_requests (id, from_id, to_id, state, created_at) VALUES (?, ?, ?, 'pending', ?)", id, p.id, target.pid, t);
  } catch (e) {
    if (!String(e && e.message).includes('UNIQUE')) throw e;
    const again = await q.one("SELECT id, created_at FROM friend_requests WHERE from_id = ? AND to_id = ? AND state = 'pending'", p.id, target.pid);
    return json({ ok: true, state: 'pending', duplicate: true, request: { id: again.id, created_at: again.created_at, to: who } });
  }
  return json({ ok: true, state: 'pending', request: { id, created_at: t, to: who } }, 201);
}

async function loadRequest(q, id) {
  if (!REQ_ID_RE.test(id)) return null;
  return q.one('SELECT * FROM friend_requests WHERE id = ?', id);
}

const GONE = () => new ApiError(410, 'gone', "That request isn't there any more.");

// POST /v1/friends/requests/<id>/accept
async function acceptRequest(req, env, D, id) {
  const { profile: p } = await D.requireUser(req, env);
  const q = D.db(env);
  const t = D.clock(env);
  const r = await loadRequest(q, id);
  if (!r || r.to_id !== p.id) throw GONE();
  const from = await summary(q, r.from_id);
  if (r.state === 'accepted') return json({ ok: true, state: 'accepted', duplicate: true, friend: from });
  if (r.state !== 'pending') throw GONE();
  const sender = await q.one(`SELECT 1 AS x FROM profiles pr WHERE pr.id = ? AND ${activeSql('pr', '?')}`, r.from_id, t);
  const blocked = await q.one('SELECT 1 AS x FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)',
    p.id, r.from_id, r.from_id, p.id);
  if (!sender || blocked) {
    await q.run("UPDATE friend_requests SET state = 'cancelled', resolved_at = ? WHERE id = ? AND state = 'pending'", t, r.id);
    throw GONE();
  }
  await capsAllow(q, p.id, r.from_id);
  await q.batch([
    link(q, p.id, r.from_id, t),
    q.stmt("UPDATE friend_requests SET state = 'accepted', resolved_at = ? WHERE id = ?", t, r.id),
    // (my own request the other way, if any, is answered by this)
    q.stmt("UPDATE friend_requests SET state = 'accepted', resolved_at = ? WHERE from_id = ? AND to_id = ? AND state = 'pending'", t, p.id, r.from_id),
  ]);
  return json({ ok: true, state: 'accepted', friend: from });
}

// POST /v1/friends/requests/<id>/decline: the receiver says no, or the
// sender takes it back (also DELETE /v1/friends/requests/<id>).  The sender
// is never told it was declined: it simply stops showing as "Requested"
// once it is gone from their list.
async function declineRequest(req, env, D, id) {
  const { profile: p } = await D.requireUser(req, env, { allowSuspended: true });
  const q = D.db(env);
  const t = D.clock(env);
  const r = await loadRequest(q, id);
  if (!r || (r.to_id !== p.id && r.from_id !== p.id)) throw GONE();
  if (r.state === 'pending') {
    await q.run("UPDATE friend_requests SET state = ?, resolved_at = ? WHERE id = ? AND state = 'pending'",
      r.to_id === p.id ? 'declined' : 'cancelled', t, r.id);
  }
  return json({ ok: true });
}

// DELETE /v1/friends/<profile>: no longer friends (in game).  Requests
// between the two and pending party invites end too.  Game Center friends
// stay friends through Game Center.
async function removeFriend(req, env, D, other) {
  const { profile: p } = await D.requireUser(req, env, { allowSuspended: true });
  const q = D.db(env);
  const t = D.clock(env);
  await q.batch(endStmts(q, p.id, other, t));
  return json({ ok: true });
}

// Statements that end everything in-game between two players (unfriend,
// block).
export function endStmts(q, a, b, t) {
  const [x, y] = pair(a, b);
  return [
    q.stmt('DELETE FROM friend_links WHERE a_id = ? AND b_id = ?', x, y),
    q.stmt("UPDATE friend_requests SET state = 'cancelled', resolved_at = ? WHERE state = 'pending' AND ((from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?))",
      t, a, b, b, a),
    q.stmt("UPDATE invites SET state = 'cancelled', resolved_at = ? WHERE state = 'pending' AND ((from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?))",
      t, a, b, b, a),
  ];
}

// ------------------------------------------------------------ hooks
// DELETE /v1/me
export function tagDeletionStmts(q, pid) {
  return [
    q.stmt('DELETE FROM friend_tags WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM friend_links WHERE a_id = ? OR b_id = ?', pid, pid),
    q.stmt('DELETE FROM friend_requests WHERE from_id = ? OR to_id = ?', pid, pid),
  ];
}

// Cron: requests older than 30 days go, answered or not.
export async function sweepFriendTags(q, t) {
  await q.run('DELETE FROM friend_requests WHERE created_at < ?', t - REQUEST_KEEP_MS);
}

// ------------------------------------------------------------ router
export async function routeFriendTags(req, env, path, m, D) {
  let k;
  if (m === 'GET' && path === '/v1/friends/me/tag') return getTag(req, env, D);
  if (path === '/v1/friends/requests') {
    if (m === 'GET') return listRequests(req, env, D);
    if (m === 'POST') return sendRequest(req, env, D);
  }
  if ((k = path.match(/^\/v1\/friends\/requests\/([A-Za-z0-9_]{3,48})(?:\/(accept|decline|cancel))?$/))) {
    if (m === 'POST' && k[2] === 'accept') return acceptRequest(req, env, D, k[1]);
    if ((m === 'POST' && (k[2] === 'decline' || k[2] === 'cancel')) || (m === 'DELETE' && !k[2])) return declineRequest(req, env, D, k[1]);
  }
  if (m === 'DELETE' && (k = path.match(/^\/v1\/friends\/(p_[a-z0-9]{8,40})$/))) {
    return removeFriend(req, env, D, k[1]);
  }
  return null;
}

