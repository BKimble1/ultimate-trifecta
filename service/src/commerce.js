// V6 commerce: the trusted wallet.
//
//  - Wallets per verified profile and deployment environment: Coins balance
//    (never negative), refund debt, a revision bumped by every change and the
//    StoreKit appAccountToken.
//  - An append-only ledger: every grant and spend has a globally unique
//    idempotency key (per environment), so a retried or duplicated request
//    applies once.
//  - Atomic Coin spends: debit + entitlement in one D1 batch (one
//    transaction); an overdraw (CHECK balance >= 0) or an already-owned item
//    (primary key) fails the whole batch.
//  - App Store delivery: Apple-signed transactions only (appstore.js),
//    exactly once per transaction ID, bound to the account's token; refunds
//    and revocations by transaction or by App Store Server Notification.
//  - Season 1: XP from verified rounds only, idempotent claims, Premium
//    bought with Coins.
//  - Round settlement: the room host registers a round with its admitted
//    players and reports the result; each player confirms the row their own
//    game received (a digest); the service checks identity, admission,
//    timing, plausibility and daily limits, then pays Coins and Season XP
//    once.  Peer-hosted results remain the host's (see docs/ECONOMY.md).
import { ApiError, json, readJson, str, int } from './http.js';
import { verifyAppleJws, fetchTransaction, appleEnvironment, serverApiConfigured } from './appstore.js';
import * as E from './economy.js';

const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;
const IDEM = /^[A-Za-z0-9_-]{8,64}$/;

let H = null;   // helpers from app.js: {requireUser, requireAdmin, db, rateLimit, audit, clock, liveRoom}

function envName(env) {
  return env.ENVIRONMENT === 'production' ? 'production' : 'sandbox';
}

// ---------------------------------------------------------------- wallet
async function ensureWallet(env, pid) {
  const q = H.db(env);
  const t = H.clock(env);
  await q.run('INSERT OR IGNORE INTO wallets (profile_id, environment, balance, debt, revision, app_account_token, created_at, updated_at) VALUES (?, ?, 0, 0, 0, ?, ?, ?)',
    pid, envName(env), crypto.randomUUID(), t, t);
  return q.one('SELECT * FROM wallets WHERE profile_id = ? AND environment = ?', pid, envName(env));
}

export async function snapshot(env, pid) {
  const q = H.db(env);
  const e = envName(env);
  const w = await ensureWallet(env, pid);
  const ents = await q.all('SELECT item_id, source, revoked_at FROM entitlements WHERE profile_id = ? AND environment = ? ORDER BY granted_at', pid, e);
  const prog = await q.all('SELECT season, xp, premium FROM season_progress WHERE profile_id = ? AND environment = ?', pid, e);
  const claims = await q.all('SELECT season, tier, track FROM season_claims WHERE profile_id = ? AND environment = ?', pid, e);
  const rounds = await q.all(`SELECT match_id, state, coins, xp, reason FROM round_players WHERE profile_id = ? AND environment = ? AND state != 'registered'
    ORDER BY settled_at DESC LIMIT 20`, pid, e);
  const season = {};
  for (const sid of Object.keys(E.CATALOGUE.seasons)) season[sid] = { xp: 0, premium: false, claimed: [] };
  for (const p of prog) season[p.season] = { xp: p.xp, premium: !!p.premium, claimed: [] };
  for (const c of claims) (season[c.season] ||= { xp: 0, premium: false, claimed: [] }).claimed.push(E.claimKey(c.tier, c.track));
  for (const it of ents) {
    const m = /^season:([a-z0-9]+):premium$/.exec(it.item_id);
    if (m && !it.revoked_at && season[m[1]]) season[m[1]].premium = true;
  }
  return {
    profile_id: pid, environment: e, balance: w.balance, debt: w.debt, revision: w.revision, app_account_token: w.app_account_token,
    entitlements: ents.map((x) => ({ item: x.item_id, source: x.source, revoked: !!x.revoked_at })),
    season, rounds: rounds.map((r) => ({ match_id: r.match_id, state: r.state, coins: r.coins, xp: r.xp, reason: r.reason || '' })),
    catalogue_version: E.catalogueVersion(),
  };
}

async function reply(env, pid, extra = {}) {
  return json({ ok: true, ...extra, wallet: await snapshot(env, pid) });
}

// Statements that add Coins (paying refund debt first) and write the ledger.
function grantStmts(env, q, pid, amount, idem, source, ref, t) {
  const e = envName(env);
  return [
    q.stmt('UPDATE wallets SET balance = balance + MAX(0, ? - debt), debt = MAX(0, debt - ?), revision = revision + 1, updated_at = ? WHERE profile_id = ? AND environment = ?',
      amount, amount, t, pid, e),
    q.stmt(`INSERT INTO ledger (profile_id, environment, idem_key, kind, source, amount, balance_after, revision, ref, catalogue_version, at)
      SELECT ?, ?, ?, 'grant', ?, ?, balance, revision, ?, ?, ? FROM wallets WHERE profile_id = ? AND environment = ?`,
    pid, e, idem, source, amount, ref, E.catalogueVersion(), t, pid, e),
  ];
}

// An item-only change: bump the revision and record it in the ledger.
function noteStmts(env, q, pid, idem, kind, source, ref, t) {
  const e = envName(env);
  return [
    q.stmt('UPDATE wallets SET revision = revision + 1, updated_at = ? WHERE profile_id = ? AND environment = ?', t, pid, e),
    q.stmt(`INSERT INTO ledger (profile_id, environment, idem_key, kind, source, amount, balance_after, revision, ref, catalogue_version, at)
      SELECT ?, ?, ?, ?, ?, 0, balance, revision, ?, ?, ? FROM wallets WHERE profile_id = ? AND environment = ?`,
    pid, e, idem, kind, source, ref, E.catalogueVersion(), t, pid, e),
  ];
}

