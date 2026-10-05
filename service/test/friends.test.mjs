// Friends (FINAL_RELEASE_SWEEP): mutual friend sets, presence and invites,
// run against the whole API on the in-memory D1 (service/test/helpers.mjs).
// Two or more "players" here are separate verified sessions in one process:
// this is test-harness evidence of the service logic, not of Game Center or
// a device.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createVerify } from 'node:crypto';
import { makeEnv, call, signIn, user, ADMIN } from './helpers.mjs';
import { sweep } from '../src/app.js';
import { friendHash, MAX_FRIENDS, INVITE_TTL_MS, PRESENCE_TTL_MS, FRIEND_SET_TTL_MS, INVITE_RATE, INVITE_PAIR_RATE } from '../src/friends.js';

const P = 8;        // protocol
const BUILD = 200;
const KEY = 'test-friend-hash-key-0123456789abcdefghijklmn';

function env(over = {}) {
  return makeEnv({ FRIEND_HASH_KEY: KEY, ...over });
}

async function mk(ctx, tid, name) {
  const u = await user(ctx, tid, name);
  return { ...u, tid, pid: u.profile.profile_id, seq: 0, inst: 'inst_' + tid.replace(/[^A-Za-z0-9]/g, '') + '_1' };
}

const share = (ctx, u, ids) => call(ctx, 'PUT', '/v1/friends', { ids }, u.token);
async function mutual(ctx, a, b) {
  assert.equal((await share(ctx, a, [b.tid])).status, 200);
  assert.equal((await share(ctx, b, [a.tid])).status, 200);
}
function beat(ctx, u, o = {}) {
  u.seq += 1;
  return call(ctx, 'POST', '/v1/presence', { instance: o.instance ?? u.inst, seq: o.seq ?? u.seq, state: o.state ?? 'online',
    room: o.room, protocol: o.protocol ?? P, build: BUILD }, u.token);
}
async function presence(ctx, u) {
  const r = await call(ctx, 'GET', '/v1/friends/presence', undefined, u.token);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body;
}
const entry = (body, tid) => body.friends.find((f) => f.id === tid);
const tick = (ctx, ms) => { ctx.clock.t += ms; };
// time passes while the host's game keeps the room alive (every 15 s)
async function wait(ctx, ms, host, code) {
  for (let left = ms; left > 0; left -= 15000) {
    tick(ctx, Math.min(15000, left));
    await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, {}, host.token);
  }
}
const rows = async (ctx, sql, ...a) => (await ctx.env.DB.prepare(sql).bind(...a).all()).results;

async function party(ctx, host, capacity = 8) {
  const room = await call(ctx, 'POST', '/v1/rooms', { build: BUILD, protocol: P, capacity }, host.token);
  assert.equal(room.status, 201, JSON.stringify(room.body));
  const code = room.body.room.code;
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  return code;
}
// join through the normal admission and be confirmed by the host
async function joinConfirmed(ctx, host, u, code) {
  const j = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, u.token);
  assert.equal(j.status, 200, JSON.stringify(j.body));
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { connected: [u.pid] }, host.token);
  return j;
}

test('features: friends is offered only when FRIEND_HASH_KEY is set; routes say so otherwise', async () => {
  const on = env();
  assert.ok((await call(on, 'GET', '/v1/config')).body.features.includes('friends'));
  const off = makeEnv();
  assert.ok(!(await call(off, 'GET', '/v1/config')).body.features.includes('friends'));
  const a = await mk(off, 'T:_a', 'Comfy Frog');
  const r = await share(off, a, ['T:_b']);
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'not_configured');
});

