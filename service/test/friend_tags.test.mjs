// Friend tags and in-game friends (add by tag, no Game Center friendship),
// run against the whole API on the in-memory D1 (service/test/helpers.mjs).
// Several "players" are separate verified sessions in one process: test
// harness evidence of the service logic, not of a device.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeEnv, call, user, signIn, ADMIN } from './helpers.mjs';
import { sweep } from '../src/app.js';
import { parseTag, tagKey, formatTag, MAX_TAG_FRIENDS, MAX_PENDING_OUT, REQUEST_RATE, REQUEST_KEEP_MS } from '../src/friend_tags.js';

const P = 8;
const BUILD = 200;
const KEY = 'test-friend-hash-key-0123456789abcdefghijklmn';

function env(over = {}) {
  return makeEnv({ FRIEND_HASH_KEY: KEY, ...over });
}

async function mk(ctx, tid, name) {
  const u = await user(ctx, tid, name);
  return { ...u, tid, pid: u.profile.profile_id, tag: u.profile.friend_tag, seq: 0, inst: 'inst_' + tid.replace(/[^A-Za-z0-9]/g, '') + '_1' };
}
const add = (ctx, u, tag) => call(ctx, 'POST', '/v1/friends/requests', { tag }, u.token);
const lists = async (ctx, u) => {
  const r = await call(ctx, 'GET', '/v1/friends/requests', undefined, u.token);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body;
};
const accept = (ctx, u, id) => call(ctx, 'POST', `/v1/friends/requests/${id}/accept`, {}, u.token);
const decline = (ctx, u, id) => call(ctx, 'POST', `/v1/friends/requests/${id}/decline`, {}, u.token);
const rows = async (ctx, sql, ...a) => (await ctx.env.DB.prepare(sql).bind(...a).all()).results;
function beat(ctx, u, o = {}) {
  u.seq += 1;
  return call(ctx, 'POST', '/v1/presence', { instance: u.inst, seq: u.seq, state: o.state ?? 'online', room: o.room, protocol: P, build: BUILD }, u.token);
}
async function presence(ctx, u) {
  const r = await call(ctx, 'GET', '/v1/friends/presence', undefined, u.token);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body;
}
async function befriend(ctx, a, b) {
  const r = await add(ctx, a, b.tag);
  assert.equal(r.status, 201, JSON.stringify(r.body));
  const ok = await accept(ctx, b, r.body.request.id);
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
}
async function party(ctx, host) {
  const room = await call(ctx, 'POST', '/v1/rooms', { build: BUILD, protocol: P, capacity: 8 }, host.token);
  assert.equal(room.status, 201, JSON.stringify(room.body));
  const code = room.body.room.code;
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  return code;
}

test('parseTag: case, @, spaces and full-width forgiven; anything else is a clear error', () => {
  assert.deepEqual(parseTag('ComfyFrog#4821'), { ok: true, key: 'comfyfrog', disc: 4821 });
  assert.deepEqual(parseTag('  @comfyfrog#4821 '), { ok: true, key: 'comfyfrog', disc: 4821 });
  assert.deepEqual(parseTag('Comfy Frog # 0042'), { ok: true, key: 'comfyfrog', disc: 42 });
  assert.deepEqual(parseTag('ＣｏｍｆｙＦｒｏｇ＃４８２１'), { ok: true, key: 'comfyfrog', disc: 4821 }, 'full-width (NFKC)');
  for (const bad of ['', '   ', '@', 'ComfyFrog', 'ComfyFrog#', 'ComfyFrog#12345', 'ComfyFrog#0', 'ComfyFrog#12a', '#4821', 'Comfy-Frog#4821',
    'a#1234', 'x'.repeat(17) + '#1234', 42, null]) {
    const r = parseTag(bad);
    assert.equal(r.ok, false, `rejects ${JSON.stringify(bad)}`);
    assert.equal(r.error, 'bad_tag');
    assert.ok(r.message.length > 0 && r.message.length < 80, 'a short message');
  }
  assert.equal(tagKey('Comfy Frog'), 'comfyfrog');
  assert.equal(formatTag('Comfy Frog', 7), 'ComfyFrog#0007');
});

