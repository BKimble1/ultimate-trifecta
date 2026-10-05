// Pass 8 challenges (service/src/challenges.js): daily and weekly goals that
// add Season XP, settled with the round they come from.  Every boundary of
// docs/ECONOMY.md §10: UTC day / Monday week of the registered start, the
// 24 h settlement grace, role flexibility, the 3-credit round cap, the active
// play threshold, idempotent progress and bonus, and every round that must
// add nothing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeEnv, call, user, ADMIN, trustTestRoot } from './helpers.mjs';
import * as E from '../src/economy.js';
import * as CH from '../src/challenges.js';

const DAY = 24 * 3600 * 1000;
const C = E.ECONOMY.challenges;

// The next Monday 00:00 UTC at least two days from now (tokens and the test
// certificate are valid from "now"; the clock may move forward freely).
function nextMonday() {
  let t = CH.weekStart(Date.now()) + 7 * DAY;
  if (t - Date.now() < 2 * DAY) t += 7 * DAY;
  return t;
}

function setup(at) {
  const ctx = makeEnv();
  trustTestRoot(ctx);
  if (at) ctx.clock.t = at;
  return ctx;
}

async function party(ctx, n = '') {
  const host = await user(ctx, 'T:_host', n ? null : 'Host Otter');
  const guest = await user(ctx, 'T:_guest', n ? null : 'Guest Otter');
  const room = await call(ctx, 'POST', '/v1/rooms', { build: 105, protocol: 7, capacity: 8 }, host.token);
  assert.equal(room.status, 201, JSON.stringify(room.body));
  const code = room.body.room.code;
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  const j = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: 105, protocol: 7 }, guest.token);
  assert.equal(j.status, 200, JSON.stringify(j.body));
  const beat = () => call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { connected: [guest.profile.profile_id] }, host.token);
  await beat();
  return { host, guest, code, beat, hp: host.profile.profile_id, gp: guest.profile.profile_id, n: 0 };
}

const hostRow = (pid, o = {}) => ({ profile_id: pid, slot: 0, role: 0, stamps: 3, finished: true, first_home: true, unique_captures: 0, coins_picked: 1,
  present: true, away_s: 0, active_s: 200, ...o });
const guestRow = (pid, o = {}) => ({ profile_id: pid, slot: 1, role: 1, stamps: 0, finished: false, first_home: false, unique_captures: 2, coins_picked: 0,
  present: true, away_s: 0, active_s: 200, ...o });

async function advance(ctx, P, ms) {
  for (let left = ms; left > 0; left -= 30 * 1000) {
    ctx.clock.t += Math.min(30 * 1000, left);
    await P.beat();
  }
}

// Registers a round now, plays it for `len` ms, reports it and (unless told
// otherwise) has both players confirm the rows their games received.
async function playRound(ctx, P, o = {}) {
  P.n += 1;
  const mid = `${P.code}-${P.n}-0000c0de`;
  const rt = o.rt ?? 240;
  const outcome = o.outcome ?? 1;
  const v = o.report_version ?? 2;
  const reg = await call(ctx, 'POST', '/v1/rounds', { code: P.code, match_id: mid, participants: [{ profile_id: P.hp, slot: 0 }, { profile_id: P.gp, slot: 1 }] }, P.host.token);
  assert.equal(reg.status, 200, JSON.stringify(reg.body));
  await advance(ctx, P, o.len ?? 3 * 60 * 1000);
  const hr = hostRow(P.hp, o.host);
  const gr = guestRow(P.gp, o.guest);
  if (v < 2) {
    delete hr.active_s;
    delete gr.active_s;
  }
  const body = { outcome, round_time_s: rt, coin_spawns: 8, players: o.solo ? [hr] : [hr, gr] };
  if (v >= 2) body.report_version = v;
  const rep = await call(ctx, 'POST', `/v1/rounds/${mid}/report`, body, P.host.token);
  const dig = (row) => E.rowDigest(mid, outcome, rt, v >= 2 ? { ...row, v: 2 } : row);
  const out = { mid, rep, hr, gr, dig, outcome, rt };
  if (o.ack !== false && rep.status === 200) {
    out.ah = await call(ctx, 'POST', `/v1/rounds/${mid}/ack`, { digest: await dig(hr) }, P.host.token);
    if (!o.solo) out.ag = await call(ctx, 'POST', `/v1/rounds/${mid}/ack`, { digest: await dig(gr) }, P.guest.token);
  }
  // the next round in this party may start a minute after this one
  await advance(ctx, P, 60 * 1000);
  return out;
}