test('only mutual friends see each other; one-sided lists show nothing either way', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  const c = await mk(ctx, 'T:_carol', 'Moonlit Koala');
  for (const u of [a, b, c]) await beat(ctx, u);
  await share(ctx, a, [b.tid]);
  assert.deepEqual((await presence(ctx, a)).friends, [], 'A lists B but B has not listed A: nothing');
  assert.deepEqual((await presence(ctx, b)).friends, [], 'and B sees nothing of A');
  await share(ctx, b, [a.tid]);
  const pa = await presence(ctx, a);
  assert.equal(pa.friends.length, 1);
  const eb = entry(pa, b.tid);
  assert.equal(eb.status, 'online');
  assert.equal(eb.name, 'Snoozy Gecko', 'the verified game name');
  assert.equal(eb.profile_id, b.pid, 'a profile for Report / Block');
  assert.equal(eb.can_invite, true);
  assert.equal(entry(await presence(ctx, b), a.tid).status, 'online');
  // C lists A; A doesn't list C
  await share(ctx, c, [a.tid, b.tid]);
  assert.equal(entry(await presence(ctx, a), c.tid), undefined, 'C is not shown to A');
  assert.deepEqual((await presence(ctx, c)).friends, [], 'and C sees nobody');
  // the whole set is replaced on each sync: A drops B and the relationship ends
  await share(ctx, a, []);
  assert.deepEqual((await presence(ctx, b)).friends, [], 'B no longer sees A');
  assert.deepEqual((await presence(ctx, a)).friends, []);
});

test('enumeration: arbitrary IDs reveal nothing; invites to non-friends all fail the same way', async () => {
  const ctx = env();
  const mallory = await mk(ctx, 'T:_mallory', 'Quiet Duck');
  const victims = [];
  for (const id of ['v1', 'v2', 'v3']) {
    const v = await mk(ctx, 'T:_' + id, 'Player ' + id.toUpperCase() + 'x');
    await beat(ctx, v);
    victims.push(v);
  }
  // v1 really is Mallory's friend one way only; v2 lists someone else
  await share(ctx, victims[1], ['T:_somebody']);
  const guesses = ['T:_v1', 'T:_v2', 'T:_v3', 'T:_nobody'];
  for (let i = 0; guesses.length < MAX_FRIENDS; i++) guesses.push(`T:_guess${i}`);
  const up = await share(ctx, mallory, guesses);
  assert.equal(up.status, 200);
  assert.equal(up.body.count, MAX_FRIENDS, 'the reply counts what was stored, never who matched');
  const pm = await presence(ctx, mallory);
  assert.deepEqual(pm.friends, [], 'no presence for any guessed ID');
  const host = victims[0];
  const code = await party(ctx, host);
  await beat(ctx, host, { state: 'lobby', room: code });
  const txt = JSON.stringify(await presence(ctx, mallory));
  assert.ok(!txt.includes(code), 'room codes never appear');
  // invites: unknown, one-sided, blocked and suspended targets look identical
  const mroom = await party(ctx, mallory);
  assert.ok(mroom);
  const answers = [];
  for (const to of ['T:_nobody', 'T:_v1', 'T:_v2']) answers.push(await call(ctx, 'POST', '/v1/invites', { to }, mallory.token));
  for (const r of answers) {
    assert.equal(r.status, 404);
    assert.equal(r.body.error, 'not_friend');
    assert.equal(r.body.message, answers[0].body.message, 'one message for every non-friend');
  }
  assert.equal((await call(ctx, 'POST', '/v1/invites', { to: 'not a valid id' }, mallory.token)).status, 400);
  // stored as keyed hashes only: no raw ID in the table
  const stored = await rows(ctx, 'SELECT friend_hash FROM friend_claims WHERE profile_id = ?', mallory.pid);
  assert.equal(stored.length, MAX_FRIENDS);
  assert.ok(stored.every((r) => /^[0-9a-f]{32}$/.test(r.friend_hash)), 'hex hashes');
  assert.ok(!JSON.stringify(stored).includes('T:_'), 'never the teamPlayerIDs themselves');
  assert.ok(stored.map((r) => r.friend_hash).includes(await friendHash(ctx.env, 'T:_v1')));
  // validation and the cap
  assert.equal((await share(ctx, mallory, [...guesses, 'T:_one_more'])).body.error, 'too_many_friends');
  assert.equal((await share(ctx, mallory, ['ok', 42])).status, 400);
  assert.equal((await share(ctx, mallory, ['has space'])).status, 400);
});

