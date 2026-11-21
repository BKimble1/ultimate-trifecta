class_name HubWalk
extends Node
## Walk around in the party room (V6).
##
## Menu mode (the default) is V5's composition: everyone on their mark,
## faces readable, names in the party panel.  Walk mode moves your own
## runner with the touch stick (HubStick), a controller's left stick or the
## keys, with collision against the room's furniture and walls (HubRoom).
## Party members see each other walk through HubSync (10 Hz poses from the
## host, drawn 150 ms in the past and interpolated); a member who stops
## walking strolls back to their mark.  Nameplates show over walkers.
##
## Ownership: movement is read only while walk mode is on, the party room
## screen is showing with no sheet or popover open and no menu owns input
## (InputOwner: the chat drawer, a keyboard).  Menu input never moves the
## runner.  Leaving the party room screen (Wardrobe/Locker, Shop, pass,
## results) or a round starting ends walk mode at once for this device;
## HubSync drops every pose at a start, so all members switch consistently.
## No jump, no player-to-player collision (nobody can be trapped or body-
## blocked), and avatars exist only for members of the roster.
##
## (build 20) Things to do: walk up to the couch, the floor lamp or the plant
## by the fireplace and prompt() offers what you can do there (LobbyScreen
## shows it as one button on the right).  Jumping on the couch hops you up
## onto the seat and you bounce until you press Stop jumping (the cushions
## squash under you); Hide ducks you into the plant (it rustles) until Jump
## out.  Everyone sees it: the couch and the plant are pose modes (HubSync),
## one person at a time, and each device draws the same hop up, bounce and
## hop down from the pose.  The lamp is one switch for the whole party.
##
## (build 24) The basketball (BallSync): walk up to it and the button says
## Pick up; holding it you dribble as you walk, the button says Shoot (the
## runner turns to the hoop, winds up and lets it go) and Drop and, with
## other people in the party, Pass sit above it.  You stand still for the
## windup.  Holding the ball, the couch, the lamp and the plant wait.

const RETURN_SPEED := 2.0
## (2.2 build 16) at most this long turning round on the mark
const TURN_S := 0.5
## (build 20) the couch and the plant
const COUCH_IN_S := 0.55
const COUCH_OUT_S := 0.5
const BOUNCE_S := 0.7
const BOUNCE_H := 0.42
const PLANT_IN_S := 0.4
const PLANT_OUT_S := 0.42

## (build 20) something to tell the player ("Someone's already on the couch")
signal notice(text: String)

var stage: DormStage
var session: NetSession
var walking := false
## the touch stick (x right, y up), set by HubStick
var stick := Vector2.ZERO
## the screen may veto movement (a sheet or popover is open)
var input_allowed: Callable
var _pos := Vector2.ZERO
var _vel := Vector2.ZERO
var _yaw := 0.0
var _returning: Dictionary = {}    # key -> true while walking back to its mark
var _turning: Dictionary = {}      # key -> seconds spent turning round on the mark
var _last: Dictionary = {}         # key -> last drawn position (Vector2)
## frames in which movement input was read (tests: menu input never moves)
var moved_frames := 0
## (build 20) what the local runner is doing: HubSync.MODE_WALK, MODE_COUCH
## or MODE_PLANT
var act := HubSync.MODE_WALK
## key -> {mode, phase ("in", "on", "out"), t, from (floor spot, Vector2),
## at (drawn position when the phase began), yaw0, last (Vector3), n}
var _acts: Dictionary = {}
var _hub_hooked: HubSync


static func attach(p_stage: DormStage, p_session: NetSession) -> HubWalk:
	for c in p_stage.get_children():
		if c is HubWalk:
			var hw := c as HubWalk
			hw.session = p_session
			return hw
	var w := HubWalk.new()
	w.name = "HubWalk"
	w.stage = p_stage
	w.session = p_session
	p_stage.busy_fn = func(k: String) -> bool: return is_instance_valid(w) and w._acts.has(k)
	p_stage.add_child(w)
	return w


