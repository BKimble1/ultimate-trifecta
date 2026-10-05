// FINAL_RELEASE_SWEEP: one release candidate for TestFlight, App Review and
// the App Store, with sandbox and production value isolated.
//
// Two deployments, as wrangler.toml defines them: the default sandbox one
// (ENVIRONMENT=sandbox, APPLE_ENVIRONMENT=Sandbox, its own D1) and
// [env.production] (its own D1).  Each credits only its own App Store
// environment; a verified Apple transaction from the other environment gets a
// routing reply (409 sandbox_purchase / production_purchase) and is neither
// recorded nor credited.  The appAccountToken is derived from the Game Center
// player with one key shared by both deployments, so the App Review fallback
// (production refuses -> the game moves to sandbox -> the same unfinished
// transaction is delivered there) credits the same player exactly once.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeEnv, call, user, ADMIN, appleChain, appleJws, trustTestRoot, storeTx } from './helpers.mjs';
import { deriveAccountToken } from '../src/commerce.js';

const PACK = 'com.idlery.ultimatetrifecta.coins.1500';
const SKIN = 'com.idlery.ultimatetrifecta.skin.moonlight_runner';

// The two deployments: separate databases and clocks, the same secrets
// (deploy.sh uploads one .secrets/ folder to both).
function deployments() {
  const sandbox = makeEnv();
  const production = makeEnv({ ENVIRONMENT: 'production', APPLE_ENVIRONMENT: 'Production' });
  for (const d of [sandbox, production]) trustTestRoot(d);
  assert.notEqual(sandbox.env.DB, production.env.DB, 'separate databases');
  return { sandbox, production };
}

async function wallet(ctx, u) {
  const r = await call(ctx, 'GET', '/v1/wallet', undefined, u.token);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.wallet;
}

function deliver(ctx, u, tx, chain) {
  return call(ctx, 'POST', '/v1/wallet/apple', { jws: appleJws(tx, chain), transaction_id: tx.transactionId }, u.token);
}

async function appleRows(ctx) {
  return (await ctx.env.DB.prepare('SELECT * FROM apple_transactions').all()).results;
}

async function ledgerRows(ctx) {
  return (await ctx.env.DB.prepare('SELECT * FROM ledger').all()).results;
}

test('derived appAccountToken: same player, same token on both deployments; different players differ', async () => {
  const { sandbox, production } = deployments();
  const sa = await user(sandbox, 'T:_ann', 'Ann Otter');
  const pa = await user(production, 'T:_ann', 'Ann Otter');
  const pb = await user(production, 'T:_ben', 'Ben Otter');
  const ts = (await wallet(sandbox, sa)).app_account_token;
  const tp = (await wallet(production, pa)).app_account_token;
  assert.match(ts, /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/, 'a UUID (version 8, RFC variant) StoreKit accepts');
  assert.notEqual(sa.profile.profile_id, pa.profile.profile_id, 'separate profiles in separate databases');
  assert.equal(ts, tp, 'the same Game Center player has the same token in both deployments');
  assert.notEqual((await wallet(production, pb)).app_account_token, tp, 'another player has another token');
  assert.equal(await deriveAccountToken(sandbox.env, 'T:_ann'), ts, 'HMAC(APP_ACCOUNT_TOKEN_KEY, "gamecenter:" + teamPlayerID)');
  // a different key (a misconfigured deployment) gives different tokens: the
  // key must be identical on both (docs/COMMERCE_SETUP.md)
  assert.notEqual(await deriveAccountToken({ APP_ACCOUNT_TOKEN_KEY: 'another-key-0123456789abcdef-0123456789' }, 'T:_ann'), ts);
  // no key: no token, and the deployment never delivers a purchase unbound
  assert.equal(await deriveAccountToken({}, 'T:_ann'), null);
  // deleting and recreating the profile keeps the token (restore follows the player)
  sandbox.clock.t += 1000;
  const again = await user(sandbox, 'T:_ann', null);
  assert.equal((await call(sandbox, 'DELETE', '/v1/me', { confirm: 'DELETE' }, again.token)).status, 200);
  const back = await user(sandbox, 'T:_ann', 'Ann Again');
  assert.notEqual(back.profile.profile_id, sa.profile.profile_id);
  assert.equal((await wallet(sandbox, back)).app_account_token, ts);
});

