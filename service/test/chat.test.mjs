import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createVerify } from 'node:crypto';
import { makeEnv, call, user, ADMIN } from './helpers.mjs';
import { checkChat, CHAT_MAX, normalizeChat } from '../src/chat_rules.js';

const b = (s) => Buffer.from(s, 'base64').toString();   // keeps slurs out of the test source

async function party(ctx) {
  const host = await user(ctx, 'T:_host', 'Host Otter');
  const room = await call(ctx, 'POST', '/v1/rooms', { build: 30, protocol: 6, capacity: 4 }, host.token);
  const code = room.body.room.code;
  await call(ctx, 'POST', `/v1/rooms/${code}/heartbeat`, { state: 'open' }, host.token);
  const guest = await user(ctx, 'T:_g', 'Comfy Frog');
  const j = await call(ctx, 'POST', `/v1/rooms/${code}/join`, { build: 30, protocol: 6 }, guest.token);
  assert.equal(j.status, 200);
  return { host, guest, code };
}

function claimsOf(ctx, token) {
  const [h, p, s] = token.split('.');
  const v = createVerify('RSA-SHA256');
  v.update(`${h}.${p}`);
  assert.ok(v.verify(ctx.admPub, Buffer.from(s, 'base64url')), 'RS256 signature verifies with the public key the game ships');
  return JSON.parse(Buffer.from(p, 'base64url'));
}

test('chat policy: abuse, links, contact, markup, spam and control characters are rejected, with evasions', () => {
  const rejected = {
    slur: [b('bjFnZ2E='), b('dGhlIGNvb24='), 'f a g'],
    sexual: ['sexy', 'you are an a$$', "You're an ass!", '@ss pic'.replace('@ss pic', 'nude pic')],
    profanity: ['f u c k this', 'sh.it', 'f*ck', 'sh!t', 'fuuuuuck', 'what the f​u​ck', 'ｆｕｃｋ'],
    threat: ['kill you', 'I will kill your self', 'kys'],
    contact: ['visit www.example.com', 'add me on snap', 'my discord is bob', 'call 555 123 4567', 'discord.gg/abc', 'mail x@y.com',
      'follow @sleepyotter', 'http://x', 'example dot com'],
    markup: ['<b>hi</b>', 'hello [color=red]x[/color]', '{x}', 'a\\nb', '`code`'],
    spam: ['aaaaaaaaaa', 'go go go go go go'],
    characters: ['tiny \u{1F600}', 'привет', 'hi\u0007there', 'bad\u0085x'],
    length: ['x'.repeat(CHAT_MAX + 1)],
    empty: ['', '   ', '​'],
  };
  for (const [reason, msgs] of Object.entries(rejected)) {
    for (const m of msgs) {
      const r = checkChat(m);
      assert.equal(r.ok, false, `${JSON.stringify(m)} should be rejected (${reason})`);
      assert.equal(r.reason, reason, `${JSON.stringify(m)} rejected as ${r.reason}, expected ${reason}`);
      assert.ok(r.message && r.message.length > 10, 'a friendly message');
    }
  }
});

test('chat policy: ordinary messages pass, including words that contain flagged letters', () => {
  const fine = ['gg', 'gg everyone!', 'Nice run!', 'I got 10 coins', 'Heading home, cover me', 'The Night Watch is by the fountain',
    'That was a classic assist', 'analysis paralysis', 'second place again', 'bacon', 'raccoon at the pond', 'my therapist says hi',
    'Scunthorpe united', 'café crème', 'good game, well played', 'grape juice', 'cocky move', 'thorny bush', 'entity',
    'Is anyone here?', 'wait for me!!', 'Bob is fast', 'Essex vs Sussex', 'passing the class', 'Skyscraper view', 'title fight',
    'Button mash', 'cucumber cool', 'Nigel is ready', 'Japan trip', '3 of 3 splashes', 'Round 2 of 5', 'Shiitake soup'];
  for (const m of fine) assert.equal(checkChat(m).ok, true, `${JSON.stringify(m)} should pass (got ${checkChat(m).reason})`);
  assert.equal(checkChat('  spaced   out  ').text, 'spaced out', 'normalised: trimmed, single spaces');
  assert.equal(normalizeChat('a\tb\nc'), 'a b c');
});

