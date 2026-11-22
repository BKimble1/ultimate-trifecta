// Party-code relay (src/relay.js).  The routing runs as a plain class
// (RelayCore) over a small fake of the Durable Object's hibernation API; the
// Worker-side checks run through the whole API (handle()) with a stand-in
// RELAY binding that records what would reach the Durable Object.  The real
// Durable Object and WebSockets are exercised by tools/relay_e2e.sh
// (wrangler dev, two Godot sessions).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeEnv, call, user } from './helpers.mjs';
import { RelayCore, CLOSE, CONTROL, CTRL_JOINED, CTRL_LEFT, LIMITS, STRIKES_TO_CLOSE, MAX_FRAME } from '../src/relay.js';

// ------------------------------------------------------------ the fake
class FakeWs {
  constructor(name) {
    this.name = name;
    this.sent = [];
    this.closed = null;
    this.tags = [];
    this._att = null;
  }
  send(b) {
    if (this.closed) throw new Error('send on a closed socket');
    this.sent.push(Uint8Array.from(b));
  }
  close(code, reason) {
    if (!this.closed) this.closed = { code, reason };
  }
  serializeAttachment(a) {
    this._att = structuredClone(a);
  }
  deserializeAttachment() {
    return this._att ? structuredClone(this._att) : null;
  }
  take() {
    const s = this.sent;
    this.sent = [];
    return s;
  }
}

class FakeCtx {
  constructor() {
    this.sockets = [];
  }
  acceptWebSocket(ws, tags) {
    ws.tags = tags;
    this.sockets.push(ws);
  }
  getWebSockets(tag) {
    return this.sockets.filter((w) => !w.closed && (!tag || w.tags.includes(tag)));
  }
}

const u16 = (n) => [(n >> 8) & 0xff, n & 0xff];
const bytes = (...a) => new Uint8Array(a.flat());
const toHost = (to, ...payload) => bytes(u16(to), payload);
const ctrl = (f) => ({ kind: f[2], peer: (f[3] << 8) | f[4], player: new TextDecoder().decode(f.subarray(5)) });
const isCtrl = (f) => ((f[0] << 8) | f[1]) === CONTROL;

function relay(opts = {}) {
  const clock = { t: 1_000_000 };
  const ctx = new FakeCtx();
  const core = new RelayCore(ctx, { now: () => clock.t, ...opts });
  return { ctx, core, clock };
}

function hostIn(r, room = 'room_a') {
  const h = new FakeWs('host');
  assert.deepEqual(r.core.accept(h, { role: 'host', pid: 'p_host', gc: 'G:host', room }), { ok: true, peer: 1 });
  return h;
}

function guestIn(r, n, room = 'room_a') {
  const g = new FakeWs('g' + n);
  const res = r.core.accept(g, { role: 'guest', pid: 'p_' + n, gc: 'G:' + n, room });
  return { g, res };
}

// ------------------------------------------------------------ routing
test('relay: guests get ids from 2, the host hears who joined (with their verified player), frames are routed both ways', () => {
  const r = relay();
  const h = hostIn(r);
  const a = guestIn(r, 'a');
  const b = guestIn(r, 'b');
  assert.equal(a.res.peer, 2);
  assert.equal(b.res.peer, 3);
  const joins = h.take();
  assert.equal(joins.length, 2);
  for (const f of joins) assert.ok(isCtrl(f), 'control frames start 0xFFFF');
  assert.deepEqual(ctrl(joins[0]), { kind: CTRL_JOINED, peer: 2, player: 'G:a' });
  assert.deepEqual(ctrl(joins[1]), { kind: CTRL_JOINED, peer: 3, player: 'G:b' });
  // guest -> host: payload only in, [u16 from][payload] out
  r.core.message(a.g, bytes(9, 8, 7).buffer);
  assert.deepEqual([...h.take()[0]], [0, 2, 9, 8, 7]);
  r.core.message(b.g, bytes(1));
  assert.deepEqual([...h.take()[0]], [0, 3, 1]);
  // host -> one guest: [u16 to][payload] in, payload only out
  r.core.message(h, toHost(3, 5, 5));
  assert.deepEqual(b.g.take().map((x) => [...x]), [[5, 5]]);
  assert.equal(a.g.sent.length, 0, 'only the addressed guest');
  // host -> everyone: to = 0, one frame in, one copy each
  r.core.message(h, toHost(0, 42));
  assert.deepEqual(a.g.take().map((x) => [...x]), [[42]]);
  assert.deepEqual(b.g.take().map((x) => [...x]), [[42]]);
  // nobody gets frames addressed to the host itself, the control id or an unknown peer
  for (const to of [1, CONTROL, 77]) r.core.message(h, toHost(to, 1));
  assert.equal(a.g.sent.length + b.g.sent.length, 0);
  // empty payloads go nowhere
  r.core.message(h, bytes(u16(2)));
  r.core.message(a.g, new Uint8Array(0));
  assert.equal(a.g.sent.length + h.sent.length, 0);
});

