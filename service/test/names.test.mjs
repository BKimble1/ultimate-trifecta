import { test } from 'node:test';
import assert from 'node:assert/strict';
import { moderate, suggestions, normalizeName, shapeError } from '../src/names.js';
import { makeEnv, call, user, signIn, ADMIN } from './helpers.mjs';

const b = (s) => Buffer.from(s, 'base64').toString();   // keeps slurs out of the test source too

test('character rules: length, characters, spacing, letters, long numbers', () => {
  assert.equal(normalizeName('  Sleepy   Otter  '), 'Sleepy Otter');
  assert.equal(shapeError('ab'), 'length');
  assert.equal(shapeError('x'.repeat(17)), 'length');
  assert.equal(shapeError('Emoji 😀'), 'characters');
  assert.equal(shapeError('Dot.Name'), 'characters');
  assert.equal(shapeError('Ünïcode'), 'characters');
  assert.equal(shapeError('a  b c'), 'spacing');
  assert.equal(shapeError('12345a'), 'letters');
  assert.equal(shapeError('Call 5551234'), 'digits');
  assert.equal(moderate('  Sleepy   Otter 42 ').name, 'Sleepy Otter 42', 'normalised before checking');
  assert.equal(moderate('Ｓｌｅｅｐｙ').name, 'Sleepy', 'full-width letters fold (NFKC)');
});

test('rejects slurs, sexual content, profanity, threats, impersonation and contact info, including disguised spellings', () => {
  const rejected = {
    slur: [b('Q29vb29vbg=='), b('TjFHR0E='), b('bmlnZ2VyIGJveQ=='), b('Tmlnz2Vy').replace(/[^a-z]/gi, 'g'), b('ZmFnIGZhbg=='), b('UjN0NHJk'), b('a2lrZQ==') + 'man'],
    sexual: ['Big D1ck', 'P0rnStar', 'sexy_time', 'ass', 'Nude Beach', b('Qm9vb29i')],
    profanity: ['FuuuckYou', 'f_u_c_k', 'Sh1tHead', 'xX_B1tch_Xx', 'twat'],
    // (V6) stretched letters still match a term matched as spelled
    threat: ['KYS', 'Kill Bill', 'killyou', 'Hitler', 'shoot up'],
    impersonation: ['Admin', 'm0d', 'B0t', 'Trifecta Staff', 'Official Team', 'GameCenter'],
    contact: ['discord gg', 'insta me', 'www site', 'site com', 'snapchat me', 'Add Me Now'],
  };
  for (const [cat, names] of Object.entries(rejected)) {
    for (const n of names) {
      const r = moderate(n);
      assert.equal(r.ok, false, `"${n}" should be rejected (${cat})`);
      assert.equal(r.reason, cat, `"${n}" rejected as ${r.reason}, expected ${cat}`);
      assert.ok(r.message && !r.message.toLowerCase().includes(n.toLowerCase()), 'the message never repeats the name');
    }
  }
  for (const n of ['Nightwatch', 'Night Watch', 'Player', 'Guest']) assert.equal(moderate(n).reason, 'reserved', n);
});

test('false positives: ordinary names that contain blocked letters are allowed', () => {
  const fine = ['Scunthorpe', 'Dickens Fan', 'Peacock', 'Cocktail', 'Hancock', 'Assassin', 'Classy Bass', 'Grass Hopper',
    'grape juice', 'Drape Cat', 'Skyscraper', 'Raccoon', 'Cocoon', 'Tycoon', 'Sussex Lad', 'Essex Owl', 'Arsenal FC',
    'Badminton Pro', 'Cassandra', 'Torpedo', 'Speedo', 'Pistachio', 'Mississippi', 'Shiitake', 'Titanic', 'Japan Fan',
    'Nigel Otter', 'Snoozy Gecko', 'Splash Bomb', 'Hello Kitty', 'Swatch', 'Watchful Owl', 'Therapist', 'Button Nose',
    'Cucumber', 'Document', 'Spicy Taco', 'Knight Rider', 'Pakistan Fan', 'Sleepy Otter 42', 'Moonlit Koala', 'Comfy Frog 11',
    // V6: rejected by the V5 rule (a collapsed term became a common fragment,
    // or a number was read as leetspeak)
    'Bob Builder', 'Iconic Otter', 'Second Wind', 'Contact Lens', 'Bacon Bits', 'Otter 99', 'Frog 10', 'Cocky Kid', 'Thorny Rose',
    'Entity', 'Blue Skys', 'Raccoon 99', 'Tycoon 10'];
  for (const n of fine) assert.equal(moderate(n).ok, true, `"${n}" should be allowed (got ${moderate(n).reason})`);
});

test('suggestions are friendly, valid and different', () => {
  const s = suggestions('seed', 3);
  assert.equal(s.length, 3);
  assert.equal(new Set(s).size, 3);
  for (const n of s) assert.equal(moderate(n).ok, true);
});

test('setting a name: approval, duplicates get different discriminators, cooldown, rate limit', async () => {
  const ctx = makeEnv();
  const a = await user(ctx, 'T:_a', 'Sleepy Otter');
  const c = await user(ctx, 'T:_c', 'sleepy otter');
  assert.equal(a.profile.display_name, 'Sleepy Otter');
  assert.match(a.profile.discriminator, /^\d{4}$/);
  assert.notEqual(a.profile.discriminator, c.profile.discriminator, 'same name, different discriminator');
  assert.equal(a.profile.needs_name, false);
  // rejected names explain and suggest
  const e = await signIn(ctx, 'T:_e');
  const bad = await call(ctx, 'POST', '/v1/me/name', { name: 'Admin' }, e.token);
  assert.equal(bad.status, 422);
  assert.equal(bad.body.error, 'name_rejected');
  assert.equal(bad.body.suggestions.length, 3);
  // once a day
  const again = await call(ctx, 'POST', '/v1/me/name', { name: 'Comfy Owl' }, a.token);
  assert.equal(again.status, 429);
  assert.equal(again.body.error, 'rename_cooldown');
  ctx.clock.t += 24 * 3600 * 1000 + 1000;
  const fresh = await signIn(ctx, 'T:_a');
  const ok = await call(ctx, 'POST', '/v1/me/name', { name: 'Comfy Owl' }, fresh.token);
  assert.equal(ok.status, 200);
  // tries are rate limited (6 per 10 minutes)
  const d = await signIn(ctx, 'T:_d');
  let last;
  for (let i = 0; i < 7; i++) last = await call(ctx, 'POST', '/v1/me/name', { name: 'Admin' + i }, d.token);
  assert.equal(last.status, 429);
  assert.equal(last.body.error, 'rate_limited');
});

test('reserved names and forced renames', async () => {
  const ctx = makeEnv();
  const r = await call(ctx, 'POST', '/v1/admin/reserved', { name: 'Captain Comfy', note: 'event host' }, undefined, ADMIN);
  assert.equal(r.status, 200);
  const u = await signIn(ctx, 'T:_u');
  const res = await call(ctx, 'POST', '/v1/me/name', { name: 'captain  comfy' }, u.token);
  assert.equal(res.body.error, 'name_reserved');
});