async function wallet(ctx, u) {
  const r = await call(ctx, 'GET', '/v1/wallet', undefined, u.token);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.wallet;
}

function progress(w, cid, current = true) {
  const it = [...w.challenges.items, ...w.challenges.recent].find((x) => x.challenge_id === cid && x.current === current);
  return it ? `${it.progress}/${it.goal}${it.bonus_xp ? ` +${it.bonus_xp}` : ''}` : 'none';
}

test('challenge rules: the catalogue set, UTC periods, Monday weeks, credits, the active threshold, the schema', () => {
  assert.deepEqual(C.daily.map((d) => [d.id, d.metric, d.goal, d.xp]), [
    ['night_shift', 'active_rounds', 2, 50], ['campus_contribution', 'credits', 6, 50], ['team_effort', 'round_wins', 1, 50]]);
  assert.deepEqual(C.weekly.map((d) => [d.id, d.metric, d.goal, d.xp]), [
    ['campus_regular', 'active_rounds', 10, 150], ['pull_your_weight', 'credits', 18, 150], ['strong_together', 'round_wins', 4, 150]]);
  assert.equal(C.grace_s, 86400, '24 h settlement grace');
  assert.equal(C.credit_cap_per_round, 3);
  // periods
  const mon = nextMonday();
  assert.equal(new Date(mon).getUTCDay(), 1, 'weeks start on Monday');
  assert.equal(new Date(mon).toISOString().slice(11), '00:00:00.000Z', 'at 00:00 UTC');
  assert.equal(CH.weekStart(mon), mon);
  assert.equal(CH.weekStart(mon - 1), mon - 7 * DAY, 'Sunday 23:59:59.999 is the previous week');
  assert.equal(CH.weekStart(mon + 7 * DAY - 1), mon, 'the whole week up to the next Monday');
  assert.equal(CH.dayStart(mon + 5 * 3600e3), mon);
  assert.equal(CH.dayStart(mon - 1), mon - DAY, 'the day before ends at 23:59:59.999');
  const d = CH.periodOf('daily', mon + 1);
  assert.deepEqual([d.start, d.end], [mon, mon + DAY]);
  assert.equal(CH.instanceId('weekly', CH.periodOf('weekly', mon + 3 * DAY).key, 'pull_your_weight'), `w:${new Date(mon).toISOString().slice(0, 10)}:pull_your_weight`);
  // credits: unique stamps or different runners tagged, at most 3 a round
  assert.equal(CH.credits({ role: 0, stamps: 3 }), 3);
  assert.equal(CH.credits({ role: 0, stamps: 2 }), 2);
  assert.equal(CH.credits({ role: 1, unique_captures: 5 }), 3, 'five different runners: capped at 3');
  assert.equal(CH.credits({ role: 1, unique_captures: 1, captures: 9 }), 1, 'tagging one runner nine times: 1');
  // active play: min(60 s, 40% of the round)
  assert.equal(CH.activeNeed(240), 60);
  assert.equal(CH.activeNeed(100), 40);
  assert.ok(CH.activeEnough({ v: 2, active_s: 60 }, 240) && !CH.activeEnough({ v: 2, active_s: 59 }, 240));
  assert.ok(!CH.activeEnough({ active_s: 200 }, 240), 'a v1 row proves no activity');
  assert.deepEqual(CH.increments({ v: 2, role: 1, unique_captures: 2, active_s: 100 }, 2, 240), { state: 'applied', active_rounds: 1, credits: 2, round_wins: 1 });
  assert.deepEqual(CH.increments({ v: 2, role: 0, stamps: 3, active_s: 10 }, 1, 240), { state: 'inactive', active_rounds: 0, credits: 0, round_wins: 0 });
  // the schema's per-round credit bound is the catalogue's
  const sql = readFileSync(new URL('../migrations/0004_challenges.sql', import.meta.url), 'utf8');
  assert.ok(sql.includes(`credits <= ${C.credit_cap_per_round})`), 'credit CHECK = economy.challenges.credit_cap_per_round');
  // the digest: v2 binds active_s, v1 rows hash as before
  const row = { role: 0, stamps: 2, finished: false, first_home: false, unique_captures: 0, coins_picked: 1, present: true, away_s: 3.4 };
  assert.equal(E.rowCanonical('M-1', 2, 200, row), 'v1|M-1|2|0|2|0|0|0|1|1|3|200');
  assert.equal(E.rowCanonical('M-1', 2, 200, { ...row, v: 2, active_s: 150 }), 'v2|M-1|2|0|2|0|0|0|1|1|3|200|150');
});

