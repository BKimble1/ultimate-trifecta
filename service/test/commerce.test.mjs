import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { generateKeyPairSync } from 'node:crypto';
import { makeEnv, call, user, ADMIN, appleChain, appleJws, trustTestRoot, storeTx } from './helpers.mjs';
import * as E from '../src/economy.js';
import { render } from '../tools/sync_catalogue.mjs';
import { verifyAppleJws, APPLE_ROOT_G3_SHA256 } from '../src/appstore.js';

const PACK = 'com.idlery.ultimatetrifecta.coins.1500';
const SKIN = 'com.idlery.ultimatetrifecta.skin.moonlight_runner';

async function wallet(ctx, u) {
  const r = await call(ctx, 'GET', '/v1/wallet', undefined, u.token);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.wallet;
}

async function grant(ctx, u, amount, key = 'g' + Math.random().toString(36).slice(2, 10)) {
  const r = await call(ctx, 'POST', `/v1/admin/wallets/${u.profile.profile_id}/adjust`, { amount, note: 'test grant', idempotency_key: key }, undefined, ADMIN);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.wallet;
}

async function deliver(ctx, u, tx, chain) {
  return call(ctx, 'POST', '/v1/wallet/apple', { jws: appleJws(tx, chain), transaction_id: tx.transactionId }, u.token);
}

function setup(over = {}) {
  const ctx = makeEnv(over);
  trustTestRoot(ctx);
  return ctx;
}

test('the service copy of the catalogue is current; economy matches the game', () => {
  assert.equal(readFileSync(new URL('../src/catalogue_data.js', import.meta.url), 'utf8'), render(), 'run node tools/sync_catalogue.mjs');
  // the same canonical row as Economy.row_canonical (game/tests/test_catalogue.gd)
  const row = { role: 0, stamps: 2, finished: false, first_home: false, unique_captures: 0, coins_picked: 1, present: true, away_s: 3.4 };
  assert.equal(E.rowCanonical('M-1', 2, 200, row), 'v1|M-1|2|0|2|0|0|0|1|1|3|200');
  const sql = readFileSync(new URL('../migrations/0002_commerce.sql', import.meta.url), 'utf8');
  assert.ok(sql.includes(`CHECK (rounds <= ${E.ECONOMY.eligibility.daily_round_cap})`), 'daily cap in the schema = economy daily_round_cap');
  assert.equal(E.price('season:s1:premium'), 1500);
  assert.equal(E.legacyImportAmount(99999, 10, 0), 750);
  assert.ok(E.maxRoundCoins() <= 40);
});

test('JWS: only an Apple-shaped chain under a trusted root verifies', async () => {
  const ctx = setup();
  const tx = storeTx(ctx);
  const ok = await verifyAppleJws(appleJws(tx), ctx.env, ctx.clock.t);
  assert.equal(ok.transactionId, tx.transactionId);
  // without the test root, only Apple Root CA - G3 (pinned) is trusted
  await assert.rejects(verifyAppleJws(appleJws(tx), { BUNDLE_ID: 'x' }, ctx.clock.t), (e) => e.code === 'bad_transaction' && e.extra.reason === 'root');
  assert.equal(APPLE_ROOT_G3_SHA256.length, 64);
  // another self-made root is refused
  const evil = appleChain('evil');
  await assert.rejects(verifyAppleJws(appleJws(tx, evil), ctx.env, ctx.clock.t), (e) => e.extra.reason === 'root');
  // the marker OIDs are required
  const nomark = appleChain('nomark', { leafMarker: false });
  trustTestRoot(ctx, nomark);
  await assert.rejects(verifyAppleJws(appleJws(tx, nomark), ctx.env, ctx.clock.t), (e) => e.extra.reason === 'marker');
  trustTestRoot(ctx);
  // tampering with the payload breaks the signature
  const [h, , s] = appleJws(tx).split('.');
  const forged = Buffer.from(JSON.stringify({ ...tx, productId: 'com.idlery.ultimatetrifecta.coins.3500' })).toString('base64url');
  await assert.rejects(verifyAppleJws(`${h}.${forged}.${s}`, ctx.env, ctx.clock.t), (e) => e.extra.reason === 'signature');
  await assert.rejects(verifyAppleJws('not.a.jws', ctx.env, ctx.clock.t), (e) => e.code === 'bad_transaction');
  // signed in the future
  await assert.rejects(verifyAppleJws(appleJws({ ...tx, signedDate: ctx.clock.t + 3600e3 }), ctx.env, ctx.clock.t), (e) => e.extra.reason === 'date');
});

