// Ultimate Trifecta trusted service: request handling.
//
// Game Center is the transport and invite system, the party host runs the
// simulation, and this service owns what must not be left to clients:
// verified identity, opaque profiles, display-name approval, blocks, reports
// and moderation, and the party room directory with admission.
import { ApiError, json, errorResponse, readJson, str, int } from './http.js';
import { verifyIdentity } from './gamecenter.js';
import { issueSession, verifySession, issueAdmission, SESSION_TTL_S } from './tokens.js';
import { moderate, suggestions, normalizeName } from './names.js';
import { randomId, newRoomCode, normalizeCode } from './ids.js';
import { chatCheck, reportMessage } from './chat.js';
import { routeCommerce, deletionStmts, sweepCommerce } from './commerce.js';
import CATALOGUE from './catalogue_data.js';

const HOUR = 3600 * 1000;
export const RENAME_COOLDOWN_MS = 24 * HOUR;
export const REAUTH_WINDOW_S = 10 * 60;
export const ROOM_HEARTBEAT_S = 15;
export const ROOM_STALE_MS = 45 * 1000;
export const RESERVATION_MS = 90 * 1000;
export const REPORT_REASONS = ['name', 'harassment', 'cheating', 'inappropriate', 'other'];
const LIVE = ['forming', 'open', 'full', 'loading', 'in_match', 'results'];
const TRANSITIONS = {
  forming: ['forming', 'open', 'closing'],
  open: ['open', 'full', 'loading', 'closing'],
  full: ['full', 'open', 'loading', 'closing'],
  loading: ['loading', 'in_match', 'open', 'closing'],
  in_match: ['in_match', 'results', 'closing'],
  results: ['results', 'open', 'loading', 'closing'],
};

export function clock(env) {
  return env.__now ? env.__now() : Date.now();
}

export function db(env) {
  const d = env.DB;
  if (!d) throw new ApiError(503, 'not_configured', 'The service is not configured.');
  return {
    one: (sql, ...a) => d.prepare(sql).bind(...a).first(),
    all: async (sql, ...a) => (await d.prepare(sql).bind(...a).all()).results || [],
    run: (sql, ...a) => d.prepare(sql).bind(...a).run(),
    stmt: (sql, ...a) => d.prepare(sql).bind(...a),
    batch: (s) => d.batch(s),
  };
}

export async function audit(env, actor, action, target = null, detail = null) {
  await db(env).run('INSERT INTO audit (at, actor, action, target, detail) VALUES (?, ?, ?, ?, ?)',
    clock(env), actor, action, target, detail === null ? null : JSON.stringify(detail));
}

// Sliding-window limit: at most `max` events per `windowMs` for `key`.
export async function rateLimit(env, key, max, windowMs, message = 'Too many tries. Please wait a moment.') {
  const t = clock(env);
  const q = db(env);
  const row = await q.one('SELECT COUNT(*) AS n, MIN(at) AS first FROM rate_events WHERE key = ? AND at > ?', key, t - windowMs);
  if (row && row.n >= max) {
    const retry = Math.max(1, Math.ceil(((row.first || t) + windowMs - t) / 1000));
    throw new ApiError(429, 'rate_limited', message, { retry_after_s: retry });
  }
  await q.run('INSERT INTO rate_events (key, at) VALUES (?, ?)', key, t);
}

function shownName(p) {
  if (!p || !p.display_name || p.forced_rename) return null;
  return p.display_name;
}

function publicProfile(p, self = false) {
  const out = {
    profile_id: p.id,
    display_name: shownName(p),
    discriminator: p.discriminator ? String(p.discriminator).padStart(4, '0') : null,
    appearance: p.appearance ? JSON.parse(p.appearance) : null,
  };
  if (self) {
    out.status = p.status;
    out.suspended_until = p.suspended_until || null;
    out.needs_name = !p.display_name || !!p.forced_rename;
    out.forced_rename = !!p.forced_rename;
    out.name_set_at = p.name_set_at || null;
    out.created_at = p.created_at;
  }
  return out;
}

export async function requireUser(req, env, { allowSuspended = false } = {}) {
  const h = req.headers.get('authorization') || '';
  if (!h.startsWith('Bearer ')) throw new ApiError(401, 'signed_out', 'Please sign in.');
  const s = await verifySession(env, h.slice(7), clock(env));
  const q = db(env);
  if (await q.one('SELECT jti FROM revoked_sessions WHERE jti = ?', s.jti)) throw new ApiError(401, 'signed_out', 'Please sign in again.');
  const p = await q.one('SELECT * FROM profiles WHERE id = ?', s.sub);
  if (!p) throw new ApiError(401, 'signed_out', 'Please sign in again.');
  if (p.status === 'suspended' && p.suspended_until && p.suspended_until <= clock(env)) {
    await q.run("UPDATE profiles SET status = 'active', suspended_until = NULL, updated_at = ? WHERE id = ?", clock(env), p.id);
    p.status = 'active';
    p.suspended_until = null;
  }
  if (p.status === 'suspended' && !allowSuspended) {
    throw new ApiError(403, 'suspended', 'Your account is suspended from online play.', { until: p.suspended_until });
  }
  return { profile: p, session: s };
}