## (build 20) the session's HubSync tells us when the couch or the plant
## was someone else's, and when the lamp goes off or on (connected once per
## session).
func _hook_hub() -> void:
	if session == null or not is_instance_valid(session):
		return
	var h := session.social.hub
	if h == _hub_hooked:
		return
	_hub_hooked = h
	h.denied.connect(_on_denied)
	h.lamp_changed.connect(func(on: bool) -> void:
		if stage != null and is_instance_valid(stage):
			stage.set_lamp(on))
	if stage != null and is_instance_valid(stage):
		stage.set_lamp(h.lamp_on, false)
	# (build 24) the basketball
	var b := session.social.ball
	if stage != null and is_instance_valid(stage) and stage.ball_view != null:
		stage.ball_view.ball = b
	b.made.connect(_on_made)


## (build 25) A basket: a tap for the shooter.  No words on screen (the
## confetti, the chime and the net say it).
func _on_made(slot: int, _swish: bool) -> void:
	if session == null or not is_instance_valid(session) or slot != session.local_slot:
		return
	Haptics.tap()


func local_key() -> String:
	if session == null or not is_instance_valid(session) or session.local_slot < 0 or session.roster[session.local_slot] == null:
		return ""
	return String(session.roster[session.local_slot]["uid"])


func in_party_room() -> bool:
	return session != null and is_instance_valid(session) and session.mode != NetSession.Mode.OFFLINE \
		and session.phase == TC.Phase.LOBBY and stage != null and is_instance_valid(stage)


## Walk mode on/off.  Turning it off walks the runner back to its mark.
func set_walking(on: bool) -> void:
	if on == walking:
		return
	var key := local_key()
	if on:
		if not in_party_room() or key == "":
			return
		var v: CharacterView = stage.chars.get(key)
		if v == null:
			return
		stage.stop_previews()
		walking = true
		_pos = HubRoom.resolve(Vector2(v.position.x, v.position.z))
		if _acts.has(key):
			_pos = _acts[key]["from"]   # (build 20) still hopping off the couch
		_yaw = v.rotation.y
		_vel = Vector2.ZERO
		_returning.erase(key)
		stage.free_roam[key] = true
		stage.walk_focus = Vector3(_pos.x, 0, _pos.y)
		stage.set_mode("walk")
		session.social.hub.set_local(HubSync.MODE_WALK, _pos, _yaw, 0.0)
	else:
		walking = false
		stick = Vector2.ZERO
		_vel = Vector2.ZERO
		Controls.reset_touch()
		if act != HubSync.MODE_WALK:
			# off the couch / out of the plant first, then the stroll back
			act = HubSync.MODE_WALK
			_end_act(key)
		if key != "" and stage.free_roam.has(key):
			_returning[key] = true
		if session != null and is_instance_valid(session):
			session.social.hub.set_local(HubSync.MODE_MARK, _pos, _yaw, 0.0)
		if stage != null and is_instance_valid(stage) and stage.mode == "walk":
			stage.set_mode("lobby")


## Leave walk mode with no stroll back (a round starting, the room closing):
## everyone is put straight back on their marks.
func reset() -> void:
	walking = false
	stick = Vector2.ZERO
	_vel = Vector2.ZERO
	_returning.clear()
	_turning.clear()
	_last.clear()
	act = HubSync.MODE_WALK
	_acts.clear()
	if stage != null and is_instance_valid(stage):
		stage.clear_hiding()
		stage.couch_bounce(0.0)
		for k in stage.free_roam.keys():
			stage.free_roam.erase(k)
			stage.place(k)
		if stage.mode == "walk":
			stage.set_mode("lobby", false)
		stage.show_names(false)


## May movement be read now?  (No menu, sheet or popover owns input.)
func input_open() -> bool:
	if InputOwner.menu_owns():
		return false
	return not input_allowed.is_valid() or bool(input_allowed.call())