test('Coin pack: verified, delivered exactly once, bound to the account', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const b = await user(ctx, 'T:_ben', 'Ben Otter');
  const wa = await wallet(ctx, a);
  assert.match(wa.app_account_token, /^[0-9a-f-]{36}$/);
  const tx = storeTx(ctx, { appAccountToken: wa.app_account_token.toUpperCase() });
  const r1 = await deliver(ctx, a, tx);
  assert.equal(r1.status, 200, JSON.stringify(r1.body));
  assert.deepEqual(r1.body.delivered, { coins: 1500 });
  assert.equal(r1.body.wallet.balance, 1500);
  // StoreKit hands it over again (unfinished / duplicate callback): no second credit
  const r2 = await deliver(ctx, a, tx);
  assert.equal(r2.body.replay, true);
  assert.equal(r2.body.wallet.balance, 1500);
  // the same transaction presented by another account
  const r3 = await deliver(ctx, b, tx);
  assert.equal(r3.status, 409);
  assert.equal(r3.body.error, 'account_mismatch');
  // a purchase made for A's token presented by B
  const tx2 = storeTx(ctx, { appAccountToken: wa.app_account_token });
  assert.equal((await deliver(ctx, b, tx2)).body.error, 'account_mismatch');
  assert.equal((await wallet(ctx, b)).balance, 0);
  // concurrent duplicates of a new transaction
  const tx3 = storeTx(ctx, { appAccountToken: wa.app_account_token });
  const both = await Promise.all([deliver(ctx, a, tx3), deliver(ctx, a, tx3)]);
  assert.ok(both.every((x) => x.status === 200));
  assert.equal((await wallet(ctx, a)).balance, 3000, 'two racing callbacks, one credit');
  const ledger = await call(ctx, 'GET', `/v1/admin/wallets/${a.profile.profile_id}`, undefined, undefined, ADMIN);
  assert.equal(ledger.body.ledger.filter((l) => l.source === 'apple').length, 2, 'one ledger row per transaction');
});

test('App Store checks: bundle, environment, product, type', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  assert.equal((await deliver(ctx, a, storeTx(ctx, { bundleId: 'com.other.app' }))).body.error, 'wrong_app');
  assert.equal((await deliver(ctx, a, storeTx(ctx, { environment: 'Production' }))).body.error, 'wrong_environment', 'a production purchase never reaches the sandbox ledger');
  assert.equal((await deliver(ctx, a, storeTx(ctx, { environment: 'Xcode' }))).body.error, 'wrong_environment', 'local Xcode StoreKit testing never reaches a ledger');
  assert.equal((await deliver(ctx, a, storeTx(ctx, { productId: 'com.idlery.ultimatetrifecta.coins.999999' }))).body.error, 'unknown_product');
  assert.equal((await deliver(ctx, a, storeTx(ctx, { type: 'Non-Consumable' }))).body.extra?.reason ?? (await deliver(ctx, a, storeTx(ctx, { type: 'Non-Consumable' }))).body.reason, 'type');
  // an unsigned client "success" is worthless
  const bare = await call(ctx, 'POST', '/v1/wallet/apple', { jws: 'test.' + Buffer.from(JSON.stringify(storeTx(ctx))).toString('base64'), transaction_id: '1' }, a.token);
  assert.equal(bare.body.error, 'bad_transaction');
  assert.equal((await wallet(ctx, a)).balance, 0);
});

