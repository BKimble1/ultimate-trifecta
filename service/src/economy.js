// V6 economy rules, the service side of game/src/core/economy.gd: the same
// numbers (catalogue_data.js "economy") and the same functions, so the
// client's projection and the service's settlement agree.  test/economy
// checks the canonical row form against the client's.
import CAT from './catalogue_data.js';

export const OUTCOME = { NONE: 0, RUNNERS_WIN: 1, PATROL_WIN: 2, CANCELLED: 3 };
export const ROLE = { RUNNER: 0, PATROL: 1 };
const E = CAT.economy;

const byId = new Map(CAT.items.map((it) => [it.id, it]));
export function item(id) {
  return byId.get(id) || null;
}
export function product(pid) {
  return CAT.products[pid] || null;
}
export function catalogueVersion() {
  return CAT.catalogue_version;
}
export function season(sid) {
  return CAT.seasons[sid] || null;
}
export function price(id) {
  const it = item(id);
  return it && (it.kind === 'coin_item' || it.kind === 'season_premium') ? it.price : 0;
}

function teamWon(row, outcome) {
  return (row.role === ROLE.RUNNER && outcome === OUTCOME.RUNNERS_WIN) || (row.role === ROLE.PATROL && outcome === OUTCOME.PATROL_WIN);
}

export function coinsPicked(row, coinSpawns) {
  const spawns = Math.min(Math.max(0, coinSpawns ?? E.eligibility.max_coin_spawns), E.eligibility.max_coin_spawns);
  return Math.min(Math.max(0, row.coins_picked | 0), spawns);
}

// Coins for one eligible completed round (the row is the host's report).
export function roundCoins(row, outcome, coinSpawns) {
  if (outcome === OUTCOME.CANCELLED) return 0;
  const c = E.round_coins;
  let n = c.completed + coinsPicked(row, coinSpawns) * c.pickup;
  if (teamWon(row, outcome)) n += c.team_win;
  if (row.role === ROLE.RUNNER) {
    if (row.finished) n += c.runner_home;
    if (row.first_home && row.finished) n += c.first_home;
  } else {
    n += Math.min(row.unique_captures | 0, c.watch_distinct_tag_cap) * c.watch_distinct_tag;
  }
  return n;
}

export function roundSeasonXp(row, outcome) {
  if (outcome === OUTCOME.CANCELLED) return 0;
  const c = E.season_xp;
  let n = c.completed;
  if (row.role === ROLE.RUNNER) {
    n += Math.min(Math.max(0, row.stamps | 0), c.stamp_cap) * c.stamp;
    if (row.finished) n += c.runner_home;
  } else {
    n += Math.min(Math.max(0, row.unique_captures | 0), c.watch_distinct_tag_cap) * c.watch_distinct_tag;
  }
  if (teamWon(row, outcome)) n += c.team_win;
  return n;
}

export function maxRoundCoins() {
  const c = E.round_coins;
  return c.completed + c.team_win + Math.max(c.runner_home + c.first_home, c.watch_distinct_tag * c.watch_distinct_tag_cap)
    + c.pickup * E.eligibility.max_coin_spawns;
}

export function presentEnough(row, roundTime) {
  const share = E.eligibility.present_share;
  return !!row.present && (roundTime <= 0 || (row.away_s || 0) <= (1 - share) * roundTime);
}

// GDScript round() is half away from zero; Math.round is half up: agree on
// non-negative values (times are never negative here).
function roundHalfAway(x) {
  return x < 0 ? -Math.round(-x) : Math.round(x);
}

// The row as both sides hash it (Economy.row_canonical in the game).
// v2 (Pass 8, report_version 2) appends active_s, the seconds of active play
// the host's simulation counted (challenges); a v1 row (no v) hashes as before.
export function rowCanonical(matchId, outcome, roundTime, row) {
  const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
  const v2 = (row.v | 0) >= 2;
  const parts = [v2 ? 'v2' : 'v1', matchId, outcome | 0, row.role | 0, clamp(row.stamps | 0, 0, 3), row.finished ? 1 : 0,
    row.first_home && row.finished ? 1 : 0, clamp(row.unique_captures | 0, 0, 7), Math.max(0, row.coins_picked | 0),
    row.present ? 1 : 0, roundHalfAway(Number(row.away_s) || 0), roundHalfAway(Number(roundTime) || 0)];
  if (v2) parts.push(Math.max(0, Math.trunc(Number(row.active_s) || 0)));
  return parts.join('|');
}

export async function rowDigest(matchId, outcome, roundTime, row) {
  const bytes = new TextEncoder().encode(rowCanonical(matchId, outcome, roundTime, row));
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return [...h].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// ---------------------------------------------------------------- season
export function tiers(sid) {
  return (season(sid) || { tiers: [] }).tiers;
}

export function tierForXp(sid, xp) {
  let t = 0;
  for (const r of tiers(sid)) if (xp >= r.xp) t = r.tier;
  return t;
}

// Pass 9: the last tier this service's table has (Season 1: 100; an older
// deployment's table: 30).  Reported in the snapshot so a game can tell
// which of its tiers this service can grant.
export function maxTier(sid) {
  return tiers(sid).length;
}

export function rewardAt(sid, tier, track) {
  const t = tiers(sid).find((r) => r.tier === tier);
  return t && t[track] ? t[track] : null;
}

export function claimKey(tier, track) {
  return `${tier}:${track}`;
}

// A reward as one string ("coins:50" or the item id), as season_claims.reward
// stores it and as a game names the reward it showed (Pass 9 claims).
export function rewardKey(r) {
  if (!r) return '';
  return r.coins ? `coins:${r.coins}` : String(r.item || '');
}

export function cellState(sid, tier, track, xp, premium, claimed) {
  if (!rewardAt(sid, tier, track)) return 'empty';
  if (claimed.has(claimKey(tier, track))) return 'claimed';
  if (tierForXp(sid, xp) < tier) return 'locked';
  if (track === 'premium' && !premium) return 'premium_locked';
  return 'claimable';
}

// ---------------------------------------------------------------- legacy
export function legacyImportAmount(coins, onlineRounds, practiceRounds) {
  const l = E.legacy_import;
  const plausible = Math.max(0, onlineRounds | 0) * l.per_online_round + Math.max(0, practiceRounds | 0) * l.per_practice_round;
  return Math.min(Math.max(0, Math.min(coins | 0, plausible)), l.cap);
}

export const ECONOMY = E;
export const CATALOGUE = CAT;