test('every named profile has a unique tag; it follows renames and keeps its number', async () => {
  const ctx = makeEnv();     // (tags work without FRIEND_HASH_KEY)
  assert.ok((await call(ctx, 'GET', '/v1/config')).body.features.includes('friend_tags'));
  const a = await mk(ctx, 'T:_a', 'Comfy Frog');
  assert.match(a.tag, /^ComfyFrog#\d{4}$/, 'name without spaces + 4 digits');
  assert.equal(a.tag, `ComfyFrog#${a.profile.discriminator}`, 'the same number as the shown name');
  const me = await call(ctx, 'GET', '/v1/me', undefined, a.token);
  assert.equal(me.body.profile.friend_tag, a.tag, '/v1/me has it');
  const t1 = await call(ctx, 'GET', '/v1/friends/me/tag', undefined, a.token);
  assert.equal(t1.body.tag, a.tag);
  // the same name and the same name without its space never share a tag
  const seen = new Set([a.tag.toLowerCase()]);
  for (let i = 0; i < 12; i++) {
    const u = await mk(ctx, `T:_dup${i}`, i % 2 ? 'Comfy Frog' : 'ComfyFrog');
    assert.ok(!seen.has(u.tag.toLowerCase()), `unique: ${u.tag}`);
    seen.add(u.tag.toLowerCase());
  }
  const all = await rows(ctx, 'SELECT tag_key, disc FROM friend_tags');
  assert.equal(new Set(all.map((r) => `${r.tag_key}#${r.disc}`)).size, all.length, 'unique in the table');
  // a nameless profile has no tag yet
  const n = await mk(ctx, 'T:_nameless');
  assert.equal(n.profile.friend_tag, null);
  const nt = await call(ctx, 'GET', '/v1/friends/me/tag', undefined, n.token);
  assert.equal(nt.body.tag, null);
  assert.equal(nt.body.needs_name, true);
  // rename (after the cooldown): the name part follows, the number stays
  ctx.clock.t += 25 * 3600 * 1000;
  a.token = (await signIn(ctx, 'T:_a')).token;     // (a day later: a fresh session)
  const disc = a.tag.split('#')[1];
  const rn = await call(ctx, 'POST', '/v1/me/name', { name: 'Sleepy Otter' }, a.token);
  assert.equal(rn.status, 200, JSON.stringify(rn.body));
  assert.equal(rn.body.profile.friend_tag, `SleepyOtter#${disc}`, 'renamed, same number');
  const b = await mk(ctx, 'T:_b', 'Busy Badger');
  assert.equal((await add(ctx, b, a.tag)).body.error, 'no_player', 'the old tag finds nobody now');
  assert.equal((await add(ctx, b, `SleepyOtter#${disc}`)).status, 201, 'the new one does');
  // renaming onto a name whose tag already uses that number: a new number
  const c = await mk(ctx, 'T:_c', 'Moonlit Koala');
  const cDisc = c.tag.split('#')[1];
  ctx.clock.t += 25 * 3600 * 1000;
  c.token = (await signIn(ctx, 'T:_c')).token;
  // (make "SleepyOtter#<c's number>" taken by someone else first)
  await ctx.env.DB.prepare('UPDATE friend_tags SET disc = ? WHERE profile_id = ?').bind(Number(cDisc), a.pid).run();
  await ctx.env.DB.prepare('UPDATE profiles SET discriminator = ? WHERE id = ?').bind(Number(cDisc), a.pid).run();
  const rc = await call(ctx, 'POST', '/v1/me/name', { name: 'Sleepy Otter' }, c.token);
  assert.equal(rc.status, 200);
  assert.match(rc.body.profile.friend_tag, /^SleepyOtter#\d{4}$/);
  assert.notEqual(rc.body.profile.friend_tag, `SleepyOtter#${cDisc}`, 'taken: another number');
  assert.equal(rc.body.profile.friend_tag, `SleepyOtter#${rc.body.profile.discriminator}`, 'still the shown number');
});

test('add by tag: case-insensitive, @ ignored; errors are short and clear; duplicates and both-ways requests', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_a', 'Comfy Frog');
  const b = await mk(ctx, 'T:_b', 'Snoozy Gecko');
  const c = await mk(ctx, 'T:_c', 'Moonlit Koala');
  // errors
  assert.equal((await add(ctx, a, 'nope')).body.error, 'bad_tag');
  assert.equal((await add(ctx, a, 'Nobody#1234')).status, 404);
  assert.equal((await add(ctx, a, 'Nobody#1234')).body.message, 'No player with that tag.');
  const self = await add(ctx, a, a.tag.toLowerCase());
  assert.equal(self.status, 400);
  assert.equal(self.body.error, 'self');
  // a request, by any spelling
  const r1 = await add(ctx, a, '@' + b.tag.toUpperCase());
  assert.equal(r1.status, 201, JSON.stringify(r1.body));
  assert.equal(r1.body.state, 'pending');
  assert.equal(r1.body.request.to.name, 'Snoozy Gecko');
  assert.equal(r1.body.request.to.tag, b.tag);
  const again = await add(ctx, a, b.tag);
  assert.equal(again.status, 200);
  assert.equal(again.body.duplicate, true);
  assert.equal(again.body.request.id, r1.body.request.id, 'asking twice: the same request');
  // lists: outgoing for A ("Requested"), incoming for B
  const la = await lists(ctx, a);
  assert.equal(la.tag, a.tag);
  assert.deepEqual(la.outgoing.map((x) => x.to.tag), [b.tag]);
  assert.deepEqual(la.incoming, []);
  const lb = await lists(ctx, b);
  assert.equal(lb.incoming.length, 1);
  assert.equal(lb.incoming[0].from.name, 'Comfy Frog');
  assert.equal(lb.incoming[0].from.tag, a.tag);
  assert.equal(lb.incoming[0].from.profile_id, a.pid, 'a profile for Report / Block');
  // the heartbeat counts requests waiting (for the badge)
  assert.equal((await beat(ctx, b)).body.requests, 1);
  assert.equal((await beat(ctx, a)).body.requests, 0);
  // only the receiver accepts
  assert.equal((await accept(ctx, a, r1.body.request.id)).status, 410);
  assert.equal((await accept(ctx, c, r1.body.request.id)).status, 410);
  assert.equal((await accept(ctx, b, 'frq_doesnotexist0')).status, 410);
  const ok = await accept(ctx, b, r1.body.request.id);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.friend.name, 'Comfy Frog');
  assert.equal((await accept(ctx, b, r1.body.request.id)).body.duplicate, true, 'a second tap is harmless');
  assert.deepEqual((await lists(ctx, a)).friends.map((f) => f.tag), [b.tag]);
  assert.deepEqual((await lists(ctx, b)).friends.map((f) => f.tag), [a.tag]);
  assert.deepEqual((await lists(ctx, a)).outgoing, [], 'no longer "Requested"');
  const dup = await add(ctx, b, a.tag);
  assert.equal(dup.status, 409);
  assert.equal(dup.body.error, 'already_friends');
  // both ask each other: the second request is the yes
  const rc = await add(ctx, c, a.tag);
  assert.equal(rc.status, 201);
  const back = await add(ctx, a, c.tag);
  assert.equal(back.status, 200);
  assert.equal(back.body.state, 'accepted', 'auto-accepted');
  assert.deepEqual((await lists(ctx, c)).friends.map((f) => f.tag), [a.tag]);
  assert.deepEqual((await lists(ctx, c)).outgoing, []);
  assert.deepEqual((await lists(ctx, a)).incoming, []);
  // decline (receiver) and cancel (sender): nothing is kept pending
  const d = await mk(ctx, 'T:_d', 'Quiet Duck');
  const rd = await add(ctx, d, b.tag);
  assert.equal((await decline(ctx, b, rd.body.request.id)).status, 200);
  assert.deepEqual((await lists(ctx, b)).incoming, []);
  assert.deepEqual((await lists(ctx, d)).outgoing, [], 'the sender sees it gone (never "declined")');
  assert.equal((await accept(ctx, b, rd.body.request.id)).status, 410, 'a declined request can not be accepted later');
  const rd2 = await add(ctx, d, b.tag);
  assert.equal(rd2.status, 201, 'asking again later is allowed');
  assert.equal((await call(ctx, 'DELETE', `/v1/friends/requests/${rd2.body.request.id}`, undefined, d.token)).status, 200);
  assert.deepEqual((await lists(ctx, b)).incoming, [], 'cancelled by the sender');
  // remove a friend
  assert.equal((await call(ctx, 'DELETE', `/v1/friends/${b.pid}`, undefined, a.token)).status, 200);
  assert.deepEqual((await lists(ctx, a)).friends.map((f) => f.tag), [c.tag]);
  assert.deepEqual((await lists(ctx, b)).friends, []);
  // a player without a name can't send one
  const n = await mk(ctx, 'T:_n');
  const rn = await add(ctx, n, a.tag);
  assert.equal(rn.status, 409);
  assert.equal(rn.body.error, 'needs_name');
});