export function requireAdmin(req, env) {
  const want = env.ADMIN_TOKEN || '';
  const got = (req.headers.get('authorization') || '').replace(/^Bearer /, '');
  if (want.length < 24) throw new ApiError(503, 'not_configured', 'Admin access is not configured.');
  // constant-time compare
  let diff = want.length ^ got.length;
  for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ (got.charCodeAt(i) || 0);
  if (diff !== 0) throw new ApiError(401, 'unauthorized', 'Admin token required.');
  return 'admin';
}

function clientIp(req) {
  return req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || 'unknown';
}

// --------------------------------------------------------------- handlers
async function signIn(req, env) {
  await rateLimit(env, `signin:${clientIp(req)}`, 30, 60 * 1000);
  const body = await readJson(req);
  const subject = await verifyIdentity(body, env, clock(env));
  const q = db(env);
  const t = clock(env);
  const envName = env.ENVIRONMENT || 'development';
  const ident = await q.one('SELECT profile_id FROM identities WHERE provider = ? AND subject = ? AND environment = ?', 'gamecenter', subject, envName);
  let p;
  if (ident) {
    p = await q.one('SELECT * FROM profiles WHERE id = ?', ident.profile_id);
    await q.run('UPDATE identities SET last_seen = ? WHERE provider = ? AND subject = ? AND environment = ?', t, 'gamecenter', subject, envName);
  }
  if (!p) {
    const id = randomId('p');
    await q.batch([
      q.stmt('INSERT INTO profiles (id, created_at, updated_at) VALUES (?, ?, ?)', id, t, t),
      q.stmt('INSERT OR REPLACE INTO identities (provider, subject, environment, profile_id, created_at, last_seen) VALUES (?, ?, ?, ?, ?, ?)',
        'gamecenter', subject, envName, id, t, t),
    ]);
    await audit(env, 'system', 'profile_created', id);
    p = await q.one('SELECT * FROM profiles WHERE id = ?', id);
  }
  const { token, payload } = await issueSession(env, p.id, t);
  return json({ ok: true, token, expires_at: payload.exp * 1000, profile: publicProfile(p, true) });
}

async function signOut(req, env) {
  const { session } = await requireUser(req, env, { allowSuspended: true });
  await db(env).run('INSERT OR IGNORE INTO revoked_sessions (jti, expires_at) VALUES (?, ?)', session.jti, session.exp * 1000);
  return json({ ok: true });
}

async function getMe(req, env) {
  const { profile } = await requireUser(req, env, { allowSuspended: true });
  return json({ ok: true, profile: publicProfile(profile, true) });
}

async function setName(req, env) {
  const { profile: p } = await requireUser(req, env);
  const body = await readJson(req);
  const raw = str(body.name, 'name', { max: 64 });
  const t = clock(env);
  await rateLimit(env, `name:${p.id}`, 6, 10 * 60 * 1000, 'Too many name tries. Please wait a few minutes.');
  if (p.display_name && !p.forced_rename && p.name_set_at && t - p.name_set_at < RENAME_COOLDOWN_MS) {
    throw new ApiError(429, 'rename_cooldown', 'You can change your name once a day.', { next_allowed_at: p.name_set_at + RENAME_COOLDOWN_MS });
  }
  const q = db(env);
  const reserved = (await q.all('SELECT name_norm FROM reserved_names')).map((r) => r.name_norm);
  const m = moderate(raw, reserved);
  await q.run('INSERT INTO name_history (profile_id, attempted, decision, reason, at) VALUES (?, ?, ?, ?, ?)',
    p.id, normalizeName(raw).slice(0, 32), m.ok ? 'approved' : 'rejected', m.ok ? null : m.reason, t);
  if (!m.ok) {
    throw new ApiError(422, m.error, m.message, { reason: m.reason, suggestions: suggestions(p.id + raw, 3, reserved) });
  }
  // discriminator: a free number for this name (duplicates allowed, told apart)
  let disc = null;
  const taken = new Set((await q.all('SELECT discriminator FROM profiles WHERE name_norm = ? AND id != ?', m.norm, p.id)).map((r) => r.discriminator));
  if (p.name_norm === m.norm && p.discriminator) disc = p.discriminator;
  for (let i = 0; i < 40 && disc === null; i++) {
    const d = 1 + Math.floor(Math.random() * 9999);
    if (!taken.has(d)) disc = d;
  }
  for (let d = 1; d <= 9999 && disc === null; d++) if (!taken.has(d)) disc = d;
  if (disc === null) throw new ApiError(409, 'name_taken', 'That name is very popular. Try adding a word or number.', { suggestions: suggestions(p.id, 3, reserved) });
  const first = !p.display_name;
  await q.run('UPDATE profiles SET display_name = ?, name_norm = ?, discriminator = ?, name_set_at = ?, forced_rename = 0, updated_at = ? WHERE id = ?',
    m.name, m.norm, disc, t, t, p.id);
  await audit(env, p.id, first ? 'name_set' : 'name_changed', p.id, { name: m.name });
  const np = await q.one('SELECT * FROM profiles WHERE id = ?', p.id);
  return json({ ok: true, profile: publicProfile(np, true) });
}

