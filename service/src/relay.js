// Party-code relay: a WebSocket relay per room code, so joining by code
// never depends on Game Center matchmaking.
//
//   GET /v1/relay/<CODE>?role=host|guest   (Upgrade: websocket)
//   auth: the normal session token, as "Authorization: Bearer <token>" or
//   "?token=<token>" (some WebSocket clients can't set headers)
//
// The Worker checks who is connecting (relayAuth) and hands the socket to
// one Durable Object per room code (RelayRoom), which only forwards bytes:
//
//   host -> relay   [u16 to][payload]        to = 0: every guest
//   relay -> host   [u16 from][payload]
//   relay -> host   [0xFFFF][u8 kind][u16 peer][utf8 player]   kind 1 joined, 2 left
//   guest <-> relay [payload]                always to / from the host
//
// (u16 big-endian.)  The host is peer 1, guests are 2, 3, ...  The "joined"
// frame carries the guest's verified Game Center player (the one its
// admission credential names), so the host can bind admission to the real
// sender.  When the host goes, every guest is closed (4000 "host left").
// The relay never reads the game protocol: admission, names and the match
// stay between host and guests exactly as on Game Center.
import { ApiError, json } from './http.js';
import { normalizeCode } from './ids.js';

export const HOST_PEER = 1;
export const FIRST_GUEST = 2;
export const CONTROL = 0xffff;
export const CTRL_JOINED = 1;
export const CTRL_LEFT = 2;
export const MAX_GUESTS = 7;
export const MAX_FRAME = 64 * 1024;
// per socket per second; a sender over budget has the extra frames dropped,
// and one that stays over for STRIKES_TO_CLOSE seconds in a row is closed
export const LIMITS = {
  host: { msgs: 2400, bytes: 4 * 1024 * 1024 },
  guest: { msgs: 300, bytes: 512 * 1024 },
};
export const STRIKES_TO_CLOSE = 5;
// WebSocket close codes the game shows a reason for
export const CLOSE = {
  HOST_LEFT: 4000,
  REPLACED: 4001,
  NO_HOST: 4002,
  FULL: 4003,
  BAD_FRAME: 1003,
  TOO_BIG: 1009,
  FLOOD: 1008,
};

const enc = new TextEncoder();

// --------------------------------------------------------------- the relay
// The routing, as a plain class over the Durable Object's hibernation API
// (ctx.acceptWebSocket / ctx.getWebSockets, ws.serializeAttachment), so the
// tests drive it with a small fake.  Everything it must remember across
// hibernation lives in each socket's attachment.
export class RelayCore {
  constructor(ctx, opts = {}) {
    this.ctx = ctx;
    this.now = opts.now || (() => Date.now());
    this.maxGuests = opts.maxGuests ?? MAX_GUESTS;
    this.maxFrame = opts.maxFrame ?? MAX_FRAME;
    this.limits = opts.limits || LIMITS;
    this.rates = new WeakMap();   // ws -> {w, msgs, bytes, struck, strikes} (in memory: idle sockets have nothing to limit)
    this.nextPeer = FIRST_GUEST;
    this.seq = 0;
  }

  static att(ws) {
    try {
      return ws.deserializeAttachment() || null;
    } catch {
      return null;
    }
  }

  static setAtt(ws, a) {
    ws.serializeAttachment(a);
  }

  static safeSend(ws, bytes) {
    try {
      ws.send(bytes);
      return true;
    } catch {
      return false;
    }
  }

  static safeClose(ws, code, reason) {
    try {
      ws.close(code, reason);
    } catch {
      // already closed
    }
  }

  // live sockets of a role, optionally for one room, without `except`
  live(role, room = null, except = null) {
    const out = [];
    const exceptSid = except ? (RelayCore.att(except) || {}).sid : null;
    for (const ws of this.ctx.getWebSockets(role)) {
      const a = RelayCore.att(ws);
      if (!a || a.dead || a.role !== role) continue;
      if (exceptSid && a.sid === exceptSid) continue;
      if (room !== null && a.room !== room) continue;
      out.push(ws);
    }
    return out;
  }

  host(room) {
    return this.live('host', room)[0] || null;
  }