test('blocks either way: the tag finds nobody, the friendship and requests end, accepting fails', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_a', 'Comfy Frog');
  const b = await mk(ctx, 'T:_b', 'Snoozy Gecko');
  const c = await mk(ctx, 'T:_c', 'Moonlit Koala');
  await call(ctx, 'POST', '/v1/blocks', { profile_id: a.pid }, b.token);
  const r = await add(ctx, a, b.tag);
  assert.equal(r.status, 404);
  assert.equal(r.body.message, 'No player with that tag.', 'blocked by them: the same answer as an unknown tag');
  const r2 = await add(ctx, b, a.tag);
  assert.equal(r2.status, 404, 'and the blocker can not add them either');
  await call(ctx, 'DELETE', `/v1/blocks/${a.pid}`, undefined, b.token);
  // friends, then a block: gone from both lists and from presence
  await befriend(ctx, a, b);
  await beat(ctx, a);
  await beat(ctx, b);
  assert.equal((await presence(ctx, a)).friends.length, 1);
  await call(ctx, 'POST', '/v1/blocks', { profile_id: b.pid }, a.token);
  assert.deepEqual((await lists(ctx, a)).friends, []);
  assert.deepEqual((await lists(ctx, b)).friends, []);
  assert.deepEqual((await presence(ctx, b)).friends, [], 'no status across a block');
  await call(ctx, 'DELETE', `/v1/blocks/${b.pid}`, undefined, a.token);
  assert.deepEqual((await lists(ctx, a)).friends, [], 'unblocking does not make them friends again');
  // a pending request, then a block: it can not be accepted
  const rc = await add(ctx, c, a.tag);
  await call(ctx, 'POST', '/v1/blocks', { profile_id: a.pid }, c.token);
  assert.deepEqual((await lists(ctx, a)).incoming, [], 'a blocker\'s request is not shown');
  assert.equal((await accept(ctx, a, rc.body.request.id)).status, 410);
  assert.deepEqual((await lists(ctx, a)).friends, []);
});