test('production deployment: production purchases only, separate ledger', async () => {
  const ctx = setup({ ENVIRONMENT: 'production', APPLE_ENVIRONMENT: 'Production' });
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  assert.equal((await deliver(ctx, a, storeTx(ctx))).body.error, 'wrong_environment', 'a sandbox (TestFlight) credit never becomes production Coins');
  const r = await deliver(ctx, a, storeTx(ctx, { environment: 'Production' }));
  assert.equal(r.body.wallet.balance, 1500);
  assert.equal(r.body.wallet.environment, 'production');
});

test('direct skin: delivered, restored after deletion, one profile at a time, refund revokes only it', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const b = await user(ctx, 'T:_ben', 'Ben Otter');
  const sk = storeTx(ctx, { productId: SKIN, type: 'Non-Consumable' });
  const r = await deliver(ctx, a, sk);
  assert.deepEqual(r.body.delivered, { item: 'outfit:moonlight_runner' });
  assert.ok(r.body.wallet.entitlements.some((e) => e.item === 'outfit:moonlight_runner' && e.source === 'apple'));
  assert.equal((await deliver(ctx, b, sk)).body.error, 'owned_by_other_profile');
  // A buys a Coin item too, then Apple refunds the skin
  await grant(ctx, a, 300);
  const sp = await call(ctx, 'POST', '/v1/wallet/spend', { item_id: 'outfit:robe', price: 300, idempotency_key: 'robe-0001' }, a.token);
  assert.equal(sp.status, 200);
  const refund = await deliver(ctx, a, { ...sk, revocationDate: ctx.clock.t });
  assert.equal(refund.body.revoked, true);
  const w = refund.body.wallet;
  assert.ok(w.entitlements.find((e) => e.item === 'outfit:moonlight_runner').revoked, 'refunded skin revoked');
  assert.ok(!w.entitlements.find((e) => e.item === 'outfit:robe').revoked, 'unrelated Coin item kept');
  // a second skin purchase, then the owner deletes the profile: the skin
  // follows the Apple Account to a new profile (restore)
  const sk2 = storeTx(ctx, { productId: 'com.idlery.ultimatetrifecta.skin.starry_sleeper', type: 'Non-Consumable' });
  await deliver(ctx, b, sk2);
  ctx.clock.t += 1000;
  const fresh = await user(ctx, 'T:_ben', null);
  const del = await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token);
  assert.equal(del.status, 200, JSON.stringify(del.body));
  const c = await user(ctx, 'T:_cat', 'Cat Otter');
  const rr = await deliver(ctx, c, sk2);
  assert.equal(rr.status, 200);
  assert.ok(rr.body.wallet.entitlements.some((e) => e.item === 'outfit:starry_sleeper'), 'restored to the new profile');
});

test('refunded Coin pack: Coins taken back, debt when spent, paid from later grants', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const tx = storeTx(ctx);
  await deliver(ctx, a, tx);
  const sp = await call(ctx, 'POST', '/v1/wallet/spend', { item_id: 'outfit:lantern_scout', price: 1200, idempotency_key: 'lantern-01' }, a.token);
  assert.equal(sp.body.wallet.balance, 300);
  const r = await deliver(ctx, a, { ...tx, revocationDate: ctx.clock.t });
  assert.equal(r.body.wallet.balance, 0);
  assert.equal(r.body.wallet.debt, 1200, 'the spent part is recorded as debt');
  assert.ok(!r.body.wallet.entitlements.find((e) => e.item === 'outfit:lantern_scout').revoked, 'items bought with it are not erased');
  const g = await grant(ctx, a, 1500);
  assert.equal(g.balance, 300, 'later grants pay the debt first');
  assert.equal(g.debt, 0);
  // the refund again: nothing more
  const again = await deliver(ctx, a, { ...tx, revocationDate: ctx.clock.t });
  assert.equal(again.body.wallet.balance, 300);
});