async function ledgerHas(env, idem) {
  return H.db(env).one('SELECT profile_id, ref FROM ledger WHERE environment = ? AND idem_key = ?', envName(env), idem);
}

function failure(e) {
  return String((e && e.message) || e);
}

// ---------------------------------------------------------------- handlers
async function getWallet(req, env) {
  const { profile: p } = await H.requireUser(req, env, { allowSuspended: true });
  await H.rateLimit(env, `wallet:${p.id}`, 120, 60 * 1000);
  return reply(env, p.id);
}

async function spend(req, env) {
  const { profile: p } = await H.requireUser(req, env);
  const b = await readJson(req);
  const id = str(b.item_id, 'item_id', { max: 64 });
  const key = str(b.idempotency_key, 'idempotency_key', { max: 64 });
  if (!IDEM.test(key)) throw new ApiError(400, 'bad_request', 'Bad idempotency key.');
  const shown = int(b.price, 'price', { min: 0, max: 1e7 });
  await H.rateLimit(env, `spend:${p.id}`, 30, 60 * 1000);
  const it = E.item(id);
  if (!it || !['coin_item', 'season_premium'].includes(it.kind)) throw new ApiError(400, 'not_for_sale', "That item isn't sold for Coins.");
  const idem = `spend:${p.id}:${key}`;
  const prev = await ledgerHas(env, idem);
  if (prev) return reply(env, p.id, { replay: true });
  if (shown !== E.price(id)) throw new ApiError(409, 'price_changed', 'The price changed. Check it and try again.', { price: E.price(id) });
  await ensureWallet(env, p.id);
  const q = H.db(env);
  const e = envName(env);
  const owned = await q.one('SELECT revoked_at FROM entitlements WHERE profile_id = ? AND environment = ? AND item_id = ?', p.id, e, id);
  if (owned && !owned.revoked_at) throw new ApiError(409, 'already_owned', 'You already own this.');
  const t = H.clock(env);
  const price = E.price(id);
  const stmts = [
    // the CHECK (balance >= 0) makes an overdraw fail the whole batch
    q.stmt('UPDATE wallets SET balance = balance - ?, revision = revision + 1, updated_at = ? WHERE profile_id = ? AND environment = ?', price, t, p.id, e),
    q.stmt(`INSERT INTO ledger (profile_id, environment, idem_key, kind, source, amount, balance_after, revision, ref, catalogue_version, at)
      SELECT ?, ?, ?, 'spend', 'coin_purchase', ?, balance, revision, ?, ?, ? FROM wallets WHERE profile_id = ? AND environment = ?`,
    p.id, e, idem, -price, id, E.catalogueVersion(), t, p.id, e),
    owned
      ? q.stmt("UPDATE entitlements SET revoked_at = NULL, source = 'coin_purchase', ref = ?, granted_at = ? WHERE profile_id = ? AND environment = ? AND item_id = ? AND revoked_at IS NOT NULL", idem, t, p.id, e, id)
      : q.stmt("INSERT INTO entitlements (profile_id, environment, item_id, source, ref, granted_at) VALUES (?, ?, ?, 'coin_purchase', ?, ?)", p.id, e, id, idem, t),
  ];
  if (it.kind === 'season_premium') {
    stmts.push(q.stmt(`INSERT INTO season_progress (profile_id, environment, season, xp, premium, premium_at, updated_at) VALUES (?, ?, ?, 0, 1, ?, ?)
      ON CONFLICT(profile_id, environment, season) DO UPDATE SET premium = 1, premium_at = excluded.premium_at, updated_at = excluded.updated_at`,
    p.id, e, it.season, t, t));
  }
  try {
    await q.batch(stmts);
  } catch (err) {
    const m = failure(err);
    if (m.includes('CHECK')) throw new ApiError(409, 'insufficient_funds', "You don't have enough Coins.");
    if (m.includes('UNIQUE')) {
      if (await ledgerHas(env, idem)) return reply(env, p.id, { replay: true });
      throw new ApiError(409, 'already_owned', 'You already own this.');
    }
    throw err;
  }
  return reply(env, p.id, { bought: id });
}

// ---------------------------------------------------------------- Apple
function normToken(s) {
  return typeof s === 'string' ? s.toLowerCase() : '';
}

async function appleDeliver(req, env) {
  const { profile: p } = await H.requireUser(req, env, { allowSuspended: true });
  const b = await readJson(req);
  await H.rateLimit(env, `apple:${p.id}`, 30, 60 * 1000);
  const t = H.clock(env);
  let tx = await verifyAppleJws(str(b.jws, 'jws', { max: 16000 }), env, t);
  if (serverApiConfigured(env)) {
    // Apple's own record of the transaction is authoritative when available
    const api = await fetchTransaction(env, String(tx.transactionId), t);
    if (api) tx = api;
  }
  return deliverTransaction(env, p.id, tx, b.transaction_id);
}