test('blocks in either direction hide both players and stop invites; unblocking restores', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  await mutual(ctx, a, b);
  await beat(ctx, a);
  await beat(ctx, b);
  const code = await party(ctx, a);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'online');
  for (const [blocker, blocked] of [[a, b], [b, a]]) {
    await call(ctx, 'POST', '/v1/blocks', { profile_id: blocked.pid }, blocker.token);
    assert.deepEqual((await presence(ctx, a)).friends, [], 'A sees nothing');
    assert.deepEqual((await presence(ctx, b)).friends, [], 'B sees nothing');
    const inv = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
    assert.equal(inv.body.error, 'not_friend', 'no invite either way (and no hint about the block)');
    await call(ctx, 'DELETE', `/v1/blocks/${blocked.pid}`, undefined, blocker.token);
    assert.equal(entry(await presence(ctx, a), b.tid).status, 'online', 'unblocked: visible again');
  }
  // a block made after an invite was sent removes the invite from the inbox
  const inv = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
  assert.equal(inv.status, 201, JSON.stringify(inv.body));
  assert.equal((await call(ctx, 'GET', '/v1/invites', undefined, b.token)).body.invites.length, 1);
  await call(ctx, 'POST', '/v1/blocks', { profile_id: a.pid }, b.token);
  assert.equal((await call(ctx, 'GET', '/v1/invites', undefined, b.token)).body.invites.length, 0, 'gone once blocked');
  const acc = await call(ctx, 'POST', `/v1/invites/${inv.body.invite.id}/accept`, { build: BUILD, protocol: P }, b.token);
  assert.equal(acc.status, 410, 'and it cannot be accepted');
  assert.ok(code);
});

test('suspended and deleted players drop out of presence and invites', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  const c = await mk(ctx, 'T:_carol', 'Moonlit Koala');
  // (each upload replaces the whole set: A shares both friends at once)
  await share(ctx, a, [b.tid, c.tid]);
  await share(ctx, b, [a.tid]);
  await share(ctx, c, [a.tid]);
  for (const u of [a, b, c]) await beat(ctx, u);
  await party(ctx, b);
  const inv = await call(ctx, 'POST', '/v1/invites', { to: a.tid }, b.token);
  assert.equal(inv.status, 201);
  assert.equal((await presence(ctx, a)).friends.length, 2);
  // a moderator suspends B
  const rep = await call(ctx, 'POST', '/v1/reports', { profile_id: b.pid, reason: 'harassment' }, c.token);
  await call(ctx, 'POST', `/v1/admin/reports/${rep.body.receipt}/resolve`, { action: 'suspend', hours: 24 }, undefined, ADMIN);
  assert.equal(entry(await presence(ctx, a), b.tid), undefined, 'a suspended friend is not shown');
  assert.equal((await call(ctx, 'GET', '/v1/invites', undefined, a.token)).body.invites.length, 0, "their invite is not delivered");
  assert.equal((await beat(ctx, b)).status, 403, 'a suspended player cannot send presence');
  assert.equal((await call(ctx, 'POST', '/v1/invites', { to: a.tid }, b.token)).status, 403, 'or invites');
  // C deletes their profile (fresh sign-in first, as the game does)
  const fresh = await signIn(ctx, c.tid);
  const del = await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token);
  assert.equal(del.status, 200);
  assert.equal(entry(await presence(ctx, a), c.tid), undefined, 'a deleted friend is gone');
  for (const t of ['friend_sets', 'friend_claims', 'presence']) {
    assert.equal((await rows(ctx, `SELECT * FROM ${t} WHERE profile_id = ?`, c.pid)).length, 0, `${t}: nothing left`);
  }
  // the suspension lapses: B is a friend again
  tick(ctx, 25 * 3600 * 1000);
  const b2 = { ...b, ...(await signIn(ctx, b.tid)) };
  const a2 = { ...a, ...(await signIn(ctx, a.tid)) };
  await share(ctx, a2, [b.tid, c.tid]);
  await share(ctx, b2, [a.tid]);
  await beat(ctx, b2);
  assert.equal(entry(await presence(ctx, a2), b.tid).status, 'online', 'back once the suspension ended');
});

