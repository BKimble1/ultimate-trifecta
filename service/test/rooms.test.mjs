import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createVerify } from 'node:crypto';
import { makeEnv, call, user } from './helpers.mjs';
import { normalizeCode, newRoomCode, CODE_ALPHABET } from '../src/ids.js';

const P = 4;      // protocol
const BUILD = 30;

async function party(ctx, n = 2) {
  const host = await user(ctx, 'T:_host', 'Host Otter');
  const room = await call(ctx, 'POST', '/v1/rooms', { build: BUILD, protocol: P, capacity: n }, host.token);
  assert.equal(room.status, 201);
  await call(ctx, 'POST', `/v1/rooms/${room.body.room.code}/heartbeat`, { state: 'open' }, host.token);
  return { host, code: room.body.room.code, room: room.body.room };
}

test('party codes: 6 unambiguous characters; typing is forgiven for case, spaces and dashes only', () => {
  for (let i = 0; i < 200; i++) {
    const c = newRoomCode();
    assert.equal(c.length, 6);
    for (const ch of c) assert.ok(CODE_ALPHABET.includes(ch));
  }
  for (const ch of '01IOLSZB5') assert.ok(!CODE_ALPHABET.includes(ch), `no look-alike ${ch}`);
  assert.deepEqual(normalizeCode(' acd-efg '), { ok: true, code: 'ACDEFG' });
  assert.equal(normalizeCode('ACDEF').error, 'code_format');
  assert.ok(normalizeCode('ACDEFGH').message.includes('7'), 'too long is an error, never truncated');
  assert.equal(normalizeCode('ACDEF0').ok, false, 'a character outside the alphabet is an error, never dropped');
  assert.equal(normalizeCode('ACD!FG').ok, false);
  assert.equal(normalizeCode(42).ok, false);
});

test('create, join with admission, version sync, capacity, own room, needs a name', async () => {
  const ctx = makeEnv();
  const { host, code } = await party(ctx, 3);
  const noname = await user(ctx, 'T:_nn');
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, noname.token)).body.error, 'needs_name');
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, host.token)).body.error, 'own_room');
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const old = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: 20, protocol: 3 }, a.token);
  assert.equal(old.body.error, 'version_mismatch');
  assert.equal(old.body.host_protocol, P);
  const j = await call(ctx, 'POST', `/v1/rooms/${code.toLowerCase()}/join`, { build: BUILD, protocol: P }, a.token);
  assert.equal(j.status, 200);
  assert.equal(j.body.slot, 1);
  assert.equal(j.body.host_gc_player, 'T:_host', 'the joiner learns which Game Center player is the host');
  // the admission credential verifies with the service public key and binds room, player, slot
  const [h, p, s] = j.body.admission.split('.');
  const v = createVerify('RSA-SHA256');
  v.update(`${h}.${p}`);
  assert.ok(v.verify(ctx.admPub, Buffer.from(s, 'base64url')), 'RS256 signature verifies');
  const claims = JSON.parse(Buffer.from(p, 'base64url'));
  assert.equal(claims.gc, 'T:_a');
  assert.equal(claims.slot, 1);
  assert.equal(claims.code, code);
  assert.equal(claims.aud, 'trifecta-host');
  assert.ok(claims.exp - claims.iat <= 120, 'short-lived');
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token)).body.slot, 2);
  const c = await user(ctx, 'T:_c', 'Moonlit Koala');
  const full = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, c.token);
  assert.equal(full.body.error, 'full');
  assert.equal((await call(ctx, 'GET', `/v1/rooms/${code}`, undefined, c.token)).body.room.state, 'full');
});