test('App Store Server Notifications: REFUND revokes once', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const tx = storeTx(ctx);
  await deliver(ctx, a, tx);
  const note = { notificationType: 'REFUND', notificationUUID: '0f0e0d0c-1111-2222-3333-444455556666', signedDate: ctx.clock.t,
    data: { bundleId: 'com.idlery.ultimatetrifecta', environment: 'Sandbox', signedTransactionInfo: appleJws({ ...tx, revocationDate: ctx.clock.t }) } };
  const r = await call(ctx, 'POST', '/v1/appstore/notifications', { signedPayload: appleJws(note) });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal((await wallet(ctx, a)).balance, 0);
  const again = await call(ctx, 'POST', '/v1/appstore/notifications', { signedPayload: appleJws(note) });
  assert.equal(again.body.replay, true);
  const forged = await call(ctx, 'POST', '/v1/appstore/notifications', { signedPayload: appleJws(note, appleChain('evil')) });
  assert.equal(forged.body.error, 'bad_transaction');
});

test('App Store Server API (when configured) is asked for the transaction', async () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const seen = [];
  let apiTx = null;
  const base = makeEnv().env.__fetch;
  const ctx = setup({
    ASC_IAP_KEY_ID: 'KEY123', ASC_IAP_ISSUER_ID: 'issuer', ASC_IAP_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    __fetch: async (url, init) => {
      if (!String(url).includes('storekit')) return base(url, init);
      seen.push([url, init && init.headers && init.headers.authorization ? 'auth' : '']);
      if (!apiTx) return new Response('{}', { status: 404 });
      return new Response(JSON.stringify({ signedTransactionInfo: appleJws(apiTx) }), { status: 200 });
    },
  });
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const tx = storeTx(ctx);
  const r = await deliver(ctx, a, tx);
  assert.equal(r.body.error, 'bad_transaction', 'Apple has no such transaction: refused');
  assert.ok(seen[0][0].startsWith('https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/'), 'sandbox host for the sandbox deployment');
  assert.equal(seen[0][1], 'auth');
  apiTx = tx;
  assert.equal((await deliver(ctx, a, tx)).body.wallet.balance, 1500);
});

test('spend: atomic debit + grant, never negative, never twice', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 1000);
  const body = (id, key, price) => ({ item_id: id, price: price ?? E.price(id), idempotency_key: key });
  assert.equal((await call(ctx, 'POST', '/v1/wallet/spend', body('outfit:robe', 'k-robe-1', 1), a.token)).body.error, 'price_changed');
  assert.equal((await call(ctx, 'POST', '/v1/wallet/spend', body('outfit:after_hours_hoodie', 'k-hoodie-1', 0), a.token)).body.error, 'not_for_sale', 'season rewards are never sold');
  const ok = await call(ctx, 'POST', '/v1/wallet/spend', body('outfit:robe', 'k-robe-1'), a.token);
  assert.equal(ok.body.wallet.balance, 700);
  const rev = ok.body.wallet.revision;
  const replay = await call(ctx, 'POST', '/v1/wallet/spend', body('outfit:robe', 'k-robe-1'), a.token);
  assert.equal(replay.body.replay, true, 'same key: the first result, no second debit');
  assert.equal(replay.body.wallet.revision, rev);
  assert.equal((await call(ctx, 'POST', '/v1/wallet/spend', body('outfit:robe', 'k-robe-2'), a.token)).body.error, 'already_owned');
  // racing purchases of the same item with different keys: charged once
  const race = await Promise.all([call(ctx, 'POST', '/v1/wallet/spend', body('outfit:frog', 'k-frog-1'), a.token),
    call(ctx, 'POST', '/v1/wallet/spend', body('outfit:frog', 'k-frog-2'), a.token)]);
  assert.equal(race.filter((r) => r.status === 200).length, 1);
  assert.equal((await wallet(ctx, a)).balance, 200);
  // racing purchases that together overdraw: one fails, balance never negative
  await grant(ctx, a, 500);
  const race2 = await Promise.all([call(ctx, 'POST', '/v1/wallet/spend', body('outfit:duck', 'k-duck-1'), a.token),
    call(ctx, 'POST', '/v1/wallet/spend', body('outfit:varsity_sprinter', 'k-vars-1'), a.token)]);
  assert.equal(race2.filter((r) => r.status === 200).length, 1);
  assert.ok(race2.some((r) => r.body.error === 'insufficient_funds'));
  const w = await wallet(ctx, a);
  assert.ok(w.balance >= 0);
  assert.equal(w.balance, 700 - (race2[0].status === 200 ? 450 : 600));
});