  guest(room, peer) {
    for (const ws of this.live('guest', room)) if (RelayCore.att(ws).peer === peer) return ws;
    return null;
  }

  sid() {
    this.seq += 1;
    return `${this.now().toString(36)}.${this.seq}.${Math.floor(Math.random() * 1e9).toString(36)}`;
  }

  // A free guest id (2..0xFFFE): never one a live guest holds.
  assignPeer(room) {
    const used = new Set(this.live('guest', room).map((w) => RelayCore.att(w).peer));
    for (const w of this.live('guest')) used.add(RelayCore.att(w).peer);
    for (let i = 0; i < 0xfffd; i++) {
      const p = this.nextPeer;
      this.nextPeer = p >= 0xfffe ? FIRST_GUEST : p + 1;
      if (!used.has(p)) return p;
    }
    return -1;
  }

  static control(kind, peer, player = '') {
    const id = enc.encode(String(player || '').slice(0, 128));
    const b = new Uint8Array(5 + id.length);
    b[0] = 0xff;
    b[1] = 0xff;
    b[2] = kind;
    b[3] = (peer >> 8) & 0xff;
    b[4] = peer & 0xff;
    b.set(id, 5);
    return b;
  }

  // info: {role: 'host'|'guest', pid, gc, room} (checked by relayAuth)
  accept(ws, info) {
    const role = info.role === 'host' ? 'host' : 'guest';
    this.ctx.acceptWebSocket(ws, [role]);
    const a = { sid: this.sid(), role, pid: String(info.pid || ''), gc: String(info.gc || ''), room: String(info.room || ''), at: this.now() };
    if (role === 'host') {
      // a reconnecting host replaces its old socket; a host of another room
      // with this code (an old party) ends that party's guests
      for (const old of this.live('host', null, ws)) {
        const oa = RelayCore.att(old);
        RelayCore.setAtt(old, { ...oa, dead: true });
        RelayCore.safeClose(old, CLOSE.REPLACED, 'replaced');
      }
      a.peer = HOST_PEER;
      RelayCore.setAtt(ws, a);
      for (const g of this.live('guest')) {
        const ga = RelayCore.att(g);
        if (ga.room !== a.room) {
          RelayCore.setAtt(g, { ...ga, dead: true });
          RelayCore.safeClose(g, CLOSE.HOST_LEFT, 'host left');
        } else {
          RelayCore.safeSend(ws, RelayCore.control(CTRL_JOINED, ga.peer, ga.gc));
        }
      }
      return { ok: true, peer: HOST_PEER };
    }
    const h = this.host(a.room);
    if (!h) return this.reject(ws, a, CLOSE.NO_HOST, 'host not connected');
    // the same player on a new connection replaces the old one
    for (const old of this.live('guest', a.room, ws)) {
      const oa = RelayCore.att(old);
      if (a.pid && oa.pid === a.pid) {
        RelayCore.setAtt(old, { ...oa, dead: true });
        RelayCore.safeClose(old, CLOSE.REPLACED, 'replaced');
        RelayCore.safeSend(h, RelayCore.control(CTRL_LEFT, oa.peer, oa.gc));
      }
    }
    if (this.live('guest', a.room, ws).length >= this.maxGuests) return this.reject(ws, a, CLOSE.FULL, 'party full');
    const peer = this.assignPeer(a.room);
    if (peer < 0) return this.reject(ws, a, CLOSE.FULL, 'party full');
    a.peer = peer;
    RelayCore.setAtt(ws, a);
    RelayCore.safeSend(h, RelayCore.control(CTRL_JOINED, peer, a.gc));
    return { ok: true, peer };
  }

  reject(ws, a, code, reason) {
    RelayCore.setAtt(ws, { ...a, dead: true });
    RelayCore.safeClose(ws, code, reason);
    return { ok: false, code, reason };
  }

