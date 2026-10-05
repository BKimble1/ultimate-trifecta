// Pass 8: scheduled rotating Shop offers (src/offers.js + the spend path in
// src/commerce.js) and the six Coin packs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { makeEnv, call, user, ADMIN, appleJws, trustTestRoot, storeTx } from './helpers.mjs';
import * as E from '../src/economy.js';
import * as O from '../src/offers.js';

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const ROTATION = E.CATALOGUE.items.filter((it) => it.rotation === true).map((it) => it.id);

function setup() {
  const ctx = makeEnv();
  trustTestRoot(ctx);
  return ctx;
}

// A test schedule relative to the test clock (sessions last an hour, so the
// windows are minutes long).  env.__offerSchedule must be a function: a
// deployment's configuration can never replace the catalogue's schedule.
function useSchedule(ctx, offers, revision = 7) {
  const iso = (t) => new Date(t).toISOString();
  ctx.env.__offerSchedule = () => ({
    schedule_revision: revision, rule: { slots: 4 },
    schedule: offers.map((o) => ({ ...o, starts_at_utc: iso(o.starts), ends_at_utc: iso(o.ends), revision })),
  });
}

async function grant(ctx, u, amount) {
  const r = await call(ctx, 'POST', `/v1/admin/wallets/${u.profile.profile_id}/adjust`, { amount, note: 'test', idempotency_key: 'g' + Math.random().toString(36).slice(2, 10) }, undefined, ADMIN);
  assert.equal(r.status, 200, JSON.stringify(r.body));
}

async function wallet(ctx, u) {
  return (await call(ctx, 'GET', '/v1/wallet', undefined, u.token)).body.wallet;
}

function spend(ctx, u, item, offer, price, key) {
  const b = { item_id: item, price, idempotency_key: key };
  if (offer !== null) b.offer_id = offer;
  return call(ctx, 'POST', '/v1/wallet/spend', b, u.token);
}

async function spends(ctx, u) {
  const r = await call(ctx, 'GET', `/v1/admin/wallets/${u.profile.profile_id}`, undefined, undefined, ADMIN);
  return r.body.ledger.filter((l) => l.kind === 'spend');
}

// ---------------------------------------------------------------- schedule
test('the catalogue schedule follows its written rule', () => {
  const sec = E.CATALOGUE.offers;
  const rule = sec.rule;
  const sched = O.buildSchedule(sec);
  assert.ok(sched.offers.length >= 8 * 7 * 2, 'a bounded schedule of at least 8 weeks');
  assert.ok(sched.offers.length <= 12 * 7 * 2 + 4, 'and at most about 12 weeks');
  assert.equal(rule.slots, 4, 'four Featured slots');
  assert.deepEqual(ROTATION.slice().sort(), ['outfit:arcade_sprinter', 'outfit:bedtime_bandit', 'outfit:campus_courier', 'outfit:cloud_nine',
    'outfit:lantern_scout', 'outfit:midnight_mechanic', 'outfit:moonwalk_cadet', 'outfit:pumpkin_pajamas', 'outfit:raincoat_explorer',
    'outfit:varsity_sprinter'], 'the pool: six new outfits and the four V6 Coin outfits');
  const ids = new Set();
  for (const o of sched.offers) {
    assert.ok(!ids.has(o.offer_id), `unique offer id ${o.offer_id}`);
    ids.add(o.offer_id);
    const it = E.item(o.item_id);
    assert.ok(it && it.kind === 'coin_item' && it.rotation === true, `${o.offer_id} sells a rotating Coin item`);
    assert.equal(o.price, it.price, `${o.offer_id}: the catalogue price (no sale prices)`);
    assert.ok(o.ends_at - o.starts_at >= 48 * HOUR, `${o.offer_id} lasts at least 48 h`);
    assert.equal(o.starts_at % DAY, 0, `${o.offer_id} starts at 00:00 UTC`);
    assert.equal(o.ends_at % DAY, 0, `${o.offer_id} ends at 00:00 UTC`);
    assert.ok(o.slot >= 1 && o.slot <= 4);
    assert.equal(o.revision, sec.schedule_revision);
  }
  const start = Date.parse(rule.start_utc);
  const end = start + rule.days * DAY;
  for (let t = start; t < end; t += 6 * HOUR) {
    const on = O.activeAt(sched, t);
    assert.equal(on.length, 4, `four offers on sale at ${new Date(t).toISOString()}`);
    assert.equal(new Set(on.map((o) => o.item_id)).size, 4, 'never the same skin twice at once');
    assert.equal(new Set(on.map((o) => o.slot)).size, 4, 'one per slot');
  }
  for (let t = start; t < end; t += DAY) {
    assert.equal(sched.offers.filter((o) => o.starts_at === t).length, 2, `two offers change at ${new Date(t).toISOString()}`);
  }
  // no back-to-back repeats: a skin that leaves never starts again at once
  for (const o of sched.offers) {
    assert.ok(!sched.offers.some((x) => x.item_id === o.item_id && x.starts_at === o.ends_at), `${o.item_id} doesn't come straight back`);
  }
  // the pool is cycled evenly
  const per = {};
  for (const o of sched.offers) per[o.item_id] = (per[o.item_id] || 0) + 1;
  assert.equal(Object.keys(per).length, ROTATION.length, 'every pool skin is scheduled');
  assert.ok(Math.max(...Object.values(per)) - Math.min(...Object.values(per)) <= 1, `evenly: ${JSON.stringify(per)}`);
  // rotating skins are never always-available, Apple, legacy or a reward
  for (const id of ROTATION) assert.ok(!E.item(id).featured && !E.item(id).legacy, `${id} is only sold through offers`);
  for (const it of E.CATALOGUE.items) {
    if (it.kind !== 'coin_item') assert.ok(it.rotation !== true, `${it.id} (${it.kind}) never rotates`);
  }
});