test('progress settles with the round: role-flexible, 3 credits a round, bonus once, Season XP only', async () => {
  const ctx = setup(nextMonday() + 10 * 3600e3);   // Monday 10:00 UTC
  const P = await party(ctx);
  // round 1: runners win; the host (runner) splashes 3 waters, the guest (Night Watch) tags 2 different runners
  const r1 = await playRound(ctx, P, { outcome: 1 });
  assert.equal(r1.ah.body.settlement.state, 'settled', JSON.stringify(r1.ah.body));
  const hs = r1.ah.body.settlement.challenges;
  assert.equal(hs.state, 'applied');
  assert.deepEqual(hs.items.filter((i) => i.completed_now).map((i) => i.challenge_id), ['team_effort'], 'one Round Win: Team Effort complete');
  assert.equal(hs.xp, 50);
  let hw = await wallet(ctx, P.host);
  assert.equal(hw.season.s1.xp, E.roundSeasonXp(r1.hr, 1) + 50, 'the bonus is Season XP, added in the settlement');
  assert.equal(hw.balance, E.roundCoins(r1.hr, 1, 8), 'Coins are the round\'s only: challenges add no Coins');
  assert.deepEqual(['night_shift', 'campus_contribution', 'team_effort', 'campus_regular', 'pull_your_weight', 'strong_together'].map((c) => progress(hw, c)),
    ['1/2', '3/6', '1/1 +50', '1/10', '3/18', '1/4']);
  let gw = await wallet(ctx, P.guest);
  assert.deepEqual(['night_shift', 'campus_contribution', 'team_effort', 'pull_your_weight'].map((c) => progress(gw, c)), ['1/2', '2/6', '0/1', '2/18'],
    'the Night Watch progresses by different runners tagged; a lost round is no win');
  assert.equal(gw.season.s1.xp, E.roundSeasonXp(r1.gr, 1));
  // round 2: the Night Watch wins and tags 5 different runners (3 credits)
  const r2 = await playRound(ctx, P, { outcome: 2, host: { stamps: 2, finished: false, first_home: false }, guest: { unique_captures: 5 } });
  assert.deepEqual(r2.ag.body.settlement.challenges.items.filter((i) => i.completed_now).map((i) => i.challenge_id), ['night_shift', 'team_effort']);
  gw = await wallet(ctx, P.guest);
  assert.deepEqual(['night_shift', 'campus_contribution', 'team_effort'].map((c) => progress(gw, c)), ['2/2 +50', '5/6', '1/1 +50'], 'role-flexible: 5 tags = 3 credits');
  hw = await wallet(ctx, P.host);
  assert.deepEqual(['night_shift', 'campus_contribution', 'team_effort'].map((c) => progress(hw, c)), ['2/2 +50', '5/6', '1/1 +50'], 'no second Team Effort bonus');
  // round 3: both reach 6 credits; progress stops at the goal
  const r3 = await playRound(ctx, P, { outcome: 1 });
  hw = await wallet(ctx, P.host);
  assert.equal(progress(hw, 'campus_contribution'), '6/6 +50', 'capped at the goal');
  assert.deepEqual(r3.ah.body.settlement.challenges.items.find((i) => i.challenge_id === 'campus_contribution'),
    { challenge_id: 'campus_contribution', instance_id: `d:${new Date(CH.dayStart(ctx.clock.t)).toISOString().slice(0, 10)}:campus_contribution`, period: 'daily',
      inc: 3, progress: 6, goal: 6, completed: true, completed_now: true, xp: 50 });
  const base = [r1, r2, r3].reduce((a, r) => a + E.roundSeasonXp(r.hr, r.outcome), 0);
  assert.equal(hw.season.s1.xp, base + 150, 'base XP + Team Effort + Night Shift + Campus Contribution');
  // round 4: dailies are done; weeklies keep counting
  await playRound(ctx, P, { outcome: 1 });
  hw = await wallet(ctx, P.host);
  assert.deepEqual(['campus_contribution', 'campus_regular', 'pull_your_weight', 'strong_together'].map((c) => progress(hw, c)), ['6/6 +50', '4/10', '11/18', '3/4']);
  // the ledger: no challenge Coins, ever
  const lg = await call(ctx, 'GET', `/v1/admin/wallets/${P.hp}`, undefined, undefined, ADMIN);
  assert.ok(lg.body.ledger.every((l) => l.source === 'round'), 'Coins only from the rounds themselves');
});