test('relay: a guest leaving is told to the host; the host leaving closes every guest (4000 host left)', () => {
  const r = relay();
  const h = hostIn(r);
  const a = guestIn(r, 'a');
  const b = guestIn(r, 'b');
  h.take();
  a.g.closed = { code: 1000 };
  r.core.closed(a.g, 1000, 'bye');
  const left = h.take();
  assert.equal(left.length, 1);
  assert.deepEqual(ctrl(left[0]), { kind: CTRL_LEFT, peer: 2, player: 'G:a' });
  r.core.closed(a.g, 1000, 'bye');
  assert.equal(h.sent.length, 0, 'a close is reported once');
  h.closed = { code: 1001 };
  r.core.closed(h, 1001, 'going away');
  assert.deepEqual(b.g.closed, { code: CLOSE.HOST_LEFT, reason: 'host left' });
});

test('relay: no host yet -> 4002; at most 7 guests -> 4003; ids are never shared by live guests', () => {
  const r = relay();
  const early = guestIn(r, 'early');
  assert.equal(early.res.ok, false);
  assert.equal(early.g.closed.code, CLOSE.NO_HOST);
  const h = hostIn(r);
  const gs = [];
  for (let i = 0; i < 7; i++) gs.push(guestIn(r, i));
  assert.ok(gs.every((x) => x.res.ok));
  assert.deepEqual(gs.map((x) => x.res.peer), [2, 3, 4, 5, 6, 7, 8]);
  const eighth = guestIn(r, 'eighth');
  assert.equal(eighth.res.ok, false);
  assert.equal(eighth.g.closed.code, CLOSE.FULL);
  h.take();
  r.core.message(eighth.g, bytes(1, 2, 3));
  assert.equal(h.sent.length, 0, 'a refused socket relays nothing');
  // a seat frees up: the newcomer gets an id nobody live holds
  gs[0].g.closed = { code: 1000 };
  r.core.closed(gs[0].g, 1000, '');
  const next = guestIn(r, 'next');
  assert.ok(next.res.ok);
  const live = r.core.live('guest').map((w) => w.deserializeAttachment().peer);
  assert.equal(new Set(live).size, live.length, 'unique ids');
  assert.ok(!live.includes(1), 'never the host id');
});

test('relay: the same player reconnecting replaces their old socket; a reconnecting host keeps the guests', () => {
  const r = relay();
  const h = hostIn(r);
  const a1 = guestIn(r, 'a');
  h.take();
  const a2 = guestIn(r, 'a');
  assert.equal(a1.g.closed.code, CLOSE.REPLACED);
  const f = h.take().map(ctrl);
  assert.deepEqual(f.map((x) => [x.kind, x.peer]), [[CTRL_LEFT, 2], [CTRL_JOINED, a2.res.peer]]);
  r.core.closed(a1.g, CLOSE.REPLACED, 'replaced');
  assert.equal(h.sent.length, 0, 'the replaced socket closing says nothing more');
  // the host on a new connection: the old one is closed, guests stay, and the
  // new host hears about everyone already here
  const h2 = new FakeWs('host2');
  r.core.accept(h2, { role: 'host', pid: 'p_host', gc: 'G:host', room: 'room_a' });
  assert.equal(h.closed.code, CLOSE.REPLACED);
  assert.deepEqual(h2.take().map(ctrl).map((x) => [x.kind, x.peer, x.player]), [[CTRL_JOINED, a2.res.peer, 'G:a']]);
  r.core.closed(h, CLOSE.REPLACED, 'replaced');
  assert.equal(a2.g.closed, null, 'the old host socket closing does not end the party');
  r.core.message(a2.g, bytes(4));
  assert.deepEqual([...h2.take()[0]], [...u16(a2.res.peer), 4]);
});

test('relay: a new party with the same code (another room id) ends the old room\'s guests', () => {
  const r = relay();
  hostIn(r, 'room_old');
  const a = guestIn(r, 'a', 'room_old');
  const h2 = new FakeWs('newhost');
  r.core.accept(h2, { role: 'host', pid: 'p_other', gc: 'G:other', room: 'room_new' });
  assert.equal(a.g.closed.code, CLOSE.HOST_LEFT);
  assert.equal(h2.sent.length, 0, 'the new host hears nothing of the old room');
});