test('suspended and renamed-by-moderation players can not be found; caps and rate limits', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_a', 'Comfy Frog');
  const b = await mk(ctx, 'T:_b', 'Snoozy Gecko');
  const m = await mk(ctx, 'T:_m', 'Rude Name');
  // moderation hid m's name: no tag, not findable, its old tag row never matches
  await ctx.env.DB.prepare('UPDATE profiles SET forced_rename = 1 WHERE id = ?').bind(m.pid).run();
  assert.equal((await add(ctx, a, m.tag)).body.error, 'no_player');
  assert.equal((await call(ctx, 'GET', '/v1/friends/me/tag', undefined, m.token)).body.tag, null);
  // suspended: not findable
  await ctx.env.DB.prepare("UPDATE profiles SET status = 'suspended', suspended_until = ? WHERE id = ?").bind(ctx.clock.t + 3600000, b.pid).run();
  assert.equal((await add(ctx, a, b.tag)).body.error, 'no_player');
  await ctx.env.DB.prepare("UPDATE profiles SET status = 'active', suspended_until = NULL WHERE id = ?").bind(b.pid).run();
  // the friend cap (both sides)
  const ins = ctx.env.DB.prepare('INSERT INTO friend_links (a_id, b_id, created_at) VALUES (?, ?, ?)');
  for (let i = 0; i < MAX_TAG_FRIENDS; i++) await ins.bind(a.pid, `p_zzfake${String(i).padStart(4, '0')}`, 1).run();
  const full = await add(ctx, a, b.tag);
  assert.equal(full.status, 409);
  assert.equal(full.body.error, 'friends_full');
  const theirs = await add(ctx, b, a.tag);
  assert.equal(theirs.body.error, 'their_friends_full');
  await ctx.env.DB.prepare("DELETE FROM friend_links WHERE b_id LIKE 'p_zzfake%'").run();
  // waiting requests from one player are capped
  await ctx.env.DB.prepare('DELETE FROM rate_events').run();
  const reqIns = ctx.env.DB.prepare("INSERT INTO friend_requests (id, from_id, to_id, state, created_at) VALUES (?, ?, ?, 'pending', ?)");
  for (let i = 0; i < MAX_PENDING_OUT; i++) await reqIns.bind(`frq_fake${String(i).padStart(8, '0')}`, a.pid, `p_zzfake${String(i).padStart(4, '0')}`, ctx.clock.t).run();
  assert.equal((await add(ctx, a, b.tag)).body.error, 'too_many_requests');
  await ctx.env.DB.prepare("DELETE FROM friend_requests WHERE to_id LIKE 'p_zzfake%'").run();
  // rate limit: every try counts, unknown tags too (no bulk guessing)
  await ctx.env.DB.prepare('DELETE FROM rate_events').run();
  for (let i = 0; i < REQUEST_RATE.max; i++) await add(ctx, a, `Guess${i}#1234`);
  const limited = await add(ctx, a, b.tag);
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, 'rate_limited');
  ctx.clock.t += REQUEST_RATE.windowMs + 1000;
  assert.equal((await add(ctx, a, b.tag)).status, 201, 'fine again later');
});