test('repeated reports, acks, reconnects and racing settlements never duplicate progress or bonus', async () => {
  const ctx = setup(nextMonday() + 12 * 3600e3);
  const P = await party(ctx);
  const r1 = await playRound(ctx, P, { outcome: 1, ack: false });
  // both confirmations of the host arrive at once (a retry after a lost reply)
  const d = await r1.dig(r1.hr);
  const both = await Promise.all([1, 2, 3].map(() => call(ctx, 'POST', `/v1/rounds/${r1.mid}/ack`, { digest: d }, P.host.token)));
  assert.ok(both.every((x) => x.status === 200 && x.body.settlement.state === 'settled'));
  // the host reports again, confirms again, reopens results, signs in on another device
  await call(ctx, 'POST', `/v1/rounds/${r1.mid}/report`, { outcome: 1, round_time_s: 240, coin_spawns: 8, report_version: 2, players: [r1.hr, r1.gr] }, P.host.token);
  await call(ctx, 'POST', `/v1/rounds/${r1.mid}/ack`, { digest: d }, P.host.token);
  const me = await call(ctx, 'GET', `/v1/rounds/${r1.mid}/me`, undefined, P.host.token);
  assert.equal(me.body.settlement.challenge_xp, 50, 'the round\'s challenge result replays');
  assert.equal(me.body.settlement.challenges.items.find((i) => i.challenge_id === 'team_effort').completed_now, true);
  const again = await user(ctx, 'T:_host', null);
  const w1 = await wallet(ctx, again);
  assert.equal(progress(w1, 'campus_contribution'), '3/6');
  assert.equal(progress(w1, 'team_effort'), '1/1 +50');
  assert.equal(w1.season.s1.xp, E.roundSeasonXp(r1.hr, 1) + 50, 'one bonus, one round');
  // two different rounds both reach the goal concurrently: one bonus
  const r2 = await playRound(ctx, P, { outcome: 2, ack: false, host: { stamps: 2, finished: false, first_home: false } });
  const r3 = await playRound(ctx, P, { outcome: 2, ack: false, host: { stamps: 2, finished: false, first_home: false } });
  const race = await Promise.all([
    call(ctx, 'POST', `/v1/rounds/${r2.mid}/ack`, { digest: await r2.dig(r2.hr) }, P.host.token),
    call(ctx, 'POST', `/v1/rounds/${r3.mid}/ack`, { digest: await r3.dig(r3.hr) }, P.host.token),
  ]);
  assert.ok(race.every((x) => x.body.settlement.state === 'settled'));
  const ns = race.flatMap((x) => x.body.settlement.challenges.items).filter((i) => i.challenge_id === 'night_shift' && i.completed_now);
  assert.equal(ns.length, 1, 'Night Shift completed by exactly one of the two rounds');
  const w2 = await wallet(ctx, P.host);
  assert.equal(progress(w2, 'night_shift'), '2/2 +50');
  assert.equal(progress(w2, 'campus_contribution'), '6/6 +50', '3 + 2 + 2 credits, stopped at 6');
  const base = [r1, r2, r3].reduce((a, r) => a + E.roundSeasonXp(r.hr, r.outcome), 0);
  assert.equal(w2.season.s1.xp, base + 150);
  const bonus = await ctx.env.DB.prepare('SELECT COUNT(*) AS n, SUM(xp) AS xp FROM challenge_bonus WHERE profile_id = ?').bind(P.hp).first();
  assert.deepEqual([bonus.n, bonus.xp], [3, 150], 'three bonus rows, never more');
});