test('chat check: a member gets a signed approval token; non-members, rejected text and floods get none', async () => {
  const ctx = makeEnv();
  const { host, guest, code } = await party(ctx);
  const ok = await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: '  Ready when you are! ' }, guest.token);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.text, 'Ready when you are!');
  const c = claimsOf(ctx, ok.body.token);
  assert.equal(c.aud, 'trifecta-chat');
  assert.equal(c.sub, guest.profile.profile_id);
  assert.equal(c.room, code);
  assert.equal(c.ch, 0);
  assert.equal(c.text, 'Ready when you are!');
  assert.ok(c.exp - c.iat <= 300, 'short-lived');
  assert.match(c.name, /^Comfy Frog#\d{4}$/);
  // the host is a member too
  assert.equal((await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'hi' }, host.token)).status, 200);
  // rejected text: the reason and a friendly message, no token
  const bad = await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'add me on snap' }, guest.token);
  assert.equal(bad.status, 422);
  assert.equal(bad.body.error, 'chat_rejected');
  assert.equal(bad.body.reason, 'contact');
  assert.equal(bad.body.token, undefined);
  // not in the room
  const outsider = await user(ctx, 'T:_o', 'Moonlit Koala');
  assert.equal((await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'hi' }, outsider.token)).body.error, 'not_member');
  // bad requests
  assert.equal((await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 9, text: 'hi' }, guest.token)).status, 400);
  assert.equal((await call(ctx, 'POST', '/v1/chat/check', { room_code: 'NOPE', channel: 0, text: 'hi' }, guest.token)).status, 400);
  assert.equal((await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'hi' })).status, 401, 'signed in only');
  // flood: 8 attempts per 10 s (rejected ones count too)
  let last;
  for (let i = 0; i < 9; i++) last = await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: `msg ${i}` }, host.token);
  assert.equal(last.status, 429);
  assert.equal(last.body.error, 'rate_limited');
  ctx.clock.t += 11 * 1000;
  assert.equal((await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'back' }, host.token)).status, 200, 'the window slides');
  // a player who leaves can't chat in that room any more
  await call(ctx, 'POST', `/v1/rooms/${code}/leave`, {}, guest.token);
  assert.equal((await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'hi' }, guest.token)).body.error, 'not_member');
  // config advertises chat so an older deployment never looks chat-capable
  assert.ok((await call(ctx, 'GET', '/v1/config')).body.features.includes('chat'));
});

test('message reports: the signed message is the evidence; duplicates, tampering, self-reports and stale messages handled', async () => {
  const ctx = makeEnv();
  const { host, guest, code } = await party(ctx);
  const sent = await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'you are slow lol' }, host.token);
  const token = sent.body.token;
  const r = await call(ctx, 'POST', '/v1/reports/message', { token, reason: 'harassment', details: 'keeps teasing' }, guest.token);
  assert.equal(r.status, 200);
  assert.match(r.body.receipt, /^R-[A-Z0-9]{10}$/);
  assert.equal(r.body.status, 'received');
  const dup = await call(ctx, 'POST', '/v1/reports/message', { token, reason: 'harassment' }, guest.token);
  assert.equal(dup.body.receipt, r.body.receipt, 'the same message reported twice is one report');
  // the owner's queue shows the message itself
  const q = await call(ctx, 'GET', '/v1/admin/reports?status=open', undefined, undefined, ADMIN);
  assert.equal(q.body.reports.length, 1);
  assert.equal(q.body.reports[0].kind, 'message');
  assert.equal(q.body.reports[0].evidence, 'you are slow lol');
  assert.equal(q.body.reports[0].target_id, host.profile.profile_id);
  assert.equal(q.body.reports[0].context.room_code, code);
  // a forged or edited message is refused (never a "reported" for nothing)
  const [h, p, s] = token.split('.');
  const forged = JSON.parse(Buffer.from(p, 'base64url'));
  forged.text = 'something worse';
  const ft = `${h}.${Buffer.from(JSON.stringify(forged)).toString('base64url')}.${s}`;
  assert.equal((await call(ctx, 'POST', '/v1/reports/message', { token: ft, reason: 'harassment' }, guest.token)).body.error, 'bad_token');
  assert.equal((await call(ctx, 'POST', '/v1/reports/message', { token: 'x.y.z', reason: 'harassment' }, guest.token)).status, 400);
  assert.equal((await call(ctx, 'POST', '/v1/reports/message', { token, reason: 'because' }, guest.token)).body.error, 'bad_reason');
  assert.equal((await call(ctx, 'POST', '/v1/reports/message', { token, reason: 'spam' }, host.token)).body.error, 'self');
  // stale: older than a day
  ctx.clock.t += 25 * 3600 * 1000;
  const later = await user(ctx, 'T:_g', null);
  assert.equal((await call(ctx, 'POST', '/v1/reports/message', { token, reason: 'spam' }, later.token)).body.error, 'too_old');
  // a moderator acts on it like any report
  const act = await call(ctx, 'POST', `/v1/admin/reports/${r.body.receipt}/resolve`, { action: 'suspend', hours: 1 }, undefined, ADMIN);
  assert.equal(act.body.status, 'actioned');
});

test('deleting a profile removes the quoted text of its reported messages', async () => {
  const ctx = makeEnv();
  const { host, guest, code } = await party(ctx);
  const sent = await call(ctx, 'POST', '/v1/chat/check', { room_code: code, channel: 0, text: 'meet me later' }, host.token);
  await call(ctx, 'POST', '/v1/reports/message', { token: sent.body.token, reason: 'other' }, guest.token);
  ctx.clock.t += 11 * 60 * 1000;
  const fresh = await user(ctx, 'T:_host', null);
  assert.equal((await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token)).status, 200);
  const q = await call(ctx, 'GET', '/v1/admin/reports?status=dismissed', undefined, undefined, ADMIN);
  assert.equal(q.body.reports.length, 1);
  assert.equal(q.body.reports[0].evidence, null);
  assert.equal(q.body.reports[0].target_name, null);
});
