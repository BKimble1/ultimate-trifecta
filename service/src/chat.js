// V6 typed party chat and message reports.
//
// The party host relays chat over Game Center; this service is what makes a
// typed message trustworthy.  POST /v1/chat/check runs the message policy
// (chat_rules.js) for a signed-in member of a live room and, if it passes,
// signs the approved text into a short-lived RS256 token (the admission
// key: the game already ships its public key).  The host relays only typed
// messages carrying a valid token for its room and that sender's profile,
// and every receiver verifies the token again before showing anything, so
// neither a modified client nor a modified host can put unapproved text on
// another player's screen.  Message text is not stored here; it is kept
// only when someone reports the message, from the token the reporter
// presents (proof that the service approved exactly that text from exactly
// that sender for that room).
//
// Routes are registered in app.js; its helpers arrive as `deps` so this file
// adds no edits to the shared request code.
import { ApiError, json, readJson, str, int } from './http.js';
import { checkChat, CHAT_MAX } from './chat_rules.js';
import { b64url, fromB64url } from './tokens.js';
import { pemToDer } from './x509.js';
import { normalizeCode, randomId } from './ids.js';

export const CHAT_AUD = 'trifecta-chat';
export const CHAT_TTL_S = 300;
// reports may quote a message for this long after it was approved
export const REPORT_WINDOW_S = 24 * 3600;
export const CHAT_RATE = { max: 8, windowMs: 10 * 1000 };
export const CHAT_HOURLY = { max: 150, windowMs: 3600 * 1000 };
export const MESSAGE_REASONS = ['harassment', 'inappropriate', 'spam', 'other'];
// 0 party (lobby), 1 team (own role during a round), 2 everyone (results),
// 3 spectators (finished / watching players during a round)
export const CHANNELS = [0, 1, 2, 3];
const LIVE = "('forming','open','full','loading','in_match','results')";
const enc = new TextEncoder();