test('periods: the registered start\'s UTC day and Monday week, the 24 h grace, expired goals take no new rounds', async () => {
  const mon = nextMonday();
  // a round registered at Sunday 23:57 UTC finishes and settles after midnight
  const ctx = setup(mon - 3 * 60 * 1000);
  let P = await party(ctx);
  const late = await playRound(ctx, P, { outcome: 1 });
  assert.ok(ctx.clock.t > mon, 'settled after the reset');
  const s = late.ah.body.settlement.challenges;
  const sunday = new Date(mon - DAY).toISOString().slice(0, 10);
  const lastWeek = new Date(mon - 7 * DAY).toISOString().slice(0, 10);
  assert.ok(s.items.every((i) => i.instance_id.includes(sunday) || i.instance_id.includes(lastWeek)), 'credited to Sunday and last week');
  let hw = await wallet(ctx, P.host);
  assert.equal(progress(hw, 'team_effort'), '0/1', 'Monday\'s goal starts empty');
  assert.equal(progress(hw, 'team_effort', false), '1/1 +50', 'Sunday\'s completed goal is still shown (within its grace)');
  assert.equal(hw.challenges.daily.start, mon, 'the current day');
  assert.equal(hw.challenges.weekly.start, mon, 'the current week starts this Monday');
  // a round registered after the reset belongs to the new period: Sunday's expired goal takes no more rounds
  const fresh = await playRound(ctx, P, { outcome: 1 });
  assert.ok(fresh.ah.body.settlement.challenges.items.every((i) => i.instance_id.includes(new Date(mon).toISOString().slice(0, 10))));
  hw = await wallet(ctx, P.host);
  assert.equal(progress(hw, 'campus_contribution', false), '3/6', 'Sunday\'s goal stays where it stopped');
  assert.equal(progress(hw, 'campus_contribution'), '3/6', 'Monday\'s has its own progress');

  // Tuesday 23:50: a round whose confirmation arrives late
  ctx.clock.t = mon + 2 * DAY - 10 * 60 * 1000;
  P = await party(ctx, 'again');
  const tue = await playRound(ctx, P, { outcome: 1, ack: false });
  const tueKey = new Date(mon + DAY).toISOString().slice(0, 10);
  // ... the guest's game confirms exactly at the end of the grace (Wednesday 24:00): still Tuesday's
  ctx.clock.t = mon + 2 * DAY + CH.graceMs();
  let guest = await user(ctx, 'T:_guest', null);
  const onTime = await call(ctx, 'POST', `/v1/rounds/${tue.mid}/ack`, { digest: await tue.dig(tue.gr) }, guest.token);
  assert.equal(onTime.body.settlement.state, 'settled');
  assert.ok(onTime.body.settlement.challenges.items.some((i) => i.instance_id === `d:${tueKey}:night_shift`), 'within the grace: Tuesday\'s goal');
  // ... the host's game confirms 1 ms after the grace: no daily progress, the week still counts, Coins and XP still paid
  ctx.clock.t += 1;
  let host = await user(ctx, 'T:_host', null);
  const hb = (await wallet(ctx, host)).season.s1.xp;
  const tooLate = await call(ctx, 'POST', `/v1/rounds/${tue.mid}/ack`, { digest: await tue.dig(tue.hr) }, host.token);
  const tl = tooLate.body.settlement;
  assert.equal(tl.state, 'settled', 'the round itself still pays');
  assert.deepEqual(tl.challenges.closed, ['daily']);
  assert.ok(tl.challenges.items.every((i) => i.period === 'weekly'), 'only the week, which is still open');
  assert.equal(tooLate.body.wallet.season.s1.xp, hb + E.roundSeasonXp(tue.hr, 1) + 0, 'no daily bonus');
  // a round confirmed after its week's grace too: nothing for challenges
  ctx.clock.t = mon + 7 * DAY - 10 * 60 * 1000;   // Sunday 23:50
  P = await party(ctx, 'third');
  const sun = await playRound(ctx, P, { outcome: 1, ack: false });
  ctx.clock.t = mon + 8 * DAY + CH.graceMs() + 1;   // Wednesday after next, 00:00:00.001
  host = await user(ctx, 'T:_host', null);
  const closed = await call(ctx, 'POST', `/v1/rounds/${sun.mid}/ack`, { digest: await sun.dig(sun.hr) }, host.token);
  assert.equal(closed.body.settlement.state, 'settled');
  assert.equal(closed.body.settlement.challenges.state, 'closed');
  assert.deepEqual(closed.body.settlement.challenges.items, []);
  guest = await user(ctx, 'T:_guest', null);
  assert.equal((await wallet(ctx, guest)).challenges.items.every((i) => i.progress === 0), true, 'a new week: everything starts at 0');
});

