// Pass 9: Season 1 · After Hours extended from 30 to 100 tiers (the same
// season, no reset).  The table, the migration of 30-tier-era accounts,
// tier 50 / tier 100 unlocks, Premium and XP gates, idempotent claims across
// retries, devices and concurrent requests, and games on another catalogue.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { makeEnv, call, user, ADMIN } from './helpers.mjs';
import * as E from '../src/economy.js';

const V2 = JSON.parse(readFileSync(new URL('../../game/tests/data/season_s1_v2.json', import.meta.url), 'utf8'));
const MIG = new URL('../migrations/', import.meta.url);

const xpOf = (tier) => E.tiers('s1')[tier - 1].xp;

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

function setXp(ctx, pid, xp, premium = 0) {
  return ctx.env.DB.prepare(`INSERT INTO season_progress (profile_id, environment, season, xp, premium, updated_at) VALUES (?, 'sandbox', 's1', ?, ?, 0)
    ON CONFLICT(profile_id, environment, season) DO UPDATE SET xp = excluded.xp, premium = excluded.premium`).bind(pid, xp, premium).run();
}

function every(from = 1, to = 100) {
  const out = [];
  for (let tier = from; tier <= to; tier++) for (const track of ['free', 'premium']) out.push({ tier, track });
  return out;
}

const claim = (ctx, u, claims) => call(ctx, 'POST', '/v1/season/s1/claim', { claims }, u.token);

async function buyPremium(ctx, u, key = 'premium-' + Math.random().toString(36).slice(2, 10)) {
  await grant(ctx, u, 1500);
  const r = await call(ctx, 'POST', '/v1/wallet/spend', { item_id: 'season:s1:premium', price: 1500, idempotency_key: key }, u.token);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.wallet;
}

test('the 100-tier table keeps tiers 1-30 exactly and extends them from the pacing rule', () => {
  const t = E.tiers('s1');
  assert.equal(E.catalogueVersion(), 3, 'one catalogue version bump for the extension');
  assert.equal(t.length, 100);
  assert.equal(E.maxTier('s1'), 100);
  assert.deepEqual(t.slice(0, 30), V2.tiers, 'tiers 1-30: thresholds, rewards and order exactly as version 2 shipped them');
  for (let i = 0; i < t.length; i++) {
    assert.equal(t[i].tier, i + 1);
    if (i > 0) assert.ok(t[i].xp > t[i - 1].xp, `tier ${i + 1} needs more XP than tier ${i}`);
    if (i >= 30) {
      assert.equal(t[i].xp - t[i - 1].xp, 350, `tier ${i + 1} costs 350 Season XP (the tier 21-30 step)`);
      assert.equal(t[i].added_in, 3, `tier ${i + 1} is marked as added in catalogue version 3`);
    }
  }
  assert.equal(xpOf(50), 15300);
  assert.equal(xpOf(100), 32800);
  assert.deepEqual(E.rewardAt('s1', 50, 'premium'), { item: 'outfit:record_breaker' });
  assert.deepEqual(E.rewardAt('s1', 100, 'premium'), { item: 'outfit:dr_doom' });
  assert.deepEqual(E.rewardAt('s1', 30, 'premium'), { item: 'outfit:library_cardigan' }, 'Library Cardigan stays at 30');
  assert.deepEqual(E.rewardAt('s1', 30, 'free'), { item: 'badge:s1_finisher' }, 'the old finisher badge stays at 30');
  assert.deepEqual(E.rewardAt('s1', 100, 'free'), { item: 'badge:s1_legend' }, 'a separate tier-100 completion badge');
  // the two skins are pass rewards only: never sold, never rotated
  for (const id of ['outfit:record_breaker', 'outfit:dr_doom']) {
    const it = E.item(id);
    assert.equal(it.kind, 'season_reward');
    assert.equal(it.season, 's1');
    assert.equal(E.price(id), 0);
    assert.ok(!it.rotation && !it.product, `${id}: no offer, no App Store product`);
  }
  assert.equal(E.item('outfit:record_breaker').name, 'Record Breaker');
  assert.equal(E.item('outfit:dr_doom').name, 'Dr. Doom');
  // premium access unchanged
  assert.equal(E.price('season:s1:premium'), V2.premium_price);
  assert.equal(E.season('s1').premium_item, V2.premium_item);
  // no item is granted by two cells (a duplicate would be "already owned")
  const seen = new Map();
  for (const r of t) {
    for (const track of ['free', 'premium']) {
      const w = r[track];
      if (w && w.item) {
        assert.ok(!seen.has(w.item), `${w.item} at tier ${r.tier} ${track} and ${seen.get(w.item)}`);
        seen.set(w.item, `tier ${r.tier} ${track}`);
        assert.ok(E.item(w.item), `${w.item} is catalogued`);
      }
    }
  }
  // Premium Coins never pay back the pass
  const coins = (track) => t.reduce((n, r) => n + (r[track] && r[track].coins ? r[track].coins : 0), 0);
  assert.ok(coins('premium') < E.price('season:s1:premium'), `Premium Coins ${coins('premium')} < 1,500`);
});