export async function deliverTransaction(env, pid, tx, claimedId) {
  const q = H.db(env);
  const e = envName(env);
  const t = H.clock(env);
  if (tx.bundleId !== env.BUNDLE_ID) throw new ApiError(400, 'wrong_app', 'This purchase is for a different app.');
  if (tx.environment !== appleEnvironment(env)) throw new ApiError(400, 'wrong_environment', 'This purchase is from a different App Store environment.');
  const tid = String(tx.transactionId || '');
  if (!/^[0-9]{1,24}$/.test(tid) || (claimedId !== undefined && claimedId !== null && String(claimedId) !== tid)) {
    throw new ApiError(400, 'bad_transaction', "This purchase couldn't be verified with Apple.", { reason: 'transaction_id' });
  }
  const prod = E.product(String(tx.productId || ''));
  if (!prod) throw new ApiError(400, 'unknown_product', 'Unknown product.');
  const wantType = prod.kind === 'coin_pack' ? 'Consumable' : 'Non-Consumable';
  if (tx.type && tx.type !== wantType) throw new ApiError(400, 'bad_transaction', "This purchase couldn't be verified with Apple.", { reason: 'type' });
  const w = await ensureWallet(env, pid);
  const token = normToken(tx.appAccountToken);
  if (token && token !== normToken(w.app_account_token)) {
    throw new ApiError(409, 'account_mismatch', 'This purchase belongs to another player profile.');
  }
  const revoked = !!tx.revocationDate;
  const orig = String(tx.originalTransactionId || tid);
  const row = await q.one('SELECT * FROM apple_transactions WHERE environment = ? AND transaction_id = ?', e, tid);
  if (row) {
    if (row.profile_id && row.profile_id !== pid) {
      throw new ApiError(409, prod.kind === 'coin_pack' ? 'account_mismatch' : 'owned_by_other_profile', 'This purchase belongs to another player profile.');
    }
    if (!row.profile_id && prod.kind === 'apple_skin' && row.state === 'delivered' && !revoked) {
      // the owner deleted their game profile: the skin follows the Apple Account
      await q.batch([
        q.stmt('UPDATE apple_transactions SET profile_id = ?, app_account_token = ? WHERE environment = ? AND transaction_id = ?', pid, token || null, e, tid),
        q.stmt(`INSERT INTO entitlements (profile_id, environment, item_id, source, ref, granted_at) VALUES (?, ?, ?, 'apple', ?, ?)
          ON CONFLICT(profile_id, environment, item_id) DO UPDATE SET revoked_at = NULL, source = 'apple', ref = excluded.ref`, pid, e, prod.item, tid, t),
        ...noteStmts(env, q, pid, `apple_rebind:${tid}:${pid}`, 'grant', 'apple', tid, t),
      ]);
      return reply(env, pid, { delivered: { item: prod.item }, restored: true });
    }
    if (revoked && row.state === 'delivered') {
      await revokeTransaction(env, row, t);
      return reply(env, pid, { revoked: true });
    }
    return reply(env, pid, { replay: true, revoked: row.state === 'revoked' });
  }
  if (prod.kind === 'apple_skin') {
    const other = await q.one(`SELECT profile_id FROM apple_transactions WHERE environment = ? AND original_transaction_id = ? AND state = 'delivered'
      AND profile_id IS NOT NULL AND profile_id != ?`, e, orig, pid);
    if (other) throw new ApiError(409, 'owned_by_other_profile', 'This skin is already linked to another player profile.');
  }
  const ins = q.stmt(`INSERT INTO apple_transactions (environment, transaction_id, original_transaction_id, product_id, kind, coins, profile_id,
      app_account_token, apple_environment, purchase_date, state, delivered_at, revoked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  e, tid, orig, tx.productId, prod.kind, prod.coins || 0, pid, token || null, tx.environment, Number(tx.purchaseDate) || null,
  revoked ? 'refused' : 'delivered', t, revoked ? t : null);
  if (revoked) {
    // refunded before it was ever delivered: recorded, nothing granted
    await q.batch([ins]);
    return reply(env, pid, { revoked: true });
  }
  const stmts = [ins];
  let delivered;
  if (prod.kind === 'coin_pack') {
    stmts.push(...grantStmts(env, q, pid, prod.coins, `apple:${tid}`, 'apple', tid, t));
    delivered = { coins: prod.coins };
  } else {
    stmts.push(q.stmt(`INSERT INTO entitlements (profile_id, environment, item_id, source, ref, granted_at) VALUES (?, ?, ?, 'apple', ?, ?)
      ON CONFLICT(profile_id, environment, item_id) DO UPDATE SET revoked_at = NULL, source = 'apple', ref = excluded.ref`, pid, e, prod.item, tid, t));
    stmts.push(...noteStmts(env, q, pid, `apple:${tid}`, 'grant', 'apple', tid, t));
    delivered = { item: prod.item };
  }
  try {
    await q.batch(stmts);
  } catch (err) {
    if (failure(err).includes('UNIQUE')) return reply(env, pid, { replay: true });   // a racing duplicate delivered it
    throw err;
  }
  return reply(env, pid, { delivered });
}

// Refund / revocation policy: a refunded Coin pack takes back its Coins (as
// much as the balance holds; the rest is recorded as debt, paid from later
// grants before the balance grows), a refunded direct skin is revoked.
// Nothing else is touched: Coin-bought items, earned items and claims stay.
export async function revokeTransaction(env, row, t) {
  const q = H.db(env);
  const e = row.environment;
  const stmts = [q.stmt("UPDATE apple_transactions SET state = 'revoked', revoked_at = ? WHERE environment = ? AND transaction_id = ? AND state = 'delivered'",
    t, e, row.transaction_id)];
  if (row.profile_id) {
    if (row.kind === 'coin_pack') {
      stmts.push(q.stmt('UPDATE wallets SET debt = debt + MAX(0, ? - balance), balance = MAX(0, balance - ?), revision = revision + 1, updated_at = ? WHERE profile_id = ? AND environment = ?',
        row.coins, row.coins, t, row.profile_id, e));
      stmts.push(q.stmt(`INSERT INTO ledger (profile_id, environment, idem_key, kind, source, amount, balance_after, revision, ref, catalogue_version, at)
        SELECT ?, ?, ?, 'revoke', 'refund', ?, balance, revision, ?, ?, ? FROM wallets WHERE profile_id = ? AND environment = ?`,
      row.profile_id, e, `refund:${row.transaction_id}`, -row.coins, row.transaction_id, E.catalogueVersion(), t, row.profile_id, e));
    } else {
      const prod = E.product(row.product_id);
      stmts.push(q.stmt('UPDATE entitlements SET revoked_at = ? WHERE profile_id = ? AND environment = ? AND item_id = ? AND source = ?',
        t, row.profile_id, e, prod ? prod.item : '', 'apple'));
      stmts.push(...noteStmts({ ENVIRONMENT: e }, q, row.profile_id, `refund:${row.transaction_id}`, 'revoke', 'refund', row.transaction_id, t));
    }
  }
  try {
    await q.batch(stmts);
  } catch (err) {
    if (!failure(err).includes('UNIQUE')) throw err;   // already revoked
  }
  await H.audit(env, 'system', 'apple_revoked', row.profile_id, { transaction: row.transaction_id, product: row.product_id });
}

// App Store Server Notifications V2 (the URL set in App Store Connect).
async function appleNotification(req, env) {
  const b = await readJson(req);
  const t = H.clock(env);
  const n = await verifyAppleJws(str(b.signedPayload, 'signedPayload', { max: 16000 }), env, t);
  const data = n.data || {};
  if (data.bundleId !== env.BUNDLE_ID) throw new ApiError(400, 'wrong_app', 'Wrong app.');
  if (data.environment !== appleEnvironment(env)) throw new ApiError(400, 'wrong_environment', 'Wrong environment.');
  const uuid = String(n.notificationUUID || '');
  if (!/^[0-9a-fA-F-]{8,64}$/.test(uuid)) throw new ApiError(400, 'bad_request', 'Missing notification id.');
  const q = H.db(env);
  if (await q.one('SELECT uuid FROM apple_notifications WHERE uuid = ?', uuid)) return json({ ok: true, replay: true });
  let tid = null;
  if (['REFUND', 'REVOKE'].includes(n.notificationType) && data.signedTransactionInfo) {
    const tx = await verifyAppleJws(String(data.signedTransactionInfo), env, t);
    tid = String(tx.transactionId);
    const row = await q.one('SELECT * FROM apple_transactions WHERE environment = ? AND transaction_id = ?', envName(env), tid);
    if (row && row.state === 'delivered') await revokeTransaction(env, row, t);
  }
  await q.run('INSERT OR IGNORE INTO apple_notifications (uuid, type, subtype, transaction_id, at) VALUES (?, ?, ?, ?, ?)',
    uuid, String(n.notificationType || ''), n.subtype ? String(n.subtype) : null, tid, t);
  return json({ ok: true });
}

// ---------------------------------------------------------------- legacy
async function subjectHash(env, pid) {
  const r = await H.db(env).one("SELECT subject FROM identities WHERE profile_id = ? AND provider = 'gamecenter' ORDER BY created_at LIMIT 1", pid);
  if (!r) return null;
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`legacy|${envName(env)}|${r.subject}`)));
  return [...h].map((x) => x.toString(16).padStart(2, '0')).join('');
}

async function legacyImport(req, env) {
  const { profile: p } = await H.requireUser(req, env);
  const b = await readJson(req);
  await H.rateLimit(env, `legacy:${p.id}`, 6, HOUR);
  const coins = int(b.coins ?? 0, 'coins', { min: 0, max: 1e9 });
  const online = int(b.online_rounds ?? 0, 'online_rounds', { min: 0, max: 1e6 });
  const practice = int(b.practice_rounds ?? 0, 'practice_rounds', { min: 0, max: 1e6 });
  const items = Array.isArray(b.items) ? b.items.slice(0, 64).filter((x) => typeof x === 'string' && E.item(x) && E.item(x).legacy === true) : [];
  const q = H.db(env);
  const e = envName(env);
  const sh = await subjectHash(env, p.id);
  const done = await q.one('SELECT profile_id FROM legacy_imports WHERE environment = ? AND (profile_id = ? OR (subject_hash IS NOT NULL AND subject_hash = ?))', e, p.id, sh);
  if (done) return reply(env, p.id, { already_imported: true, imported_coins: 0, imported_items: [] });
  await ensureWallet(env, p.id);
  const t = H.clock(env);
  const amount = E.legacyImportAmount(coins, online, practice);
  const stmts = [q.stmt('INSERT INTO legacy_imports (profile_id, environment, claimed_coins, imported_coins, items, subject_hash, at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    p.id, e, coins, amount, JSON.stringify(items), sh, t)];
  stmts.push(...(amount > 0 ? grantStmts(env, q, p.id, amount, `legacy:${p.id}`, 'legacy_beta', 'pre-V6 device balance', t)
    : noteStmts(env, q, p.id, `legacy:${p.id}`, 'grant', 'legacy_beta', 'pre-V6 device items', t)));
  for (const id of items) {
    stmts.push(q.stmt("INSERT OR IGNORE INTO entitlements (profile_id, environment, item_id, source, ref, granted_at) VALUES (?, ?, ?, 'legacy_beta', 'pre-V6', ?)", p.id, e, id, t));
  }
  try {
    await q.batch(stmts);
  } catch (err) {
    if (failure(err).includes('UNIQUE')) return reply(env, p.id, { already_imported: true, imported_coins: 0, imported_items: [] });
    throw err;
  }
  await H.audit(env, p.id, 'legacy_import', p.id, { claimed: coins, imported: amount, items: items.length, online, practice });
  return reply(env, p.id, { imported_coins: amount, imported_items: items });
}

// ---------------------------------------------------------------- season
async function claim(req, env, sid) {
  const { profile: p } = await H.requireUser(req, env);
  const s = E.season(sid);
  if (!s) throw new ApiError(404, 'no_season', 'No such season.');
  const b = await readJson(req);
  await H.rateLimit(env, `claim:${p.id}`, 30, 60 * 1000);
  const want = Array.isArray(b.claims) ? b.claims.slice(0, 60) : [];
  await ensureWallet(env, p.id);
  const q = H.db(env);
  const e = envName(env);
  for (let attempt = 0; attempt < 2; attempt++) {
    const snap = await snapshot(env, p.id);
    const st = snap.season[sid] || { xp: 0, premium: false, claimed: [] };
    const claimed = new Set(st.claimed);
    const owned = new Set(snap.entitlements.filter((x) => !x.revoked).map((x) => x.item));
    const t = H.clock(env);
    const stmts = [];
    const done = [];
    const seen = new Set();
    for (const c of want) {
      const tier = Number(c && c.tier);
      const track = c && c.track;
      if (!Number.isInteger(tier) || !['free', 'premium'].includes(track) || seen.has(E.claimKey(tier, track))) continue;
      seen.add(E.claimKey(tier, track));
      if (E.cellState(sid, tier, track, st.xp, st.premium, claimed) !== 'claimable') continue;
      const r = E.rewardAt(sid, tier, track);
      let result = 'granted';
      if (r.coins) {
        stmts.push(...grantStmts(env, q, p.id, r.coins, `claim:${sid}:${tier}:${track}:${p.id}`, 'season_claim', `${sid}:${tier}:${track}`, t));
      } else if (owned.has(r.item)) {
        result = 'already_owned';   // a duplicate never grants twice
      } else {
        stmts.push(q.stmt("INSERT INTO entitlements (profile_id, environment, item_id, source, ref, granted_at) VALUES (?, ?, ?, 'season', ?, ?)",
          p.id, e, r.item, `${sid}:${tier}:${track}`, t));
        owned.add(r.item);
      }
      stmts.push(q.stmt('INSERT INTO season_claims (profile_id, environment, season, tier, track, reward, result, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        p.id, e, sid, tier, track, r.coins ? `coins:${r.coins}` : r.item, result, t));
      done.push({ tier, track, result });
    }
    if (done.length === 0) return reply(env, p.id, { claimed: [] });
    stmts.push(q.stmt('UPDATE wallets SET revision = revision + 1, updated_at = ? WHERE profile_id = ? AND environment = ?', t, p.id, e));
    try {
      await q.batch(stmts);
      return reply(env, p.id, { claimed: done });
    } catch (err) {
      if (!failure(err).includes('UNIQUE') || attempt > 0) throw err;
      // a racing Claim: recompute from the new state (idempotent)
    }
  }
  return reply(env, p.id, { claimed: [] });
}

// ---------------------------------------------------------------- rounds
const MID = /^[A-Z0-9]{3,12}-[0-9]{1,3}-[0-9a-f]{1,16}$/;

async function registerRound(req, env) {
  const { profile: p } = await H.requireUser(req, env);
  const b = await readJson(req);
  const code = str(b.code, 'code', { max: 12 });
  const mid = str(b.match_id, 'match_id', { max: 64 });
  if (!MID.test(mid) || !mid.startsWith(code + '-')) throw new ApiError(400, 'bad_round', 'That round id is not for this party.');
  const r = await H.liveRoom(env, code);
  if (r.host_profile_id !== p.id) throw new ApiError(403, 'not_host', 'Only the host can start rounds.');
  await H.rateLimit(env, `round:${p.id}`, 20, 10 * 60 * 1000, 'Too many rounds started. Please wait.');
  const parts = Array.isArray(b.participants) ? b.participants : [];
  if (parts.length < 1 || parts.length > 8) throw new ApiError(400, 'bad_round', 'A round has 1 to 8 players.');
  const q = H.db(env);
  const e = envName(env);
  const t = H.clock(env);
  const existing = await q.one('SELECT host_profile_id FROM rounds WHERE environment = ? AND match_id = ?', e, mid);
  if (existing) {
    if (existing.host_profile_id !== p.id) throw new ApiError(409, 'bad_round', 'That round belongs to another party.');
    return json({ ok: true, replay: true });
  }
  const last = await q.one("SELECT MAX(started_at) AS at FROM rounds WHERE room_id = ? AND state != 'cancelled'", r.id);
  if (last && last.at && t - last.at < E.ECONOMY.eligibility.min_round_s * 1000) {
    throw new ApiError(429, 'too_soon', 'Rounds in a party start at most once a minute.');
  }
  const seenP = new Set();
  const seenS = new Set();
  const rows = [];
  for (const x of parts) {
    const pid = str(x && x.profile_id, 'profile_id', { max: 40 });
    const slot = int(x && x.slot, 'slot', { min: 0, max: 7 });
    if (seenP.has(pid) || seenS.has(slot)) throw new ApiError(400, 'bad_round', 'Each player once.');
    seenP.add(pid);
    seenS.add(slot);
    const m = await q.one("SELECT state FROM room_members WHERE room_id = ? AND profile_id = ? AND state != 'left' AND kicked = 0", r.id, pid);
    if (!m) throw new ApiError(409, 'not_member', 'Every player must have been admitted to this party.');
    rows.push([pid, slot]);
  }
  await q.batch([
    q.stmt("INSERT INTO rounds (environment, match_id, room_id, host_profile_id, state, started_at) VALUES (?, ?, ?, ?, 'started', ?)", e, mid, r.id, p.id, t),
    ...rows.map(([pid, slot]) => q.stmt("INSERT INTO round_players (environment, match_id, profile_id, slot, state) VALUES (?, ?, ?, ?, 'registered')", e, mid, pid, slot)),
  ]);
  return json({ ok: true });
}

// The host's numbers must be possible: bounds per row, at most the round's
// coins collected in total, one first-home, finishes only with three stamps.
export function checkReport(b, registered) {
  const el = E.ECONOMY.eligibility;
  const outcome = Number(b.outcome);
  if (![E.OUTCOME.RUNNERS_WIN, E.OUTCOME.PATROL_WIN, E.OUTCOME.CANCELLED].includes(outcome)) return 'outcome';
  const rt = Number(b.round_time_s);
  if (!Number.isFinite(rt) || rt < 0 || rt > el.max_round_s) return 'round_time';
  const spawns = Number(b.coin_spawns);
  if (!Number.isInteger(spawns) || spawns < 0 || spawns > el.max_coin_spawns) return 'coin_spawns';
  const players = Array.isArray(b.players) ? b.players : null;
  if (!players || players.length > 8) return 'players';
  let picked = 0;
  let first = 0;
  const seen = new Set();
  for (const r of players) {
    if (!r || typeof r.profile_id !== 'string' || !registered.has(r.profile_id) || seen.has(r.profile_id)) return 'player';
    seen.add(r.profile_id);
    if (![0, 1].includes(r.role)) return 'role';
    for (const [k, hi] of [['stamps', 3], ['unique_captures', 7], ['coins_picked', spawns]]) {
      if (!Number.isInteger(r[k] ?? 0) || (r[k] ?? 0) < 0 || (r[k] ?? 0) > hi) return k;
    }
    const away = Number(r.away_s ?? 0);
    if (!Number.isFinite(away) || away < 0 || away > rt + 1) return 'away';
    if (r.finished && (r.role !== E.ROLE.RUNNER || r.stamps !== 3)) return 'finished';
    if (r.role === E.ROLE.PATROL && (r.stamps || r.finished || r.first_home)) return 'watch_row';
    if (r.first_home) {
      if (!r.finished) return 'first_home';
      first += 1;
    }
    picked += r.coins_picked || 0;
  }
  if (first > 1) return 'first_home';
  if (picked > spawns) return 'coins_total';
  return '';
}

async function reportRound(req, env, mid) {
  const { profile: p } = await H.requireUser(req, env);
  const b = await readJson(req);
  const q = H.db(env);
  const e = envName(env);
  const rd = await q.one('SELECT * FROM rounds WHERE environment = ? AND match_id = ?', e, mid);
  if (!rd) throw new ApiError(404, 'no_round', 'Unknown round.');
  if (rd.host_profile_id !== p.id) throw new ApiError(403, 'not_host', 'Only the host reports a round.');
  if (rd.state !== 'started') return json({ ok: true, replay: true, state: rd.state });
  const t = H.clock(env);
  const el = E.ECONOMY.eligibility;
  const players = await q.all('SELECT * FROM round_players WHERE environment = ? AND match_id = ?', e, mid);
  const registered = new Set(players.map((x) => x.profile_id));
  let why = '';
  if (t - rd.started_at > el.report_window_s * 1000) why = 'late';
  else if (Number(b.outcome) !== E.OUTCOME.CANCELLED && t - rd.started_at < el.min_round_s * 1000) why = 'too_short';
  else why = checkReport(b, registered);
  if (why) {
    await q.batch([
      q.stmt("UPDATE rounds SET state = 'rejected', reject_reason = ?, reported_at = ? WHERE environment = ? AND match_id = ?", why, t, e, mid),
      q.stmt("UPDATE round_players SET state = 'rejected', reason = ?, settled_at = ? WHERE environment = ? AND match_id = ? AND state = 'registered'", why, t, e, mid),
    ]);
    await H.audit(env, p.id, 'round_rejected', mid, { reason: why });
    throw new ApiError(422, 'implausible', "This round's result couldn't be accepted.", { reason: why });
  }
  const outcome = Number(b.outcome);
  if (outcome === E.OUTCOME.CANCELLED) {
    await q.batch([
      q.stmt("UPDATE rounds SET state = 'cancelled', outcome = ?, reported_at = ? WHERE environment = ? AND match_id = ?", outcome, t, e, mid),
      q.stmt("UPDATE round_players SET state = 'cancelled', settled_at = ? WHERE environment = ? AND match_id = ? AND state = 'registered'", t, e, mid),
    ]);
    return json({ ok: true, state: 'cancelled' });
  }
  const rt = Number(b.round_time_s);
  const rows = new Map(b.players.map((r) => [r.profile_id, r]));
  const stmts = [q.stmt("UPDATE rounds SET state = 'reported', outcome = ?, round_time_s = ?, coin_spawns = ?, reported_at = ? WHERE environment = ? AND match_id = ?",
    outcome, Math.round(rt * 1000) / 1000, b.coin_spawns, t, e, mid)];
  for (const pr of players) {
    const r = rows.get(pr.profile_id);
    if (!r) continue;
    const keep = { role: r.role, stamps: r.stamps | 0, finished: !!r.finished, first_home: !!r.first_home, unique_captures: r.unique_captures | 0,
      coins_picked: r.coins_picked | 0, present: r.present !== false, away_s: Number(r.away_s) || 0 };
    stmts.push(q.stmt('UPDATE round_players SET report = ? WHERE environment = ? AND match_id = ? AND profile_id = ?', JSON.stringify(keep), e, mid, pr.profile_id));
  }
  await q.batch(stmts);
  let settled = 0;
  for (const pr of await q.all("SELECT * FROM round_players WHERE environment = ? AND match_id = ? AND ack_digest IS NOT NULL AND state = 'registered'", e, mid)) {
    const s = await settle(env, mid, pr.profile_id);
    if (s.state === 'settled') settled += 1;
  }
  return json({ ok: true, state: 'reported', settled });
}

async function ackRound(req, env, mid) {
  const { profile: p } = await H.requireUser(req, env, { allowSuspended: true });
  const b = await readJson(req);
  const digest = str(b.digest, 'digest', { min: 64, max: 64 });
  if (!/^[0-9a-f]{64}$/.test(digest)) throw new ApiError(400, 'bad_request', 'Bad digest.');
  await H.rateLimit(env, `ack:${p.id}`, 60, 60 * 1000);
  const q = H.db(env);
  const e = envName(env);
  const rd = await q.one('SELECT * FROM rounds WHERE environment = ? AND match_id = ?', e, mid);
  const pr = rd && (await q.one('SELECT * FROM round_players WHERE environment = ? AND match_id = ? AND profile_id = ?', e, mid, p.id));
  if (!rd || !pr) throw new ApiError(404, 'no_round', "This round wasn't registered for you.");
  const t = H.clock(env);
  if (t - rd.started_at > E.ECONOMY.eligibility.ack_window_s * 1000 && pr.state === 'registered') {
    throw new ApiError(410, 'expired', 'This round is too old to confirm.');
  }
  // the first confirmation counts (a replay can't change it)
  await q.run('UPDATE round_players SET ack_digest = ?, ack_at = ? WHERE environment = ? AND match_id = ? AND profile_id = ? AND ack_digest IS NULL',
    digest, t, e, mid, p.id);
  const s = rd.state === 'started' ? { state: 'pending', coins: 0, xp: 0 } : await settle(env, mid, p.id);
  return reply(env, p.id, { settlement: { match_id: mid, ...s } });
}

function utcDay(t) {
  return new Date(t).toISOString().slice(0, 10);
}

// Pays one player of a reported round once (or records why not).
export async function settle(env, mid, pid) {
  const q = H.db(env);
  const e = envName(env);
  const rd = await q.one('SELECT * FROM rounds WHERE environment = ? AND match_id = ?', e, mid);
  const pr = await q.one('SELECT * FROM round_players WHERE environment = ? AND match_id = ? AND profile_id = ?', e, mid, pid);
  const out = (s) => ({ state: s.state, coins: s.coins || 0, xp: s.xp || 0, reason: s.reason || '' });
  if (!rd || !pr) return { state: 'unknown', coins: 0, xp: 0, reason: '' };
  if (pr.state !== 'registered') return out(pr);
  const t = H.clock(env);
  const mark = async (state, reason) => {
    await q.run('UPDATE round_players SET state = ?, reason = ?, settled_at = ? WHERE environment = ? AND match_id = ? AND profile_id = ? AND state = ?',
      state, reason, t, e, mid, pid, 'registered');
    return { state, coins: 0, xp: 0, reason };
  };
  if (rd.state === 'cancelled') return mark('cancelled', 'cancelled');
  if (rd.state === 'rejected') return mark('rejected', rd.reject_reason || 'rejected');
  if (!pr.report) return mark('ineligible', 'not_reported');
  if (!pr.ack_digest) return { state: 'pending', coins: 0, xp: 0, reason: '' };
  const row = JSON.parse(pr.report);
  const digest = await E.rowDigest(mid, rd.outcome, rd.round_time_s, row);
  if (digest !== pr.ack_digest) {
    await H.audit(env, 'system', 'round_mismatch', pid, { match: mid });
    return mark('mismatch', 'digest');
  }
  if (!E.presentEnough(row, rd.round_time_s)) return mark('ineligible', 'away');
  const all = await q.all('SELECT report FROM round_players WHERE environment = ? AND match_id = ? AND report IS NOT NULL', e, mid);
  const humans = all.filter((x) => E.presentEnough(JSON.parse(x.report), rd.round_time_s)).length;
  if (humans < E.ECONOMY.eligibility.min_humans) return mark('ineligible', 'few_humans');
  const coins = E.roundCoins(row, rd.outcome, rd.coin_spawns);
  const xp = E.roundSeasonXp(row, rd.outcome);
  const sid = Object.keys(E.CATALOGUE.seasons)[0];
  await ensureWallet(env, pid);
  try {
    await q.batch([
      // the CHECK on daily_rounds is the per-day cap: past it the batch fails
      q.stmt('INSERT INTO daily_rounds (profile_id, environment, day, rounds) VALUES (?, ?, ?, 1) ON CONFLICT(profile_id, environment, day) DO UPDATE SET rounds = rounds + 1',
        pid, e, utcDay(t)),
      ...grantStmts(env, q, pid, coins, `round:${mid}:${pid}`, 'round', mid, t),
      q.stmt(`INSERT INTO season_progress (profile_id, environment, season, xp, premium, updated_at) VALUES (?, ?, ?, ?, 0, ?)
        ON CONFLICT(profile_id, environment, season) DO UPDATE SET xp = xp + excluded.xp, updated_at = excluded.updated_at`, pid, e, sid, xp, t),
      q.stmt("UPDATE round_players SET state = 'settled', coins = ?, xp = ?, settled_at = ? WHERE environment = ? AND match_id = ? AND profile_id = ? AND state = 'registered'",
        coins, xp, t, e, mid, pid),
    ]);
  } catch (err) {
    const m = failure(err);
    if (m.includes('CHECK')) return mark('capped', 'daily_cap');
    if (m.includes('UNIQUE')) return out(await q.one('SELECT * FROM round_players WHERE environment = ? AND match_id = ? AND profile_id = ?', e, mid, pid));
    throw err;
  }
  return { state: 'settled', coins, xp, reason: '' };
}

async function roundMe(req, env, mid) {
  const { profile: p } = await H.requireUser(req, env, { allowSuspended: true });
  const pr = await H.db(env).one('SELECT * FROM round_players WHERE environment = ? AND match_id = ? AND profile_id = ?', envName(env), mid, p.id);
  if (!pr) throw new ApiError(404, 'no_round', 'Unknown round.');
  return json({ ok: true, settlement: { match_id: mid, state: pr.state === 'registered' ? 'pending' : pr.state, coins: pr.coins, xp: pr.xp, reason: pr.reason || '' } });
}

// ---------------------------------------------------------------- admin
async function adminWallet(req, env, pid) {
  H.requireAdmin(req, env);
  const ledger = await H.db(env).all('SELECT * FROM ledger WHERE profile_id = ? AND environment = ? ORDER BY id DESC LIMIT 100', pid, envName(env));
  const apple = await H.db(env).all('SELECT transaction_id, product_id, state, delivered_at, revoked_at FROM apple_transactions WHERE profile_id = ? AND environment = ?', pid, envName(env));
  return json({ ok: true, wallet: await snapshot(env, pid), ledger, apple });
}

// Support reconciliation: grant Coins (positive) or forgive refund debt.
async function adminAdjust(req, env, pid) {
  const actor = H.requireAdmin(req, env);
  const b = await readJson(req);
  const key = str(b.idempotency_key, 'idempotency_key', { max: 64 });
  const note = str(b.note, 'note', { max: 200 });
  const q = H.db(env);
  const t = H.clock(env);
  await ensureWallet(env, pid);
  if (b.forgive_debt) {
    await q.batch([q.stmt('UPDATE wallets SET debt = 0, revision = revision + 1, updated_at = ? WHERE profile_id = ? AND environment = ?', t, pid, envName(env)),
      ...noteStmts(env, q, pid, `admin:${key}`, 'grant', 'admin', note, t).slice(1)]);
  } else {
    const amount = int(b.amount, 'amount', { min: 1, max: 100000 });
    try {
      await q.batch(grantStmts(env, q, pid, amount, `admin:${key}`, 'admin', note, t));
    } catch (err) {
      if (!failure(err).includes('UNIQUE')) throw err;
    }
  }
  await H.audit(env, actor, 'wallet_adjust', pid, { note, amount: b.amount || 0, forgive_debt: !!b.forgive_debt });
  return json({ ok: true, wallet: await snapshot(env, pid) });
}

// ---------------------------------------------------------------- lifecycle
// Profile deletion: Coins, items, Season progress and settlements go; ledger
// and App Store rows stay for reconciliation without the profile link.
export function deletionStmts(q, pid) {
  return [
    q.stmt('UPDATE ledger SET profile_id = NULL WHERE profile_id = ?', pid),
    q.stmt('UPDATE apple_transactions SET profile_id = NULL WHERE profile_id = ?', pid),
    q.stmt('UPDATE legacy_imports SET profile_id = ? WHERE profile_id = ?', 'deleted:' + pid.slice(-6) + ':' + Date.now(), pid),
    q.stmt('DELETE FROM wallets WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM entitlements WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM season_progress WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM season_claims WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM round_players WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM daily_rounds WHERE profile_id = ?', pid),
  ];
}

export async function sweepCommerce(env, q, t) {
  await q.run("DELETE FROM round_players WHERE match_id IN (SELECT match_id FROM rounds WHERE started_at < ? AND state != 'started')", t - 30 * DAY);
  await q.run("DELETE FROM rounds WHERE started_at < ? AND state != 'started'", t - 30 * DAY);
  await q.run('DELETE FROM daily_rounds WHERE day < ?', utcDay(t - 7 * DAY));
  await q.run('DELETE FROM apple_notifications WHERE at < ?', t - 90 * DAY);
}

// ---------------------------------------------------------------- router
export async function routeCommerce(req, env, path, m, helpers) {
  H = helpers;
  let k;
  if (m === 'GET' && path === '/v1/wallet') return getWallet(req, env);
  if (m === 'POST' && path === '/v1/wallet/spend') return spend(req, env);
  if (m === 'POST' && path === '/v1/wallet/apple') return appleDeliver(req, env);
  if (m === 'POST' && path === '/v1/wallet/legacy-import') return legacyImport(req, env);
  if (m === 'POST' && path === '/v1/appstore/notifications') return appleNotification(req, env);
  if (m === 'POST' && (k = path.match(/^\/v1\/season\/([a-z0-9]{1,8})\/claim$/))) return claim(req, env, k[1]);
  if (m === 'POST' && path === '/v1/rounds') return registerRound(req, env);
  if ((k = path.match(/^\/v1\/rounds\/([A-Za-z0-9-]{3,64})\/(report|ack|me)$/))) {
    if (m === 'POST' && k[2] === 'report') return reportRound(req, env, k[1]);
    if (m === 'POST' && k[2] === 'ack') return ackRound(req, env, k[1]);
    if (m === 'GET' && k[2] === 'me') return roundMe(req, env, k[1]);
  }
  if (m === 'GET' && (k = path.match(/^\/v1\/admin\/wallets\/([A-Za-z0-9_]{3,40})$/))) return adminWallet(req, env, k[1]);
  if (m === 'POST' && (k = path.match(/^\/v1\/admin\/wallets\/([A-Za-z0-9_]{3,40})\/adjust$/))) return adminAdjust(req, env, k[1]);
  return null;
}

export function bindHelpers(helpers) {
  H = helpers;
}
