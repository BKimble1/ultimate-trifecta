// Pass 8 challenges: three daily and three weekly goals that add Season XP
// to the existing pass.  (2.2 build 22) The daily three come from a pool of
// 21 on a fixed Monday-to-Sunday schedule (economy.challenges.daily_pool /
// daily_schedule, UTC days, Monday first) that repeats every week; a round
// counts toward the daily three of the UTC day it started on.  The game's ChallengeRules (game/src/core/
// challenge_rules.gd) implements the same rules from the same catalogue
// numbers (economy.challenges).
//
//  - Progress only from a verified round's settlement: settle() in
//    commerce.js puts settleStmts() into its single D1 batch, so a round's
//    Coins, Season XP, challenge progress and any completion bonus land
//    together or not at all, and only once (round_players state, the round
//    ledger key and challenge_rounds' primary key).
//  - A round counts only when its row proves active play (report v2
//    active_s >= min(active.min_s, active.min_share x round time)), and then
//    adds: one active round, its contribution credits (unique water stamps +
//    different runners tagged, at most 3) and a Round Win when the player's
//    team won.  Role-flexible: runners and the Night Watch progress alike.
//  - A round belongs to the UTC day and week of its registered start
//    (rounds.started_at, the service's clock).  It settles into those
//    periods until grace_s after they end; later it adds nothing to them
//    ("closed").  A round started after a reset belongs to the new period,
//    so an expired goal never takes a new round.
//  - The bonus: INSERT OR IGNORE into challenge_bonus (primary key: player +
//    instance) for every touched instance at its goal, then the season XP
//    grows by the bonus rows this match created.  Concurrent settlements of
//    two rounds can't both deliver it; a repeated settlement fails its whole
//    batch.
import CAT from './catalogue_data.js';

export const DAY = 24 * 3600 * 1000;
const C = CAT.economy.challenges;
const OUTCOME = { RUNNERS_WIN: 1, PATROL_WIN: 2 };
const ROLE = { RUNNER: 0, PATROL: 1 };
// the report version that carries active_s (economy.js rowCanonical v2)
export const REPORT_VERSION = 2;

export function config() {
  return C;
}

export function dailyPool() {
  return C.daily_pool || C.daily || [];
}

// 0 Monday .. 6 Sunday (UTC; 1970-01-01 was a Thursday).
export function weekdayIndex(t) {
  return (Math.floor(t / DAY) + 3) % 7;
}

// The daily challenges of the UTC day containing t, in schedule order.
export function dailyDefs(t) {
  const sched = C.daily_schedule;
  const pool = dailyPool();
  if (!Array.isArray(sched) || sched.length !== 7) return pool.slice(0, 3);
  const out = sched[weekdayIndex(t)].map((id) => pool.find((d) => d.id === id)).filter(Boolean);
  return out.length ? out : pool.slice(0, 3);
}

// The goals in display order: the daily three of t's day, then weekly.
export function defs(t = Date.now()) {
  return [...dailyDefs(t).map((d) => ({ ...d, period: 'daily' })), ...C.weekly.map((d) => ({ ...d, period: 'weekly' }))];
}

// Every challenge there is (any day's daily and the weekly), by id.
export function defById(id) {
  const d = dailyPool().find((x) => x.id === id);
  if (d) return { ...d, period: 'daily' };
  const w = C.weekly.find((x) => x.id === id);
  return w ? { ...w, period: 'weekly' } : null;
}

export function graceMs() {
  return C.grace_s * 1000;
}

// ---------------------------------------------------------------- periods
export function dayStart(t) {
  return Math.floor(t / DAY) * DAY;
}

// Monday 00:00 UTC (1970-01-01 was a Thursday).
export function weekStart(t) {
  const d = Math.floor(t / DAY);
  return (d - ((d + 3) % 7)) * DAY;
}

export function periodOf(kind, t) {
  const start = kind === 'daily' ? dayStart(t) : weekStart(t);
  const end = start + (kind === 'daily' ? 1 : 7) * DAY;
  return { start, end, key: new Date(start).toISOString().slice(0, 10) };
}

export function instanceId(kind, key, cid) {
  return `${kind === 'daily' ? 'd' : 'w'}:${key}:${cid}`;
}

// ---------------------------------------------------------------- rounds
// Seconds of active play a round needs (documented in docs/ECONOMY.md §10).
export function activeNeed(roundTime) {
  return Math.min(C.active.min_s, C.active.min_share * Math.max(0, Number(roundTime) || 0));
}

export function activeEnough(row, roundTime) {
  if ((row.v | 0) < REPORT_VERSION) return false;
  const a = Number(row.active_s);
  return Number.isFinite(a) && a >= activeNeed(roundTime);
}

export function credits(row) {
  const s = Math.min(Math.max(0, row.stamps | 0), 3);
  const u = Math.max(0, row.unique_captures | 0);
  return Math.min(C.credit_cap_per_round, s + u);
}

function teamWon(row, outcome) {
  return (row.role === ROLE.RUNNER && outcome === OUTCOME.RUNNERS_WIN) || (row.role === ROLE.PATROL && outcome === OUTCOME.PATROL_WIN);
}