test('migration 0005 keeps every 30-tier-era row and only adds the audit column', () => {
  const files = readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort();
  // (later migrations, e.g. 0006_friends, add their own tables after it)
  assert.ok(files.includes('0005_season_100.sql'), 'the Season 100 migration is applied');
  const db = new DatabaseSync(':memory:');
  for (const f of files.filter((x) => x < '0005')) db.exec(readFileSync(new URL(f, MIG), 'utf8'));
  // a 30-tier-era account: XP past the old cap, Premium, every old cell claimed
  db.prepare("INSERT INTO season_progress (profile_id, environment, season, xp, premium, premium_at, updated_at) VALUES ('p1', 'sandbox', 's1', 12000, 1, 5, 5)").run();
  for (const r of V2.tiers) {
    for (const track of ['free', 'premium']) {
      if (r[track]) db.prepare("INSERT INTO season_claims (profile_id, environment, season, tier, track, reward, result, at) VALUES ('p1', 'sandbox', 's1', ?, ?, ?, 'granted', 7)")
        .run(r.tier, track, E.rewardKey(r[track]));
    }
  }
  const before = db.prepare('SELECT * FROM season_claims ORDER BY tier, track').all().map((x) => ({ ...x }));
  db.exec(readFileSync(new URL('0005_season_100.sql', MIG), 'utf8'));
  const after = db.prepare('SELECT * FROM season_claims ORDER BY tier, track').all().map((x) => ({ ...x }));
  assert.equal(after.length, before.length, 'no claim lost or added');
  for (let i = 0; i < after.length; i++) {
    const { catalogue_version: cv, ...rest } = after[i];
    assert.deepEqual(rest, before[i], 'claim rows unchanged');
    assert.equal(cv, null, 'old rows: table version not recorded (they are all version 2)');
  }
  const prog = { ...db.prepare("SELECT xp, premium FROM season_progress WHERE profile_id = 'p1'").get() };
  assert.deepEqual(prog, { xp: 12000, premium: 1 }, 'XP past the old cap and Premium untouched');
});