test('legacy import: bounded, once per account and per Game Center player', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const imp = (u, o = {}) => call(ctx, 'POST', '/v1/wallet/legacy-import', { coins: 99999, items: ['hat:crown', 'outfit:lantern_scout', 'outfit:after_hours_hoodie'],
    online_rounds: 10, practice_rounds: 0, ...o }, u.token);
  const r = await imp(a);
  assert.equal(r.body.imported_coins, 750, 'bounded by what 10 rounds could earn');
  assert.deepEqual(r.body.imported_items, ['hat:crown'], 'only pre-V6 Coin items (never Shop skins or Season rewards)');
  assert.ok(r.body.wallet.entitlements.some((e) => e.item === 'hat:crown' && e.source === 'legacy_beta'));
  const again = await imp(a);
  assert.equal(again.body.already_imported, true);
  assert.equal(again.body.wallet.balance, 750);
  // delete the profile and come back with the same Game Center player: no second import
  ctx.clock.t += 1000;
  const fresh = await user(ctx, 'T:_ann', null);
  await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token);
  const back = await user(ctx, 'T:_ann', 'Ann Again');
  assert.equal((await imp(back)).body.already_imported, true);
  assert.equal((await wallet(ctx, back)).balance, 0, 'deletion forfeited the Coins; nothing re-imported');
});

test('Season: free claims, Premium for Coins, late unlock, repeated Claim all, duplicates', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const pid = a.profile.profile_id;
  await ctx.env.DB.prepare("INSERT INTO season_progress (profile_id, environment, season, xp, premium, updated_at) VALUES (?, 'sandbox', 's1', 400, 0, 0)").bind(pid).run();
  const claimAll = (claims) => call(ctx, 'POST', '/v1/season/s1/claim', { claims }, a.token);
  const every = [];
  for (let tier = 1; tier <= 30; tier++) for (const track of ['free', 'premium']) every.push({ tier, track });
  const r = await claimAll(every);
  assert.deepEqual(r.body.claimed.map((c) => `${c.tier}:${c.track}`), ['1:free', '3:free'], 'free track without buying; Premium locked; tier 4+ locked');
  assert.equal((await claimAll(every)).body.claimed.length, 0, 'repeated Claim all: nothing');
  // Premium for Coins (not Apple, not a subscription), then the late unlock
  await grant(ctx, a, 1500);
  const buy = await call(ctx, 'POST', '/v1/wallet/spend', { item_id: 'season:s1:premium', price: 1500, idempotency_key: 'premium-1' }, a.token);
  assert.equal(buy.status, 200);
  assert.equal(buy.body.wallet.season.s1.premium, true);
  assert.equal(buy.body.wallet.season.s1.xp, 400, 'buying adds no XP (no tier skips)');
  // a duplicate: tier 3 Premium badge already owned
  await ctx.env.DB.prepare("INSERT INTO entitlements (profile_id, environment, item_id, source, granted_at) VALUES (?, 'sandbox', 'badge:lantern', 'admin', 0)").bind(pid).run();
  const late = await claimAll(every);
  assert.deepEqual(late.body.claimed.map((c) => `${c.tier}:${c.track}:${c.result}`), ['1:premium:granted', '2:premium:granted', '3:premium:already_owned']);
  assert.equal(late.body.wallet.balance, 50, 'tier 2 Premium Coins once');
  assert.equal((await claimAll(every)).body.wallet.balance, 50);
  // tier boundaries
  assert.equal(E.tierForXp('s1', 199), 1);
  assert.equal(E.tierForXp('s1', 200), 2);
  assert.equal(E.tierForXp('s1', 8300), 30);
});