test('a wallet row from before derived tokens takes the derived token', async () => {
  const { sandbox } = deployments();
  const a = await user(sandbox, 'T:_ann', 'Ann Otter');
  const derived = (await wallet(sandbox, a)).app_account_token;
  await sandbox.env.DB.prepare('UPDATE wallets SET app_account_token = ? WHERE profile_id = ?').bind('3f0c8a52-1b7e-4c2a-9d1e-1234567890ab', a.profile.profile_id).run();
  assert.equal((await wallet(sandbox, a)).app_account_token, derived, 'an old random token is replaced on the next read');
  // a deployment without the key: no token in the snapshot, purchases kept unfinished (503)
  const nokey = makeEnv({ APP_ACCOUNT_TOKEN_KEY: undefined });
  trustTestRoot(nokey);
  const u = await user(nokey, 'T:_ann', 'Ann Otter');
  assert.equal((await wallet(nokey, u)).app_account_token, null);
  const r = await deliver(nokey, u, storeTx(nokey));
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'not_configured');
  assert.equal((await appleRows(nokey)).length, 0);
});

test('a valid sandbox purchase credits only the sandbox deployment', async () => {
  const { sandbox, production } = deployments();
  const sa = await user(sandbox, 'T:_ann', 'Ann Otter');
  const pa = await user(production, 'T:_ann', 'Ann Otter');
  const tok = (await wallet(sandbox, sa)).app_account_token;
  const tx = storeTx(sandbox, { environment: 'Sandbox', appAccountToken: tok });
  const r = await deliver(sandbox, sa, tx);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.wallet.balance, 1500);
  assert.equal(r.body.wallet.environment, 'sandbox');
  // the same transaction presented to production: refused, nothing recorded
  const p = await deliver(production, pa, tx);
  assert.equal(p.status, 409);
  assert.equal(p.body.error, 'sandbox_purchase');
  assert.equal((await wallet(production, pa)).balance, 0);
  assert.equal((await appleRows(production)).length, 0);
  assert.equal((await ledgerRows(production)).length, 0);
});

test('a valid production purchase credits only production', async () => {
  const { sandbox, production } = deployments();
  const sa = await user(sandbox, 'T:_ann', 'Ann Otter');
  const pa = await user(production, 'T:_ann', 'Ann Otter');
  const tok = (await wallet(production, pa)).app_account_token;
  for (const [pid, type] of [[PACK, 'Consumable'], [SKIN, 'Non-Consumable']]) {
    const tx = storeTx(production, { environment: 'Production', productId: pid, type, appAccountToken: tok });
    const r = await deliver(production, pa, tx);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const s = await deliver(sandbox, sa, tx);
    assert.equal(s.status, 409);
    assert.equal(s.body.error, 'production_purchase', 'the sandbox never credits a real purchase (the game moves back to production)');
  }
  const wp = await wallet(production, pa);
  assert.equal(wp.balance, 1500);
  assert.ok(wp.entitlements.some((e) => e.item === 'outfit:moonlight_runner' && e.source === 'apple'));
  const ws = await wallet(sandbox, sa);
  assert.equal(ws.balance, 0);
  assert.equal(ws.entitlements.length, 0);
  assert.equal((await appleRows(sandbox)).length, 0);
});

test('App Review fallback: production refuses a sandbox purchase, the sandbox credits it once', async () => {
  const { sandbox, production } = deployments();
  // the App Store build starts on production (receipt "receipt"), signs in
  const pa = await user(production, 'T:_reviewer', 'Review Otter');
  const token = (await wallet(production, pa)).app_account_token;
  // App Review's purchase is a verified Apple *Sandbox* transaction bound to that token
  const tx = storeTx(production, { environment: 'Sandbox', appAccountToken: token });
  const refused = await deliver(production, pa, tx);
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, 'sandbox_purchase');
  assert.equal(refused.body.apple_environment, 'Sandbox');
  // the game signs out of production, signs in to the sandbox deployment
  // with the same Game Center player and re-delivers the unfinished transaction
  const sa = await user(sandbox, 'T:_reviewer', 'Review Otter');
  assert.equal((await wallet(sandbox, sa)).app_account_token, token, 'the same token: the account binding holds');
  const ok = await deliver(sandbox, sa, tx);
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.deepEqual(ok.body.delivered, { coins: 1500 });
  // StoreKit replays it (finish raced a relaunch): still once
  const replay = await deliver(sandbox, sa, tx);
  assert.equal(replay.body.replay, true);
  assert.equal((await wallet(sandbox, sa)).balance, 1500);
  assert.equal((await ledgerRows(sandbox)).filter((l) => l.source === 'apple').length, 1);
  // production never recorded or credited it, and refuses it again the same way
  assert.equal((await deliver(production, pa, tx)).body.error, 'sandbox_purchase');
  assert.equal((await wallet(production, pa)).balance, 0);
  assert.equal((await appleRows(production)).length, 0);
  // account binding stays strict on the sandbox: another player can't take it
  const sb = await user(sandbox, 'T:_other', 'Other Otter');
  const tx2 = storeTx(sandbox, { environment: 'Sandbox', appAccountToken: token });
  assert.equal((await deliver(sandbox, sb, tx2)).body.error, 'account_mismatch');
  assert.equal((await wallet(sandbox, sb)).balance, 0);
});

