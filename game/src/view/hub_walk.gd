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

const RETURN_SPEED := 2.0

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
var _last: Dictionary = {}         # key -> last drawn position (Vector2)
## frames in which movement input was read (tests: menu input never moves)
var moved_frames := 0


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
	p_stage.add_child(w)
	return w


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
	_last.clear()
	if stage != null and is_instance_valid(stage):
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
		var roaming := stage != null and is_instance_valid(stage) and not stage.free_roam.is_empty()
		if walking or roaming:
			reset()
		return
	var key := local_key()
	if walking and key != "":
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
		stage.walk_focus = Vector3(_pos.x, 0, _pos.y)
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
		if not s.is_empty() and int(s["mode"]) == HubSync.MODE_WALK:
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
	# strolling back to the mark
	for k in _returning.keys():
		var v: CharacterView = stage.chars.get(k)
		if v == null or not is_instance_valid(v) or (k == key and walking):
			_returning.erase(k)
			continue
		var at := Vector2(v.position.x, v.position.z)
		var mark := stage.mark_position(k)
		var to := Vector2(mark.x, mark.z) - at
		if to.length() < 0.06:
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