async function party(ctx) {
  const host = await user(ctx, 'T:_host', 'Host Otter');
  const guest = await user(ctx, 'T:_guest', 'Guest Otter');
  const room = await call(ctx, 'POST', '/v1/rooms', { build: 105, protocol: 5, capacity: 8 }, host.token);
  const code = room.body.room.code;
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  const j = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: 105, protocol: 5 }, guest.token);
  assert.equal(j.status, 200, JSON.stringify(j.body));
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { connected: [guest.profile.profile_id] }, host.token);
  return { host, guest, code, beat: () => call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { connected: [guest.profile.profile_id] }, host.token) };
}

const hostRow = (pid, o = {}) => ({ profile_id: pid, slot: 0, role: 0, stamps: 3, finished: true, first_home: true, unique_captures: 0, coins_picked: 2, present: true, away_s: 0, ...o });
const guestRow = (pid, o = {}) => ({ profile_id: pid, slot: 1, role: 1, stamps: 0, finished: false, first_home: false, unique_captures: 1, coins_picked: 1, present: true, away_s: 0, ...o });

test('round settlement: registered, reported, confirmed, paid once', async () => {
  const ctx = setup();
  const { host, guest, code, beat } = await party(ctx);
  const hp = host.profile.profile_id;
  const gp = guest.profile.profile_id;
  const mid = `${code}-1-0000beef`;
  const stranger = await user(ctx, 'T:_x', 'Xavier Otter');
  assert.equal((await call(ctx, 'POST', '/v1/rounds', { code, match_id: mid, participants: [{ profile_id: hp, slot: 0 }, { profile_id: stranger.profile.profile_id, slot: 1 }] }, host.token)).body.error, 'not_member', 'only admitted players');
  assert.equal((await call(ctx, 'POST', '/v1/rounds', { code, match_id: mid, participants: [{ profile_id: gp, slot: 1 }] }, guest.token)).body.error, 'not_host');
  assert.equal((await call(ctx, 'POST', '/v1/rounds', { code, match_id: 'ZZZZZZ-1-00', participants: [{ profile_id: hp, slot: 0 }] }, host.token)).body.error, 'bad_round', 'the round id is bound to the party');
  const reg = await call(ctx, 'POST', '/v1/rounds', { code, match_id: mid, participants: [{ profile_id: hp, slot: 0 }, { profile_id: gp, slot: 1 }] }, host.token);
  assert.equal(reg.status, 200, JSON.stringify(reg.body));
  const report = { outcome: 1, round_time_s: 180, coin_spawns: 8, players: [hostRow(hp), guestRow(gp)] };
  assert.equal((await call(ctx, 'POST', `/v1/rounds/${mid}/report`, report, host.token)).body.reason, 'too_short', 'a result seconds after the start is refused');
  // (that rejection ended this round; register the next one)
  ctx.clock.t += 30 * 1000;
  await beat();
  ctx.clock.t += 31 * 1000;
  await beat();
  const mid2 = `${code}-2-0000beef`;
  await call(ctx, 'POST', '/v1/rounds', { code, match_id: mid2, participants: [{ profile_id: hp, slot: 0 }, { profile_id: gp, slot: 1 }] }, host.token);
  // the guest confirms first (digest of the row its game received)
  const gd = await E.rowDigest(mid2, 1, 180, guestRow(gp));
  const a1 = await call(ctx, 'POST', `/v1/rounds/${mid2}/ack`, { digest: gd }, guest.token);
  assert.equal(a1.body.settlement.state, 'pending', 'waiting for the host report');
  ctx.clock.t += 120 * 1000;
  assert.equal((await call(ctx, 'POST', `/v1/rounds/${mid2}/report`, report, guest.token)).body.error, 'not_host');
  const rep = await call(ctx, 'POST', `/v1/rounds/${mid2}/report`, report, host.token);
  assert.equal(rep.status, 200, JSON.stringify(rep.body));
  assert.equal(rep.body.settled, 1, 'the guest (already confirmed) is paid at once');
  const gw = await wallet(ctx, guest);
  assert.equal(gw.balance, E.roundCoins(guestRow(gp), 1, 8));
  assert.equal(gw.season.s1.xp, E.roundSeasonXp(guestRow(gp), 1));
  // the host confirms; then everything replays harmlessly
  const hd = await E.rowDigest(mid2, 1, 180, hostRow(hp));
  const a2 = await call(ctx, 'POST', `/v1/rounds/${mid2}/ack`, { digest: hd }, host.token);
  assert.equal(a2.body.settlement.state, 'settled');
  assert.equal(a2.body.wallet.balance, E.roundCoins(hostRow(hp), 1, 8));
  await call(ctx, 'POST', `/v1/rounds/${mid2}/ack`, { digest: hd }, host.token);
  await call(ctx, 'POST', `/v1/rounds/${mid2}/report`, report, host.token);
  assert.equal((await wallet(ctx, host)).balance, E.roundCoins(hostRow(hp), 1, 8), 'reopened results / duplicated packets never pay twice');
  assert.equal((await call(ctx, 'GET', `/v1/rounds/${mid2}/me`, undefined, guest.token)).body.settlement.state, 'settled');
});

