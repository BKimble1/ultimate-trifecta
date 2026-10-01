class_name Autopilot
extends RefCounted
## Automation input for *client* processes in soak tests (no MatchSim there).
## Uses only what that client can see: its predicted self + interpolated others.
## Runners wander toward the active targets and jump in; patrol chases the
## nearest visible runner and tags when close. Labelled as automation input.

var rng := RandomNumberGenerator.new()
var wander := Vector2.ZERO
var wander_t := 0.0
var jump_cd := 0.0


func _init(seed_v: int) -> void:
	rng.seed = seed_v


func cmd_for(mc: MatchController) -> InputCmd:
	var c := InputCmd.new()
	if mc.pred == null:
		return c
	var dt := 1.0 / 60.0
	jump_cd = maxf(0.0, jump_cd - dt)
	var me := mc.pred.pos()
	var my2 := Vector2(me.x, me.z)
	if mc.pred.is_patrol():
		var best := Vector2.INF
		var bd := 1e9
		for slot in mc.roster:
			if int(mc.roster[slot]["role"]) != TC.Role.RUNNER:
				continue
			var rs := mc._player_rs(int(slot))
			if not rs.has("pos") or not bool(rs.get("visible", false)) or int(rs.get("state", 0)) != TC.PState.ACTIVE:
				continue
			var p: Vector3 = rs["pos"]
			var d := my2.distance_to(Vector2(p.x, p.z))
			if d < bd:
				bd = d
				best = Vector2(p.x, p.z)
		if best != Vector2.INF:
			c.move = (best - my2).normalized()
			c.cam_yaw = atan2(-c.move.x, -c.move.y)
			if bd < 1.5 and rng.randf() < 0.2:
				c.pressed |= TC.BTN_TAG
			return c
	else:
		# head for the first un-stamped target
		var rs2 := mc._player_rs(mc.local_slot)
		var stamps: int = rs2.get("stamps", 0)
		for i in mc.targets.size():
			if (stamps & (1 << i)) == 0:
				var w: Dictionary = mc.layout.waters[int(mc.targets[i])]
				var tgt: Vector2 = w["center"]
				if my2.distance_to(tgt) > 9.0:
					c.move = (tgt - my2).normalized()
				else:
					c.move = (tgt - my2).normalized()
					if jump_cd <= 0.0:
						c.pressed |= TC.BTN_JUMP
						jump_cd = 0.8
				if rng.randf() < 0.3:
					c.held |= TC.BTN_SPRINT
				break
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = rng.randf_range(0.6, 1.6)
		wander = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * 0.5
	c.move = (c.move + wander).limit_length(1.0)
	if c.move.length() < 0.1:
		c.move = wander
	if jump_cd <= 0.0 and rng.randf() < 0.01:
		c.pressed |= TC.BTN_JUMP
		jump_cd = 1.0
	return c