test('forged, Xcode-signed and wrong-app transactions mint nothing on either deployment', async () => {
  const { sandbox, production } = deployments();
  for (const d of [sandbox, production]) {
    const u = await user(d, 'T:_ann', 'Ann Otter');
    const token = (await wallet(d, u)).app_account_token;
    const envs = ['Sandbox', 'Production'];
    for (const environment of envs) {
      const base = { appAccountToken: token, environment };
      // a chain under another (self-made, or Xcode's local StoreKit) root
      for (const name of ['evil', 'xcode-local']) {
        const r = await deliver(d, u, storeTx(d, base), appleChain(name));
        assert.equal(r.body.error, 'bad_transaction', `${name} chain on ${d.env.ENVIRONMENT}`);
        assert.equal(r.body.reason, 'root');
      }
      // the right chain but another app: wrong_app before any routing reply
      assert.equal((await deliver(d, u, storeTx(d, { ...base, bundleId: 'com.other.app' }))).body.error, 'wrong_app');
      // a tampered payload
      const [h, , s] = appleJws(storeTx(d, base)).split('.');
      const forged = Buffer.from(JSON.stringify(storeTx(d, { ...base, productId: 'com.idlery.ultimatetrifecta.coins.7500' }))).toString('base64url');
      const fr = await call(d, 'POST', '/v1/wallet/apple', { jws: `${h}.${forged}.${s}` }, u.token);
      assert.equal(fr.body.reason, 'signature');
    }
    // Xcode's environment, even under a trusted chain, reaches no ledger
    assert.equal((await deliver(d, u, storeTx(d, { appAccountToken: token, environment: 'Xcode' }))).body.error, 'wrong_environment');
    // an unsigned client "success"
    const bare = await call(d, 'POST', '/v1/wallet/apple', { jws: 'test.' + Buffer.from(JSON.stringify(storeTx(d))).toString('base64') }, u.token);
    assert.equal(bare.body.error, 'bad_transaction');
    const w = await wallet(d, u);
    assert.equal(w.balance, 0);
    assert.equal(w.entitlements.length, 0);
    assert.equal((await appleRows(d)).length, 0, `nothing recorded on ${d.env.ENVIRONMENT}`);
  }
});

test('a sandbox session cannot spend, claim or deliver on production', async () => {
  const { sandbox, production } = deployments();
  const sa = await user(sandbox, 'T:_ann', 'Ann Otter');
  const pa = await user(production, 'T:_ann', 'Ann Otter');
  // sandbox value: Coins, a Coin item, Premium and Season XP
  const g = await call(sandbox, 'POST', `/v1/admin/wallets/${sa.profile.profile_id}/adjust`, { amount: 3000, note: 'test', idempotency_key: 'sandbox-grant-1' }, undefined, ADMIN);
  assert.equal(g.status, 200);
  assert.equal((await call(sandbox, 'POST', '/v1/wallet/spend', { item_id: 'season:s1:premium', price: 1500, idempotency_key: 'premium-sb-1' }, sa.token)).status, 200);
  assert.equal((await call(sandbox, 'POST', '/v1/wallet/spend', { item_id: 'outfit:robe', price: 300, idempotency_key: 'robe-sb-1' }, sa.token)).status, 200);
  // the sandbox session token is bound to its environment: production refuses it
  for (const [m, path, body] of [['GET', '/v1/wallet'], ['POST', '/v1/wallet/spend', { item_id: 'outfit:duck', price: 450, idempotency_key: 'duck-x-1' }],
    ['POST', '/v1/season/s1/claim', { claims: [{ tier: 1, track: 'free' }] }], ['POST', '/v1/wallet/apple', { jws: appleJws(storeTx(production, { environment: 'Production' })) }]]) {
    const r = await call(production, m, path, body, sa.token);
    assert.equal(r.status, 401, `${m} ${path} with a sandbox session`);
  }
  // and the production wallet of the same player has none of the sandbox value
  const wp = await wallet(production, pa);
  assert.equal(wp.balance, 0);
  assert.equal(wp.entitlements.length, 0);
  assert.equal(wp.season.s1.premium, false);
  // the admin grant was a sandbox-database row only
  assert.equal((await ledgerRows(production)).length, 0);
});