  // false: over budget (dropped); a sender that stays over is closed
  rateOk(ws, role, size) {
    const lim = this.limits[role];
    const w = Math.floor(this.now() / 1000);
    let r = this.rates.get(ws);
    if (!r) {
      r = { w, msgs: 0, bytes: 0, struck: false, strikes: 0 };
      this.rates.set(ws, r);
    }
    if (r.w !== w) {
      if (!r.struck || w !== r.w + 1) r.strikes = 0;   // a calm second (or a gap) ends the run
      r.w = w;
      r.msgs = 0;
      r.bytes = 0;
      r.struck = false;
    }
    r.msgs += 1;
    r.bytes += size;
    if (r.msgs <= lim.msgs && r.bytes <= lim.bytes) return true;
    if (!r.struck) {
      r.struck = true;
      r.strikes += 1;
      if (r.strikes >= STRIKES_TO_CLOSE) this.closeFlooder(ws);
    }
    return false;
  }

  closeFlooder(ws) {
    RelayCore.safeClose(ws, CLOSE.FLOOD, 'too many messages');
    this.gone(ws);
  }

  message(ws, data) {
    const a = RelayCore.att(ws);
    if (!a || a.dead) return;
    if (typeof data === 'string') {
      // binary frames only; text counts against the budget and is dropped
      this.rateOk(ws, a.role, data.length);
      return;
    }
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    if (bytes.length > this.maxFrame + (a.role === 'host' ? 2 : 0)) {
      RelayCore.safeClose(ws, CLOSE.TOO_BIG, 'frame too large');
      this.gone(ws);
      return;
    }
    if (!this.rateOk(ws, a.role, bytes.length)) return;
    if (a.role === 'host') {
      if (bytes.length < 3) return;
      const to = (bytes[0] << 8) | bytes[1];
      const payload = bytes.subarray(2);
      if (to === 0) {
        for (const g of this.live('guest', a.room)) RelayCore.safeSend(g, payload);
      } else if (to !== CONTROL && to !== HOST_PEER) {
        const g = this.guest(a.room, to);
        if (g) RelayCore.safeSend(g, payload);
      }
      return;
    }
    if (bytes.length < 1) return;
    const h = this.host(a.room);
    if (!h) return;
    const out = new Uint8Array(bytes.length + 2);
    out[0] = (a.peer >> 8) & 0xff;
    out[1] = a.peer & 0xff;
    out.set(bytes, 2);
    RelayCore.safeSend(h, out);
  }

  // a socket closed (or errored)
  closed(ws, code = 1000, reason = '') {
    // (answer the close; 1005/1006 and other reserved codes can't be sent)
    RelayCore.safeClose(ws, code === 1000 || (code >= 3000 && code <= 4999) ? code : 1000, String(reason || '').slice(0, 100));
    this.gone(ws);
  }

  gone(ws) {
    const a = RelayCore.att(ws);
    if (!a || a.dead) return;
    RelayCore.setAtt(ws, { ...a, dead: true });
    if (a.role === 'host') {
      if (this.host(a.room)) return;   // (a newer host socket took over)
      for (const g of this.live('guest', a.room)) {
        RelayCore.setAtt(g, { ...RelayCore.att(g), dead: true });
        RelayCore.safeClose(g, CLOSE.HOST_LEFT, 'host left');
      }
      return;
    }
    const h = this.host(a.room);
    if (h && a.peer) RelayCore.safeSend(h, RelayCore.control(CTRL_LEFT, a.peer, a.gc));
  }
}

// --------------------------------------------------------------- the Durable Object
// One per room code (idFromName(code)), SQLite-backed (wrangler.toml
// migrations: new_sqlite_classes), WebSocket Hibernation API: an idle party
// costs nothing between messages.
export class RelayRoom {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.core = new RelayCore(ctx);
  }

  async fetch(req) {
    if ((req.headers.get('upgrade') || '').toLowerCase() !== 'websocket') {
      return new Response('Expected a WebSocket upgrade.', { status: 426 });
    }
    const info = {
      role: req.headers.get('x-relay-role'),
      pid: req.headers.get('x-relay-profile'),
      gc: req.headers.get('x-relay-player'),
      room: req.headers.get('x-relay-room'),
    };
    if (!['host', 'guest'].includes(info.role) || !info.room) return new Response('Bad relay request.', { status: 400 });
    // eslint-disable-next-line no-undef
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.core.accept(server, info);
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, message) {
    this.core.message(ws, message);
  }

  webSocketClose(ws, code, reason) {
    this.core.closed(ws, code, reason);
  }

  webSocketError(ws) {
    this.core.closed(ws, 1011, 'error');
  }
}