func _movement_input() -> Vector2:
	if not input_open():
		return Vector2.ZERO
	if stick.length() > 0.05:
		return stick.limit_length(1.0)
	return Controls.get_move()


func _process(delta: float) -> void:
	if not in_party_room():
		# (build 20) the lamp is back on outside the party room
		if stage != null and is_instance_valid(stage) and stage.props != null and not stage.props.lamp_on:
			stage.set_lamp(true, false)
		var roaming := stage != null and is_instance_valid(stage) and not stage.free_roam.is_empty()
		if walking or roaming:
			reset()
		return
	_hook_hub()
	var key := local_key()
	if walking and key != "" and (act != HubSync.MODE_WALK or _acts.has(key)):
		# (build 20) on the couch, in the plant or hopping off: no walking
		_vel = Vector2.ZERO
		session.social.hub.set_local(act, _pos, _yaw, 0.0)
		stage.walk_focus = Vector3(_pos.x, 0.75 if act == HubSync.MODE_COUCH else 0.0, _pos.y)
	elif walking and key != "" and _winding():
		# (build 24) winding up a shot or a pass: plant your feet and turn to it
		_vel = Vector2.ZERO
		var aim := _wind_aim()
		if aim.distance_to(_pos) > 0.05:
			var ty := atan2(-(aim - _pos).x, -(aim - _pos).y)
			_yaw = lerp_angle(_yaw, ty, 1.0 - exp(-delta * 18.0))
		_draw(key, _pos, _yaw, Vector2.ZERO)
		session.social.hub.set_local(HubSync.MODE_WALK, _pos, _yaw, 0.0)
		stage.walk_focus = _focus(delta)
	elif walking and key != "":
		var inp := _movement_input()
		if inp != Vector2.ZERO:
			moved_frames += 1
		# screen up walks away from the camera (-z), right is +x
		var want := Vector2(inp.x, -inp.y) * HubRoom.WALK_SPEED
		_vel = _vel.lerp(want, 1.0 - exp(-delta * 10.0)) if input_open() else Vector2.ZERO   # a menu stops you at once
		if _vel.length() < 0.02 and want == Vector2.ZERO:
			_vel = Vector2.ZERO
		_pos = HubRoom.step(_pos, _vel * delta)
		if _vel.length() > 0.25:
			_yaw = atan2(-_vel.x, -_vel.y)
		_draw(key, _pos, _yaw, _vel)
		session.social.hub.set_local(HubSync.MODE_WALK, _pos, _yaw, _vel.length())
		stage.walk_focus = _focus(delta)
	# everyone else
	var hub := session.social.hub
	for i in 8:
		var e: Variant = session.roster[i]
		if e == null or bool(e["is_bot"]) or i == session.local_slot:
			continue
		var k := String(e["uid"])
		if not stage.chars.has(k):
			continue
		var s := hub.sample(i)
		var smode := int(s["mode"]) if not s.is_empty() else HubSync.MODE_MARK
		if HubSync.is_act(smode):
			# (build 20) on the couch / in the plant: everyone draws the hop
			_returning.erase(k)
			stage.free_roam[k] = true
			var a: Dictionary = _acts.get(k, {})
			if a.is_empty() or int(a["mode"]) != smode or String(a["phase"]) == "out":
				_start_act(k, smode, s["pos"])
			continue
		if _acts.has(k):
			if String(_acts[k]["phase"]) != "out":
				_end_act(k)
			continue   # hopping down / out first
		if smode == HubSync.MODE_WALK:
			_returning.erase(k)
			stage.free_roam[k] = true
			var p: Vector2 = s["pos"]
			var prev: Vector2 = _last.get(k, p)
			var vel := (p - prev) / maxf(delta, 0.001) if delta > 0.0 else Vector2.ZERO
			if vel.length() > HubRoom.WALK_SPEED * 2.0:
				vel = Vector2.ZERO   # a correction: no full-speed pose for it
			_draw(k, p, float(s["yaw"]), vel)
		elif stage.free_roam.has(k) and not _returning.has(k):
			_returning[k] = true
	# someone who left the party leaves no trace
	for k in stage.free_roam.keys():
		if not stage.chars.has(k):
			stage.free_roam.erase(k)
			_last.erase(k)
	# (build 20) the couch and the plant
	var bounce := 0.0
	for k in _acts.keys():
		bounce = maxf(bounce, _draw_act(k, delta))
	stage.couch_bounce(bounce)
	# strolling back to the mark
	for k in _returning.keys():
		if _acts.has(k):
			continue   # (build 20) off the couch / out of the plant first
		var v: CharacterView = stage.chars.get(k)
		if v == null or not is_instance_valid(v) or (k == key and walking):
			_returning.erase(k)
			continue
		var at := Vector2(v.position.x, v.position.z)
		var mark := stage.mark_position(k)
		var to := Vector2(mark.x, mark.z) - at
		if to.length() < 0.06:
			# (2.2 build 16) on the mark: turn to face the room smoothly, then
			# settle (it used to snap round in one frame)
			var turned := float(_turning.get(k, 0.0)) + delta
			_turning[k] = turned
			var ry := stage.rest_yaw(k)
			v.apply_state({"pos": stage.to_global(Vector3(mark.x, 0.0, mark.z)), "yaw": ry, "state": TC.PState.ACTIVE,
				"vel": Vector3.ZERO, "on_floor": true})
			if turned < TURN_S and absf(angle_difference(v.rotation.y, ry)) > 0.03:
				continue
			_turning.erase(k)
			_returning.erase(k)
			_last.erase(k)
			stage.free_roam.erase(k)
			stage.place(k)
			v.apply_state({"pos": v.global_position, "yaw": v.rotation.y, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true})
			continue
		var step := to.normalized() * minf(to.length(), RETURN_SPEED * delta)
		var np := at + step   # marks are on open floor: a straight stroll
		_draw(k, np, atan2(-to.x, -to.y), step / maxf(delta, 0.001))
	stage.show_names(walking or not stage.free_roam.is_empty())