test('TestFlight to App Store: no sandbox balance, item or beta import reaches production', async () => {
  const { sandbox, production } = deployments();
  const sa = await user(sandbox, 'T:_tester', 'Test Otter');
  const tok = (await wallet(sandbox, sa)).app_account_token;
  // TestFlight: sandbox purchases, a beta import and a Coin item
  await deliver(sandbox, sa, storeTx(sandbox, { appAccountToken: tok }));
  await deliver(sandbox, sa, storeTx(sandbox, { productId: SKIN, type: 'Non-Consumable', appAccountToken: tok }));
  const legacy = { coins: 2000, items: ['hat:crown'], online_rounds: 100, practice_rounds: 0 };
  const li = await call(sandbox, 'POST', '/v1/wallet/legacy-import', legacy, sa.token);
  assert.equal(li.status, 200);
  assert.ok(li.body.imported_coins > 0, 'the beta balance goes to the sandbox economy');
  const ws = await wallet(sandbox, sa);
  assert.ok(ws.balance >= 1500);
  // the same player installs the App Store build: production starts empty
  const pa = await user(production, 'T:_tester', 'Test Otter');
  const wp = await wallet(production, pa);
  assert.equal(wp.balance, 0);
  assert.equal(wp.entitlements.length, 0);
  // the same device's beta balance is not imported into production
  const pli = await call(production, 'POST', '/v1/wallet/legacy-import', legacy, pa.token);
  assert.equal(pli.status, 409);
  assert.equal(pli.body.error, 'legacy_not_available');
  // the sandbox skin's transaction can't be restored into production either
  const restore = await deliver(production, pa, storeTx(production, { productId: SKIN, type: 'Non-Consumable', appAccountToken: tok }));
  assert.equal(restore.body.error, 'sandbox_purchase');
  const after = await wallet(production, pa);
  assert.equal(after.balance, 0);
  assert.equal(after.entitlements.length, 0);
  assert.equal((await ledgerRows(production)).length, 0);
});

test('notifications: each deployment applies only its own environment', async () => {
  const { sandbox, production } = deployments();
  const sa = await user(sandbox, 'T:_ann', 'Ann Otter');
  const pa = await user(production, 'T:_ann', 'Ann Otter');
  const tok = (await wallet(sandbox, sa)).app_account_token;
  const stx = storeTx(sandbox, { appAccountToken: tok });
  const ptx = storeTx(production, { environment: 'Production', appAccountToken: tok });
  await deliver(sandbox, sa, stx);
  await deliver(production, pa, ptx);
  let n = 0;
  const note = (envName, tx) => ({ notificationType: 'REFUND', notificationUUID: `0f0e0d0c-1111-2222-3333-${String(++n).padStart(12, '0')}`, signedDate: sandbox.clock.t,
    data: { bundleId: 'com.idlery.ultimatetrifecta', environment: envName, signedTransactionInfo: appleJws({ ...tx, revocationDate: sandbox.clock.t }) } });
  const post = (d, body) => call(d, 'POST', '/v1/appstore/notifications', { signedPayload: appleJws(body) });
  // the production notification sent to the sandbox URL (and vice versa): refused
  assert.equal((await post(sandbox, note('Production', ptx))).body.error, 'wrong_environment');
  assert.equal((await post(production, note('Sandbox', stx))).body.error, 'wrong_environment');
  // an envelope that claims its own environment around the other's transaction: refused
  assert.equal((await post(production, note('Production', stx))).body.error, 'wrong_environment');
  assert.equal((await wallet(sandbox, sa)).balance, 1500, 'nothing revoked by a refused notification');
  assert.equal((await wallet(production, pa)).balance, 1500);
  // the right URL: applied once, on that deployment only
  assert.equal((await post(production, note('Production', ptx))).status, 200);
  assert.equal((await wallet(production, pa)).balance, 0);
  assert.equal((await wallet(sandbox, sa)).balance, 1500);
  // a forged notification
  assert.equal((await call(sandbox, 'POST', '/v1/appstore/notifications', { signedPayload: appleJws(note('Sandbox', stx), appleChain('evil')) })).body.error, 'bad_transaction');
});

test('restore after profile deletion works for a token-bound skin (same player)', async () => {
  const { sandbox } = deployments();
  const a = await user(sandbox, 'T:_ann', 'Ann Otter');
  const tok = (await wallet(sandbox, a)).app_account_token;
  const sk = storeTx(sandbox, { productId: SKIN, type: 'Non-Consumable', appAccountToken: tok });
  assert.equal((await deliver(sandbox, a, sk)).status, 200);
  sandbox.clock.t += 1000;
  const again = await user(sandbox, 'T:_ann', null);
  assert.equal((await call(sandbox, 'DELETE', '/v1/me', { confirm: 'DELETE' }, again.token)).status, 200);
  const back = await user(sandbox, 'T:_ann', 'Ann Again');
  const r = await deliver(sandbox, back, sk);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.restored, true);
  assert.ok(r.body.wallet.entitlements.some((e) => e.item === 'outfit:moonlight_runner' && !e.revoked));
  // another Game Center player on the same Apple Account can't take it
  const other = await user(sandbox, 'T:_ben', 'Ben Otter');
  assert.equal((await deliver(sandbox, other, sk)).body.error, 'account_mismatch');
});