test('the written schedule is what the tool generates from the rule', (t) => {
  const tool = fileURLToPath(new URL('../../tools/make_offer_schedule.py', import.meta.url));
  const r = spawnSync('python3', [tool, '--check'], { encoding: 'utf8' });
  if (r.error && r.error.code === 'ENOENT') {
    t.skip('python3 not installed');
    return;
  }
  assert.equal(r.status, 0, r.stdout + r.stderr);
});

test('GET /v1/shop/offers: the service clock, the current and the upcoming offers', async () => {
  const ctx = setup();
  ctx.clock.t = Date.parse('2026-10-06T21:45:51Z');
  const r = await call(ctx, 'GET', '/v1/shop/offers');
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const b = r.body;
  assert.equal(b.server_time, ctx.clock.t, "the service's own time (no sign-in needed)");
  assert.equal(b.slots, 4);
  assert.deepEqual(b.current.map((o) => [o.slot, o.item_id]), [[1, 'outfit:pumpkin_pajamas'], [2, 'outfit:arcade_sprinter'],
    [3, 'outfit:cloud_nine'], [4, 'outfit:bedtime_bandit']]);
  assert.equal(b.next_change_at, Date.parse('2026-10-07T00:00:00Z'), 'the next 00:00 UTC change');
  assert.equal(b.current[0].ends_at_utc, '2026-10-07T00:00:00.000Z');
  assert.ok(b.upcoming.length >= 4 && b.upcoming.every((o) => o.starts_at > b.server_time && o.starts_at <= b.known_until));
  assert.equal(b.known_until - b.server_time, O.LOOKAHEAD_MS);
  assert.equal(b.schedule_revision, E.CATALOGUE.offers.schedule_revision);
  // exactly at the boundary the leaving offers are gone
  ctx.clock.t = Date.parse('2026-10-07T00:00:00Z');
  const at = (await call(ctx, 'GET', '/v1/shop/offers')).body;
  assert.deepEqual(at.current.map((o) => o.item_id), ['outfit:lantern_scout', 'outfit:campus_courier', 'outfit:cloud_nine', 'outfit:bedtime_bandit']);
  // past the written schedule: nothing on sale (the Shop says so), never a made-up offer
  ctx.clock.t = Date.parse('2027-06-01T00:00:00Z');
  const late = (await call(ctx, 'GET', '/v1/shop/offers')).body;
  assert.deepEqual(late.current, []);
  assert.equal(late.next_change_at, null);
  const cfg = await call(ctx, 'GET', '/v1/config');
  assert.ok(cfg.body.features.includes('shop_offers'), 'the deployment says it serves offers');
});