test('presence: expiry, background and sign-out clear it; lobby needs verified membership', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  const h = await mk(ctx, 'T:_host', 'Host Otter');
  await mutual(ctx, a, b);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'offline', 'a friend with no heartbeat is offline');
  const hb = await beat(ctx, b);
  assert.equal(hb.body.status, 'online');
  assert.equal(hb.body.interval_s, 20);
  assert.equal(hb.body.ttl_s, 60);
  tick(ctx, PRESENCE_TTL_MS - 1000);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'online');
  tick(ctx, 2000);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'offline', 'expired 60 s after the last heartbeat (no stuck online)');
  // a lobby claim for a room B is not in is downgraded
  const code = await party(ctx, h);
  const fake = await beat(ctx, b, { state: 'lobby', room: code });
  assert.equal(fake.body.status, 'online');
  assert.equal(fake.body.room_verified, false);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'online');
  await joinConfirmed(ctx, h, b, code);
  tick(ctx, 1500);
  const real = await beat(ctx, b, { state: 'lobby', room: code });
  assert.equal(real.body.status, 'lobby');
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'lobby');
  tick(ctx, 1500);
  await beat(ctx, b, { state: 'match', room: code });
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'match');
  // background: that launch's row goes at once
  await call(ctx, 'DELETE', '/v1/presence', { instance: b.inst }, b.token);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'offline');
  // sign-out clears what that session wrote
  await beat(ctx, b);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'online');
  await call(ctx, 'POST', '/v1/auth/signout', {}, b.token);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'offline', 'signed out: offline');
  // the sweep removes expired rows
  const b2 = { ...b, ...(await signIn(ctx, b.tid)) };
  await beat(ctx, b2);
  tick(ctx, PRESENCE_TTL_MS + 1);
  await sweep(ctx.env);
  assert.equal((await rows(ctx, 'SELECT * FROM presence')).length, 0, 'swept');
});

test('presence: several devices and late requests never let an obsolete one win', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  const h = await mk(ctx, 'T:_host', 'Host Otter');
  await mutual(ctx, a, b);
  const code = await party(ctx, h);
  await joinConfirmed(ctx, h, b, code);
  // the phone (older launch) is in the lobby
  await beat(ctx, b, { instance: 'phone_launch_1', seq: 1, state: 'lobby', room: code });
  tick(ctx, 2000);
  // the iPad opens the game later: friends see the newest launch
  await beat(ctx, b, { instance: 'ipad_launch_1', seq: 1, state: 'online' });
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'online');
  // the phone keeps sending heartbeats (and even a change): it does not take over
  tick(ctx, 5000);
  await beat(ctx, b, { instance: 'phone_launch_1', seq: 2, state: 'match', room: code });
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'online', 'the obsolete device does not overwrite the newer one');
  // one launch's late request (lower seq) is ignored
  tick(ctx, 5000);
  await beat(ctx, b, { instance: 'ipad_launch_1', seq: 5, state: 'match', room: code });
  const late = await beat(ctx, b, { instance: 'ipad_launch_1', seq: 3, state: 'online' });
  assert.equal(late.body.stale, true);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'match', 'the newer heartbeat stands');
  // the iPad goes to the background: the phone's row shows again
  await call(ctx, 'DELETE', '/v1/presence', { instance: 'ipad_launch_1' }, b.token);
  assert.equal(entry(await presence(ctx, a), b.tid).status, 'match');
  // a flood of unchanged heartbeats is not written each time; launches are capped
  tick(ctx, 5000);
  const w1 = await beat(ctx, b, { instance: 'phone_launch_1', seq: 10, state: 'match', room: code });
  const w2 = await beat(ctx, b, { instance: 'phone_launch_1', seq: 11, state: 'match', room: code });
  assert.equal(w1.body.written, true);
  assert.equal(w2.body.written, false, 'unchanged within 4 s: no write');
  for (let i = 0; i < 6; i++) await beat(ctx, b, { instance: `launch_${i}_xxxx`, seq: 1 });
  assert.ok((await rows(ctx, 'SELECT * FROM presence WHERE profile_id = ?', b.pid)).length <= 4, 'at most four launches kept');
});