func _draw(k: String, p: Vector2, yaw: float, vel: Vector2) -> void:
	var v: CharacterView = stage.chars.get(k)
	if v == null or not is_instance_valid(v):
		return
	_last[k] = p
	# an emote standing still plays out; walking away ends it
	if stage.emoting(k) and vel.length() < 0.2:
		v.position = Vector3(p.x, 0, p.y)
		return
	v.apply_state({"pos": stage.to_global(Vector3(p.x, 0.0, p.y)), "yaw": yaw, "vel": Vector3(vel.x, 0.0, vel.y),
		"on_floor": true, "state": TC.PState.ACTIVE, "fast": false})


# ---------------------------------------------------------------------------
# (build 20) Things to do in the room
# ---------------------------------------------------------------------------
## What the button beside the local runner offers right now: {} (nothing in
## reach) or {prop, text, icon, enabled}.
func prompt() -> Dictionary:
	var key := local_key()
	if not walking or key == "" or not in_party_room():
		return {}
	if act == HubSync.MODE_COUCH:
		return {"prop": HubRoom.PROP_COUCH, "text": "Stop jumping", "icon": "couch", "enabled": true}
	if act == HubSync.MODE_PLANT:
		return {"prop": HubRoom.PROP_PLANT, "text": "Jump out", "icon": "leaf", "enabled": true}
	if _acts.has(key):
		return {}   # hopping down
	# (build 24) the basketball comes first
	var ball := session.social.ball
	if ball.local_has():
		return {"prop": "ball", "text": "Shoot", "icon": "shoot", "enabled": ball.phase == BallSync.Phase.HELD}
	if ball.can_pickup(_pos):
		return {"prop": "ball_pick", "text": "Pick up", "icon": "ball", "enabled": true}
	var hub := session.social.hub
	match HubRoom.prop_near(_pos):
		HubRoom.PROP_COUCH:
			if hub.occupant(HubSync.MODE_COUCH) >= 0:
				return {"prop": HubRoom.PROP_COUCH, "text": "Couch taken", "icon": "couch", "enabled": false}
			return {"prop": HubRoom.PROP_COUCH, "text": "Jump on couch", "icon": "couch", "enabled": true}
		HubRoom.PROP_LAMP:
			return {"prop": HubRoom.PROP_LAMP, "text": "Lights off" if hub.lamp_on else "Lights on",
				"icon": "bulb", "enabled": true}
		HubRoom.PROP_PLANT:
			# (a hider stays secret: the button is always offered and the
			# host says if someone's already in there)
			return {"prop": HubRoom.PROP_PLANT, "text": "Hide", "icon": "leaf", "enabled": true}
	return {}