// ---------------------------------------------------------------- spending
test('offer boundaries: before start, at start, just before the end, at the end', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 5000);
  const T = ctx.clock.t;
  useSchedule(ctx, [
    { offer_id: 'T-cloud', item_id: 'outfit:cloud_nine', slot: 1, price: 1000, starts: T + 10 * MIN, ends: T + 40 * MIN },
    { offer_id: 'T-bandit', item_id: 'outfit:bedtime_bandit', slot: 2, price: 1000, starts: T + 10 * MIN, ends: T + 40 * MIN },
    { offer_id: 'T-arcade', item_id: 'outfit:arcade_sprinter', slot: 3, price: 900, starts: T + 10 * MIN, ends: T + 40 * MIN },
  ]);
  ctx.clock.t = T + 10 * MIN - 1;
  const early = await spend(ctx, a, 'outfit:cloud_nine', 'T-cloud', 1000, 'cloud-0001');
  assert.equal(early.status, 409);
  assert.equal(early.body.error, 'offer_changed');
  assert.equal(early.body.reason, 'not_started');
  assert.equal((await wallet(ctx, a)).balance, 5000, 'nothing charged');
  ctx.clock.t = T + 10 * MIN;
  const start = await spend(ctx, a, 'outfit:cloud_nine', 'T-cloud', 1000, 'cloud-0002');
  assert.equal(start.status, 200, JSON.stringify(start.body));
  assert.equal(start.body.offer.offer_id, 'T-cloud');
  assert.equal(start.body.accepted_at, T + 10 * MIN);
  assert.equal(start.body.wallet.balance, 4000);
  assert.ok(start.body.wallet.entitlements.some((e) => e.item === 'outfit:cloud_nine' && !e.revoked), 'a permanent entitlement');
  ctx.clock.t = T + 40 * MIN - 1;
  const last = await spend(ctx, a, 'outfit:bedtime_bandit', 'T-bandit', 1000, 'bandit-0001');
  assert.equal(last.status, 200, 'accepted in its last millisecond');
  ctx.clock.t = T + 40 * MIN;
  const gone = await spend(ctx, a, 'outfit:arcade_sprinter', 'T-arcade', 900, 'arcade-0001');
  assert.equal(gone.body.error, 'offer_changed');
  assert.equal(gone.body.reason, 'expired', 'ends_at is exclusive');
  assert.equal((await wallet(ctx, a)).balance, 3000, 'two purchases charged, the expired one not');
  const sales = await ctx.env.DB.prepare('SELECT offer_id, accepted_at, offer_ends_at FROM offer_sales ORDER BY accepted_at').all();
  assert.deepEqual(sales.results.map((s) => s.offer_id), ['T-cloud', 'T-bandit']);
  assert.ok(sales.results.every((s) => s.accepted_at < s.offer_ends_at), 'recorded as accepted while on sale');
  // the schema itself refuses an acceptance outside the window
  assert.throws(() => ctx.env.DB.db.prepare(`INSERT INTO offer_sales (environment, idem_key, profile_id, offer_id, item_id, price, schedule_revision,
    offer_starts_at, offer_ends_at, accepted_at) VALUES ('sandbox', 'x', 'p', 'o', 'i', 1, 1, 10, 20, 20)`).run(), /offer_window/);
  // the old item-price path can't buy a rotating skin outside its offer
  const plain = await spend(ctx, a, 'outfit:arcade_sprinter', null, 900, 'arcade-0002');
  assert.equal(plain.body.reason, 'not_in_rotation');
});