test('round settlement: implausible, mismatched, cancelled, away, few humans, daily cap', async () => {
  const ctx = setup();
  const { host, guest, code, beat } = await party(ctx);
  const hp = host.profile.profile_id;
  const gp = guest.profile.profile_id;
  let n = 0;
  const round = async () => {
    n += 1;
    ctx.clock.t += 31 * 1000;
    await beat();
    ctx.clock.t += 30 * 1000;
    await beat();
    const mid = `${code}-${n}-0000aaaa`;
    const r = await call(ctx, 'POST', '/v1/rounds', { code, match_id: mid, participants: [{ profile_id: hp, slot: 0 }, { profile_id: gp, slot: 1 }] }, host.token);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    for (let i = 0; i < 5; i++) {
      ctx.clock.t += 30 * 1000;
      await beat();
    }
    return mid;
  };
  // implausible numbers are refused and audited
  for (const [bad, why] of [[{ coins_picked: 9 }, 'coins_picked'], [{ stamps: 4 }, 'stamps'], [{ finished: true, stamps: 2 }, 'finished']]) {
    const mid = await round();
    const r = await call(ctx, 'POST', `/v1/rounds/${mid}/report`, { outcome: 1, round_time_s: 180, coin_spawns: 8, players: [hostRow(hp, bad), guestRow(gp)] }, host.token);
    assert.equal(r.status, 422);
    assert.equal(r.body.reason, why);
  }
  const both = await round();
  const tooMany = await call(ctx, 'POST', `/v1/rounds/${both}/report`, { outcome: 1, round_time_s: 180, coin_spawns: 2, players: [hostRow(hp, { coins_picked: 2 }), guestRow(gp, { coins_picked: 1 })] }, host.token);
  assert.equal(tooMany.body.reason, 'coins_total', 'more coins collected than spawned');
  // the host reports different numbers from what the guest's game showed
  const mm = await round();
  await call(ctx, 'POST', `/v1/rounds/${mm}/report`, { outcome: 1, round_time_s: 180, coin_spawns: 8, players: [hostRow(hp), guestRow(gp, { unique_captures: 3 })] }, host.token);
  const ack = await call(ctx, 'POST', `/v1/rounds/${mm}/ack`, { digest: await E.rowDigest(mm, 1, 180, guestRow(gp)) }, guest.token);
  assert.equal(ack.body.settlement.state, 'mismatch');
  // cancelled: nothing
  const cx = await round();
  await call(ctx, 'POST', `/v1/rounds/${cx}/report`, { outcome: 3, round_time_s: 30, coin_spawns: 8, players: [hostRow(hp, { finished: false, first_home: false, stamps: 1 }), guestRow(gp)] }, host.token);
  assert.equal((await call(ctx, 'POST', `/v1/rounds/${cx}/ack`, { digest: '0'.repeat(64) }, guest.token)).body.settlement.state, 'cancelled');
  // away for most of the round
  const aw = await round();
  const awayRow = guestRow(gp, { away_s: 120 });
  await call(ctx, 'POST', `/v1/rounds/${aw}/report`, { outcome: 1, round_time_s: 180, coin_spawns: 8, players: [hostRow(hp), awayRow] }, host.token);
  const a2 = await call(ctx, 'POST', `/v1/rounds/${aw}/ack`, { digest: await E.rowDigest(aw, 1, 180, awayRow) }, guest.token);
  assert.equal(a2.body.settlement.state, 'ineligible');
  assert.equal(a2.body.settlement.reason, 'away');
  // a host alone with bots can't farm (one human)
  const solo = await round();
  await call(ctx, 'POST', `/v1/rounds/${solo}/report`, { outcome: 1, round_time_s: 180, coin_spawns: 8, players: [hostRow(hp)] }, host.token);
  const a3 = await call(ctx, 'POST', `/v1/rounds/${solo}/ack`, { digest: await E.rowDigest(solo, 1, 180, hostRow(hp)) }, host.token);
  assert.equal(a3.body.settlement.reason, 'few_humans');
  assert.equal((await wallet(ctx, guest)).balance, 0);
  // the daily cap
  await ctx.env.DB.prepare("INSERT INTO daily_rounds (profile_id, environment, day, rounds) VALUES (?, 'sandbox', ?, 40)")
    .bind(gp, new Date(ctx.clock.t + 211 * 1000).toISOString().slice(0, 10)).run();
  const cap = await round();
  await call(ctx, 'POST', `/v1/rounds/${cap}/report`, { outcome: 1, round_time_s: 180, coin_spawns: 8, players: [hostRow(hp), guestRow(gp)] }, host.token);
  const a4 = await call(ctx, 'POST', `/v1/rounds/${cap}/ack`, { digest: await E.rowDigest(cap, 1, 180, guestRow(gp)) }, guest.token);
  assert.equal(a4.body.settlement.state, 'capped');
  assert.equal(a4.body.wallet.balance, 0);
  // someone not in the round can't confirm it
  const x = await user(ctx, 'T:_x', 'Xavier Otter');
  assert.equal((await call(ctx, 'POST', `/v1/rounds/${cap}/ack`, { digest: '0'.repeat(64) }, x.token)).status, 404);
  const audit = await call(ctx, 'GET', '/v1/admin/audit?limit=50', undefined, undefined, ADMIN);
  assert.ok(audit.body.audit.some((a) => a.action === 'round_rejected'), 'rejections are in the audit log for review');
});

