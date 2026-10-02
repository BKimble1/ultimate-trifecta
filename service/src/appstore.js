// App Store verification (server side), dependency-free for Workers.
//
// StoreKit 2 transactions, App Store Server API replies and App Store Server
// Notifications V2 are JWS (ES256) whose header carries the signing chain
// (x5c: leaf, intermediate, root).  A JWS is accepted only when:
//  - the root is Apple Root CA - G3, pinned by its SHA-256 fingerprint
//    (the same pin Apple's and the community libraries use);
//  - each certificate is issued and signed by the next one (ECDSA, verified
//    with WebCrypto), the intermediate carries Apple's WWDR marker OID and
//    the leaf Apple's App Store receipt-signing marker OID;
//  - every certificate is valid at the payload's signedDate (never later
//    than now + a small skew);
//  - the JWS signature verifies with the leaf key.
// Then the caller checks bundle, environment, product, type and account.
// Payloads are never logged.
//
// Optional second source: with an App Store Connect In-App Purchase key
// (ASC_IAP_KEY_ID, ASC_IAP_ISSUER_ID, ASC_IAP_PRIVATE_KEY) the service asks
// the App Store Server API for the transaction itself (sandbox or production
// host by the deployment) and uses Apple's own copy.
import { ApiError } from './http.js';
import { fromB64url, b64url } from './tokens.js';
import { pemToDer } from './x509.js';

export const APPLE_ROOT_G3_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179';
const OID_WWDR_INTERMEDIATE = '1.2.840.113635.100.6.2.1';
const OID_APPSTORE_LEAF = '1.2.840.113635.100.6.11.1';
const SKEW_MS = 5 * 60 * 1000;
const MAX_JWS = 16 * 1024;

// ---------------------------------------------------------------- DER
function tlv(buf, off) {
  if (off + 2 > buf.length) throw new Error('DER overrun');
  const tag = buf[off];
  let len = buf[off + 1];
  let hdr = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 4) throw new Error('bad DER length');
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + buf[off + 2 + i];
    hdr = 2 + n;
  }
  const start = off + hdr;
  const end = start + len;
  if (end > buf.length) throw new Error('DER overrun');
  return { tag, off, start, end };
}

function kids(buf, t) {
  const out = [];
  let o = t.start;
  while (o < t.end) {
    const c = tlv(buf, o);
    out.push(c);
    o = c.end;
  }
  return out;
}

function oid(buf, t) {
  const b = buf.subarray(t.start, t.end);
  const parts = [Math.floor(b[0] / 40), b[0] % 40];
  let v = 0;
  for (let i = 1; i < b.length; i++) {
    v = v * 128 + (b[i] & 0x7f);
    if (!(b[i] & 0x80)) {
      parts.push(v);
      v = 0;
    }
  }
  return parts.join('.');
}

function time(buf, t) {
  const s = new TextDecoder().decode(buf.subarray(t.start, t.end));
  let y;
  let r;
  if (t.tag === 0x17) {
    y = Number(s.slice(0, 2));
    y += y < 50 ? 2000 : 1900;
    r = s.slice(2);
  } else {
    y = Number(s.slice(0, 4));
    r = s.slice(4);
  }
  return Date.UTC(y, Number(r.slice(0, 2)) - 1, Number(r.slice(2, 4)), Number(r.slice(4, 6)), Number(r.slice(6, 8)), Number(r.slice(8, 10)));
}

// The parts of an X.509 certificate the chain check needs.
export function parseCert(der) {
  const buf = der instanceof Uint8Array ? der : new Uint8Array(der);
  const cert = tlv(buf, 0);
  if (cert.tag !== 0x30) throw new Error('not a certificate');
  const [tbs, sigAlg, sigVal] = kids(buf, cert);
  let p = kids(buf, tbs);
  if (p[0].tag === 0xa0) p = p.slice(1);
  const [, , issuer, validity, subject, spki] = p;
  const v = kids(buf, validity);
  const spkiAlg = kids(buf, kids(buf, spki)[0]);
  const exts = new Set();
  for (const x of p.slice(6)) {
    if (x.tag !== 0xa3) continue;
    for (const e of kids(buf, kids(buf, x)[0])) exts.add(oid(buf, kids(buf, e)[0]));
  }
  const sigBits = buf.subarray(sigVal.start + 1, sigVal.end);   // skip the unused-bits byte
  return {
    der: buf,
    tbs: buf.subarray(tbs.off, tbs.end),
    sigAlg: oid(buf, kids(buf, sigAlg)[0]),
    signature: sigBits,
    issuer: buf.subarray(issuer.off, issuer.end),
    subject: buf.subarray(subject.off, subject.end),
    notBefore: time(buf, v[0]),
    notAfter: time(buf, v[1]),
    spki: buf.subarray(spki.off, spki.end),
    keyAlg: oid(buf, spkiAlg[0]),
    curve: spkiAlg[1] ? oid(buf, spkiAlg[1]) : '',
    extensions: exts,
  };
}

const CURVES = { '1.2.840.10045.3.1.7': ['P-256', 32], '1.3.132.0.34': ['P-384', 48] };
const HASHES = { '1.2.840.10045.4.3.2': 'SHA-256', '1.2.840.10045.4.3.3': 'SHA-384' };

// DER ECDSA signature (SEQUENCE {r, s}) -> raw r||s for WebCrypto.
export function derToRaw(sig, n) {
  const seq = tlv(sig, 0);
  const [r, s] = kids(sig, seq);
  const out = new Uint8Array(n * 2);
  const put = (t, at) => {
    let b = sig.subarray(t.start, t.end);
    while (b.length > n && b[0] === 0) b = b.subarray(1);
    if (b.length > n) throw new Error('bad signature');
    out.set(b, at + n - b.length);
  };
  put(r, 0);
  put(s, n);
  return out;
}