test('nothing for: inactive play, a v1 report, cancelled, rejected, mismatched, away, solo with bots, the daily cap', async () => {
  const ctx = setup(nextMonday() + 9 * 3600e3);
  const P = await party(ctx);
  const snap = async (u) => (await wallet(ctx, u)).challenges.items.reduce((a, i) => a + i.progress, 0);
  // connected but idle: 30 s of activity in a 240 s round (needs 60)
  const idle = await playRound(ctx, P, { outcome: 1, host: { active_s: 30 }, guest: { active_s: 59 } });
  assert.equal(idle.ah.body.settlement.state, 'settled', 'the round still pays its Coins and Season XP');
  assert.equal(idle.ah.body.settlement.challenges.state, 'inactive');
  assert.equal(idle.ag.body.settlement.challenges.state, 'inactive', '59 s is under the 60 s threshold');
  assert.equal(await snap(P.host), 0);
  // a short round needs 40% of it: 41 s of 100 is enough
  const short = await playRound(ctx, P, { outcome: 2, rt: 100, host: { active_s: 41, stamps: 1, finished: false, first_home: false }, guest: { active_s: 39 } });
  assert.equal(short.ah.body.settlement.challenges.state, 'applied');
  assert.equal(short.ag.body.settlement.challenges.state, 'inactive');
  // an older game's report (no active play evidence): paid, no challenge
  const v1 = await playRound(ctx, P, { outcome: 1, report_version: 1 });
  assert.equal(v1.ah.body.settlement.state, 'settled', JSON.stringify(v1.ah.body));
  assert.equal(v1.ah.body.settlement.challenges.state, 'no_evidence');
  const before = await snap(P.guest);
  // implausible activity is refused
  for (const [bad, why] of [[{ active_s: 241 + 1 }, 'active_s'], [{ active_s: 200, away_s: 60 }, 'active_s'], [{ active_s: 12.5 }, 'active_s'], [{ active_s: undefined }, 'active_s']]) {
    const r = await playRound(ctx, P, { outcome: 1, guest: bad });
    assert.equal(r.rep.status, 422, JSON.stringify(bad));
    assert.equal(r.rep.body.reason, why);
  }
  // cancelled (also host loss), mismatched rows, away, solo with bots
  const cx = await playRound(ctx, P, { outcome: 3, host: { finished: false, first_home: false, stamps: 1 } });
  assert.equal(cx.ag.body.settlement.state, 'cancelled');
  const mm = await playRound(ctx, P, { outcome: 1, ack: false, guest: { unique_captures: 3 } });
  const mack = await call(ctx, 'POST', `/v1/rounds/${mm.mid}/ack`, { digest: await mm.dig(guestRow(P.gp)) }, P.guest.token);
  assert.equal(mack.body.settlement.state, 'mismatch');
  const aw = await playRound(ctx, P, { outcome: 1, guest: { away_s: 120, active_s: 100 } });
  assert.equal(aw.ag.body.settlement.reason, 'away');
  assert.equal(await snap(P.guest), before, 'none of these moved the guest\'s challenges');
  const solo = await playRound(ctx, P, { outcome: 1, solo: true });
  assert.equal(solo.ah.body.settlement.reason, 'few_humans');
  const rows = await ctx.env.DB.prepare('SELECT state, COUNT(*) AS n FROM challenge_rounds WHERE profile_id = ? GROUP BY state ORDER BY state').bind(P.gp).all();
  assert.deepEqual(rows.results.map((r) => `${r.state}:${r.n}`), ['inactive:2', 'no_evidence:1'], 'only settled rounds are recorded');
  // the daily cap: a capped round moves nothing either
  const hostBefore = await snap(P.host);
  await ctx.env.DB.prepare("INSERT INTO daily_rounds (profile_id, environment, day, rounds) VALUES (?, 'sandbox', ?, 40) ON CONFLICT DO UPDATE SET rounds = 40")
    .bind(P.hp, new Date(ctx.clock.t + 300 * 1000).toISOString().slice(0, 10)).run();
  const cap = await playRound(ctx, P, { outcome: 1 });
  assert.equal(cap.ah.body.settlement.state, 'capped');
  assert.equal(await snap(P.host), hostBefore);
  const capRow = await ctx.env.DB.prepare('SELECT COUNT(*) AS n FROM challenge_rounds WHERE profile_id = ? AND match_id = ?').bind(P.hp, cap.mid).first();
  assert.equal(capRow.n, 0, 'the capped settlement rolled back as a whole');
  assert.equal(cap.ag.body.settlement.challenges.state, 'applied', 'the guest (under the cap) progresses normally');
});

