-- Pass 8 challenges: daily and weekly goals that add Season XP to the
-- existing pass (docs/ECONOMY.md §10).  Progress comes only from a verified
-- round's settlement (service/src/challenges.js runs inside settle()'s single
-- D1 batch), so a challenge can never move without the round paying, and a
-- round can never move a challenge twice.  Times are ms since the epoch.

-- One row per player and challenge instance.  An instance is one goal in
-- one UTC period: "d:2026-10-05:campus_contribution" (the day) or
-- "w:2026-10-05:pull_your_weight" (the week, by its Monday).  The goal, the
-- XP and the set version are copied from the catalogue when the instance is
-- first touched, so a later catalogue change never rewrites a running goal.
CREATE TABLE challenge_progress (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  instance_id TEXT NOT NULL,
  challenge_id TEXT NOT NULL,
  period TEXT NOT NULL,              -- daily | weekly
  period_start INTEGER NOT NULL,     -- 00:00 UTC (weekly: Monday 00:00 UTC)
  period_end INTEGER NOT NULL,       -- the next reset; settles until period_end + grace
  set_version INTEGER NOT NULL,      -- economy.challenges.version when created
  metric TEXT NOT NULL,              -- active_rounds | credits | round_wins
  goal INTEGER NOT NULL CHECK (goal > 0),
  xp INTEGER NOT NULL CHECK (xp >= 0),
  progress INTEGER NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= goal),
  completed_at INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, environment, instance_id)
);
CREATE INDEX challenge_progress_period ON challenge_progress(profile_id, environment, period_end);

-- The completion bonus, append-only: the primary key is the player and the
-- challenge instance, so the bonus XP can be delivered once.  match_id is
-- the round whose settlement completed it (that batch also added the XP).
CREATE TABLE challenge_bonus (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  instance_id TEXT NOT NULL,
  challenge_id TEXT NOT NULL,
  season TEXT NOT NULL,
  xp INTEGER NOT NULL CHECK (xp >= 0),
  match_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, environment, instance_id)
);
CREATE INDEX challenge_bonus_match ON challenge_bonus(profile_id, environment, match_id);

-- What each settled round did for a player's challenges (once per round:
-- the primary key fails a duplicate settlement batch as a whole).
-- state: applied | inactive | no_evidence | closed
CREATE TABLE challenge_rounds (
  profile_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  match_id TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  state TEXT NOT NULL,
  active_s INTEGER,
  active_rounds INTEGER NOT NULL DEFAULT 0,
  credits INTEGER NOT NULL DEFAULT 0 CHECK (credits >= 0 AND credits <= 3),
  round_wins INTEGER NOT NULL DEFAULT 0,
  closed TEXT,                       -- periods past their grace ("daily", "daily,weekly")
  at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, environment, match_id)
);

-- The round's challenge result, shown on its results (display copy; the
-- tables above are the record).
ALTER TABLE round_players ADD COLUMN challenge_xp INTEGER NOT NULL DEFAULT 0;
ALTER TABLE round_players ADD COLUMN challenge TEXT;
