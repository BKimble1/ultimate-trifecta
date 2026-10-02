import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { makeEnv, gcBody, call, signIn, KEY_URL } from './helpers.mjs';
import { verifySession, issueSession } from '../src/tokens.js';

test('a verified Game Center signature creates an opaque profile and a session', async () => {
  const ctx = makeEnv();
  const r = await call(ctx, 'POST', '/v1/auth/gamecenter', gcBody(ctx, 'T:_abc123'));
  assert.equal(r.status, 200);
  assert.match(r.body.profile.profile_id, /^p_[a-z2-9]{20}$/);
  assert.ok(!JSON.stringify(r.body).includes('T:_abc123'), 'the Game Center ID is never echoed back');
  assert.equal(r.body.profile.needs_name, true);
  const again = await signIn(ctx, 'T:_abc123');
  assert.equal(again.profile.profile_id, r.body.profile.profile_id, 'same player, same profile');
  const other = await signIn(ctx, 'T:_other');
  assert.notEqual(other.profile.profile_id, r.body.profile.profile_id);
  assert.equal(ctx.fetches.length, 1, 'the Apple certificate is fetched once and cached');
});

test('claiming an ID without a valid Apple signature gets nothing', async () => {
  const ctx = makeEnv();
  const good = gcBody(ctx, 'T:_victim');
  const cases = {
    'no signature': { ...good, signature: '' },
    'signature for another player': gcBody(ctx, 'T:_victim', { signedPlayer: 'T:_attacker' }),
    'tampered salt': { ...good, salt: Buffer.from('different').toString('base64') },
    'tampered timestamp': { ...good, timestamp: good.timestamp - 1000 },
    'someone else\'s key': gcBody(ctx, 'T:_victim', { key: generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey }),
    'other app': gcBody(ctx, 'T:_victim', { bundle: 'com.example.other' }),
    'stale (6 min old)': gcBody(ctx, 'T:_victim', { timestamp: ctx.clock.t - 6 * 60 * 1000 }),
    'from the future': gcBody(ctx, 'T:_victim', { timestamp: ctx.clock.t + 5 * 60 * 1000 }),
    'http key URL': { ...good, public_key_url: KEY_URL.replace('https', 'http') },
    'non-Apple key host': { ...good, public_key_url: 'https://static.gc.apple.com.evil.example/k.cer' },
    'userinfo trick': { ...good, public_key_url: 'https://static.gc.apple.com@evil.example/k.cer' },
    'port trick': { ...good, public_key_url: 'https://static.gc.apple.com:8443/k.cer' },
  };
  for (const [name, body] of Object.entries(cases)) {
    const r = await call(ctx, 'POST', '/v1/auth/gamecenter', body);
    assert.ok(r.status === 401 || r.status === 400, `${name}: refused (${r.status} ${r.body.error})`);
    assert.equal(r.body.token, undefined, `${name}: no token`);
  }
  const ok = await call(ctx, 'POST', '/v1/auth/gamecenter', good);
  assert.equal(ok.status, 200, 'the genuine signature still works');
});

test('session tokens are bound to environment, bundle, audience and expiry, and sign-out revokes', async () => {
  const ctx = makeEnv();
  const s = await signIn(ctx, 'T:_p1');
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, s.token)).status, 200);
  // tampered payload
  const [body, sig] = s.token.split('.');
  const forged = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(body, 'base64url')), sub: 'p_someoneelse' })).toString('base64url') + '.' + sig;
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, forged)).status, 401);
  // another environment's token
  const prod = await issueSession({ ...ctx.env, ENVIRONMENT: 'production' }, s.profile.profile_id, ctx.clock.t);
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, prod.token)).status, 401, 'production token is not valid in sandbox');
  const otherApp = await issueSession({ ...ctx.env, BUNDLE_ID: 'com.example.other' }, s.profile.profile_id, ctx.clock.t);
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, otherApp.token)).status, 401);
  // expiry
  ctx.clock.t += 3601 * 1000;
  const exp = await call(ctx, 'GET', '/v1/me', undefined, s.token);
  assert.equal(exp.status, 401);
  assert.equal(exp.body.error, 'session_expired');
  ctx.clock.t -= 3601 * 1000;
  // sign-out
  assert.equal((await call(ctx, 'POST', '/v1/auth/signout', {}, s.token)).status, 200);
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, s.token)).status, 401, 'revoked after sign-out');
  await assert.rejects(verifySession(ctx.env, 'not.a.token'));
});

test('sign-in is rate limited per address', async () => {
  const ctx = makeEnv();
  let last;
  for (let i = 0; i < 31; i++) last = await call(ctx, 'POST', '/v1/auth/gamecenter', gcBody(ctx, 'T:_spam'), undefined, { 'cf-connecting-ip': '203.0.113.9' });
  assert.equal(last.status, 429);
  assert.ok(last.body.retry_after_s > 0);
});