## The button was pressed (or the interact key): do what prompt() offers.
func interact() -> void:
	var p := prompt()
	if p.is_empty() or not bool(p.get("enabled", true)) or not input_open():
		return
	var key := local_key()
	var hub := session.social.hub
	match String(p["prop"]):
		"ball":
			session.social.ball.request(BallSync.ACT_SHOOT)
		"ball_pick":
			session.social.ball.request(BallSync.ACT_PICKUP)
		HubRoom.PROP_COUCH, HubRoom.PROP_PLANT:
			var mode := HubSync.prop_mode(String(p["prop"]))
			if act == mode:
				act = HubSync.MODE_WALK
				_end_act(key)
				hub.set_local(HubSync.MODE_WALK, _pos, _yaw, 0.0)
			else:
				act = mode
				_vel = Vector2.ZERO
				_start_act(key, mode, _pos)
				hub.set_local(mode, _pos, _yaw, 0.0)
		HubRoom.PROP_LAMP:
			# turn to the lamp and flick the switch
			var c: Array = HubRoom.CIRCLES[0]
			var to := Vector2(float(c[0]), float(c[1])) - _pos
			if to.length() > 0.01:
				_yaw = atan2(-to.x, -to.y)
				_draw(key, _pos, _yaw, Vector2.ZERO)
			hub.request_lamp()
	Haptics.tap()


## (build 24) The smaller buttons beside Shoot while you hold the ball:
## [{id, text, icon, enabled}] (Pass only with other people in the party).
func ball_extras() -> Array:
	if not walking or not in_party_room():
		return []
	var ball := session.social.ball
	if not ball.local_has():
		return []
	var on := ball.phase == BallSync.Phase.HELD
	var out: Array = []
	if ball.party_has_others():
		out.append({"id": "pass", "text": "Pass", "icon": "pass", "enabled": on})
	out.append({"id": "drop", "text": "Drop", "icon": "drop", "enabled": on})
	return out


func ball_action(id: String) -> void:
	if not walking or not input_open() or not in_party_room():
		return
	var ball := session.social.ball
	if not ball.local_has() or ball.phase != BallSync.Phase.HELD:
		return
	match id:
		"pass":
			var to := _pass_slot()
			if to < 0:
				notice.emit("Your friends need to tap Walk to catch a pass")
				return
			ball.request(BallSync.ACT_PASS, to)
		"drop":
			ball.request(BallSync.ACT_DROP)
	Haptics.tap()


## The party member to pass to: the one walking around nearest where
## you're facing (-1: nobody is walking around).
func _pass_slot() -> int:
	var hub := session.social.hub
	var best := -1
	var bs := -INF
	var fwd := Vector2(-sin(_yaw), -cos(_yaw))
	for i in 8:
		var e: Variant = session.roster[i]
		if i == session.local_slot or e == null or bool(e["is_bot"]) or hub.mode_of(i) != HubSync.MODE_WALK:
			continue
		var s := hub.sample(i)
		if s.is_empty():
			continue
		var to: Vector2 = (s["pos"] as Vector2) - _pos
		var score := fwd.dot(to.normalized()) * 2.0 - to.length() * 0.25
		if score > bs:
			bs = score
			best = i
	return best