async function importKey(cert) {
  const c = CURVES[cert.curve];
  if (cert.keyAlg !== '1.2.840.10045.2.1' || !c) throw new Error('unsupported key');
  return crypto.subtle.importKey('spki', cert.spki, { name: 'ECDSA', namedCurve: c[0] }, false, ['verify']);
}

async function issuedBy(child, parent) {
  if (child.issuer.length !== parent.subject.length || child.issuer.some((b, i) => b !== parent.subject[i])) return false;
  const hash = HASHES[child.sigAlg];
  const c = CURVES[parent.curve];
  if (!hash || !c) return false;
  const key = await importKey(parent);
  return crypto.subtle.verify({ name: 'ECDSA', hash }, key, derToRaw(child.signature, c[1]), child.tbs);
}

async function sha256hex(bytes) {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return [...h].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Trusted root fingerprints: Apple Root CA - G3, or (tests only) roots
// handed in as Uint8Array objects on env.__appleRoots, which configuration
// variables (strings / JSON) can never produce.
async function trustedRoots(env) {
  const out = new Set([APPLE_ROOT_G3_SHA256]);
  if (Array.isArray(env.__appleRoots)) {
    for (const r of env.__appleRoots) if (r instanceof Uint8Array) out.add(await sha256hex(r));
    if (env.__appleRootsOnly) out.delete(APPLE_ROOT_G3_SHA256);
  }
  return out;
}

const bad = (why) => new ApiError(400, 'bad_transaction', "This purchase couldn't be verified with Apple.", { reason: why });

// Verifies an Apple-signed JWS and returns its payload, or throws.
export async function verifyAppleJws(jws, env, now = Date.now()) {
  if (typeof jws !== 'string' || jws.length < 20 || jws.length > MAX_JWS) throw bad('format');
  const parts = jws.split('.');
  if (parts.length !== 3) throw bad('format');
  let header;
  let payload;
  try {
    header = JSON.parse(new TextDecoder().decode(fromB64url(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(fromB64url(parts[1])));
  } catch {
    throw bad('format');
  }
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length !== 3) throw bad('header');
  let chain;
  try {
    chain = header.x5c.map((c) => parseCert(Uint8Array.from(atob(c), (ch) => ch.charCodeAt(0))));
  } catch {
    throw bad('certificate');
  }
  const [leaf, inter, root] = chain;
  if (!(await trustedRoots(env)).has(await sha256hex(root.der))) throw bad('root');
  if (!inter.extensions.has(OID_WWDR_INTERMEDIATE) || !leaf.extensions.has(OID_APPSTORE_LEAF)) throw bad('marker');
  if (!(await issuedBy(leaf, inter)) || !(await issuedBy(inter, root))) throw bad('chain');
  const leafKey = await importKey(leaf);
  const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, leafKey, fromB64url(parts[2]),
    new TextEncoder().encode(parts[0] + '.' + parts[1]));
  if (!ok) throw bad('signature');
  const at = Number(payload.signedDate || now);
  if (!Number.isFinite(at) || at > now + SKEW_MS) throw bad('date');
  for (const c of chain) if (at < c.notBefore || at > c.notAfter) throw bad('expired');
  return payload;
}

// ---------------------------------------------------------------- server API
export function appleEnvironment(env) {
  // the deployment decides which App Store environment it accepts
  return env.APPLE_ENVIRONMENT === 'Production' ? 'Production' : 'Sandbox';
}

export function serverApiConfigured(env) {
  return !!(env.ASC_IAP_KEY_ID && env.ASC_IAP_ISSUER_ID && env.ASC_IAP_PRIVATE_KEY);
}

async function serverApiToken(env, now) {
  const header = { alg: 'ES256', kid: env.ASC_IAP_KEY_ID, typ: 'JWT' };
  const iat = Math.floor(now / 1000);
  const body = { iss: env.ASC_IAP_ISSUER_ID, iat, exp: iat + 600, aud: 'appstoreconnect-v1', bid: env.BUNDLE_ID };
  const enc = new TextEncoder();
  const input = b64url(enc.encode(JSON.stringify(header))) + '.' + b64url(enc.encode(JSON.stringify(body)));
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(env.ASC_IAP_PRIVATE_KEY), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(input)));
  return input + '.' + b64url(sig);
}

// Apple's own copy of a transaction (App Store Server API, Get Transaction
// Info), verified like any JWS.  null when the API isn't configured.
export async function fetchTransaction(env, transactionId, now = Date.now()) {
  if (!serverApiConfigured(env)) return null;
  if (!/^[0-9]{1,24}$/.test(String(transactionId))) throw bad('transaction_id');
  const host = appleEnvironment(env) === 'Production' ? 'https://api.storekit.itunes.apple.com' : 'https://api.storekit-sandbox.itunes.apple.com';
  const f = env.__fetch || fetch;
  let res;
  try {
    res = await f(`${host}/inApps/v1/transactions/${transactionId}`, { headers: { authorization: 'Bearer ' + (await serverApiToken(env, now)) } });
  } catch {
    throw new ApiError(503, 'apple_unavailable', "Couldn't reach the App Store to confirm this purchase. It will be added when it's confirmed.");
  }
  if (res.status === 404) throw new ApiError(400, 'bad_transaction', 'The App Store has no such purchase in this environment.', { reason: 'not_found' });
  if (!res.ok) throw new ApiError(503, 'apple_unavailable', "Couldn't reach the App Store to confirm this purchase. It will be added when it's confirmed.");
  const body = await res.json();
  return verifyAppleJws(String(body.signedTransactionInfo || ''), env, now);
}