async function checkName(req, env) {
  // dry run for the name field (no save, no cooldown); still rate limited
  const { profile: p } = await requireUser(req, env, { allowSuspended: true });
  const body = await readJson(req);
  await rateLimit(env, `namecheck:${p.id}`, 30, 60 * 1000);
  const reserved = (await db(env).all('SELECT name_norm FROM reserved_names')).map((r) => r.name_norm);
  const m = moderate(str(body.name, 'name', { max: 64 }), reserved);
  return json(m.ok ? { ok: true, name: m.name } : { ok: false, error: m.error, reason: m.reason, message: m.message, suggestions: suggestions(p.id, 3, reserved) });
}

async function setAppearance(req, env) {
  const { profile: p } = await requireUser(req, env);
  const body = await readJson(req);
  const a = body.appearance;
  if (!a || typeof a !== 'object' || Array.isArray(a)) throw new ApiError(400, 'bad_request', 'appearance must be an object.');
  const keys = Object.keys(a);
  if (keys.length > 24 || a.schema !== 2) throw new ApiError(400, 'bad_appearance', 'Unsupported appearance format.');
  for (const k of keys) {
    if (!/^[a-z_]{1,16}$/.test(k)) throw new ApiError(400, 'bad_appearance', 'Unsupported appearance field.');
    const v = a[k];
    if (k === 'schema') continue;
    if (typeof v !== 'string' || !/^[a-z0-9_]{1,24}$/.test(v)) throw new ApiError(400, 'bad_appearance', 'Unsupported appearance value.');
  }
  await db(env).run('UPDATE profiles SET appearance = ?, updated_at = ? WHERE id = ?', JSON.stringify(a), clock(env), p.id);
  return json({ ok: true });
}

async function deleteMe(req, env) {
  const { profile: p, session } = await requireUser(req, env, { allowSuspended: true });
  const body = await readJson(req);
  if (body.confirm !== 'DELETE') throw new ApiError(400, 'confirm_required', 'Confirm deletion to continue.');
  if (Math.floor(clock(env) / 1000) - session.iat > REAUTH_WINDOW_S) {
    throw new ApiError(401, 'reauth_required', 'Please confirm with Game Center again, then delete.');
  }
  const q = db(env);
  const t = clock(env);
  await q.batch([
    q.stmt("UPDATE rooms SET state = 'closing', updated_at = ? WHERE host_profile_id = ? AND state IN ('forming','open','full','loading','in_match','results')", t, p.id),
    q.stmt("UPDATE room_members SET state = 'left', last_seen = ? WHERE profile_id = ?", t, p.id),
    q.stmt('DELETE FROM blocks WHERE blocker_id = ? OR blocked_id = ?', p.id, p.id),
    q.stmt('UPDATE reports SET reporter_id = NULL WHERE reporter_id = ?', p.id),
    q.stmt("UPDATE reports SET target_name = NULL, evidence = NULL, status = CASE WHEN status = 'open' THEN 'dismissed' ELSE status END, resolution = COALESCE(resolution, 'profile deleted') WHERE target_id = ?", p.id),
    q.stmt('DELETE FROM name_history WHERE profile_id = ?', p.id),
    q.stmt('DELETE FROM identities WHERE profile_id = ?', p.id),
    q.stmt('DELETE FROM profiles WHERE id = ?', p.id),
    q.stmt('INSERT OR IGNORE INTO revoked_sessions (jti, expires_at) VALUES (?, ?)', session.jti, session.exp * 1000),
    // V6: Coins, items, Season progress go with the profile; ledger and App
    // Store rows stay for reconciliation without the profile link
    ...deletionStmts(q, p.id),
  ]);
  await audit(env, 'system', 'profile_deleted', null, { at: t });
  return json({ ok: true, deleted_at: t });
}

async function listBlocks(req, env) {
  const { profile: p } = await requireUser(req, env, { allowSuspended: true });
  const rows = await db(env).all(
    'SELECT b.blocked_id, b.created_at, p.display_name, p.discriminator, p.forced_rename FROM blocks b LEFT JOIN profiles p ON p.id = b.blocked_id WHERE b.blocker_id = ? ORDER BY b.created_at DESC', p.id);
  return json({ ok: true, blocks: rows.map((r) => ({ profile_id: r.blocked_id, display_name: r.forced_rename ? null : r.display_name, created_at: r.created_at })) });
}

async function addBlock(req, env) {
  const { profile: p } = await requireUser(req, env, { allowSuspended: true });
  const body = await readJson(req);
  const target = str(body.profile_id, 'profile_id', { max: 40 });
  if (target === p.id) throw new ApiError(400, 'self', "You can't block yourself.");
  const q = db(env);
  if (!(await q.one('SELECT id FROM profiles WHERE id = ?', target))) throw new ApiError(404, 'not_found', 'That player could not be found.');
  const n = await q.one('SELECT COUNT(*) AS n FROM blocks WHERE blocker_id = ?', p.id);
  if (n.n >= 500) throw new ApiError(409, 'too_many_blocks', 'Your block list is full. Unblock someone first.');
  await q.run('INSERT OR IGNORE INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', p.id, target, clock(env));
  return json({ ok: true });
}

async function removeBlock(req, env, target) {
  const { profile: p } = await requireUser(req, env, { allowSuspended: true });
  await db(env).run('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?', p.id, target);
  return json({ ok: true });
}

