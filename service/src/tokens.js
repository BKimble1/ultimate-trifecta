// Session tokens (HMAC-SHA256, compact "payload.signature") bound to the
// profile, app bundle, environment, audience and expiry; revocable by jti.
// Admission tokens (RS256 JWT) that a party host can verify offline with the
// service's public key, bound to room, profile, Game Center player, slot.
import { ApiError } from './http.js';
import { pemToDer } from './x509.js';
import { randomId } from './ids.js';

const enc = new TextEncoder();

export function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromB64url(s) {
  const p = s.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(p + '='.repeat((4 - (p.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

async function hmacKey(env) {
  const raw = env.SESSION_KEY;
  if (!raw || raw.length < 32) throw new ApiError(503, 'not_configured', 'The service is not configured.');
  return crypto.subtle.importKey('raw', enc.encode(raw), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export const SESSION_AUD = 'trifecta-game';
export const SESSION_TTL_S = 3600;

export async function issueSession(env, profileId, now = Date.now()) {
  const iat = Math.floor(now / 1000);
  const payload = {
    sub: profileId, aud: SESSION_AUD, env: env.ENVIRONMENT || 'development', bid: env.BUNDLE_ID,
    iat, exp: iat + SESSION_TTL_S, jti: randomId('s', 12),
  };
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', await hmacKey(env), enc.encode(body)));
  return { token: `${body}.${b64url(sig)}`, payload };
}

export async function verifySession(env, token, now = Date.now()) {
  if (typeof token !== 'string' || token.length > 2048) throw new ApiError(401, 'signed_out', 'Please sign in again.');
  const dot = token.indexOf('.');
  if (dot < 1 || dot !== token.lastIndexOf('.')) throw new ApiError(401, 'signed_out', 'Please sign in again.');
  const body = token.slice(0, dot);
  let ok = false;
  try {
    ok = await crypto.subtle.verify('HMAC', await hmacKey(env), fromB64url(token.slice(dot + 1)), enc.encode(body));
  } catch (e) {
    if (e instanceof ApiError) throw e;
  }
  if (!ok) throw new ApiError(401, 'signed_out', 'Please sign in again.');
  let p;
  try {
    p = JSON.parse(new TextDecoder().decode(fromB64url(body)));
  } catch {
    throw new ApiError(401, 'signed_out', 'Please sign in again.');
  }
  const t = Math.floor(now / 1000);
  if (p.aud !== SESSION_AUD || p.env !== (env.ENVIRONMENT || 'development') || p.bid !== env.BUNDLE_ID) {
    throw new ApiError(401, 'signed_out', 'Please sign in again.');
  }
  if (typeof p.exp !== 'number' || t >= p.exp || typeof p.sub !== 'string') throw new ApiError(401, 'session_expired', 'Session expired. Signing in again…');
  return p;
}

let _admKey = null;
let _admKeySrc = '';

async function admissionKey(env) {
  const pem = env.ADMISSION_PRIVATE_KEY;
  if (!pem) throw new ApiError(503, 'not_configured', 'Parties are not configured on this server.');
  if (_admKey && _admKeySrc === pem) return _admKey;
  _admKey = await crypto.subtle.importKey('pkcs8', pemToDer(pem), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  _admKeySrc = pem;
  return _admKey;
}

export const ADMISSION_AUD = 'trifecta-host';
export const ADMISSION_TTL_S = 120;

export async function issueAdmission(env, claims, now = Date.now()) {
  const iat = Math.floor(now / 1000);
  const header = { alg: 'RS256', typ: 'JWT', kid: env.ADMISSION_KEY_ID || 'adm1' };
  const payload = { ...claims, aud: ADMISSION_AUD, iss: 'trifecta-service', env: env.ENVIRONMENT || 'development', iat, exp: iat + ADMISSION_TTL_S, jti: randomId('a', 12) };
  const signing = `${b64url(enc.encode(JSON.stringify(header)))}.${b64url(enc.encode(JSON.stringify(payload)))}`;
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', await admissionKey(env), enc.encode(signing)));
  return { token: `${signing}.${b64url(sig)}`, payload };
}
