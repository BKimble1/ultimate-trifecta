// Test fixtures: an in-memory D1, a controllable clock, a test-only "Apple"
// signing key with a self-signed certificate (generated per run with the
// openssl CLI; nothing is committed), and helpers to call the service.
import { generateKeyPairSync, createSign, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { D1Shim } from './d1shim.mjs';
import { handle } from '../src/app.js';
import { clearCertCache } from '../src/gamecenter.js';

export const BUNDLE = 'com.idlery.ultimatetrifecta';
export const KEY_URL = 'https://static.gc.apple.com/public-key/gc-prod-9.cer';

let apple = null;
function appleKey() {
  if (apple) return apple;
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const dir = mkdtempSync(join(tmpdir(), 'gc-'));
  const kp = join(dir, 'key.pem');
  writeFileSync(kp, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  const r = spawnSync('openssl', ['req', '-x509', '-new', '-key', kp, '-days', '3650', '-subj', '/CN=Test Game Center Key (NOT APPLE)',
    '-outform', 'DER', '-out', join(dir, 'cert.der')]);
  if (r.status !== 0) throw new Error('openssl failed: ' + r.stderr);
  apple = { privateKey, der: readFileSync(join(dir, 'cert.der')) };
  return apple;
}

export function makeEnv(over = {}) {
  clearCertCache();
  const a = appleKey();
  const { privateKey: admPriv, publicKey: admPub } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const clock = { t: Date.now() + 60 * 1000 };   // (the test certificate is valid from "now")
  const fetches = [];
  const env = {
    DB: new D1Shim(),
    ENVIRONMENT: 'sandbox',
    BUNDLE_ID: BUNDLE,
    SESSION_KEY: 'test-session-key-0123456789abcdefghijklmnop',
    ADMISSION_PRIVATE_KEY: admPriv.export({ type: 'pkcs8', format: 'pem' }),
    ADMIN_TOKEN: 'test-admin-token-0123456789abcdef',
    __now: () => clock.t,
    __fetch: async (url) => {
      fetches.push(url);
      if (url === KEY_URL) return new Response(a.der, { status: 200 });
      return new Response('nope', { status: 404 });
    },
    ...over,
  };
  return { env, clock, fetches, admPub, apple: a };
}

export function gcBody(ctx, playerId, o = {}) {
  const ts = o.timestamp ?? ctx.clock.t;
  const salt = o.salt ?? randomBytes(8);
  const bundle = o.bundle ?? BUNDLE;
  const enc = Buffer.concat([Buffer.from(playerId, 'utf8'), Buffer.from(bundle, 'utf8'),
    (() => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(ts)); return b; })(), salt]);
  const s = createSign('RSA-SHA256');
  s.update(o.signedPlayer ? Buffer.concat([Buffer.from(o.signedPlayer, 'utf8'), enc.subarray(Buffer.byteLength(playerId))]) : enc);
  const sig = s.sign(o.key ?? ctx.apple.privateKey);
  return {
    player_id: playerId, bundle_id: bundle, timestamp: ts, salt: salt.toString('base64'),
    signature: sig.toString('base64'), public_key_url: o.url ?? KEY_URL,
  };
}

export async function call(ctx, method, path, body, token, headers = {}) {
  const h = { ...headers };
  if (body !== undefined) h['content-type'] = 'application/json';
  if (token) h.authorization = `Bearer ${token}`;
  const res = await handle(new Request('https://svc.test' + path, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) }), ctx.env);
  return { status: res.status, body: await res.json() };
}

export async function signIn(ctx, playerId) {
  const r = await call(ctx, 'POST', '/v1/auth/gamecenter', gcBody(ctx, playerId));
  if (r.status !== 200) throw new Error('sign-in failed: ' + JSON.stringify(r.body));
  return r.body;
}

export async function user(ctx, playerId, name) {
  const s = await signIn(ctx, playerId);
  if (name) {
    const r = await call(ctx, 'POST', '/v1/me/name', { name }, s.token);
    if (r.status !== 200) throw new Error('name failed: ' + JSON.stringify(r.body));
    return { token: s.token, profile: r.body.profile };
  }
  return { token: s.token, profile: s.profile };
}

export const ADMIN = { authorization: 'Bearer test-admin-token-0123456789abcdef' };