## (build 24) Where the walk camera looks: at you, leaning toward the hoop
## while you have the ball and while your shot is in the air, so the hoop
## and the flight are on screen (not under the buttons on the right).
var _lean := 0.0


func _focus(delta: float) -> Vector3:
	var ball := session.social.ball
	var want := 0.0
	if ball.local_has() and (ball.phase == BallSync.Phase.HELD or ball.phase == BallSync.Phase.SHOT):
		want = 1.0
	elif ball.phase == BallSync.Phase.FREE and ball.sim.shooter == session.local_slot and ball.phase_t < 2.0 and not ball.sim.sleeping:
		want = 1.0
	_lean = move_toward(_lean, want, delta / 0.6)
	var rc := HubBall.rim_center()
	var to := Vector2(rc.x, rc.z) - _pos
	var k := _lean * _lean * (3.0 - 2.0 * _lean) * clampf((to.length() - 0.8) / 2.0, 0.0, 1.0)
	var f := _pos + to * 0.5 * k
	return Vector3(f.x, 0.0, f.y)


func _winding() -> bool:
	var ball := session.social.ball
	return ball.local_has() and (ball.phase == BallSync.Phase.SHOT or ball.phase == BallSync.Phase.PASS)


func _wind_aim() -> Vector2:
	var ball := session.social.ball
	if ball.phase == BallSync.Phase.SHOT:
		var rc := HubBall.rim_center()
		return Vector2(rc.x, rc.z)
	var s := session.social.hub.sample(ball.pass_to) if ball.pass_to >= 0 else {}
	if not s.is_empty():
		return s["pos"]
	return _pos + Vector2(-sin(_yaw), -cos(_yaw))


## The host gave the couch / the plant to someone else first.
func _on_denied(mode: int, taken: bool) -> void:
	if act == mode:
		act = HubSync.MODE_WALK
		_end_act(local_key())
	if not taken:
		return   # (out of reach by the time the host heard: just walk on)
	if mode == HubSync.MODE_COUCH:
		notice.emit("Someone's already on the couch")
	else:
		notice.emit("Someone's already hiding in there!")
		if stage != null and is_instance_valid(stage):
			stage.rustle_plant()


func _start_act(k: String, mode: int, from: Vector2) -> void:
	var v: CharacterView = stage.chars.get(k)
	if v == null or not is_instance_valid(v):
		return
	var at := stage.to_local(v.global_position)
	_acts[k] = {"mode": mode, "phase": "in", "t": 0.0, "from": from, "at": at, "yaw0": v.rotation.y,
		"last": at, "n": -1}
	stage.free_roam[k] = true
	_returning.erase(k)


func _end_act(k: String) -> void:
	var a: Dictionary = _acts.get(k, {})
	if a.is_empty() or String(a["phase"]) == "out":
		return
	a["at"] = a["last"]
	a["phase"] = "out"
	a["t"] = 0.0
	if int(a["mode"]) == HubSync.MODE_PLANT:
		a["at"] = HubRoom.plant_middle()
		if stage.is_hiding(k):
			stage.set_hiding(k, false)
			stage.rustle_plant()
			if _near(k):
				Sfx.play("hop", stage.to_global(a["at"]), -6.0)


## A hop from `a` to `b` (stage space) with an arc `h` high, u in 0..1.
static func _arc(a: Vector3, b: Vector3, u: float, h: float) -> Vector3:
	var e := u * u * (3.0 - 2.0 * u)
	var p := a.lerp(b, e)
	p.y = lerpf(a.y, b.y, u) + h * 4.0 * u * (1.0 - u)
	return p


## Close enough to the camera to be heard.
func _near(k: String) -> bool:
	if k == local_key():
		return true
	var v: Variant = stage.chars.get(k)
	return stage.cam != null and v != null and is_instance_valid(v) and stage.cam.global_position.distance_to((v as Node3D).global_position) < 14.0