async function fileReport(req, env) {
  const { profile: p } = await requireUser(req, env, { allowSuspended: true });
  const body = await readJson(req);
  const target = str(body.profile_id, 'profile_id', { max: 40 });
  const reason = str(body.reason, 'reason', { max: 20 });
  if (!REPORT_REASONS.includes(reason)) throw new ApiError(400, 'bad_reason', 'Pick a reason for the report.');
  const details = str(body.details, 'details', { max: 500, optional: true });
  const ctx = body.context && typeof body.context === 'object' ? body.context : {};
  const context = {
    room_code: typeof ctx.room_code === 'string' ? ctx.room_code.slice(0, 12) : null,
    match_id: typeof ctx.match_id === 'string' ? ctx.match_id.slice(0, 64) : null,
    build: Number.isSafeInteger(ctx.build) ? ctx.build : null,
  };
  if (target === p.id) throw new ApiError(400, 'self', "You can't report yourself.");
  const q = db(env);
  const tp = await q.one('SELECT id, display_name FROM profiles WHERE id = ?', target);
  if (!tp) throw new ApiError(404, 'not_found', 'That player could not be found.');
  const t = clock(env);
  const dup = await q.one("SELECT id FROM reports WHERE reporter_id = ? AND target_id = ? AND reason = ? AND status = 'open' AND created_at > ?",
    p.id, target, reason, t - 24 * HOUR);
  if (dup) return json({ ok: true, receipt: dup.id, status: 'received', duplicate: true });
  await rateLimit(env, `report:${p.id}`, 12, 24 * HOUR, "You've sent a lot of reports today. Our team will review them.");
  const id = randomId('R', 10).toUpperCase().replace('R_', 'R-');
  await q.run('INSERT INTO reports (id, reporter_id, target_id, target_name, reason, details, context, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    id, p.id, target, tp.display_name, reason, details, JSON.stringify(context), 'open', t);
  await audit(env, p.id, 'report_filed', target, { receipt: id, reason });
  return json({ ok: true, receipt: id, status: 'received' });
}

async function reportStatus(req, env, id) {
  const { profile: p } = await requireUser(req, env, { allowSuspended: true });
  const r = await db(env).one('SELECT id, status, created_at, resolved_at FROM reports WHERE id = ? AND reporter_id = ?', id, p.id);
  if (!r) throw new ApiError(404, 'not_found', 'No report with that receipt.');
  return json({ ok: true, receipt: r.id, status: r.status === 'open' ? 'received' : 'reviewed', created_at: r.created_at, resolved_at: r.resolved_at });
}

// --------------------------------------------------------------- admin
async function adminReports(req, env, url) {
  requireAdmin(req, env);
  const status = url.searchParams.get('status') || 'open';
  const limit = Math.min(200, Math.max(1, Number(url.searchParams.get('limit') || 50)));
  const rows = await db(env).all(
    `SELECT r.*, p.display_name AS current_name, p.status AS target_status, p.suspended_until,
       (SELECT COUNT(*) FROM reports r2 WHERE r2.target_id = r.target_id AND r2.status = 'open') AS open_for_target
     FROM reports r LEFT JOIN profiles p ON p.id = r.target_id WHERE r.status = ? ORDER BY r.created_at ASC LIMIT ?`, status, limit);
  return json({ ok: true, reports: rows.map((r) => ({ ...r, context: r.context ? JSON.parse(r.context) : null })) });
}

async function adminResolve(req, env, id) {
  const actor = requireAdmin(req, env);
  const body = await readJson(req);
  const action = str(body.action, 'action', { max: 20 });
  const note = str(body.note, 'note', { max: 500, optional: true });
  const q = db(env);
  const r = await q.one('SELECT * FROM reports WHERE id = ?', id);
  if (!r) throw new ApiError(404, 'not_found', 'No such report.');
  const t = clock(env);
  const p = await q.one('SELECT * FROM profiles WHERE id = ?', r.target_id);
  let resolution;
  if (action === 'dismiss') {
    resolution = 'dismissed';
  } else if (action === 'force_rename') {
    if (!p) throw new ApiError(409, 'gone', 'That profile no longer exists.');
    await q.run('UPDATE profiles SET forced_rename = 1, updated_at = ? WHERE id = ?', t, p.id);
    if (p.name_norm) {
      await q.run('INSERT OR IGNORE INTO reserved_names (name_norm, note, created_at) VALUES (?, ?, ?)', p.name_norm, `blocked after report ${id}`, t);
    }
    resolution = 'forced rename';
  } else if (action === 'suspend') {
    if (!p) throw new ApiError(409, 'gone', 'That profile no longer exists.');
    const hours = int(body.hours, 'hours', { min: 1, max: 24 * 365 });
    await q.run("UPDATE profiles SET status = 'suspended', suspended_until = ?, updated_at = ? WHERE id = ?", t + hours * HOUR, t, p.id);
    await q.run("UPDATE rooms SET state = 'closing', updated_at = ? WHERE host_profile_id = ? AND state IN ('forming','open','full','loading','in_match','results')", t, p.id);
    resolution = `suspended ${hours}h`;
  } else {
    throw new ApiError(400, 'bad_action', 'action must be dismiss, force_rename or suspend.');
  }
  const status = action === 'dismiss' ? 'dismissed' : 'actioned';
  if (body.all_for_target) {
    await q.run("UPDATE reports SET status = ?, resolved_at = ?, resolution = ?, resolver = ? WHERE target_id = ? AND status = 'open'", status, t, resolution, actor, r.target_id);
  } else {
    await q.run('UPDATE reports SET status = ?, resolved_at = ?, resolution = ?, resolver = ? WHERE id = ?', status, t, resolution, actor, id);
  }
  await audit(env, actor, 'report_' + action, r.target_id, { report: id, note, resolution });
  return json({ ok: true, status, resolution });
}

async function adminProfile(req, env, id) {
  requireAdmin(req, env);
  const q = db(env);
  const p = await q.one('SELECT * FROM profiles WHERE id = ?', id);
  if (!p) throw new ApiError(404, 'not_found', 'No such profile.');
  const names = await q.all('SELECT attempted, decision, reason, at FROM name_history WHERE profile_id = ? ORDER BY at DESC LIMIT 20', id);
  const reports = await q.all('SELECT id, reason, status, created_at, resolution FROM reports WHERE target_id = ? ORDER BY created_at DESC LIMIT 50', id);
  return json({ ok: true, profile: { ...publicProfile(p, true), display_name_raw: p.display_name }, names, reports });
}

async function adminUnsuspend(req, env, id) {
  const actor = requireAdmin(req, env);
  await db(env).run("UPDATE profiles SET status = 'active', suspended_until = NULL, updated_at = ? WHERE id = ?", clock(env), id);
  await audit(env, actor, 'unsuspend', id);
  return json({ ok: true });
}

async function adminAudit(req, env, url) {
  requireAdmin(req, env);
  const limit = Math.min(500, Math.max(1, Number(url.searchParams.get('limit') || 100)));
  const rows = await db(env).all('SELECT * FROM audit ORDER BY id DESC LIMIT ?', limit);
  return json({ ok: true, audit: rows.map((r) => ({ ...r, detail: r.detail ? JSON.parse(r.detail) : null })) });
}

async function adminReserve(req, env) {
  const actor = requireAdmin(req, env);
  const body = await readJson(req);
  const name = normalizeName(str(body.name, 'name', { max: 32 })).toLowerCase();
  await db(env).run('INSERT OR REPLACE INTO reserved_names (name_norm, note, created_at) VALUES (?, ?, ?)', name, str(body.note, 'note', { max: 200, optional: true }), clock(env));
  await audit(env, actor, 'reserve_name', null, { name });
  return json({ ok: true });
}

// --------------------------------------------------------------- rooms
async function gcPlayerOf(env, profileId) {
  const r = await db(env).one('SELECT subject FROM identities WHERE profile_id = ? AND provider = ? AND environment = ?',
    profileId, 'gamecenter', env.ENVIRONMENT || 'development');
  if (!r) throw new ApiError(403, 'no_game_center', 'Sign in to Game Center to play online.');
  return r.subject;
}

export async function liveRoom(env, code) {
  const q = db(env);
  const r = await q.one(`SELECT * FROM rooms WHERE code = ? AND state IN ('forming','open','full','loading','in_match','results')`, code);
  if (!r) {
    const old = await q.one('SELECT state FROM rooms WHERE code = ? ORDER BY created_at DESC LIMIT 1', code);
    if (old) throw new ApiError(410, 'expired', 'That party has ended.');
    throw new ApiError(404, 'not_found', 'No party with that code. Check the code with your host.');
  }
  if (clock(env) - r.heartbeat_at > ROOM_STALE_MS) {
    await q.run("UPDATE rooms SET state = 'expired', updated_at = ? WHERE id = ?", clock(env), r.id);
    throw new ApiError(410, 'expired', 'That party has ended (the host went away).');
  }
  return r;
}

function roomView(r, count) {
  return { room_id: r.id, code: r.code, state: r.state, capacity: r.capacity, members: count, protocol: r.protocol, build: r.client_build,
    expires_at: r.expires_at, heartbeat_interval_s: ROOM_HEARTBEAT_S };
}

async function activeCount(env, roomId) {
  const t = clock(env);
  const q = db(env);
  // reservations that never connected lapse (frees the slot)
  await q.run("UPDATE room_members SET state = 'left' WHERE room_id = ? AND state = 'reserved' AND last_seen < ?", roomId, t - RESERVATION_MS);
  return (await q.one("SELECT COUNT(*) AS n FROM room_members WHERE room_id = ? AND state != 'left'", roomId)).n;
}

async function createRoom(req, env) {
  const { profile: p } = await requireUser(req, env);
  if (!shownName(p)) throw new ApiError(409, 'needs_name', 'Choose a player name first.');
  const body = await readJson(req);
  const build = int(body.build, 'build', { min: 1, max: 1e9 });
  const protocol = int(body.protocol, 'protocol', { min: 1, max: 1000 });
  const capacity = int(body.capacity ?? 8, 'capacity', { min: 2, max: 8 });
  await rateLimit(env, `room_create:${p.id}`, 10, 10 * 60 * 1000, 'Too many new parties. Please wait a few minutes.');
  const gc = await gcPlayerOf(env, p.id);
  const q = db(env);
  const t = clock(env);
  // one live room per host: a new party closes the old one
  await q.run("UPDATE rooms SET state = 'closing', updated_at = ? WHERE host_profile_id = ? AND state IN ('forming','open','full','loading','in_match','results')", t, p.id);
  for (let i = 0; i < 8; i++) {
    const id = randomId('room');
    const code = newRoomCode();
    try {
      // atomic: the room and the host's slot 0 are created together or not at all
      await q.batch([
        q.stmt('INSERT INTO rooms (id, code, host_profile_id, host_gc_player, state, capacity, client_build, protocol, created_at, updated_at, heartbeat_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          id, code, p.id, gc, 'forming', capacity, build, protocol, t, t, t, t + ROOM_STALE_MS),
        q.stmt('INSERT INTO room_members (room_id, profile_id, gc_player, slot, state, joined_at, last_seen) VALUES (?, ?, ?, 0, ?, ?, ?)', id, p.id, gc, 'connected', t, t),
      ]);
      const r = await q.one('SELECT * FROM rooms WHERE id = ?', id);
      return json({ ok: true, room: roomView(r, 1), slot: 0 }, 201);
    } catch (e) {
      if (!String(e && e.message).includes('UNIQUE')) throw e;
    }
  }
  throw new ApiError(503, 'busy', 'Could not create a party right now. Try again.');
}

async function roomInfo(req, env, rawCode) {
  await requireUser(req, env);
  const n = normalizeCode(rawCode);
  if (!n.ok) throw new ApiError(400, n.error, n.message);
  const r = await liveRoom(env, n.code);
  const host = await db(env).one('SELECT display_name, forced_rename FROM profiles WHERE id = ?', r.host_profile_id);
  return json({ ok: true, room: { ...roomView(r, await activeCount(env, r.id)), host_name: host && !host.forced_rename ? host.display_name : null } });
}

async function joinRoom(req, env, rawCode) {
  const { profile: p } = await requireUser(req, env);
  if (!shownName(p)) throw new ApiError(409, 'needs_name', 'Choose a player name first.');
  const body = await readJson(req);
  const n = normalizeCode(String(rawCode || body.code || ''));
  if (!n.ok) throw new ApiError(400, n.error, n.message);
  await rateLimit(env, `join:${p.id}`, 20, 60 * 1000, 'Too many join attempts. Please wait a moment.');
  const build = int(body.build, 'build', { min: 1, max: 1e9 });
  const protocol = int(body.protocol, 'protocol', { min: 1, max: 1000 });
  const r = await liveRoom(env, n.code);
  const q = db(env);
  if (r.host_profile_id === p.id) throw new ApiError(409, 'own_room', "That's your own party.");
  if (protocol !== r.protocol) {
    throw new ApiError(409, 'version_mismatch', protocol < r.protocol ? 'Update the game to join this party.' : 'Your host needs to update the game.',
      { host_build: r.client_build, host_protocol: r.protocol });
  }
  const blocked = await q.one('SELECT 1 AS x FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)',
    r.host_profile_id, p.id, p.id, r.host_profile_id);
  const mine = await q.one('SELECT * FROM room_members WHERE room_id = ? AND profile_id = ?', r.id, p.id);
  if (blocked || (mine && mine.kicked)) throw new ApiError(403, 'not_allowed', "You can't join this party.");
  // blocks between the joiner and anyone already in the room
  const clash = await q.one(`SELECT 1 AS x FROM room_members m JOIN blocks b ON
      ((b.blocker_id = m.profile_id AND b.blocked_id = ?) OR (b.blocker_id = ? AND b.blocked_id = m.profile_id))
    WHERE m.room_id = ? AND m.state != 'left'`, p.id, p.id, r.id);
  if (clash) throw new ApiError(403, 'not_allowed', "You can't join this party.");
  if (r.state === 'forming') throw new ApiError(409, 'not_ready', 'The host is still setting up. Try again in a moment.');
  if (['loading', 'in_match'].includes(r.state) && !(mine && mine.state !== 'left')) {
    throw new ApiError(409, 'in_match', 'That party is in a round. Try again when it ends.');
  }
  const gc = await gcPlayerOf(env, p.id);
  const t = clock(env);
  let slot;
  if (mine && mine.state !== 'left') {
    // reconnect: the same profile keeps its own slot (nobody else can take it)
    slot = mine.slot;
    await q.run('UPDATE room_members SET last_seen = ?, gc_player = ? WHERE room_id = ? AND profile_id = ?', t, gc, r.id, p.id);
  } else {
    const count = await activeCount(env, r.id);
    if (count >= r.capacity) throw new ApiError(409, 'full', 'That party is full.');
    for (let attempt = 0; attempt < 6 && slot === undefined; attempt++) {
      const used = new Set((await q.all("SELECT slot FROM room_members WHERE room_id = ? AND state != 'left'", r.id)).map((x) => x.slot));
      let s = 1;
      while (used.has(s) && s < r.capacity) s++;
      if (s >= r.capacity) throw new ApiError(409, 'full', 'That party is full.');
      try {
        // the partial unique index on (room_id, slot) makes this atomic: two
        // joiners racing for the same slot cannot both get it
        await q.run(`INSERT INTO room_members (room_id, profile_id, gc_player, slot, state, joined_at, last_seen) VALUES (?, ?, ?, ?, 'reserved', ?, ?)
          ON CONFLICT(room_id, profile_id) DO UPDATE SET slot = excluded.slot, state = 'reserved', gc_player = excluded.gc_player, last_seen = excluded.last_seen`,
        r.id, p.id, gc, s, t, t);
        slot = s;
      } catch (e) {
        if (!String(e && e.message).includes('UNIQUE')) throw e;
      }
    }
    if (slot === undefined) throw new ApiError(503, 'busy', 'The party is busy. Try again.');
  }
  const name = `${p.display_name}#${String(p.discriminator).padStart(4, '0')}`;
  const adm = await issueAdmission(env, { room: r.id, code: r.code, sub: p.id, gc, slot, name, host: r.host_gc_player }, t);
  await q.run('UPDATE room_members SET admission_jti = ? WHERE room_id = ? AND profile_id = ?', adm.payload.jti, r.id, p.id);
  const count = await activeCount(env, r.id);
  if (count >= r.capacity && r.state === 'open') await q.run("UPDATE rooms SET state = 'full', updated_at = ? WHERE id = ?", t, r.id);
  return json({ ok: true, admission: adm.token, admission_expires_at: adm.payload.exp * 1000, slot, host_gc_player: r.host_gc_player,
    room: roomView(r, count) });
}

async function heartbeat(req, env, rawCode) {
  const { profile: p } = await requireUser(req, env);
  const n = normalizeCode(rawCode);
  if (!n.ok) throw new ApiError(400, n.error, n.message);
  const r = await liveRoom(env, n.code);
  if (r.host_profile_id !== p.id) throw new ApiError(403, 'not_host', 'Only the host can update the party.');
  const body = await readJson(req);
  const q = db(env);
  const t = clock(env);
  let state = r.state;
  if (body.state !== undefined) {
    const want = str(body.state, 'state', { max: 12 });
    if (!(TRANSITIONS[r.state] || []).includes(want)) throw new ApiError(409, 'bad_transition', `Can't go from ${r.state} to ${want}.`);
    state = want;
  }
  if (Array.isArray(body.connected)) {
    // the host confirms who is actually connected over Game Center
    const ids = body.connected.filter((x) => typeof x === 'string').slice(0, 8);
    for (const id of ids) {
      await q.run("UPDATE room_members SET state = 'connected', last_seen = ? WHERE room_id = ? AND profile_id = ? AND state != 'left'", t, r.id, id);
    }
  }
  const count = await activeCount(env, r.id);
  if (state === 'open' && count >= r.capacity) state = 'full';
  if (state === 'full' && count < r.capacity) state = 'open';
  await q.run('UPDATE rooms SET state = ?, heartbeat_at = ?, expires_at = ?, updated_at = ? WHERE id = ?', state, t, t + ROOM_STALE_MS, t, r.id);
  const members = await q.all("SELECT profile_id, slot, state FROM room_members WHERE room_id = ? AND state != 'left' ORDER BY slot", r.id);
  return json({ ok: true, room: roomView({ ...r, state, expires_at: t + ROOM_STALE_MS }, count), members });
}

async function leaveRoom(req, env, rawCode) {
  const { profile: p } = await requireUser(req, env, { allowSuspended: true });
  const n = normalizeCode(rawCode);
  if (!n.ok) throw new ApiError(400, n.error, n.message);
  const q = db(env);
  const r = await q.one(`SELECT * FROM rooms WHERE code = ? AND state IN ('forming','open','full','loading','in_match','results')`, n.code);
  if (!r) return json({ ok: true });
  const t = clock(env);
  if (r.host_profile_id === p.id) {
    await q.run("UPDATE rooms SET state = 'closing', updated_at = ? WHERE id = ?", t, r.id);
  } else {
    await q.run("UPDATE room_members SET state = 'left', last_seen = ? WHERE room_id = ? AND profile_id = ?", t, r.id, p.id);
    if (r.state === 'full') await q.run("UPDATE rooms SET state = 'open', updated_at = ? WHERE id = ?", t, r.id);
  }
  return json({ ok: true });
}

async function kickMember(req, env, rawCode) {
  const { profile: p } = await requireUser(req, env);
  const n = normalizeCode(rawCode);
  if (!n.ok) throw new ApiError(400, n.error, n.message);
  const r = await liveRoom(env, n.code);
  if (r.host_profile_id !== p.id) throw new ApiError(403, 'not_host', 'Only the host can remove players.');
  const body = await readJson(req);
  const target = str(body.profile_id, 'profile_id', { max: 40 });
  if (target === p.id) throw new ApiError(400, 'self', "You can't remove yourself.");
  await db(env).run("UPDATE room_members SET state = 'left', kicked = 1, last_seen = ? WHERE room_id = ? AND profile_id = ?", clock(env), r.id, target);
  return json({ ok: true });
}

// Periodic cleanup (Cron Trigger).
export async function sweep(env) {
  const q = db(env);
  const t = clock(env);
  await q.run(`UPDATE rooms SET state = 'expired', updated_at = ? WHERE state IN ('forming','open','full','loading','in_match','results') AND heartbeat_at < ?`, t, t - ROOM_STALE_MS);
  await q.run("DELETE FROM rooms WHERE state IN ('closing','expired') AND updated_at < ?", t - 24 * HOUR);
  await q.run('DELETE FROM rate_events WHERE at < ?', t - 24 * HOUR);
  await q.run('DELETE FROM revoked_sessions WHERE expires_at < ?', t);
  await sweepCommerce(env, q, t);
}

function config(env) {
  return json({
    ok: true,
    environment: env.ENVIRONMENT || 'development',
    support_email: env.SUPPORT_EMAIL || null,
    support_url: env.SUPPORT_URL || null,
    privacy_url: env.PRIVACY_URL || null,
    min_build: Number(env.MIN_CLIENT_BUILD || 0),
    apple_environment: env.APPLE_ENVIRONMENT === 'Production' ? 'Production' : 'Sandbox',
    catalogue_version: CATALOGUE.catalogue_version,
    admission_key_id: env.ADMISSION_KEY_ID || 'adm1',
    session_ttl_s: SESSION_TTL_S,
    // V6: what this deployment supports (an older deployment has no chat, so
    // the game keeps typed chat honestly unavailable)
    // Pass 8: scheduled rotating Shop offers (GET /v1/shop/offers)
    features: ['chat', 'message_reports', 'shop_offers'],
  });
}

// helpers handed to the V6 social routes (chat.js)
const SOCIAL_DEPS = { requireUser, db, rateLimit, audit, clock };

// --------------------------------------------------------------- router
export async function handle(req, env) {
  try {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    const m = req.method;
    let k;
    if (m === 'GET' && path === '/v1/config') return config(env);
    if (m === 'GET' && path === '/v1/health') return json({ ok: true });
    if (m === 'POST' && path === '/v1/auth/gamecenter') return await signIn(req, env);
    if (m === 'POST' && path === '/v1/auth/signout') return await signOut(req, env);
    if (m === 'GET' && path === '/v1/me') return await getMe(req, env);
    if (m === 'DELETE' && path === '/v1/me') return await deleteMe(req, env);
    if (m === 'POST' && path === '/v1/me/name') return await setName(req, env);
    if (m === 'POST' && path === '/v1/names/check') return await checkName(req, env);
    if (m === 'PUT' && path === '/v1/me/appearance') return await setAppearance(req, env);
    if (m === 'GET' && path === '/v1/blocks') return await listBlocks(req, env);
    if (m === 'POST' && path === '/v1/blocks') return await addBlock(req, env);
    if (m === 'DELETE' && (k = path.match(/^\/v1\/blocks\/([A-Za-z0-9_]{3,40})$/))) return await removeBlock(req, env, k[1]);
    if (m === 'POST' && path === '/v1/reports') return await fileReport(req, env);
    if (m === 'GET' && (k = path.match(/^\/v1\/reports\/([A-Za-z0-9_-]{3,40})$/))) return await reportStatus(req, env, k[1]);
    // V6 social (service/src/chat.js): typed chat approval and message reports
    if (m === 'POST' && path === '/v1/chat/check') return await chatCheck(req, env, SOCIAL_DEPS);
    if (m === 'POST' && path === '/v1/reports/message') return await reportMessage(req, env, SOCIAL_DEPS);
    if (m === 'POST' && path === '/v1/rooms') return await createRoom(req, env);
    if ((k = path.match(/^\/v1\/rooms\/([^/]{1,24})(\/[a-z]+)?$/))) {
      const code = decodeURIComponent(k[1]);
      const sub = k[2] || '';
      if (m === 'GET' && sub === '') return await roomInfo(req, env, code);
      if (m === 'POST' && sub === '/join') return await joinRoom(req, env, code);
      if (m === 'POST' && sub === '/heartbeat') return await heartbeat(req, env, code);
      if (m === 'POST' && sub === '/leave') return await leaveRoom(req, env, code);
      if (m === 'POST' && sub === '/kick') return await kickMember(req, env, code);
      if (m === 'DELETE' && sub === '') return await leaveRoom(req, env, code);
    }
    const c = await routeCommerce(req, env, path, m, { requireUser, requireAdmin, db, rateLimit, audit, clock, liveRoom });
    if (c) return c;
    if (m === 'GET' && path === '/v1/admin/reports') return await adminReports(req, env, url);
    if (m === 'POST' && (k = path.match(/^\/v1\/admin\/reports\/([A-Za-z0-9_-]{3,40})\/resolve$/))) return await adminResolve(req, env, k[1]);
    if (m === 'GET' && (k = path.match(/^\/v1\/admin\/profiles\/([A-Za-z0-9_]{3,40})$/))) return await adminProfile(req, env, k[1]);
    if (m === 'POST' && (k = path.match(/^\/v1\/admin\/profiles\/([A-Za-z0-9_]{3,40})\/unsuspend$/))) return await adminUnsuspend(req, env, k[1]);
    if (m === 'GET' && path === '/v1/admin/audit') return await adminAudit(req, env, url);
    if (m === 'POST' && path === '/v1/admin/reserved') return await adminReserve(req, env);
    throw new ApiError(404, 'no_route', 'Not found.');
  } catch (e) {
    if (!(e instanceof ApiError) && env.__onError) env.__onError(e);
    return errorResponse(e);
  }
}