test('in-game friends get status and invites exactly like Game Center friends (no friend list shared)', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_a', 'Comfy Frog');
  const b = await mk(ctx, 'T:_b', 'Snoozy Gecko');
  const c = await mk(ctx, 'T:_c', 'Moonlit Koala');
  for (const u of [a, b, c]) await beat(ctx, u);
  assert.deepEqual((await presence(ctx, a)).friends, [], 'not friends yet');
  await befriend(ctx, a, b);
  const pa = await presence(ctx, a);
  assert.equal(pa.shared, false, 'no Game Center list was ever shared');
  assert.equal(pa.friends.length, 1);
  const eb = pa.friends[0];
  assert.equal(eb.id, b.tid, 'keyed by the verified Game Center ID, like any friend');
  assert.equal(eb.name, 'Snoozy Gecko');
  assert.equal(eb.tag, b.tag);
  assert.equal(eb.source, 'tag');
  assert.equal(eb.status, 'online');
  assert.equal(eb.can_invite, true);
  // invite into a party, accept, join through the normal admission
  const code = await party(ctx, a);
  await beat(ctx, a, { state: 'lobby', room: code });
  const iv = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
  assert.equal(iv.status, 201, JSON.stringify(iv.body));
  const hb = await beat(ctx, b);
  assert.equal(hb.body.invites.length, 1, 'the invite reaches B');
  const acc = await call(ctx, 'POST', `/v1/invites/${iv.body.invite.id}/accept`, { protocol: P, build: BUILD }, b.token);
  assert.equal(acc.status, 200, JSON.stringify(acc.body));
  assert.equal(acc.body.code, code);
  const j = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token);
  assert.equal(j.status, 200);
  // C is nobody's friend: same generic refusal
  const nc = await call(ctx, 'POST', '/v1/invites', { to: c.tid }, a.token);
  assert.equal(nc.status, 404);
  assert.equal(nc.body.error, 'not_friend');
  // a Game Center pair that also added each other: one row, source both
  await call(ctx, 'PUT', '/v1/friends', { ids: [c.tid] }, a.token);
  await call(ctx, 'PUT', '/v1/friends', { ids: [a.tid] }, c.token);
  await befriend(ctx, c, a);
  const both = (await presence(ctx, a)).friends.find((f) => f.id === c.tid);
  assert.equal(both.source, 'both');
  assert.equal((await presence(ctx, a)).friends.filter((f) => f.id === c.tid).length, 1, 'listed once');
  // removed: no more status, invites refused, a pending invite ends
  await call(ctx, 'DELETE', `/v1/friends/${a.pid}`, undefined, b.token);
  assert.equal((await presence(ctx, a)).friends.find((f) => f.id === b.tid), undefined);
  const after = await call(ctx, 'POST', '/v1/invites', { to: b.tid }, a.token);
  assert.equal(after.status, 404);
  // suspended friends drop out of presence
  await befriend(ctx, a, b);
  await ctx.env.DB.prepare("UPDATE profiles SET status = 'suspended', suspended_until = ? WHERE id = ?").bind(ctx.clock.t + 3600000, b.pid).run();
  assert.equal((await presence(ctx, a)).friends.find((f) => f.id === b.tid), undefined, 'suspended: hidden');
});