test('price, item and unknown offers are refused without a charge; legacy items need no offer', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 3000);
  const T = ctx.clock.t;
  useSchedule(ctx, [
    { offer_id: 'P-cloud', item_id: 'outfit:cloud_nine', slot: 1, price: 1000, starts: T - MIN, ends: T + 30 * MIN },
    { offer_id: 'P-mech', item_id: 'outfit:midnight_mechanic', slot: 2, price: 900, starts: T - MIN, ends: T + 30 * MIN },
  ]);
  const price = await spend(ctx, a, 'outfit:cloud_nine', 'P-cloud', 900, 'cloud-p001');
  assert.equal(price.body.error, 'offer_changed');
  assert.equal(price.body.reason, 'price');
  assert.equal(price.body.price, 1000, 'the price on sale now, to show');
  const swap = await spend(ctx, a, 'outfit:cloud_nine', 'P-mech', 900, 'cloud-p002');
  assert.equal(swap.body.reason, 'item_mismatch', 'an offer only sells its own item');
  assert.equal(swap.body.current.offer_id, 'P-cloud', "and the item's real offer comes back");
  const unknown = await spend(ctx, a, 'outfit:cloud_nine', 'no-such-offer', 1000, 'cloud-p003');
  assert.equal(unknown.body.reason, 'unknown_offer');
  assert.equal((await wallet(ctx, a)).balance, 3000, 'nothing charged by any refusal');
  // an older client sends only the item: accepted while the item is on offer
  const plain = await spend(ctx, a, 'outfit:midnight_mechanic', null, 900, 'mech-p0001');
  assert.equal(plain.status, 200, JSON.stringify(plain.body));
  assert.equal(plain.body.offer.offer_id, 'P-mech');
  // always-available Coin items are unchanged
  const robe = await spend(ctx, a, 'outfit:robe', null, 300, 'robe-p0001');
  assert.equal(robe.status, 200);
  assert.equal(robe.body.offer, undefined);
  assert.equal((await spend(ctx, a, 'hat:crown', null, 1, 'crown-p001')).body.error, 'price_changed');
  assert.equal((await wallet(ctx, a)).balance, 3000 - 900 - 300);
});

test('overlapping offers: each is valid only in its own window', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const b = await user(ctx, 'T:_ben', 'Ben Otter');
  const c = await user(ctx, 'T:_cat', 'Cat Otter');
  for (const u of [a, b, c]) await grant(ctx, u, 2000);
  const T = ctx.clock.t;
  // a revision put the same skin into two overlapping offers (and two other
  // skins overlap in other slots, as they always do)
  useSchedule(ctx, [
    { offer_id: 'V-old', item_id: 'outfit:moonwalk_cadet', slot: 1, price: 1200, starts: T - 20 * MIN, ends: T + 10 * MIN },
    { offer_id: 'V-new', item_id: 'outfit:moonwalk_cadet', slot: 3, price: 1200, starts: T + 5 * MIN, ends: T + 50 * MIN },
    { offer_id: 'V-rain', item_id: 'outfit:raincoat_explorer', slot: 2, price: 800, starts: T - 20 * MIN, ends: T + 50 * MIN },
  ]);
  ctx.clock.t = T + 6 * MIN;
  assert.equal((await spend(ctx, a, 'outfit:moonwalk_cadet', 'V-old', 1200, 'moon-a0001')).status, 200, 'the older offer, still on sale');
  assert.equal((await spend(ctx, b, 'outfit:moonwalk_cadet', 'V-new', 1200, 'moon-b0001')).status, 200, 'the newer offer, already on sale');
  const plain = await spend(ctx, c, 'outfit:moonwalk_cadet', null, 1200, 'moon-c0001');
  assert.equal(plain.body.offer.offer_id, 'V-new', 'item-only: the offer that stays longest');
  ctx.clock.t = T + 10 * MIN;
  const d = await user(ctx, 'T:_dan', 'Dan Otter');
  await grant(ctx, d, 2000);
  const old = await spend(ctx, d, 'outfit:moonwalk_cadet', 'V-old', 1200, 'moon-d0001');
  assert.equal(old.body.reason, 'expired', 'the older offer ended');
  assert.equal(old.body.current.offer_id, 'V-new', 'the offer on sale now comes back with the refusal');
  assert.equal((await spend(ctx, d, 'outfit:moonwalk_cadet', 'V-new', 1200, 'moon-d0002')).status, 200);
  assert.equal((await spend(ctx, d, 'outfit:raincoat_explorer', 'V-rain', 800, 'rain-d0001')).status, 200);
});