test('device sync and deletion: the profile carries the progress; deleting it removes it', async () => {
  const ctx = setup(nextMonday() + 15 * 3600e3);
  const P = await party(ctx);
  await playRound(ctx, P, { outcome: 1 });
  await playRound(ctx, P, { outcome: 2 });
  // a reinstall / another device: a new sign-in, the same profile
  const other = await user(ctx, 'T:_guest', null);
  const a = await wallet(ctx, P.guest);
  const b = await wallet(ctx, other);
  assert.deepEqual(b.challenges, a.challenges, 'the same challenges from the service, nothing local');
  const direct = await call(ctx, 'GET', '/v1/challenges', undefined, other.token);
  assert.deepEqual(direct.body.challenges.items, a.challenges.items);
  assert.equal(progress(b, 'night_shift'), '2/2 +50');
  // the profile is deleted: its challenges go with it
  ctx.clock.t += 1000;
  const fresh = await user(ctx, 'T:_guest', null);
  const del = await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token);
  assert.equal(del.status, 200, JSON.stringify(del.body));
  for (const tb of ['challenge_progress', 'challenge_bonus', 'challenge_rounds']) {
    const n = await ctx.env.DB.prepare(`SELECT COUNT(*) AS n FROM ${tb} WHERE profile_id = ?`).bind(P.gp).first();
    assert.equal(n.n, 0, `${tb} cleared`);
  }
  // the periodic sweep keeps live rows and drops only long-closed ones
  const { sweep } = await import('../src/app.js');
  await sweep(ctx.env);
  assert.ok((await ctx.env.DB.prepare('SELECT COUNT(*) AS n FROM challenge_progress WHERE profile_id = ?').bind(P.hp).first()).n > 0, 'live progress kept');
  ctx.clock.t += 40 * DAY;
  await sweep(ctx.env);
  assert.equal((await ctx.env.DB.prepare('SELECT COUNT(*) AS n FROM challenge_progress').first()).n, 0, 'long-closed instances swept');
});