test('tags and requests work without the friend hash key (presence stays honestly unavailable)', async () => {
  const ctx = makeEnv();
  const a = await mk(ctx, 'T:_a', 'Comfy Frog');
  const b = await mk(ctx, 'T:_b', 'Snoozy Gecko');
  await befriend(ctx, a, b);
  assert.equal((await lists(ctx, a)).friends.length, 1);
  assert.equal((await call(ctx, 'GET', '/v1/friends/presence', undefined, a.token)).status, 503);
});

test('deleting a profile erases its tag, friendships and requests; old requests are swept', async () => {
  const ctx = env();
  const a = await mk(ctx, 'T:_a', 'Comfy Frog');
  const b = await mk(ctx, 'T:_b', 'Snoozy Gecko');
  const c = await mk(ctx, 'T:_c', 'Moonlit Koala');
  await befriend(ctx, a, b);
  await add(ctx, a, c.tag);
  await add(ctx, c, b.tag);
  const del = await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, a.token);
  assert.equal(del.status, 200, JSON.stringify(del.body));
  assert.equal((await rows(ctx, 'SELECT * FROM friend_tags WHERE profile_id = ?', a.pid)).length, 0);
  assert.equal((await rows(ctx, 'SELECT * FROM friend_links WHERE a_id = ? OR b_id = ?', a.pid, a.pid)).length, 0);
  assert.equal((await rows(ctx, 'SELECT * FROM friend_requests WHERE from_id = ? OR to_id = ?', a.pid, a.pid)).length, 0);
  assert.deepEqual((await lists(ctx, b)).friends, []);
  assert.equal((await add(ctx, b, a.tag)).body.error, 'no_player', 'the tag is free of them');
  // the sweep: requests older than 30 days go
  assert.equal((await rows(ctx, 'SELECT * FROM friend_requests')).length, 1);
  ctx.clock.t += REQUEST_KEEP_MS + 1000;
  await sweep(ctx.env);
  assert.equal((await rows(ctx, 'SELECT * FROM friend_requests')).length, 0);
  // (admin view still works for the remaining profile)
  assert.equal((await call(ctx, 'GET', `/v1/admin/profiles/${b.pid}`, undefined, undefined, ADMIN)).status, 200);
});