let _key = null;
let _keySrc = '';
async function signingKey(env) {
  const pem = env.ADMISSION_PRIVATE_KEY;
  if (!pem) throw new ApiError(503, 'not_configured', 'Chat is not configured on this server.');
  if (_key && _keySrc === pem) return _key;
  _key = await crypto.subtle.importKey('pkcs8', pemToDer(pem), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  _keySrc = pem;
  return _key;
}

async function sign(env, signing) {
  return b64url(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', await signingKey(env), enc.encode(signing))));
}

export async function issueChatToken(env, claims, now) {
  const iat = Math.floor(now / 1000);
  const header = { alg: 'RS256', typ: 'JWT', kid: env.ADMISSION_KEY_ID || 'adm1' };
  const payload = { ...claims, aud: CHAT_AUD, iss: 'trifecta-service', env: env.ENVIRONMENT || 'development', iat, exp: iat + CHAT_TTL_S, jti: randomId('c', 12) };
  const signing = `${b64url(enc.encode(JSON.stringify(header)))}.${b64url(enc.encode(JSON.stringify(payload)))}`;
  return { token: `${signing}.${await sign(env, signing)}`, payload };
}

// The service's own chat token, checked by signing it again (RSASSA-PKCS1-
// v1_5 signatures are deterministic): returns the claims or throws.
export async function readChatToken(env, token, now) {
  if (typeof token !== 'string' || token.length > 4096) throw new ApiError(400, 'bad_token', 'That message could not be identified.');
  const parts = token.split('.');
  if (parts.length !== 3) throw new ApiError(400, 'bad_token', 'That message could not be identified.');
  if ((await sign(env, `${parts[0]}.${parts[1]}`)) !== parts[2]) throw new ApiError(400, 'bad_token', 'That message could not be identified.');
  let c;
  try {
    c = JSON.parse(new TextDecoder().decode(fromB64url(parts[1])));
  } catch {
    throw new ApiError(400, 'bad_token', 'That message could not be identified.');
  }
  if (c.aud !== CHAT_AUD || c.env !== (env.ENVIRONMENT || 'development')) throw new ApiError(400, 'bad_token', 'That message could not be identified.');
  if (typeof c.iat !== 'number' || Math.floor(now / 1000) - c.iat > REPORT_WINDOW_S) {
    throw new ApiError(410, 'too_old', 'That message is too old to report. You can still report the player.');
  }
  return c;
}

// POST /v1/chat/check {room_code, channel, text}
export async function chatCheck(req, env, deps) {
  const { profile: p } = await deps.requireUser(req, env);
  const body = await readJson(req);
  const n = normalizeCode(str(body.room_code, 'room_code', { max: 24 }));
  if (!n.ok) throw new ApiError(400, n.error, n.message);
  const channel = int(body.channel, 'channel', { min: 0, max: CHANNELS.length - 1 });
  const text = str(body.text, 'text', { max: CHAT_MAX * 4 });
  // every attempt counts, so the filter can't be probed at speed
  await deps.rateLimit(env, `chat:${p.id}`, CHAT_RATE.max, CHAT_RATE.windowMs, 'You\'re sending messages too fast. Wait a moment.');
  await deps.rateLimit(env, `chat_hour:${p.id}`, CHAT_HOURLY.max, CHAT_HOURLY.windowMs, 'You\'ve sent a lot of messages. Take a short break.');
  const q = deps.db(env);
  const room = await q.one(`SELECT id, code FROM rooms WHERE code = ? AND state IN ${LIVE}`, n.code);
  if (!room) throw new ApiError(404, 'not_found', 'That party has ended.');
  const member = await q.one("SELECT slot FROM room_members WHERE room_id = ? AND profile_id = ? AND state != 'left' AND kicked = 0", room.id, p.id);
  if (!member) throw new ApiError(403, 'not_member', 'Only players in this party can chat in it.');
  const m = checkChat(text);
  if (!m.ok) throw new ApiError(422, 'chat_rejected', m.message, { reason: m.reason });
  const name = p.display_name && !p.forced_rename ? `${p.display_name}#${String(p.discriminator).padStart(4, '0')}` : null;
  const t = deps.clock(env);
  const { token, payload } = await issueChatToken(env, { sub: p.id, room: room.code, ch: channel, text: m.text, name }, t);
  return json({ ok: true, text: m.text, token, expires_at: payload.exp * 1000 });
}

// POST /v1/reports/message {token, reason, details?}
export async function reportMessage(req, env, deps) {
  const { profile: p } = await deps.requireUser(req, env, { allowSuspended: true });
  const body = await readJson(req);
  const reason = str(body.reason, 'reason', { max: 20 });
  if (!MESSAGE_REASONS.includes(reason)) throw new ApiError(400, 'bad_reason', 'Pick a reason for the report.');
  const details = str(body.details, 'details', { max: 500, optional: true });
  const t = deps.clock(env);
  const c = await readChatToken(env, body.token, t);
  if (c.sub === p.id) throw new ApiError(400, 'self', "You can't report your own message.");
  const q = deps.db(env);
  const tp = await q.one('SELECT id, display_name FROM profiles WHERE id = ?', c.sub);
  if (!tp) throw new ApiError(404, 'not_found', 'That player could not be found.');
  const dup = await q.one('SELECT id FROM reports WHERE reporter_id = ? AND evidence_ref = ?', p.id, c.jti);
  if (dup) return json({ ok: true, receipt: dup.id, status: 'received', duplicate: true });
  await deps.rateLimit(env, `report:${p.id}`, 12, 24 * 3600 * 1000, "You've sent a lot of reports today. Our team will review them.");
  const id = randomId('R', 10).toUpperCase().replace('R_', 'R-');
  const context = { kind: 'message', room_code: String(c.room || '').slice(0, 12), channel: Number.isInteger(c.ch) ? c.ch : null,
    sent_at: c.iat * 1000, build: Number.isSafeInteger(body.build) ? body.build : null };
  await q.run(`INSERT INTO reports (id, reporter_id, target_id, target_name, reason, details, context, status, created_at, kind, evidence, evidence_ref)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, 'message', ?, ?)`,
  id, p.id, c.sub, tp.display_name, reason, details, JSON.stringify(context), t, String(c.text || '').slice(0, 200), c.jti);
  await deps.audit(env, p.id, 'report_filed', c.sub, { receipt: id, reason, kind: 'message' });
  return json({ ok: true, receipt: id, status: 'received' });
}