test('a lost reply and a duplicate retry after the offer ended return the accepted purchase', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 1500);
  const T = ctx.clock.t;
  useSchedule(ctx, [{ offer_id: 'L-lantern', item_id: 'outfit:lantern_scout', slot: 1, price: 1200, starts: T - MIN, ends: T + 5 * MIN }]);
  ctx.clock.t = T + 5 * MIN - 50;
  const first = await spend(ctx, a, 'outfit:lantern_scout', 'L-lantern', 1200, 'lantern-l01');
  assert.equal(first.status, 200, 'accepted just before the end (and suppose this reply is lost)');
  ctx.clock.t = T + 9 * MIN;   // the app retries with the same key after the offer left
  const again = await spend(ctx, a, 'outfit:lantern_scout', 'L-lantern', 1200, 'lantern-l01');
  assert.equal(again.status, 200, JSON.stringify(again.body));
  assert.equal(again.body.replay, true, 'the first result, not a refusal');
  assert.equal(again.body.bought, 'outfit:lantern_scout');
  assert.equal(again.body.offer.offer_id, 'L-lantern');
  assert.equal(again.body.accepted_at, T + 5 * MIN - 50, 'with the time it was accepted');
  assert.equal(again.body.wallet.balance, 300, 'charged once');
  const dup = await Promise.all([spend(ctx, a, 'outfit:lantern_scout', 'L-lantern', 1200, 'lantern-l01'),
    spend(ctx, a, 'outfit:lantern_scout', 'L-lantern', 1200, 'lantern-l01')]);
  assert.ok(dup.every((r) => r.status === 200 && r.body.replay === true), 'racing duplicates replay too');
  assert.equal((await spends(ctx, a)).length, 1, 'one ledger spend');
  // a new key for the same skin: it is owned, so nothing more happens
  const fresh = await spend(ctx, a, 'outfit:lantern_scout', 'L-lantern', 1200, 'lantern-l02');
  assert.equal(fresh.body.error, 'already_owned');
  assert.equal((await wallet(ctx, a)).balance, 300);
});

test('a spend racing a Shop refresh at the boundary charges once', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 1000);
  const T = ctx.clock.t;
  useSchedule(ctx, [
    { offer_id: 'S-courier', item_id: 'outfit:campus_courier', slot: 1, price: 900, starts: T - MIN, ends: T + MIN },
    { offer_id: 'S-varsity', item_id: 'outfit:varsity_sprinter', slot: 1, price: 600, starts: T + MIN, ends: T + 30 * MIN },
  ]);
  ctx.clock.t = T + MIN - 1;
  const all = await Promise.all([
    spend(ctx, a, 'outfit:campus_courier', 'S-courier', 900, 'courier-s1'),
    call(ctx, 'GET', '/v1/shop/offers'),
    spend(ctx, a, 'outfit:campus_courier', 'S-courier', 900, 'courier-s2'),
    spend(ctx, a, 'outfit:campus_courier', 'S-courier', 900, 'courier-s1'),
  ]);
  assert.equal(all[1].status, 200);
  assert.deepEqual(all[1].body.current.map((o) => o.offer_id), ['S-courier'], 'the refresh still shows the offer it was bought from');
  const bought = [all[0], all[2], all[3]].filter((r) => r.status === 200);
  assert.ok(bought.length >= 1);
  assert.ok([all[0], all[2], all[3]].filter((r) => r.status !== 200).every((r) => r.body.error === 'already_owned'));
  assert.equal((await wallet(ctx, a)).balance, 100, 'charged exactly once');
  assert.equal((await spends(ctx, a)).length, 1);
  ctx.clock.t = T + MIN;
  const after = (await call(ctx, 'GET', '/v1/shop/offers')).body;
  assert.deepEqual(after.current.map((o) => o.offer_id), ['S-varsity'], 'at the boundary the slot refreshes');
});