## Draws one runner on the couch / in the plant; returns how hard the couch
## is being pressed down this frame (0..1.5).
func _draw_act(k: String, delta: float) -> float:
	var a: Dictionary = _acts[k]
	var v: CharacterView = stage.chars.get(k)
	if v == null or not is_instance_valid(v):
		_acts.erase(k)
		stage.set_hiding(k, false)
		return 0.0
	a["t"] = float(a["t"]) + delta
	var t := float(a["t"])
	var from: Vector2 = a["from"]
	var floor_p := Vector3(from.x, 0.0, from.y)
	var p := floor_p
	var yaw := v.rotation.y
	var on_floor := false
	var press := 0.0
	var phase := String(a["phase"])
	if int(a["mode"]) == HubSync.MODE_COUCH:
		var seat := HubRoom.couch_seat(from)
		match phase:
			"in":
				var u := minf(1.0, t / COUCH_IN_S)
				p = _arc(a["at"], seat, u, 0.5)
				# turning round to face the room on the way up
				yaw = lerp_angle(float(a["yaw0"]), PI, minf(1.0, u * 1.6))
				if u >= 1.0:
					a["phase"] = "on"
					a["t"] = 0.0
			"on":
				var n := int(t / BOUNCE_S)
				var u := fmod(t, BOUNCE_S) / BOUNCE_S
				# every fourth bounce goes higher
				var big := n % 4 == 3
				var h := BOUNCE_H * (1.5 if big else 1.0)
				p = seat + Vector3(0, h * 4.0 * u * (1.0 - u), 0)
				if stage.props != null:
					p.y -= stage.props.seat_drop()   # feet on the squashed cushion
				yaw = PI
				on_floor = u < 0.05 or u > 0.95
				press = (1.0 - smoothstep(0.0, 0.16, minf(u, 1.0 - u))) * (h / BOUNCE_H)
				if n != int(a["n"]):
					a["n"] = n
					if _near(k):
						Sfx.play("boing", stage.to_global(seat), -13.0 if big else -16.0, randf_range(0.92, 1.08))
			"out":
				var u2 := minf(1.0, t / COUCH_OUT_S)
				p = _arc(a["at"], floor_p, u2, 0.4)
				if u2 >= 1.0:
					_acts.erase(k)
	else:
		var mid := HubRoom.plant_middle()
		match phase:
			"in":
				var u := minf(1.0, t / PLANT_IN_S)
				p = _arc(a["at"], mid, u, 0.55)
				var to := Vector2(mid.x, mid.z) - from
				if to.length() > 0.05:
					yaw = atan2(-to.x, -to.y)
				if u >= 0.8 and not stage.is_hiding(k):
					stage.set_hiding(k, true)
					stage.rustle_plant()
					if _near(k):
						Sfx.play("hop", stage.to_global(mid), -6.0)
				if u >= 1.0:
					a["phase"] = "on"
					a["t"] = 0.0
			"on":
				p = mid
				if not stage.is_hiding(k):
					stage.set_hiding(k, true)
			"out":
				var u2 := minf(1.0, t / PLANT_OUT_S)
				p = _arc(a["at"], floor_p, u2, 0.5)
				var away := from - Vector2(mid.x, mid.z)
				if away.length() > 0.05:
					yaw = atan2(-away.x, -away.y)
				if u2 >= 1.0:
					_acts.erase(k)
	var last: Vector3 = a["last"]
	var vel := (p - last) / maxf(delta, 0.001) if delta > 0.0 else Vector3.ZERO
	a["last"] = p
	_last[k] = Vector2(p.x, p.z)
	if not _acts.has(k):
		vel = Vector3.ZERO
		on_floor = true
	v.apply_state({"pos": stage.to_global(p), "yaw": yaw, "vel": vel, "on_floor": on_floor,
		"state": TC.PState.ACTIVE, "fast": false, "quiet": true})
	return press