// Every metric a challenge can count (build 22: the daily pool's).
export const METRICS = ['active_rounds', 'credits', 'round_wins', 'stamps', 'trifectas', 'homes', 'first_homes', 'captures', 'coins',
  'runner_rounds', 'watch_rounds', 'runner_wins', 'watch_wins'];

// What one verified row adds: {state, and one count per METRICS entry}.
export function increments(row, outcome, roundTime) {
  const none = Object.fromEntries(METRICS.map((m) => [m, 0]));
  if ((row.v | 0) < REPORT_VERSION) return { state: 'no_evidence', ...none };
  if (!activeEnough(row, roundTime)) return { state: 'inactive', ...none };
  const runner = (row.role | 0) === ROLE.RUNNER;
  const won = teamWon(row, outcome);
  const stamps = runner ? Math.min(Math.max(0, row.stamps | 0), 3) : 0;
  const home = runner && !!row.finished;
  const coinCap = CAT.economy.eligibility.max_coin_spawns;
  return {
    state: 'applied', active_rounds: 1, credits: credits(row), round_wins: won ? 1 : 0,
    stamps, trifectas: stamps >= 3 ? 1 : 0, homes: home ? 1 : 0, first_homes: home && row.first_home ? 1 : 0,
    captures: runner ? 0 : Math.min(Math.max(0, row.unique_captures | 0), 7),
    coins: Math.min(Math.max(0, row.coins_picked | 0), coinCap),
    runner_rounds: runner ? 1 : 0, watch_rounds: runner ? 0 : 1, runner_wins: runner && won ? 1 : 0, watch_wins: !runner && won ? 1 : 0,
  };
}