test('invites: rate limits, de-duplication, expiry and decline are recorded', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  await mutual(ctx, a, b);
  await beat(ctx, b);
  assert.equal((await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token)).body.error, 'no_party', 'a party first');
  const code = await party(ctx, a);
  await beat(ctx, a, { state: 'lobby', room: code });
  const first = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
  assert.equal(first.status, 201, JSON.stringify(first.body));
  const again = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
  assert.equal(again.body.duplicate, true, 'a repeated tap is the same invite');
  assert.equal(again.body.invite.id, first.body.invite.id);
  assert.equal(entry(await presence(ctx, a), b.tid).invited, true, 'Invited ✓ for the inviter');
  assert.equal(entry(await presence(ctx, a), b.tid).can_invite, false);
  const inbox = await call(ctx, 'GET', '/v1/invites', undefined, b.token);
  assert.equal(inbox.body.invites.length, 1);
  const iv = inbox.body.invites[0];
  assert.equal(iv.from.name, 'Comfy Frog', 'who invited them (verified name)');
  assert.equal(iv.from.id, a.tid);
  assert.equal(iv.from_host, true);
  assert.ok(!JSON.stringify(inbox.body).includes(code), 'no room code before accepting');
  assert.ok(iv.expires_at - ctx.clock.t <= INVITE_TTL_MS);
  // the heartbeat carries the inbox too
  tick(ctx, 5000);
  assert.equal((await beat(ctx, b)).body.invites.length, 1);
  // decline is recorded; a new invite may follow (within the pair limit)
  await call(ctx, 'POST', `/v1/invites/${iv.id}/decline`, {}, b.token);
  assert.equal((await rows(ctx, 'SELECT state FROM invites WHERE id = ?', iv.id))[0].state, 'declined');
  assert.equal((await call(ctx, 'GET', '/v1/invites', undefined, b.token)).body.invites.length, 0);
  assert.equal((await call(ctx, 'POST', `/v1/invites/${iv.id}/accept`, { build: BUILD, protocol: P }, b.token)).status, 410, 'a declined invite is over');
  const second = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
  assert.equal(second.status, 201);
  // expiry: five minutes later it can't be accepted and the sweep records it
  await wait(ctx, INVITE_TTL_MS + 1000, a, code);
  assert.equal((await call(ctx, 'GET', '/v1/invites', undefined, b.token)).body.invites.length, 0, 'expired invites are not shown');
  const late = await call(ctx, 'POST', `/v1/invites/${second.body.invite.id}/accept`, { build: BUILD, protocol: P }, b.token);
  assert.equal(late.status, 410);
  assert.equal(late.body.error, 'expired');
  assert.equal((await rows(ctx, 'SELECT state FROM invites WHERE id = ?', second.body.invite.id))[0].state, 'expired', 'expiry recorded');
  // per pair: a few invites per ten minutes
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, {}, a.token);
  await beat(ctx, b);
  let last;
  for (let i = 0; i < INVITE_PAIR_RATE.max + 1; i++) {
    const r = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
    if (r.status === 201) await call(ctx, 'POST', `/v1/invites/${r.body.invite.id}/decline`, {}, b.token);
    last = r;
  }
  assert.equal(last.status, 429, 'the same friend: rate limited');
  assert.equal(last.body.error, 'rate_limited');
  // per inviter: bounded overall
  const ctx2 = env();
  const s = await mk(ctx2, 'T:_spam', 'Busy Badger');
  await party(ctx2, s);
  let res;
  for (let i = 0; i <= INVITE_RATE.max; i++) res = await call(ctx2, 'POST', '/v1/invites', { to: `T:_x${i}` }, s.token);
  assert.equal(res.status, 429, 'every attempt counts, including failed ones');
  // the sweep forgets resolved invites after a day
  tick(ctx, 25 * 3600 * 1000);
  await sweep(ctx.env);
  assert.equal((await rows(ctx, 'SELECT * FROM invites')).length, 0);
});

