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
    // the same key on both deployments (docs/COMMERCE_SETUP.md)
    APP_ACCOUNT_TOKEN_KEY: 'test-app-account-token-key-0123456789abcdef',
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

// ---------------------------------------------------------------- App Store
// A test-only certificate chain shaped like Apple's (root P-384, intermediate
// with the WWDR marker OID, leaf P-256 with the App Store marker OID),
// generated per run with the openssl CLI.  Handed to the service as
// env.__appleRoots (Uint8Array: never settable from configuration).
import { createPrivateKey, sign as nodeSign } from 'node:crypto';
let chains = {};
function run(args, input) {
  const r = spawnSync('openssl', args, { input });
  if (r.status !== 0) throw new Error('openssl ' + args.join(' ') + ': ' + r.stderr);
  return r.stdout;
}
export function appleChain(name = 'good', { leafMarker = true, interMarker = true } = {}) {
  const key = `${name}:${leafMarker}:${interMarker}`;
  if (chains[key]) return chains[key];
  const dir = mkdtempSync(join(tmpdir(), 'asc-'));
  const p = (f) => join(dir, f);
  run(['ecparam', '-name', 'secp384r1', '-genkey', '-noout', '-out', p('root.key')]);
  run(['req', '-x509', '-new', '-key', p('root.key'), '-days', '3650', '-subj', `/CN=Test Root ${name} (NOT APPLE)`, '-sha384', '-out', p('root.pem'),
    '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign']);
  run(['ecparam', '-name', 'secp384r1', '-genkey', '-noout', '-out', p('inter.key')]);
  run(['req', '-new', '-key', p('inter.key'), '-subj', `/CN=Test WWDR ${name}`, '-out', p('inter.csr')]);
  writeFileSync(p('inter.ext'), 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n' + (interMarker ? '1.2.840.113635.100.6.2.1=ASN1:NULL\n' : ''));
  run(['x509', '-req', '-in', p('inter.csr'), '-CA', p('root.pem'), '-CAkey', p('root.key'), '-CAcreateserial', '-days', '3650', '-sha384',
    '-extfile', p('inter.ext'), '-out', p('inter.pem')]);
  run(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', p('leaf.key')]);
  run(['req', '-new', '-key', p('leaf.key'), '-subj', `/CN=Test StoreKit Signing ${name}`, '-out', p('leaf.csr')]);
  writeFileSync(p('leaf.ext'), 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n' + (leafMarker ? '1.2.840.113635.100.6.11.1=ASN1:NULL\n' : ''));
  run(['x509', '-req', '-in', p('leaf.csr'), '-CA', p('inter.pem'), '-CAkey', p('inter.key'), '-CAcreateserial', '-days', '3650', '-sha384',
    '-extfile', p('leaf.ext'), '-out', p('leaf.pem')]);
  const der = (f) => run(['x509', '-in', p(f), '-outform', 'DER']);
  const out = {
    rootDer: new Uint8Array(der('root.pem')),
    x5c: [der('leaf.pem'), der('inter.pem'), der('root.pem')].map((b) => Buffer.from(b).toString('base64')),
    leafKey: createPrivateKey(readFileSync(p('leaf.key'))),
  };
  chains[key] = out;
  return out;
}

const b64u = (b) => Buffer.from(b).toString('base64url');
export function appleJws(payload, chain = appleChain()) {
  const h = b64u(JSON.stringify({ alg: 'ES256', x5c: chain.x5c }));
  const pl = b64u(JSON.stringify(payload));
  const sig = nodeSign('sha256', Buffer.from(`${h}.${pl}`), { key: chain.leafKey, dsaEncoding: 'ieee-p1363' });
  return `${h}.${pl}.${b64u(sig)}`;
}

export function trustTestRoot(ctx, chain = appleChain()) {
  ctx.env.__appleRoots = [chain.rootDer];
  ctx.env.__appleRootsOnly = true;
}

let txSeq = 4000000;
export function storeTx(ctx, o = {}) {
  txSeq += 1;
  return {
    transactionId: String(o.transactionId ?? txSeq), originalTransactionId: String(o.originalTransactionId ?? o.transactionId ?? txSeq),
    bundleId: o.bundleId ?? BUNDLE, productId: o.productId ?? 'com.idlery.ultimatetrifecta.coins.1500',
    type: o.type ?? 'Consumable', environment: o.environment ?? 'Sandbox', purchaseDate: ctx.clock.t - 1000,
    signedDate: o.signedDate ?? ctx.clock.t, quantity: 1, ...(o.appAccountToken !== undefined ? { appAccountToken: o.appAccountToken } : {}),
    ...(o.revocationDate ? { revocationDate: o.revocationDate } : {}),
  };
}
