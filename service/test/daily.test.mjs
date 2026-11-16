// 2.2 build 15: the daily present.  Once per UTC day, an amount that climbs
// over consecutive days, restarts after a missed day, never twice.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeEnv, call, user } from './helpers.mjs';
import * as E from '../src/economy.js';

const DAY = 24 * 3600 * 1000;
const LIST = E.CATALOGUE.economy.daily_gift.coins;

test('daily present: once a day, climbing streak, reset after a gap', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_dee', 'Dee Otter');
  const w0 = await call(ctx, 'GET', '/v1/wallet', undefined, a.token);
  assert.equal(w0.body.wallet.daily.claimed, false, 'a present waits on the first visit');
  assert.equal(w0.body.wallet.daily.coins, LIST[0]);
  const r1 = await call(ctx, 'POST', '/v1/wallet/daily', {}, a.token);
  assert.equal(r1.status, 200);
  assert.equal(r1.body.daily.granted, LIST[0]);
  assert.equal(r1.body.wallet.balance, LIST[0]);
  assert.equal(r1.body.wallet.daily.claimed, true);
  const again = await call(ctx, 'POST', '/v1/wallet/daily', {}, a.token);
  assert.equal(again.body.daily.granted, 0, 'never twice in a day');
  assert.equal(again.body.wallet.balance, LIST[0]);
  // the next day: day two of the streak
  ctx.clock.t += DAY;
  const a2 = await user(ctx, 'T:_dee', null);   // (sessions last an hour)
  const r2 = await call(ctx, 'POST', '/v1/wallet/daily', {}, a2.token);
  assert.equal(r2.body.daily.granted, LIST[1]);
  assert.equal(r2.body.daily.streak, 2);
  // a missed day restarts it
  ctx.clock.t += 2 * DAY;
  const a3 = await user(ctx, 'T:_dee', null);
  const r3 = await call(ctx, 'POST', '/v1/wallet/daily', {}, a3.token);
  assert.equal(r3.body.daily.streak, 1);
  assert.equal(r3.body.daily.granted, LIST[0]);
  assert.equal(r3.body.wallet.balance, LIST[0] * 2 + LIST[1]);
});

test('daily present: the streak wraps after the last day', async () => {
  const ctx = makeEnv();
  let a = await user(ctx, 'T:_eve', 'Eve Otter');
  let total = 0;
  for (let d = 0; d < LIST.length + 1; d++) {
    if (d > 0) a = await user(ctx, 'T:_eve', null);
    const r = await call(ctx, 'POST', '/v1/wallet/daily', {}, a.token);
    assert.equal(r.body.daily.granted, LIST[d % LIST.length], `day ${d + 1}`);
    total += LIST[d % LIST.length];
    ctx.clock.t += DAY;
  }
  a = await user(ctx, 'T:_eve', null);
  const w = await call(ctx, 'GET', '/v1/wallet', undefined, a.token);
  assert.equal(w.body.wallet.balance, total);
});