test('accept re-checks everything: full, started, version, block, removed, inviter or host gone', async () => {
  const ctx = env();
  const h = await mk(ctx, 'T:_host', 'Host Otter');
  const g = await mk(ctx, 'T:_guest', 'Comfy Frog');
  const f = await mk(ctx, 'T:_friend', 'Snoozy Gecko');
  const x = await mk(ctx, 'T:_other', 'Moonlit Koala');
  await share(ctx, h, [f.tid]);
  await share(ctx, g, [f.tid]);
  await share(ctx, f, [h.tid, g.tid]);
  await beat(ctx, f);
  const code = await party(ctx, h, 3);
  const invite = async (from) => {
    const r = await call(ctx, 'POST', '/v1/invites', { to: f.tid }, from.token);
    assert.equal(r.status, 201, JSON.stringify(r.body));
    return r.body.invite.id;
  };
  const accept = (id, protocol = P) => call(ctx, 'POST', `/v1/invites/${id}/accept`, { build: BUILD, protocol }, f.token);
  // version
  let id = await invite(h);
  const old = await accept(id, P - 1);
  assert.equal(old.body.error, 'version_mismatch');
  assert.equal(old.body.message, 'Update the game to join this party.');
  // started
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'loading' }, h.token);
  assert.equal((await accept(id)).body.error, 'in_match');
  for (const st of ['in_match', 'results']) await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: st }, h.token);
  // full: two more members fill the three seats
  await joinConfirmed(ctx, h, g, code);
  const filler = await mk(ctx, 'T:_filler', 'Busy Badger');
  await joinConfirmed(ctx, h, filler, code);
  assert.equal((await accept(id)).body.error, 'full');
  await call(ctx, 'POST', `/v1/rooms/${code}/leave`, {}, filler.token);
  // a block between the friend and someone already in the party
  await call(ctx, 'POST', '/v1/blocks', { profile_id: f.pid }, g.token);
  assert.equal((await accept(id)).body.error, 'not_allowed');
  await call(ctx, 'DELETE', `/v1/blocks/${f.pid}`, undefined, g.token);
  // a guest's invite: names the guest and the host; void once the guest leaves
  tick(ctx, 1000);
  const gid = await invite(g);
  const inbox = (await call(ctx, 'GET', '/v1/invites', undefined, f.token)).body.invites;
  const gi = inbox.find((i) => i.id === gid);
  assert.equal(gi.from.name, 'Comfy Frog');
  assert.equal(gi.from_host, false, 'never presented as the host');
  assert.equal(gi.host_name, 'Host Otter');
  await call(ctx, 'POST', `/v1/rooms/${code}/leave`, {}, g.token);
  assert.equal((await accept(gid)).body.error, 'inviter_left');
  // removed by the host earlier: not allowed
  const rj = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, f.token);
  assert.equal(rj.status, 200);
  await call(ctx, 'POST', `/v1/rooms/${code}/kick`, { profile_id: f.pid }, h.token);
  assert.equal((await accept(id)).body.error, 'not_allowed', 'a removed player stays out');
  // the host leaves: the party ended
  const code2 = await party(ctx, h, 4);
  assert.notEqual(code2, code);
  tick(ctx, 1000);
  id = await invite(h);
  await call(ctx, 'POST', `/v1/rooms/${code2}/leave`, {}, h.token);
  const gone = await accept(id);
  assert.equal(gone.status, 410);
  assert.equal(gone.body.message, 'That party has ended.');
  assert.ok(x);
});