test('a 30-tier-era account keeps XP, claims, items, Premium and Coins; the tier is recomputed', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_old', 'Old Otter');
  const pid = a.profile.profile_id;
  await buyPremium(ctx, a, 'premium-old');
  await setXp(ctx, pid, 12000, 1);   // 3,700 past the old last tier (8,300)
  // everything 1-30 claimed under the old table (simulated: written straight
  // into the tables as the version 2 service did, no catalogue_version)
  const items = [];
  for (const r of V2.tiers) {
    for (const track of ['free', 'premium']) {
      const w = r[track];
      if (!w) continue;
      await ctx.env.DB.prepare("INSERT INTO season_claims (profile_id, environment, season, tier, track, reward, result, at) VALUES (?, 'sandbox', 's1', ?, ?, ?, 'granted', 0)")
        .bind(pid, r.tier, track, E.rewardKey(w)).run();
      if (w.item) {
        items.push(w.item);
        await ctx.env.DB.prepare("INSERT INTO entitlements (profile_id, environment, item_id, source, ref, granted_at) VALUES (?, 'sandbox', ?, 'season', ?, 0)")
          .bind(pid, w.item, `s1:${r.tier}:${track}`).run();
      }
    }
  }
  await grant(ctx, a, 700, 'old-balance');
  const w0 = await wallet(ctx, a);
  assert.equal(w0.season.s1.xp, 12000, 'the recorded XP, including the 3,700 past the old cap');
  assert.equal(w0.season.s1.tier, 40, 'tier recomputed from that XP with the 100-tier table (11,800 = tier 40)');
  assert.equal(w0.season.s1.tiers, 100);
  assert.equal(w0.season.s1.premium, true, 'Premium entitlement kept');
  assert.equal(w0.season.s1.claimed.length, 45, 'every old claim kept');
  assert.equal(w0.balance, 700);
  const r = await claim(ctx, a, every());
  assert.deepEqual(r.body.claimed.map((c) => `${c.tier}:${c.track}:${c.result}`),
    ['35:free:granted', '35:premium:granted', '40:free:granted', '40:premium:granted'], 'only the newly reached rewards: nothing from 1-30 again');
  assert.equal(r.body.wallet.balance, 700 + 50 + 75, 'tier 35 Coins once');
  assert.ok(r.body.skipped.some((s) => s.tier === 30 && s.reason === 'already_claimed'), 'old claims answer already_claimed');
  assert.ok(r.body.skipped.some((s) => s.tier === 50 && s.reason === 'locked'), 'tier 50 not reached');
  const owned = new Set(r.body.wallet.entitlements.filter((x) => !x.revoked).map((x) => x.item));
  for (const id of items) assert.ok(owned.has(id), `${id} still owned (nothing clawed back)`);
  assert.ok(owned.has('badge:s1_finisher') && owned.has('outfit:library_cardigan'));
  assert.ok(owned.has('card:finish_line') && owned.has('badge:big_dive'), 'tier 40 rewards');
  // the claim rows written now record the table they used
  const rows = await ctx.env.DB.prepare("SELECT tier, catalogue_version FROM season_claims WHERE profile_id = ? AND tier >= 31").bind(pid).all();
  assert.ok(rows.results.length === 4 && rows.results.every((x) => x.catalogue_version === 3));
});

test('tier 50 and tier 100: Premium alone never unlocks an unearned tier; XP alone never grants a Premium reward', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const pid = a.profile.profile_id;
  await buyPremium(ctx, a);
  await setXp(ctx, pid, xpOf(50) - 1, 1);   // one XP short of tier 50, with Premium
  let r = await claim(ctx, a, [{ tier: 50, track: 'premium', reward: 'outfit:record_breaker' }, { tier: 100, track: 'premium', reward: 'outfit:dr_doom' }]);
  assert.deepEqual(r.body.claimed, [], 'nothing granted');
  assert.deepEqual(r.body.skipped.map((s) => `${s.tier}:${s.reason}`), ['50:locked', '100:locked']);
  assert.ok(!r.body.wallet.entitlements.some((x) => x.item === 'outfit:record_breaker'));
  await setXp(ctx, pid, xpOf(50), 1);
  r = await claim(ctx, a, [{ tier: 50, track: 'premium', reward: 'outfit:record_breaker' }]);
  assert.deepEqual(r.body.claimed.map((c) => `${c.tier}:${c.track}:${c.result}:${c.reward}`), ['50:premium:granted:outfit:record_breaker'], 'exactly at the threshold');
  assert.ok(r.body.wallet.entitlements.some((x) => x.item === 'outfit:record_breaker' && x.source === 'season'));

  const b = await user(ctx, 'T:_ben', 'Ben Otter');
  await setXp(ctx, b.profile.profile_id, xpOf(100) + 5000);   // well past tier 100, no Premium
  r = await claim(ctx, b, [{ tier: 100, track: 'premium' }, { tier: 100, track: 'free' }, { tier: 50, track: 'premium' }]);
  assert.deepEqual(r.body.claimed.map((c) => `${c.tier}:${c.track}`), ['100:free'], 'the free completion badge only');
  assert.deepEqual(r.body.skipped.map((s) => `${s.tier}:${s.track}:${s.reason}`), ['100:premium:premium_required', '50:premium:premium_required']);
  assert.equal(r.body.wallet.season.s1.tier, 100, 'XP past the last tier: tier 100, nothing beyond');
  // buying Premium later makes every earned Premium reward claimable, and adds no XP
  const before = r.body.wallet.season.s1.xp;
  const bw = await buyPremium(ctx, b);
  assert.equal(bw.season.s1.xp, before, 'no tier skips: Premium adds no XP');
  r = await claim(ctx, b, [{ tier: 100, track: 'premium', reward: 'outfit:dr_doom' }, { tier: 50, track: 'premium', reward: 'outfit:record_breaker' }]);
  assert.deepEqual(r.body.claimed.map((c) => `${c.tier}:${c.result}`), ['100:granted', '50:granted']);
});

