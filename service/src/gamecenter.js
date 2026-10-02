// Game Center identity verification (server side).
//
// The client calls GKLocalPlayer.fetchItemsForIdentityVerificationSignature
// and sends {player_id (teamPlayerID), public_key_url, signature, salt,
// timestamp, bundle_id}.  Apple signs, with RSASSA-PKCS1-v1_5 / SHA-256:
//     teamPlayerID (UTF-8) || bundleID (UTF-8) || timestamp (UInt64 BE) || salt
// We accept only certificates served over HTTPS from Apple's key host, check
// the certificate's validity window and the timestamp's freshness, and only
// then trust the player ID.  A client that merely *claims* an ID gets nothing.
import { ApiError } from './http.js';
import { parseCertificate } from './x509.js';

const certCache = new Map();   // url -> {key, notBefore, notAfter, at}
const CERT_TTL_MS = 6 * 3600 * 1000;
export const MAX_AGE_MS = 5 * 60 * 1000;
export const MAX_SKEW_MS = 60 * 1000;

function b64(s, name) {
  try {
    return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  } catch {
    throw new ApiError(400, 'bad_request', `${name} must be base64.`);
  }
}

export function signedPayload(playerId, bundleId, timestamp, salt) {
  const enc = new TextEncoder();
  const a = enc.encode(playerId);
  const b = enc.encode(bundleId);
  const t = new Uint8Array(8);
  new DataView(t.buffer).setBigUint64(0, BigInt(timestamp), false);
  const out = new Uint8Array(a.length + b.length + 8 + salt.length);
  out.set(a, 0);
  out.set(b, a.length);
  out.set(t, a.length + b.length);
  out.set(salt, a.length + b.length + 8);
  return out;
}

export function checkKeyUrl(url, env) {
  let u;
  try {
    u = new URL(url);
  } catch {
    throw new ApiError(400, 'bad_key_url', 'The Game Center key URL is not valid.');
  }
  const hosts = String(env.GC_KEY_HOSTS || 'static.gc.apple.com').split(',').map((h) => h.trim()).filter(Boolean);
  if (u.protocol !== 'https:' || !hosts.includes(u.hostname) || u.username || u.password || u.port) {
    throw new ApiError(401, 'bad_key_url', 'Game Center key must come from Apple.');
  }
  return u.toString();
}

async function loadKey(url, env, now) {
  const hit = certCache.get(url);
  if (hit && now - hit.at < CERT_TTL_MS) return hit;
  const f = env.__fetch || fetch;
  const res = await f(url, { cf: { cacheTtl: 21600 } });
  if (!res.ok) throw new ApiError(503, 'apple_unavailable', 'Could not reach Game Center to confirm your sign-in. Try again soon.');
  const der = new Uint8Array(await res.arrayBuffer());
  let cert;
  try {
    cert = parseCertificate(der);
  } catch {
    throw new ApiError(401, 'bad_certificate', 'Game Center certificate could not be read.');
  }
  const key = await crypto.subtle.importKey('spki', cert.spki, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const entry = { key, notBefore: cert.notBefore, notAfter: cert.notAfter, at: now };
  certCache.set(url, entry);
  return entry;
}

export function clearCertCache() {
  certCache.clear();
}

// Returns the verified teamPlayerID or throws ApiError (401 for every
// verification failure, so a forger learns nothing about which check failed).
export async function verifyIdentity(body, env, now = Date.now()) {
  const playerId = body.player_id;
  const bundleId = body.bundle_id;
  if (typeof playerId !== 'string' || playerId.length < 3 || playerId.length > 128) {
    throw new ApiError(400, 'bad_request', 'Missing Game Center player.');
  }
  if (bundleId !== env.BUNDLE_ID) throw new ApiError(401, 'wrong_app', 'This sign-in is for a different app.');
  const ts = Number(body.timestamp);
  if (!Number.isSafeInteger(ts)) throw new ApiError(400, 'bad_request', 'Missing timestamp.');
  if (ts < now - MAX_AGE_MS || ts > now + MAX_SKEW_MS) {
    throw new ApiError(401, 'stale_signature', 'Sign-in expired. Please try again.');
  }
  const url = checkKeyUrl(String(body.public_key_url || ''), env);
  const salt = b64(String(body.salt || ''), 'salt');
  const sig = b64(String(body.signature || ''), 'signature');
  if (salt.length < 4 || sig.length < 64) throw new ApiError(400, 'bad_request', 'Incomplete Game Center signature.');
  const k = await loadKey(url, env, now);
  if (now < k.notBefore || now > k.notAfter) throw new ApiError(401, 'bad_certificate', 'Game Center certificate is not valid now.');
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', k.key, sig, signedPayload(playerId, bundleId, ts, salt));
  if (!ok) throw new ApiError(401, 'bad_signature', 'Game Center sign-in could not be verified.');
  return playerId;
}