// ---------------------------------------------------------------- settlement
// Statements for settle()'s batch (after its season_progress upsert).
// rd: the rounds row (started_at, outcome, round_time_s); row: the verified
// report row; t: now.  Returns {stmts, plan} (plan: what afterSettle reads).
export function settleStmts(q, e, pid, mid, rd, row, sid, t) {
  const inc = increments(row, rd.outcome, rd.round_time_s);
  const touched = [];
  const closed = [];
  const stmts = [];
  if (inc.state === 'applied') {
    for (const kind of ['daily', 'weekly']) {
      const per = periodOf(kind, rd.started_at);
      if (t > per.end + graceMs()) {
        closed.push(kind);
        continue;
      }
      for (const d of defs(rd.started_at).filter((x) => x.period === kind)) {
        const n = inc[d.metric] | 0;
        if (n <= 0) continue;
        const iid = instanceId(kind, per.key, d.id);
        touched.push({ instance_id: iid, challenge_id: d.id, period: kind, inc: n });
        stmts.push(q.stmt(`INSERT INTO challenge_progress (profile_id, environment, instance_id, challenge_id, period, period_start, period_end,
            set_version, metric, goal, xp, progress, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, MIN(?, ?), ?)
          ON CONFLICT(profile_id, environment, instance_id) DO UPDATE SET progress = MIN(challenge_progress.goal, challenge_progress.progress + ?),
            updated_at = excluded.updated_at`,
        pid, e, iid, d.id, kind, per.start, per.end, C.version, d.metric, d.goal, d.xp, d.goal, n, t, n));
        // the bonus, once per player and instance (the primary key)
        stmts.push(q.stmt(`INSERT OR IGNORE INTO challenge_bonus (profile_id, environment, instance_id, challenge_id, season, xp, match_id, at)
          SELECT profile_id, environment, instance_id, challenge_id, ?, xp, ?, ? FROM challenge_progress
          WHERE profile_id = ? AND environment = ? AND instance_id = ? AND progress >= goal`, sid, mid, t, pid, e, iid));
        stmts.push(q.stmt(`UPDATE challenge_progress SET completed_at = COALESCE(completed_at, ?)
          WHERE profile_id = ? AND environment = ? AND instance_id = ? AND progress >= goal`, t, pid, e, iid));
      }
    }
  }
  const state = inc.state === 'applied' && touched.length === 0 && closed.length > 0 ? 'closed' : inc.state;
  if (touched.length > 0) {
    // the Season XP grows by exactly the bonuses this round created
    stmts.push(q.stmt(`UPDATE season_progress SET xp = xp + (SELECT COALESCE(SUM(xp), 0) FROM challenge_bonus
        WHERE profile_id = ? AND environment = ? AND match_id = ?), updated_at = ? WHERE profile_id = ? AND environment = ? AND season = ?`,
    pid, e, mid, t, pid, e, sid));
    stmts.push(q.stmt(`UPDATE round_players SET challenge_xp = (SELECT COALESCE(SUM(xp), 0) FROM challenge_bonus
        WHERE profile_id = ? AND environment = ? AND match_id = ?) WHERE environment = ? AND match_id = ? AND profile_id = ?`,
    pid, e, mid, e, mid, pid));
  }
  // once per round and player: a duplicate settlement fails the whole batch
  stmts.push(q.stmt(`INSERT INTO challenge_rounds (profile_id, environment, match_id, started_at, state, active_s, active_rounds, credits, round_wins, closed, at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, pid, e, mid, rd.started_at, state,
  Number.isFinite(Number(row.active_s)) ? Math.round(Number(row.active_s)) : null, inc.active_rounds, inc.credits, inc.round_wins,
  closed.length ? closed.join(',') : null, t));
  return { stmts, plan: { state, touched, closed, inc, active_s: row.active_s ?? null, need: activeNeed(rd.round_time_s) } };
}

// After the batch committed: the round's challenge result for the results
// screen ({state, xp, items: [...], closed, credits, active_s, need}),
// stored on round_players for replays.
export async function afterSettle(q, e, pid, mid, plan) {
  const bonus = await q.all('SELECT instance_id, xp FROM challenge_bonus WHERE profile_id = ? AND environment = ? AND match_id = ?', pid, e, mid);
  const got = new Map(bonus.map((b) => [b.instance_id, b.xp]));
  const items = [];
  for (const tc of plan.touched) {
    const r = await q.one('SELECT progress, goal, xp, completed_at FROM challenge_progress WHERE profile_id = ? AND environment = ? AND instance_id = ?',
      pid, e, tc.instance_id);
    if (!r) continue;
    items.push({ challenge_id: tc.challenge_id, instance_id: tc.instance_id, period: tc.period, inc: tc.inc, progress: r.progress, goal: r.goal,
      completed: r.progress >= r.goal, completed_now: got.has(tc.instance_id), xp: got.get(tc.instance_id) || 0 });
  }
  const summary = {
    state: plan.state, xp: [...got.values()].reduce((a, b) => a + b, 0), items, closed: plan.closed,
    credits: plan.inc.credits, active_s: plan.active_s, need: Math.ceil(plan.need),
  };
  await q.run('UPDATE round_players SET challenge = ? WHERE environment = ? AND match_id = ? AND profile_id = ?', JSON.stringify(summary), e, mid, pid);
  return summary;
}

// ---------------------------------------------------------------- snapshot
// The player's challenges now (part of every wallet snapshot, so any device
// signed in to the profile sees the same progress): the current daily and
// weekly instances (untouched ones at 0), plus earlier instances still in
// their settlement grace that have progress (a completed reward from
// yesterday stays visible).
export async function snapshot(q, e, pid, t) {
  const rows = await q.all(`SELECT instance_id, challenge_id, period, period_start, period_end, set_version, metric, goal, xp, progress, completed_at
    FROM challenge_progress WHERE profile_id = ? AND environment = ? AND period_end > ? ORDER BY period_start`, pid, e, t - graceMs());
  const bonus = new Map((await q.all('SELECT instance_id, xp, match_id FROM challenge_bonus WHERE profile_id = ? AND environment = ? AND at > ?',
    pid, e, t - 8 * DAY - graceMs())).map((b) => [b.instance_id, b]));
  const byId = new Map(rows.map((r) => [r.instance_id, r]));
  const periods = { daily: periodOf('daily', t), weekly: periodOf('weekly', t) };
  const view = (r, d, current) => ({
    instance_id: r.instance_id, challenge_id: r.challenge_id, period: r.period, period_start: r.period_start, period_end: r.period_end,
    name: d ? d.name : r.challenge_id, task: d ? d.task : '', metric: r.metric, goal: r.goal, xp: r.xp, progress: r.progress,
    completed: r.progress >= r.goal, completed_at: r.completed_at || null, bonus_xp: bonus.has(r.instance_id) ? bonus.get(r.instance_id).xp : 0,
    set_version: r.set_version, current,
  });
  const items = [];
  const seen = new Set();
  for (const d of defs(t)) {
    const per = periods[d.period];
    const iid = instanceId(d.period, per.key, d.id);
    seen.add(iid);
    const r = byId.get(iid) || { instance_id: iid, challenge_id: d.id, period: d.period, period_start: per.start, period_end: per.end,
      set_version: C.version, metric: d.metric, goal: d.goal, xp: d.xp, progress: 0 };
    items.push(view(r, d, true));
  }
  const recent = rows.filter((r) => !seen.has(r.instance_id) && r.progress > 0).map((r) => view(r, defById(r.challenge_id), false));
  return {
    version: C.version, server_time: t, grace_s: C.grace_s,
    daily: { start: periods.daily.start, end: periods.daily.end }, weekly: { start: periods.weekly.start, end: periods.weekly.end },
    items, recent,
  };
}

// ---------------------------------------------------------------- lifecycle
export function deletionStmts(q, pid) {
  return [
    q.stmt('DELETE FROM challenge_progress WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM challenge_bonus WHERE profile_id = ?', pid),
    q.stmt('DELETE FROM challenge_rounds WHERE profile_id = ?', pid),
  ];
}

// Instances can't be touched after period end + grace, so their rows (and
// the bonus rows that guard them) can go once that is well past.
export async function sweep(q, t) {
  const old = t - 30 * DAY;
  await q.run('DELETE FROM challenge_progress WHERE period_end < ?', old - graceMs());
  await q.run('DELETE FROM challenge_bonus WHERE at < ?', old - 8 * DAY - graceMs());
  await q.run('DELETE FROM challenge_rounds WHERE at < ?', old);
}
