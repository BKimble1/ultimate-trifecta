import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeEnv, call, user, signIn, ADMIN } from './helpers.mjs';

test('reports reach the queue with a receipt; duplicates are idempotent; self-reports and junk are refused', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  const r = await call(ctx, 'POST', '/v1/reports', { profile_id: b.profile.profile_id, reason: 'harassment', details: 'spam emotes', context: { room_code: 'ACDEFG', build: 30 } }, a.token);
  assert.equal(r.status, 200);
  assert.match(r.body.receipt, /^R-[A-Z0-9]{10}$/);
  const dup = await call(ctx, 'POST', '/v1/reports', { profile_id: b.profile.profile_id, reason: 'harassment' }, a.token);
  assert.equal(dup.body.receipt, r.body.receipt, 'same report again returns the same receipt');
  assert.equal((await call(ctx, 'POST', '/v1/reports', { profile_id: a.profile.profile_id, reason: 'name' }, a.token)).body.error, 'self');
  assert.equal((await call(ctx, 'POST', '/v1/reports', { profile_id: b.profile.profile_id, reason: 'because' }, a.token)).body.error, 'bad_reason');
  assert.equal((await call(ctx, 'POST', '/v1/reports', { profile_id: 'p_nobody', reason: 'name' }, a.token)).status, 404);
  const st = await call(ctx, 'GET', `/v1/reports/${r.body.receipt}`, undefined, a.token);
  assert.equal(st.body.status, 'received');
  assert.equal((await call(ctx, 'GET', `/v1/reports/${r.body.receipt}`, undefined, b.token)).status, 404, 'only the reporter can look it up');
  // the owner's queue
  assert.equal((await call(ctx, 'GET', '/v1/admin/reports')).status, 401, 'queue needs the admin token');
  const q = await call(ctx, 'GET', '/v1/admin/reports?status=open', undefined, undefined, ADMIN);
  assert.equal(q.status, 200);
  assert.equal(q.body.reports.length, 1);
  assert.equal(q.body.reports[0].target_name, 'Snoozy Gecko');
  assert.equal(q.body.reports[0].context.room_code, 'ACDEFG');
});

test('admin actions: forced rename hides the name and requires a new one; suspension blocks online play and expires; all audited', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const b = await user(ctx, 'T:_b', 'Rude Name Here');
  const rep = await call(ctx, 'POST', '/v1/reports', { profile_id: b.profile.profile_id, reason: 'name' }, a.token);
  const fr = await call(ctx, 'POST', `/v1/admin/reports/${rep.body.receipt}/resolve`, { action: 'force_rename', note: 'offensive' }, undefined, ADMIN);
  assert.equal(fr.body.status, 'actioned');
  const me = await call(ctx, 'GET', '/v1/me', undefined, b.token);
  assert.equal(me.body.profile.needs_name, true);
  assert.equal(me.body.profile.display_name, null, 'others no longer see the old name');
  assert.equal((await call(ctx, 'POST', '/v1/me/name', { name: 'Rude Name Here' }, b.token)).body.error, 'name_reserved', 'and it cannot be taken again');
  assert.equal((await call(ctx, 'POST', '/v1/me/name', { name: 'Kind Otter' }, b.token)).status, 200, 'a forced rename skips the cooldown');
  // suspension
  const rep2 = await call(ctx, 'POST', '/v1/reports', { profile_id: b.profile.profile_id, reason: 'cheating' }, a.token);
  await call(ctx, 'POST', `/v1/admin/reports/${rep2.body.receipt}/resolve`, { action: 'suspend', hours: 2 }, undefined, ADMIN);
  const blocked = await call(ctx, 'POST', '/v1/rooms', { build: 30, protocol: 4 }, b.token);
  assert.equal(blocked.status, 403);
  assert.equal(blocked.body.error, 'suspended');
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, b.token)).body.profile.status, 'suspended', 'they can still see their own status');
  ctx.clock.t += 2 * 3600 * 1000 + 1000;
  const later = await signIn(ctx, 'T:_b');
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, later.token)).body.profile.status, 'active', 'suspension expires by itself');
  const audit = await call(ctx, 'GET', '/v1/admin/audit', undefined, undefined, ADMIN);
  const actions = audit.body.audit.map((x) => x.action);
  for (const want of ['report_filed', 'report_force_rename', 'report_suspend', 'name_set', 'name_changed', 'profile_created']) {
    assert.ok(actions.includes(want), `audit has ${want}`);
  }
  assert.equal((await call(ctx, 'POST', `/v1/admin/reports/${rep2.body.receipt}/resolve`, { action: 'explode' }, undefined, ADMIN)).status, 400);
});

test('blocks persist per profile and can be listed and removed', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  assert.equal((await call(ctx, 'POST', '/v1/blocks', { profile_id: b.profile.profile_id }, a.token)).status, 200);
  assert.equal((await call(ctx, 'POST', '/v1/blocks', { profile_id: b.profile.profile_id }, a.token)).status, 200, 'idempotent');
  assert.equal((await call(ctx, 'POST', '/v1/blocks', { profile_id: a.profile.profile_id }, a.token)).body.error, 'self');
  const fresh = await signIn(ctx, 'T:_a');
  const list = await call(ctx, 'GET', '/v1/blocks', undefined, fresh.token);
  assert.deepEqual(list.body.blocks.map((x) => x.display_name), ['Snoozy Gecko'], 'survives a new session');
  await call(ctx, 'DELETE', `/v1/blocks/${b.profile.profile_id}`, undefined, fresh.token);
  assert.equal((await call(ctx, 'GET', '/v1/blocks', undefined, fresh.token)).body.blocks.length, 0);
});

test('deleting a game profile needs confirmation and a fresh sign-in, removes personal data, and keeps others\' reports', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_a', 'Comfy Frog');
  const b = await user(ctx, 'T:_b', 'Snoozy Gecko');
  await call(ctx, 'POST', '/v1/blocks', { profile_id: b.profile.profile_id }, a.token);
  const rep = await call(ctx, 'POST', '/v1/reports', { profile_id: b.profile.profile_id, reason: 'harassment' }, a.token);
  assert.equal((await call(ctx, 'DELETE', '/v1/me', {}, a.token)).body.error, 'confirm_required');
  ctx.clock.t += 11 * 60 * 1000;
  assert.equal((await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, a.token)).body.error, 'reauth_required', 'old session: confirm with Game Center again');
  const fresh = await signIn(ctx, 'T:_a');
  const del = await call(ctx, 'DELETE', '/v1/me', { confirm: 'DELETE' }, fresh.token);
  assert.equal(del.status, 200);
  assert.equal((await call(ctx, 'GET', '/v1/me', undefined, fresh.token)).status, 401, 'session ends');
  const again = await signIn(ctx, 'T:_a');
  assert.notEqual(again.profile.profile_id, a.profile.profile_id, 'signing in again starts a brand-new profile');
  assert.equal(again.profile.needs_name, true);
  const q = await call(ctx, 'GET', '/v1/admin/reports', undefined, undefined, ADMIN);
  const kept = q.body.reports.find((x) => x.id === rep.body.receipt);
  assert.ok(kept, 'the report about someone else stays in the queue');
  assert.equal(kept.reporter_id, null, 'without the deleted reporter');
  const prof = await call(ctx, 'GET', `/v1/admin/profiles/${a.profile.profile_id}`, undefined, undefined, ADMIN);
  assert.equal(prof.status, 404, 'profile and its name history are gone');
});