test('distinct errors: unknown code, ended party, round in progress, host still setting up', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  assert.equal((await call(ctx, 'POST', '/v1/rooms/ACDEFG/join', { build: BUILD, protocol: P }, a.token)).body.error, 'not_found');
  assert.equal((await call(ctx, 'POST', '/v1/rooms/ACD/join', { build: BUILD, protocol: P }, a.token)).body.error, 'code_format');
  const host = await user(ctx, 'T:_host', 'Host Otter');
  const room = await call(ctx, 'POST', '/v1/rooms', { build: BUILD, protocol: P }, host.token);
  const code = room.body.room.code;
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token)).body.error, 'not_ready');
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'loading' }, host.token);
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'in_match' }, host.token);
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token)).body.error, 'in_match');
  ctx.clock.t += 46 * 1000;   // the host stopped sending heartbeats
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token)).body.error, 'expired');
});

test('only the host updates the room; transitions follow the lifecycle', async () => {
  const ctx = makeEnv();
  const { host, code } = await party(ctx);
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token);
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'loading' }, a.token)).body.error, 'not_host');
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'results' }, host.token)).body.error, 'bad_transition');
  for (const s of ['loading', 'in_match', 'results', 'open']) {
    assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: s }, host.token)).status, 200, `-> ${s}`);
  }
  await call(ctx, 'POST', `/v1/rooms/${code}/leave`, {}, host.token);
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token)).body.error, 'expired', 'host leaving closes the party');
});

test('reconnecting keeps your own slot; nobody can take a slot that is held', async () => {
  const ctx = makeEnv();
  const { host, code } = await party(ctx, 4);
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  const ja = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token);
  const jb = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token);
  assert.deepEqual([ja.body.slot, jb.body.slot], [1, 2]);
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { connected: [ja.body && (await call(ctx, 'GET', '/v1/me', undefined, a.token)).body.profile.profile_id] }, host.token);
  const again = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token);
  assert.equal(again.body.slot, 1, 'same slot after a reconnect');
  // concurrent joins never share a slot
  const others = [];
  for (const id of ['c', 'd']) others.push(await user(ctx, 'T:_' + id, 'Player ' + id.toUpperCase() + 'x'));
  const res = await Promise.all(others.map((u) => call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, u.token)));
  const slots = res.filter((r) => r.status === 200).map((r) => r.body.slot);
  assert.equal(new Set(slots).size, slots.length, 'distinct slots');
  assert.ok(slots.every((s) => s >= 3), 'held slots 1 and 2 were not taken');
});

test('blocks and removals: a blocked or removed player cannot get in', async () => {
  const ctx = makeEnv();
  const { host, code } = await party(ctx, 4);
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  const c = await user(ctx, 'T:_c', 'Moonlit Koala');
  await call(ctx, 'POST', '/v1/blocks', { profile_id: a.profile.profile_id }, host.token);
  const ra = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token);
  assert.equal(ra.body.error, 'not_allowed', 'host blocked them');
  assert.ok(!ra.body.message.toLowerCase().includes('block'), 'without saying who blocked whom');
  const jb = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token);
  assert.equal(jb.status, 200);
  await call(ctx, 'POST', '/v1/blocks', { profile_id: b.profile.profile_id }, c.token);
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, c.token)).body.error, 'not_allowed', 'blocks between members count too');
  await call(ctx, 'POST', `/v1/rooms/${code}/kick`, { profile_id: b.profile.profile_id }, host.token);
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token)).body.error, 'not_allowed', 'removed players stay out of this party');
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/kick`, { profile_id: c.profile.profile_id }, b.token)).body.error, 'not_host');
});

test('one live party per host; unconnected reservations lapse', async () => {
  const ctx = makeEnv();
  const { host, code } = await party(ctx, 2);
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token);
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token)).body.error, 'full');
  // a never connects over Game Center; the host keeps the room alive
  for (let i = 0; i < 7; i++) {
    ctx.clock.t += 15 * 1000;
    await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, {}, host.token);
  }
  const jb = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token);
  assert.equal(jb.status, 200, 'the lapsed reservation freed the slot');
  const second = await call(ctx, 'POST', '/v1/rooms', { build: BUILD, protocol: P }, host.token);
  assert.equal(second.status, 201);
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token)).body.error, 'expired', 'the old party closed');
});