// --------------------------------------------------------------- the Worker side
function bearer(req, url) {
  const h = req.headers.get('authorization') || '';
  if (h.startsWith('Bearer ')) return h.slice(7);
  return url.searchParams.get('token') || '';
}

// Who may connect: {role, pid, gc, room, code} or an ApiError.
//  host:  the room is live and is this profile's
//  guest: the room is live, not their own, they hold a place in it (the
//         normal /v1/rooms/<code>/join, which checks state, capacity,
//         version and blocks), they weren't removed, and nobody in it
//         blocks them or is blocked by them
export async function relayAuth(req, env, rawCode, url, deps) {
  const role = url.searchParams.get('role');
  if (role !== 'host' && role !== 'guest') throw new ApiError(400, 'bad_role', 'role must be host or guest.');
  const n = normalizeCode(rawCode);
  if (!n.ok) throw new ApiError(400, n.error, n.message);
  const token = bearer(req, url);
  if (!token) throw new ApiError(401, 'signed_out', 'Please sign in.');
  const { profile: p } = await deps.requireUser(new Request('https://relay.invalid/', { headers: { authorization: `Bearer ${token}` } }), env);
  await deps.rateLimit(env, `relay:${p.id}`, 30, 60 * 1000, 'Too many connection attempts. Please wait a moment.');
  const r = await deps.liveRoom(env, n.code);
  const q = deps.db(env);
  if (role === 'host') {
    if (r.host_profile_id !== p.id) throw new ApiError(403, 'not_host', 'Only the host can open this party.');
    return { role, pid: p.id, gc: r.host_gc_player, room: r.id, code: n.code };
  }
  if (r.host_profile_id === p.id) throw new ApiError(409, 'own_room', "That's your own party.");
  const mine = await q.one('SELECT * FROM room_members WHERE room_id = ? AND profile_id = ?', r.id, p.id);
  if (mine && mine.kicked) throw new ApiError(403, 'not_allowed', "You can't join this party.");
  if (!mine || mine.state === 'left') throw new ApiError(403, 'not_member', 'Join the party with its code first.');
  const blocked = await q.one('SELECT 1 AS x FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)',
    r.host_profile_id, p.id, p.id, r.host_profile_id);
  if (blocked) throw new ApiError(403, 'not_allowed', "You can't join this party.");
  const clash = await q.one(`SELECT 1 AS x FROM room_members m JOIN blocks b ON
      ((b.blocker_id = m.profile_id AND b.blocked_id = ?) OR (b.blocker_id = ? AND b.blocked_id = m.profile_id))
    WHERE m.room_id = ? AND m.state != 'left' AND m.profile_id != ?`, p.id, p.id, r.id, p.id);
  if (clash) throw new ApiError(403, 'not_allowed', "You can't join this party.");
  return { role, pid: p.id, gc: mine.gc_player || '', room: r.id, code: n.code };
}

// GET /v1/relay/<CODE>: check, then hand the upgrade to the room's relay.
export async function relayUpgrade(req, env, rawCode, url, deps) {
  if ((req.headers.get('upgrade') || '').toLowerCase() !== 'websocket') {
    throw new ApiError(426, 'upgrade_required', 'Connect with a WebSocket.');
  }
  if (!env.RELAY) throw new ApiError(503, 'not_configured', 'Party relay is not configured on this server.');
  const who = await relayAuth(req, env, rawCode, url, deps);
  const h = new Headers();
  for (const [k, v] of req.headers) if (!k.toLowerCase().startsWith('x-relay-') && k.toLowerCase() !== 'authorization') h.set(k, v);
  h.set('x-relay-role', who.role);
  h.set('x-relay-profile', who.pid);
  h.set('x-relay-player', who.gc);
  h.set('x-relay-room', who.room);
  const stub = env.RELAY.get(env.RELAY.idFromName(who.code));
  const res = await stub.fetch(new Request(`https://relay.internal/${who.code}`, { method: 'GET', headers: h }));
  return res || json({ ok: false, error: 'relay', message: 'The party relay did not answer.' }, 502);
}