test('relay: state survives hibernation (a fresh RelayCore over the same sockets keeps routing)', () => {
  const r = relay();
  const h = hostIn(r);
  const a = guestIn(r, 'a');
  h.take();
  const woken = new RelayCore(r.ctx, { now: () => r.clock.t });
  woken.message(a.g, bytes(3));
  assert.deepEqual([...h.take()[0]], [0, 2, 3]);
  woken.message(h, toHost(2, 6));
  assert.deepEqual([...a.g.take()[0]], [6]);
  const b = new FakeWs('b');
  assert.equal(woken.accept(b, { role: 'guest', pid: 'p_b', gc: 'G:b', room: 'room_a' }).peer, 3, 'no id reused for a live guest after waking');
});

test('relay: frames over 64 KB close the sender (1009); text frames are dropped', () => {
  const r = relay();
  const h = hostIn(r);
  const a = guestIn(r, 'a');
  h.take();
  r.core.message(a.g, 'hello');
  assert.equal(h.sent.length, 0, 'text is not relayed');
  r.core.message(a.g, new Uint8Array(MAX_FRAME));
  assert.equal(h.take().length, 1, 'exactly 64 KB is fine');
  r.core.message(h, new Uint8Array(MAX_FRAME + 2).fill(0, 0, 2));
  assert.equal(h.closed, null, 'the host may send 64 KB plus its 2-byte header');
  r.core.message(a.g, new Uint8Array(MAX_FRAME + 1));
  assert.equal(a.g.closed.code, CLOSE.TOO_BIG);
  const left = h.take().map(ctrl);
  assert.deepEqual(left.map((x) => x.kind), [CTRL_LEFT], 'the host is told the guest is gone');
});

test('relay: a flooding sender has the excess dropped, and one that keeps flooding is closed (1008)', () => {
  const r = relay();
  const h = hostIn(r);
  const a = guestIn(r, 'a');
  h.take();
  const lim = LIMITS.guest.msgs;
  for (let i = 0; i < lim + 50; i++) r.core.message(a.g, bytes(1));
  assert.equal(h.take().length, lim, 'over the per-second budget: dropped');
  // a normal second resets the run
  r.clock.t += 1000;
  for (let i = 0; i < 60; i++) r.core.message(a.g, bytes(1));
  assert.equal(h.take().length, 60);
  // flooding several seconds in a row closes the socket
  for (let s = 0; s < STRIKES_TO_CLOSE; s++) {
    r.clock.t += 1000;
    for (let i = 0; i < lim + 5; i++) r.core.message(a.g, bytes(1));
  }
  assert.equal(a.g.closed.code, CLOSE.FLOOD);
  assert.ok(h.take().some((f) => isCtrl(f) && ctrl(f).kind === CTRL_LEFT));
  // the host's budget is larger (it fans out to up to 7 guests)
  assert.ok(LIMITS.host.msgs >= 7 * LIMITS.guest.msgs / 2);
});

// ------------------------------------------------------------ the Worker side
const P = 4;
const BUILD = 30;

function relayEnv() {
  const ctx = makeEnv();
  const seen = [];
  ctx.env.RELAY = {
    idFromName: (n) => ({ name: n }),
    get: (id) => ({
      fetch: async (req) => {
        const hd = Object.fromEntries([...req.headers]);
        seen.push({ code: id.name, headers: hd });
        return new Response(JSON.stringify({ ok: true, relayed: true }), { status: 200 });
      },
    }),
  };
  return { ctx, seen };
}

const WS = { upgrade: 'websocket', connection: 'Upgrade' };

async function openParty(ctx) {
  const host = await user(ctx, 'T:_host', 'Host Otter');
  const room = await call(ctx, 'POST', '/v1/rooms', { build: BUILD, protocol: P, capacity: 8 }, host.token);
  assert.equal(room.status, 201);
  const code = room.body.room.code;
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  return { host, code, roomId: room.body.room.room_id };
}