test('accept hands over to the normal join: same admission, same checks as a typed code', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Host Otter');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  const m = await mk(ctx, 'T:_member', 'Comfy Frog');
  await mutual(ctx, a, b);
  await beat(ctx, b);
  const code = await party(ctx, a, 4);
  await joinConfirmed(ctx, a, m, code);
  const inv = (await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token)).body.invite;
  const acc = await call(ctx, 'POST', `/v1/invites/${inv.id}/accept`, { build: BUILD, protocol: P }, b.token);
  assert.equal(acc.status, 200, JSON.stringify(acc.body));
  assert.equal(acc.body.code, code, 'the code of the inviter’s party');
  assert.equal(acc.body.host_name, 'Host Otter');
  assert.equal(acc.body.from_name, 'Host Otter');
  // a retry after a lost reply gets the same answer
  assert.equal((await call(ctx, 'POST', `/v1/invites/${inv.id}/accept`, { build: BUILD, protocol: P }, b.token)).body.code, code);
  // the join decides again: a block added after accepting still keeps B out
  await call(ctx, 'POST', '/v1/blocks', { profile_id: b.pid }, m.token);
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${acc.body.code}/join`, { build: BUILD, protocol: P }, b.token)).body.error, 'not_allowed');
  await call(ctx, 'DELETE', `/v1/blocks/${b.pid}`, undefined, m.token);
  const j = await call(ctx, 'POST', `/v1/rooms/${acc.body.code}/join`, { build: BUILD, protocol: P }, b.token);
  assert.equal(j.status, 200);
  const [hh, pp, ss] = j.body.admission.split('.');
  const v = createVerify('RSA-SHA256');
  v.update(`${hh}.${pp}`);
  assert.ok(v.verify(ctx.admPub, Buffer.from(ss, 'base64url')), 'the usual RS256 admission token');
  const claims = JSON.parse(Buffer.from(pp, 'base64url'));
  assert.equal(claims.gc, b.tid);
  assert.equal(claims.host, a.tid);
  assert.equal(claims.code, code);
  // once connected, presence says so (in your party) and the invite is used
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { connected: [b.pid] }, a.token);
  tick(ctx, 1500);
  await beat(ctx, b, { state: 'lobby', room: code });
  const pa = await presence(ctx, a);
  assert.equal(entry(pa, b.tid).in_your_party, true);
  assert.equal(entry(pa, b.tid).why, 'in_your_party');
  assert.equal((await rows(ctx, 'SELECT state FROM invites WHERE id = ?', inv.id))[0].state, 'accepted');
});

test('two players end to end (test harness): A in a lobby, B on Friends; invite, accept, join, round, back out', async () => {
  const ctx = env();
  const A = await mk(ctx, 'T:_aaaa', 'Comfy Frog');
  const B = await mk(ctx, 'T:_bbbb', 'Snoozy Gecko');
  // both opened Friends: each game uploads its own Game Center friends
  await share(ctx, A, [B.tid, 'T:_someone_else']);
  await share(ctx, B, [A.tid]);
  const code = await party(ctx, A);
  await beat(ctx, A, { state: 'lobby', room: code });
  await beat(ctx, B, { state: 'online' });
  // B sees A's real status; A sees B can be invited
  assert.equal(entry(await presence(ctx, B), A.tid).status, 'lobby');
  const ea = entry(await presence(ctx, A), B.tid);
  assert.deepEqual([ea.status, ea.can_invite], ['online', true]);
  const sent = await call(ctx, 'POST', '/v1/invites', { to: B.tid }, A.token);
  assert.equal(sent.status, 201);
  // B's next heartbeat delivers it
  tick(ctx, 20000);
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, {}, A.token);
  const hb = await beat(ctx, B);
  assert.equal(hb.body.invites.length, 1);
  const acc = await call(ctx, 'POST', `/v1/invites/${hb.body.invites[0].id}/accept`, { build: BUILD, protocol: P }, B.token);
  await joinConfirmed(ctx, A, B, acc.body.code);
  tick(ctx, 2000);
  await beat(ctx, B, { state: 'lobby', room: code });
  assert.equal(entry(await presence(ctx, A), B.tid).in_your_party, true);
  // the round starts: both show "in a round"
  for (const st of ['loading', 'in_match']) await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: st }, A.token);
  tick(ctx, 2000);
  await beat(ctx, A, { state: 'match', room: code });
  await beat(ctx, B, { state: 'match', room: code });
  assert.equal(entry(await presence(ctx, B), A.tid).status, 'match');
  // B backs out to Home, then goes to the background
  await call(ctx, 'POST', `/v1/rooms/${code}/leave`, {}, B.token);
  tick(ctx, 2000);
  await beat(ctx, B, { state: 'online' });
  assert.equal(entry(await presence(ctx, A), B.tid).status, 'online');
  await call(ctx, 'DELETE', '/v1/presence', { instance: B.inst }, B.token);
  assert.equal(entry(await presence(ctx, A), B.tid).status, 'offline');
  // B blocks A: both disappear for each other
  await call(ctx, 'POST', '/v1/blocks', { profile_id: A.pid }, B.token);
  assert.equal(entry(await presence(ctx, A), B.tid), undefined);
  assert.equal(entry(await presence(ctx, B), A.tid), undefined);
});

test('revoking friend access (DELETE /v1/friends), deletion and the 30-day age-out', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  await mutual(ctx, a, b);
  await beat(ctx, a);
  await beat(ctx, b);
  await party(ctx, a);
  const inv = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
  assert.equal(inv.status, 201);
  // B turns friend access off in Settings: the game clears B's data
  assert.equal((await call(ctx, 'DELETE', '/v1/friends', undefined, b.token)).status, 200);
  assert.deepEqual((await presence(ctx, a)).friends, [], 'A no longer sees B');
  assert.equal((await rows(ctx, 'SELECT * FROM friend_sets WHERE profile_id = ?', b.pid)).length, 0);
  assert.equal((await rows(ctx, 'SELECT * FROM presence WHERE profile_id = ?', b.pid)).length, 0);
  assert.equal((await rows(ctx, 'SELECT state FROM invites WHERE id = ?', inv.body.invite.id))[0].state, 'cancelled');
  // B shares again; then A deletes the profile: all of A's rows go
  await share(ctx, b, [a.tid]);
  await beat(ctx, b);
  await call(ctx, 'POST', '/v1/invites', { to: a.tid }, b.token);
  const fresh = await signIn(ctx, a.tid);
  assert.equal((await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token)).status, 200);
  for (const [t, col] of [['friend_sets', 'profile_id'], ['friend_claims', 'profile_id'], ['presence', 'profile_id'], ['invites', 'from_id'], ['invites', 'to_id']]) {
    assert.equal((await rows(ctx, `SELECT * FROM ${t} WHERE ${col} = ?`, a.pid)).length, 0, `${t}.${col} cleared`);
  }
  // a set nobody refreshes for 30 days ages out
  tick(ctx, FRIEND_SET_TTL_MS + 1000);
  await sweep(ctx.env);
  assert.equal((await rows(ctx, 'SELECT * FROM friend_sets')).length, 0, 'aged out');
  assert.equal((await rows(ctx, 'SELECT * FROM friend_claims')).length, 0);
});

test('stale friend sets do not count; a refresh restores the relationship', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_alice', 'Comfy Frog');
  const b = await mk(ctx, 'T:_bob', 'Snoozy Gecko');
  await mutual(ctx, a, b);
  tick(ctx, FRIEND_SET_TTL_MS + 1000);
  const a2 = { ...a, ...(await signIn(ctx, a.tid)) };
  const b2 = { ...b, ...(await signIn(ctx, b.tid)) };
  await beat(ctx, b2);
  assert.deepEqual((await presence(ctx, a2)).friends, [], "B's 30-day-old list no longer counts");
  await share(ctx, a2, [b.tid]);
  assert.deepEqual((await presence(ctx, a2)).friends, [], 'one fresh side is not enough');
  await share(ctx, b2, [a.tid]);
  assert.equal(entry(await presence(ctx, a2), b.tid).status, 'online');
});