test('claims are idempotent: repeats, a lost reply, two devices at once, a reinstall', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const pid = a.profile.profile_id;
  await buyPremium(ctx, a);
  await setXp(ctx, pid, xpOf(100), 1);
  // a second device signs in to the same profile (another token)
  const a2 = await user(ctx, 'T:_ann');
  assert.equal(a2.profile.profile_id, pid);
  const body = every(31, 100).map((c) => ({ ...c, reward: E.rewardKey(E.rewardAt('s1', c.tier, c.track)) })).filter((c) => c.reward !== '');
  const [r1, r2] = await Promise.all([claim(ctx, a, body), claim(ctx, a2, body)]);
  assert.equal(r1.status, 200);
  assert.equal(r2.status, 200);
  const granted = [...r1.body.claimed, ...r2.body.claimed].map((c) => `${c.tier}:${c.track}`).sort();
  assert.equal(new Set(granted).size, granted.length, 'no cell granted twice across devices');
  assert.equal(granted.length, 28, 'tiers 31-100: 14 reward tiers x 2 tracks');
  const coins = E.tiers('s1').slice(30).reduce((n, r) => n + (r.free && r.free.coins ? r.free.coins : 0) + (r.premium && r.premium.coins ? r.premium.coins : 0), 0);
  const w = await wallet(ctx, a);
  assert.equal(w.balance, coins, 'tier 31-100 Coins exactly once (Premium spent the 1,500 granted)');
  // the reply was lost: the game retries the same request; nothing more
  const again = await claim(ctx, a, body);
  assert.deepEqual(again.body.claimed, []);
  assert.ok(again.body.skipped.every((s) => s.reason === 'already_claimed'));
  assert.equal(again.body.wallet.balance, coins);
  // a reinstall (no local state) reads the same claimed cells from the snapshot
  const fresh = await user(ctx, 'T:_ann');
  const fw = await wallet(ctx, fresh);
  for (const c of body) assert.ok(fw.season.s1.claimed.includes(`${c.tier}:${c.track}`));
  const ledger = await ctx.env.DB.prepare("SELECT COUNT(*) AS n FROM ledger WHERE profile_id = ? AND source = 'season_claim'").bind(pid).all();
  assert.equal(ledger.results[0].n, 14, 'one ledger grant per Coin cell (7 free + 7 Premium)');
  const claims = await ctx.env.DB.prepare('SELECT COUNT(*) AS n FROM season_claims WHERE profile_id = ?').bind(pid).all();
  assert.equal(claims.results[0].n, 28);
});

test('another catalogue: an old 30-tier game, a changed reward, unknown tiers, an owned skin', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const pid = a.profile.profile_id;
  await buyPremium(ctx, a);
  await setXp(ctx, pid, xpOf(52), 1);
  // an old (version 2) game: its own Claim all, at most 60 cells of tiers
  // 1-30, no reward names; this service grants its (identical) tier 1-30 rewards
  const old = every(1, 30);
  assert.equal(old.length, 60);
  const r = await claim(ctx, a, old);
  const granted = r.body.claimed;
  assert.equal(granted.length, 45, 'every reward of tiers 1-30');
  for (const c of granted) assert.equal(c.reward, E.rewardKey(V2.tiers[c.tier - 1][c.track]), `tier ${c.tier} ${c.track}: the reward the old game showed`);
  assert.ok(!granted.some((c) => c.tier > 30), 'nothing past the old game\'s table');
  assert.ok(r.body.wallet.season.s1.claimed.length === 45);
  // a game that showed a different reward for a cell (another catalogue):
  // nothing granted, and the reply names this service's reward
  const ch = await claim(ctx, a, [{ tier: 35, track: 'premium', reward: 'coins:500' }, { tier: 50, track: 'premium', reward: 'outfit:dr_doom' }]);
  assert.deepEqual(ch.body.claimed, []);
  assert.deepEqual(ch.body.skipped.map((s) => `${s.tier}:${s.reason}:${s.reward}`), ['35:reward_changed:coins:75', '50:reward_changed:outfit:record_breaker']);
  // tiers outside the table and malformed cells
  const bad = await claim(ctx, a, [{ tier: 0, track: 'free' }, { tier: 101, track: 'premium' }, { tier: 'x', track: 'free' }, { tier: 2, track: 'gold' }]);
  assert.deepEqual(bad.body.claimed, []);
  assert.deepEqual(bad.body.skipped.map((s) => `${s.tier}:${s.reason}`), ['0:no_reward', '101:no_reward'], 'unknown tiers are answered, malformed cells ignored');
  assert.deepEqual((await claim(ctx, a, [{ tier: 36, track: 'free' }])).body.skipped, [{ tier: 36, track: 'free', reason: 'no_reward' }], 'a progress tier has no reward');
  // the skin already owned (support grant): recorded as claimed, never granted twice
  await ctx.env.DB.prepare("INSERT INTO entitlements (profile_id, environment, item_id, source, granted_at) VALUES (?, 'sandbox', 'outfit:record_breaker', 'admin', 0)").bind(pid).run();
  const own = await claim(ctx, a, [{ tier: 50, track: 'premium', reward: 'outfit:record_breaker' }]);
  assert.deepEqual(own.body.claimed.map((c) => c.result), ['already_owned']);
  const ents = own.body.wallet.entitlements.filter((x) => x.item === 'outfit:record_breaker');
  assert.equal(ents.length, 1);
  assert.equal(ents[0].source, 'admin');
});