test('relay endpoint: the host of the room (token in the query) is handed to the room\'s relay with its verified identity', async () => {
  const { ctx, seen } = relayEnv();
  const { host, code, roomId } = await openParty(ctx);
  assert.ok((await call(ctx, 'GET', '/v1/config')).body.features.includes('relay'), 'the deployment offers the relay');
  const r = await call(ctx, 'GET', `/v1/relay/${code.toLowerCase()}?role=host&token=${encodeURIComponent(host.token)}`, undefined, null,
    { ...WS, 'x-relay-role': 'guest', 'x-relay-profile': 'p_spoofed', 'x-relay-player': 'G:spoofed' });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(seen.length, 1);
  assert.equal(seen[0].code, code, 'one relay per (normalised) room code');
  assert.equal(seen[0].headers['x-relay-role'], 'host');
  assert.equal(seen[0].headers['x-relay-profile'], host.profile.profile_id, 'what the client claims is overwritten');
  assert.equal(seen[0].headers['x-relay-player'], 'T:_host');
  assert.equal(seen[0].headers['x-relay-room'], roomId);
  assert.equal(seen[0].headers.upgrade, 'websocket', 'the upgrade goes through');
  assert.equal(seen[0].headers.authorization, undefined, 'the session token does not');
  // the header works as well as the query
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=host`, undefined, host.token, WS)).status, 200);
});

test('relay endpoint: guests need a place from /join; blocks, removals, own room, unknown and ended parties are refused', async () => {
  const { ctx, seen } = relayEnv();
  const { host, code, roomId } = await openParty(ctx);
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const g = (u, extra = '') => call(ctx, 'GET', `/v1/relay/${code}?role=guest${extra}`, undefined, u.token, WS);
  assert.equal((await g(a)).body.error, 'not_member', 'a guest must join with the code first');
  assert.equal((await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, a.token)).status, 200);
  const ok = await g(a);
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  const last = seen[seen.length - 1].headers;
  assert.equal(last['x-relay-role'], 'guest');
  assert.equal(last['x-relay-player'], 'T:_a', 'the same Game Center player the admission credential names');
  assert.equal(last['x-relay-profile'], a.profile.profile_id);
  assert.equal(last['x-relay-room'], roomId);
  // a guest can't open the party as its host, and the host isn't a guest
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=host`, undefined, a.token, WS)).body.error, 'not_host');
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=guest`, undefined, host.token, WS)).body.error, 'own_room');
  // removed by the host
  await call(ctx, 'POST', `/v1/rooms/${code}/kick`, { profile_id: a.profile.profile_id }, host.token);
  assert.equal((await g(a)).body.error, 'not_allowed');
  // blocked by someone already in the party
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  const c = await user(ctx, 'T:_c', 'Moonlit Koala');
  await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, b.token);
  await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, c.token);
  assert.equal((await g(c)).status, 200);
  await call(ctx, 'POST', '/v1/blocks', { profile_id: c.profile.profile_id }, b.token);
  const blocked = await g(c);
  assert.equal(blocked.body.error, 'not_allowed', 'blocks between members count');
  assert.ok(!blocked.body.message.toLowerCase().includes('block'), 'without saying who blocked whom');
  // the host blocks a member after they joined
  const d = await user(ctx, 'T:_d', 'Sleepy Owl');
  await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, d.token);
  await call(ctx, 'POST', '/v1/blocks', { profile_id: d.profile.profile_id }, host.token);
  assert.equal((await g(d)).body.error, 'not_allowed');
  // a guest who left needs to join again
  await call(ctx, 'POST', `/v1/rooms/${code}/leave`, {}, b.token);
  assert.equal((await g(b)).body.error, 'not_member');
  // unknown and ended parties
  assert.equal((await call(ctx, 'GET', '/v1/relay/ACDEFG?role=guest', undefined, a.token, WS)).body.error, 'not_found');
  ctx.clock.t += 46 * 1000;
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=host`, undefined, host.token, WS)).body.error, 'expired');
});

test('relay endpoint: needs a WebSocket, a session, a role, a well-formed code and a configured relay', async () => {
  const { ctx } = relayEnv();
  const { host, code } = await openParty(ctx);
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=host`, undefined, host.token)).status, 426, 'plain GET');
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=host`, undefined, null, WS)).status, 401, 'no token');
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=host&token=nope`, undefined, null, WS)).status, 401, 'bad token');
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=boss`, undefined, host.token, WS)).body.error, 'bad_role');
  assert.equal((await call(ctx, 'GET', '/v1/relay/AC0?role=host', undefined, host.token, WS)).body.error, 'code_format');
  // a suspended player can't relay
  const s = await user(ctx, 'T:_s', 'Quiet Mole');
  await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: BUILD, protocol: P }, s.token);
  await ctx.env.DB.prepare("UPDATE profiles SET status = 'suspended', suspended_until = ? WHERE id = ?").bind(ctx.clock.t + 3600e3, s.profile.profile_id).run();
  assert.equal((await call(ctx, 'GET', `/v1/relay/${code}?role=guest`, undefined, s.token, WS)).body.error, 'suspended');
  // connection attempts are rate limited per player
  let limited = false;
  for (let i = 0; i < 40 && !limited; i++) {
    limited = (await call(ctx, 'GET', `/v1/relay/${code}?role=host`, undefined, host.token, WS)).body.error === 'rate_limited';
  }
  assert.ok(limited, 'reconnect storms are refused');
  // a deployment without the binding says so (and doesn't offer it)
  const bare = makeEnv();
  const h2 = await openParty(bare);
  assert.equal((await call(bare, 'GET', `/v1/relay/${h2.code}?role=host`, undefined, h2.host.token, WS)).body.error, 'not_configured');
  assert.ok(!(await call(bare, 'GET', '/v1/config')).body.features.includes('relay'));
});