test('an owned skin that returns stays owned and is never sold again', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 3000);
  const T = ctx.clock.t;
  useSchedule(ctx, [
    { offer_id: 'R-1', item_id: 'outfit:pumpkin_pajamas', slot: 1, price: 800, starts: T - MIN, ends: T + 5 * MIN },
    { offer_id: 'R-2', item_id: 'outfit:pumpkin_pajamas', slot: 2, price: 800, starts: T + 20 * MIN, ends: T + 50 * MIN },
  ]);
  assert.equal((await spend(ctx, a, 'outfit:pumpkin_pajamas', 'R-1', 800, 'pumpkin-r1')).status, 200);
  ctx.clock.t = T + 10 * MIN;   // out of rotation: still owned
  const w = await wallet(ctx, a);
  assert.ok(w.entitlements.some((e) => e.item === 'outfit:pumpkin_pajamas' && !e.revoked), 'ownership never expires with the offer');
  assert.deepEqual((await call(ctx, 'GET', '/v1/shop/offers')).body.current, []);
  ctx.clock.t = T + 25 * MIN;   // it returns under a new offer id
  const back = (await call(ctx, 'GET', '/v1/shop/offers')).body;
  assert.deepEqual(back.current.map((o) => o.offer_id), ['R-2']);
  const r = await spend(ctx, a, 'outfit:pumpkin_pajamas', 'R-2', 800, 'pumpkin-r2');
  assert.equal(r.body.error, 'already_owned');
  assert.equal((await wallet(ctx, a)).balance, 2200, 'charged only the first time');
});

// ---------------------------------------------------------------- Coin packs
test('six Coin packs: every product maps to its quantity and is delivered once, independent of offers', async () => {
  const ctx = setup();
  const want = [[250, 'com.idlery.ultimatetrifecta.coins.250'], [500, 'com.idlery.ultimatetrifecta.coins.500'],
    [1000, 'com.idlery.ultimatetrifecta.coins.1000'], [1500, 'com.idlery.ultimatetrifecta.coins.1500'],
    [3500, 'com.idlery.ultimatetrifecta.coins.3500'], [7500, 'com.idlery.ultimatetrifecta.coins.7500']];
  const packs = Object.entries(E.CATALOGUE.products).filter(([, p]) => p.kind === 'coin_pack').map(([pid, p]) => [p.coins, pid]);
  packs.sort((x, y) => x[0] - y[0]);
  assert.deepEqual(packs, want, 'exactly 250 / 500 / 1,000 / 1,500 / 3,500 / 7,500, existing IDs kept');
  for (const [n, pid] of want) {
    const p = E.product(pid);
    assert.equal(p.item, `coins:${n}`);
    assert.equal(p.apple_type, 'CONSUMABLE');
    assert.equal(E.item(`coins:${n}`).product, pid, `coins:${n} names its product`);
    assert.equal(E.item(`coins:${n}`).coins, n);
  }
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const tok = (await wallet(ctx, a)).app_account_token;
  // no offer on sale at all: Coin packs don't care
  const T = ctx.clock.t;
  useSchedule(ctx, [{ offer_id: 'C-x', item_id: 'outfit:cloud_nine', slot: 1, price: 1000, starts: T - 9 * MIN, ends: T - MIN }]);
  let total = 0;
  for (const [n, pid] of want) {
    const tx = storeTx(ctx, { productId: pid, appAccountToken: tok });
    const r = await call(ctx, 'POST', '/v1/wallet/apple', { jws: appleJws(tx), transaction_id: tx.transactionId }, a.token);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.deepEqual(r.body.delivered, { coins: n }, `${pid} delivers ${n} Coins`);
    total += n;
    assert.equal(r.body.wallet.balance, total);
    const again = await call(ctx, 'POST', '/v1/wallet/apple', { jws: appleJws(tx), transaction_id: tx.transactionId }, a.token);
    assert.equal(again.body.replay, true, `${pid}: once per transaction ID`);
    assert.equal(again.body.wallet.balance, total);
  }
  assert.equal(total, 14250);
});

test('profile deletion keeps offer sales for reconciliation without the profile', async () => {
  const ctx = setup();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  await grant(ctx, a, 1000);
  const T = ctx.clock.t;
  useSchedule(ctx, [{ offer_id: 'D-1', item_id: 'outfit:cloud_nine', slot: 1, price: 1000, starts: T - MIN, ends: T + 30 * MIN }]);
  assert.equal((await spend(ctx, a, 'outfit:cloud_nine', 'D-1', 1000, 'cloud-d001')).status, 200);
  ctx.clock.t += 1000;
  const fresh = await user(ctx, 'T:_ann', null);
  assert.equal((await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token)).status, 200);
  const rows = await ctx.env.DB.prepare('SELECT profile_id, offer_id FROM offer_sales').all();
  assert.deepEqual(rows.results, [{ profile_id: null, offer_id: 'D-1' }]);
});
