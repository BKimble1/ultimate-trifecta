class_name ActivityMeter
extends RefCounted
## Pass 8: how long each human player actively played a round, counted by
## the authoritative simulation (host or practice) for challenges
## (docs/ECONOMY.md §10).  The result is the row's `active_s`, a whole
## number of seconds the host reports and every player's own game confirms
## in the row digest (Economy.row_canonical v2); the service checks it is
## bounded (never more than the round, never while away) and counts a round
## for challenges only when active_s >= min(60 s, 40% of the round).
##
## Evidence, per playing tick, for a slot a person controls (connected, no
## bot covering it):
##  - a fresh input (one that arrived this tick, never the host's repeat of
##    the last one) with a button press, a stick / steering / pedal change of
##    more than STICK_DELTA or a camera turn of more than YAW_DELTA since the
##    last evidence, or a steady stick that actually moves the player
##    (SPEED_MIN m/s);
##  - an objective event of their own: a water stamp, a home finish, a tag
##    on a runner, a coin.
## A tick counts as active within window_s (5 s) of evidence, which absorbs
## packet gaps.  Being captured, splashing and being home keep an active
## player active (they can't act then); a pause menu, idling, a held key
## against a wall or a bare connection gather no evidence, and a
## disconnected or bot-covered slot counts nothing until fresh evidence after
## it returns.  Bounded, plausible evidence, not anti-cheat: a modified host
## can still report any plausible number (docs/ECONOMY.md §5).

const STICK_DELTA := 0.12
const YAW_DELTA := 0.035          # about 2 degrees
const INTENT_MIN := 0.2
const SPEED_MIN := 1.0            # m/s of actual horizontal movement
const TELEPORT_M := 2.0           # a respawn is not movement
const HOLD := [TC.PState.CAPTURED, TC.PState.SPLASHING, TC.PState.FINISHED]

var window_ticks := 300
var _last := {}      # slot -> tick of the last evidence
var _ticks := {}     # slot -> active ticks
var _anchor := {}    # slot -> [move, steer, drive, cam_yaw, held] at the last evidence


func setup(sim_hz: int) -> void:
	var a: Dictionary = ChallengeRules.cfg().get("active", {})
	window_ticks = int(round(float(a.get("window_s", 5.0)) * float(sim_hz)))


## One playing tick, after the rules ran (`sim.events` holds this tick's
## events; `inputs` only the inputs that arrived for this tick).
func step(sim: MatchSim, inputs: Dictionary) -> void:
	var dt := sim.cfg.dt()
	var own := {}
	for ev in sim.events:
		match int(ev["type"]):
			TC.Ev.SPLASH_STAMP, TC.Ev.FINISH, TC.Ev.COIN_PICKUP:
				own[int(ev["a"])] = true
			TC.Ev.CAPTURE:
				own[int(ev["b"])] = true   # the Night Watch who tagged
	for p in sim.players:
		var slot := p.id
		if p.is_bot or p.bot_takeover or not p.connected:
			_last.erase(slot)
			_anchor.erase(slot)
			continue
		var last := int(_last.get(slot, -(1 << 30)))
		var cmd: Variant = inputs.get(slot)
		var evidence := own.has(slot)
		if cmd is InputCmd and _evidence(slot, cmd, p, dt):
			evidence = true
		if evidence:
			last = sim.tick
		elif p.state in HOLD and sim.tick - last <= window_ticks:
			last = sim.tick
		_last[slot] = last
		if sim.tick - last <= window_ticks:
			_ticks[slot] = int(_ticks.get(slot, 0)) + 1


func _evidence(slot: int, cmd: InputCmd, p: SimPlayer, dt: float) -> bool:
	var a: Array = _anchor.get(slot, [])
	var changed := cmd.pressed != 0 or (a.is_empty() and (cmd.move.length() > INTENT_MIN or cmd.held != 0))
	if not a.is_empty():
		changed = changed or (cmd.move - (a[0] as Vector2)).length() > STICK_DELTA or absf(cmd.steer - float(a[1])) > STICK_DELTA \
			or absf(cmd.drive - float(a[2])) > STICK_DELTA or absf(angle_difference(float(a[3]), cmd.cam_yaw)) > YAW_DELTA \
			or cmd.held != int(a[4])
	if not changed and (cmd.move.length() > INTENT_MIN or absf(cmd.drive) > INTENT_MIN) and is_finite(p.prev_pos.x):
		var d := Vector2(p.pos().x - p.prev_pos.x, p.pos().z - p.prev_pos.z).length()
		changed = d < TELEPORT_M and d / maxf(dt, 1e-6) >= SPEED_MIN
	# the first fresh input is the baseline later changes are measured from
	if changed or a.is_empty():
		_anchor[slot] = [cmd.move, cmd.steer, cmd.drive, cmd.cam_yaw, cmd.held]
	return changed


## Whole seconds of active play for a slot.
func active_s(slot: int, sim_hz: int) -> int:
	return floori(float(_ticks.get(slot, 0)) / float(maxi(1, sim_hz)))