test('a whole 100-tier Claim all in one request; Season XP keeps counting past tier 30', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_ann', 'Ann Otter');
  const pid = a.profile.profile_id;
  await buyPremium(ctx, a);
  await setXp(ctx, pid, xpOf(100), 1);
  const all = every(1, 100);
  assert.equal(all.length, 200);
  const r = await claim(ctx, a, all);
  const cells = E.tiers('s1').reduce((n, t) => n + (t.free ? 1 : 0) + (t.premium ? 1 : 0), 0);
  assert.equal(r.body.claimed.length, cells, `all ${cells} reward cells in one request (an old service capped a request at 60)`);
});

test('a verified round settles Season XP past the old last tier (no cap, no reset)', async () => {
  const ctx = makeEnv();
  const host = await user(ctx, 'T:_host', 'Host Otter');
  const guest = await user(ctx, 'T:_guest', 'Guest Otter');
  const gp = guest.profile.profile_id;
  const hp = host.profile.profile_id;
  const room = await call(ctx, 'POST', '/v1/rooms', { build: 105, protocol: 5, capacity: 8 }, host.token);
  const code = room.body.room.code;
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: 105, protocol: 5 }, guest.token);
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { connected: [gp] }, host.token);
  await setXp(ctx, gp, 8290);   // 10 short of the old last tier
  const mid = `${code}-1-0000beef`;
  const reg = await call(ctx, 'POST', '/v1/rounds', { code, match_id: mid, participants: [{ profile_id: hp, slot: 0 }, { profile_id: gp, slot: 1 }] }, host.token);
  assert.equal(reg.status, 200, JSON.stringify(reg.body));
  const guestRow = { profile_id: gp, slot: 1, role: 1, stamps: 0, finished: false, first_home: false, unique_captures: 2, coins_picked: 1, present: true, away_s: 0 };
  const hostRow = { profile_id: hp, slot: 0, role: 0, stamps: 3, finished: true, first_home: true, unique_captures: 0, coins_picked: 2, present: true, away_s: 0 };
  await call(ctx, 'POST', `/v1/rounds/${mid}/ack`, { digest: await E.rowDigest(mid, 2, 180, guestRow) }, guest.token);
  ctx.clock.t += 120 * 1000;
  const rep = await call(ctx, 'POST', `/v1/rounds/${mid}/report`, { outcome: 2, round_time_s: 180, coin_spawns: 8, players: [hostRow, guestRow] }, host.token);
  assert.equal(rep.status, 200, JSON.stringify(rep.body));
  const w = await wallet(ctx, guest);
  const gain = E.roundSeasonXp(guestRow, 2);
  assert.equal(w.season.s1.xp, 8290 + gain, `the whole +${gain}, past 8,300`);
  assert.equal(w.season.s1.tier, 30 + Math.floor((8290 + gain - 8300) / 350));
});