test('profile deletion removes the wallet and keeps an anonymous ledger', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 100);
  ctx.clock.t += 1000;
  const fresh = await user(ctx, 'T:_ann', null);
  const r = await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token);
  assert.equal(r.status, 200);
  const rows = await ctx.env.DB.prepare('SELECT profile_id FROM ledger').all();
  assert.ok(rows.results.length > 0 && rows.results.every((x) => x.profile_id === null), 'ledger kept without the profile link');
  const w = await ctx.env.DB.prepare('SELECT COUNT(*) AS n FROM wallets WHERE profile_id = ?').bind(a.profile.profile_id).first();
  assert.equal(w.n, 0);
});

test('request bounds and auth', async () => {
  const ctx = setup();
  assert.equal((await call(ctx, 'GET', '/v1/wallet')).status, 401);
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  assert.equal((await call(ctx, 'POST', '/v1/wallet/spend', { item_id: 'outfit:robe', price: 300, idempotency_key: 'x' }, a.token)).body.error, 'bad_request', 'idempotency key required');
  const huge = await call(ctx, 'POST', '/v1/wallet/apple', { jws: 'a'.repeat(20000) }, a.token);
  assert.equal(huge.status, 413);
  const cfg = await call(ctx, 'GET', '/v1/config');
  assert.equal(cfg.body.apple_environment, 'Sandbox');
  assert.equal(cfg.body.catalogue_version, E.catalogueVersion());
});
