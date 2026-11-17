extends Node
## Development-only footage (src/dev: never exported): a director's camera
## over a real round.  capture.gd creates it for --capture=film, with
## --autoplay=runner --local-bot, so every seat is played by the game's own
## bots in an ordinary offline practice round: the simulation, the bots, the
## campus, the characters, the water and the carts are the game's, nothing is
## staged or moved.  Only the camera is different: the round's HUD, touch
## controls and name tags are hidden and a free camera cuts between shots of
## whatever is happening (a chase, a runner reaching a water, a runner coming
## home, carts, wide views of the campus), chosen from the live round state.
## Record it with Movie Maker at a fixed clock:
##   tools/capture_film.sh OUT_DIR SEED [WxH]
## Every cut and game event is printed ("FILM ..."), so the clips can be cut
## from the recording by time.

var cam: Camera3D
var _t := 0.0           # recording time (s), the Movie Maker clock
var _shot := ""
var _shot_t := 0.0      # time the current shot started
var _subj := -1         # slot followed by the shot
var _aux := -1          # second slot (chase: the runner chased)
var _fixed := Vector3.INF   # fixed camera spot for water / home / door shots
var _look := Vector3.ZERO
var _pos := Vector3.ZERO
var _fwd := {}           # slot -> smoothed heading (Vector3)
var _orbit := 0.0
var _rng := RandomNumberGenerator.new()
var _ended_t := -1.0
var _started := false
var _go_t := -1.0
var _last_subj: Array = []
var _hooked := false
var _door: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000   # after MatchController placed its own camera
	_rng.seed = 7
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--seed="):
			_rng.seed = int(String(a).get_slice("=", 1)) * 31 + 7
	Save.set_setting("quality", QualityPreset.STANDARD)
	QualityPreset.apply(QualityPreset.STANDARD)
	var msaa := 0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--film-msaa="):
			msaa = int(String(a).get_slice("=", 1))
	get_viewport().msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}.get(msaa, Viewport.MSAA_DISABLED)
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	cam = Camera3D.new()
	cam.fov = 52.0
	cam.near = 0.15
	cam.far = 900.0


func _mc() -> MatchController:
	var mc: MatchController = App.match_ctrl
	if mc == null or not is_instance_valid(mc) or mc.sim == null:
		return null
	return mc


func _process(delta: float) -> void:
	_t += delta
	var mc := _mc()
	if mc == null:
		return
	if not mc.view_ready():
		return
	if cam.get_parent() == null:
		mc.add_child(cam)
	_quiet(mc)
	if not _hooked:
		_hooked = true
		mc.sim.event_emitted.connect(_on_event)
	cam.current = true
	var phase: int = mc.sim.phase
	if phase == TC.Phase.REVEAL or phase == TC.Phase.COUNTDOWN:
		_dorm_shot(mc, delta, false)
		return
	if phase != TC.Phase.PLAYING and _ended_t < 0.0:
		return
	if _go_t < 0.0:
		_go_t = _t
		printerr("FILM t=%.2f go" % _t)
	if _ended_t >= 0.0 and _t > _ended_t + 2.5:
		printerr("FILM t=%.2f quit" % _t)
		get_tree().quit()
		return
	if _t - _go_t < 1.7:
		_dorm_shot(mc, delta, false)
		return
	if _t - _go_t < 5.2 and not _door_done(mc):
		_dorm_shot(mc, delta, true)
		return
	_direct(mc, delta)


## The door shot has done its job once the runners are past it.
func _door_done(mc: MatchController) -> bool:
	if _shot != "door_out" or _t - _shot_t < 1.8 or _door.is_empty():
		return false
	var dp: Vector2 = _door["pos"]
	for p in mc.sim.players:
		if p.is_runner():
			var q := _ppos(mc, p.id)
			if Vector2(q.x, q.z).distance_to(dp) < 7.0:
				return false
	return true


## HUD, touch controls, name tags, toasts: hidden, every frame (views are
## created during the round too).
func _quiet(mc: MatchController) -> void:
	if mc.hud:
		mc.hud.visible = false
	if mc.touch:
		mc.touch.visible = false
	for v in mc.views.values():
		var cv := v as CharacterView
		if cv != null and cv.name_label != null:
			cv.name_label.visible = false
	if App._ui_layer:
		App._ui_layer.visible = false
	# sound effects only: the music tracks' rights are the owner's to clear
	for b in ["MusicA", "MusicB"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0 and not AudioServer.is_bus_mute(i):
			AudioServer.set_bus_mute(i, true)


func _on_event(ev: Dictionary) -> void:
	var names := TC.Ev.keys()
	var ty: int = int(ev["type"])
	var tn: String = names[ty] if ty >= 0 and ty < names.size() else str(ty)
	if ty in [TC.Ev.PHASE, TC.Ev.EMOTE]:
		return
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	printerr("FILMEV t=%.2f %s a=%d b=%d v=%d pos=%.1f,%.1f,%.1f shot=%s subj=%d" % [_t, tn, ev["a"], ev["b"], ev["v"], p.x, p.y, p.z, _shot, _subj])
	if ty == TC.Ev.MATCH_END and _ended_t < 0.0:
		_ended_t = _t


# ---------------------------------------------------------------- helpers
func _rs(mc: MatchController, slot: int) -> Dictionary:
	return mc._render_rs(slot)


func _ppos(mc: MatchController, slot: int) -> Vector3:
	var rs := _rs(mc, slot)
	var p: Vector3 = rs.get("pos", mc.sim.player(slot).pos())
	var st: int = rs.get("state", 0)
	if st == TC.PState.IN_CART or st == TC.PState.ENTERING:
		var ci := int(rs.get("cart_id", -1))
		if ci >= 0:
			var crs := mc._render_cart(ci)
			if crs.has("pos"):
				p = crs["pos"]
	return p


## Smoothed heading of a player (velocity when moving, else facing).
func _heading(mc: MatchController, slot: int, delta: float) -> Vector3:
	var p := mc.sim.player(slot)
	var v := p.vel
	v.y = 0.0
	var want: Vector3
	if p.cart_id >= 0:
		var c: SimCart = mc.sim.carts[p.cart_id]
		want = Basis(Vector3.UP, c.yaw) * Vector3(0, 0, -1)
	elif v.length() > 1.0:
		want = v.normalized()
	else:
		want = Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
	var cur: Vector3 = _fwd.get(slot, want)
	cur = cur.lerp(want, 1.0 - exp(-delta / 0.45))
	if cur.length() < 0.01:
		cur = want
	cur = cur.normalized()
	_fwd[slot] = cur
	return cur


## Pulls a camera spot in front of anything solid between it and the subject.
func _clear(mc: MatchController, from: Vector3, to: Vector3) -> Vector3:
	var ss := mc.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(from, to, TC.L_WORLD)
	var hit := ss.intersect_ray(rq)
	if hit.is_empty():
		return to
	var hp: Vector3 = hit["position"]
	return hp + (from - hp).normalized() * 0.35


func _place(pos: Vector3, look: Vector3, delta: float, tau_p: float, tau_l: float, cut: bool) -> void:
	if cut:
		_pos = pos
		_look = look
	else:
		_pos = _pos.lerp(pos, 1.0 - exp(-delta / tau_p))
		_look = _look.lerp(look, 1.0 - exp(-delta / tau_l))
	cam.global_position = _pos
	if _pos.distance_to(_look) > 0.05:
		cam.look_at(_look, Vector3.UP)


func _focus(mc: MatchController, p: Vector3) -> void:
	if mc._foliage_mat:
		mc._foliage_mat.set_shader_parameter("focus", Vector4(p.x, p.y + 0.85, p.z, 1.4))


func _cut(name: String, subj: int, aux: int = -1) -> void:
	_shot = name
	_shot_t = _t
	_subj = subj
	_aux = aux
	_fixed = Vector3.INF
	_orbit = _rng.randf_range(0.0, TAU)
	if subj >= 0:
		_last_subj.push_front(subj)
	if _last_subj.size() > 3:
		_last_subj.pop_back()
	printerr("FILM t=%.2f cut %s subj=%d aux=%d" % [_t, name, subj, aux])


# ---------------------------------------------------------------- the dorm
## Before GO and just after: inside the home dorm, by the door the runners
## face (they run at the camera and out past it); then outside that door as
## they burst out.
func _dorm_shot(mc: MatchController, delta: float, outside: bool) -> void:
	var runners: Array = []
	for p in mc.sim.players:
		if p.is_runner():
			runners.append(p)
	if runners.is_empty():
		return
	var c := Vector3.ZERO
	var face := Vector3.ZERO
	for p in runners:
		c += _ppos(mc, p.id)
		face += Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
	c /= float(runners.size())
	face.y = 0.0
	face = face.normalized() if face.length() > 0.01 else Vector3.FORWARD
	var want_shot := "door_out" if outside else "dorm"
	var cut := _shot != want_shot
	if cut:
		_cut(want_shot, runners[0].id)
	if not outside:
		# in front of the runners on their pads, looking back at them: faces
		# before GO, then they run at the camera and past it
		var side := face.cross(Vector3.UP).normalized()
		var cp := c + face * 4.6 + side * 0.8 + Vector3(0, 1.35, 0)
		var look := c + Vector3(0, 0.95, 0) - face * 0.6
		cp = _clear(mc, look, cp)
		_place(cp, look, delta, 0.6, 0.35, cut)
		cam.fov = 60.0
	else:
		if cut:
			# the door most runners are heading out of
			var best := -1
			_door = {}
			for d in mc.sim.home_doors:
				var dp0: Vector2 = d["pos"]
				var k0 := 0
				for p in runners:
					var q0 := _ppos(mc, p.id)
					var mine := true
					for e in mc.sim.home_doors:
						var ep: Vector2 = e["pos"]
						if Vector2(q0.x, q0.z).distance_to(ep) < Vector2(q0.x, q0.z).distance_to(dp0) - 0.01:
							mine = false
					if mine:
						k0 += 1
				if k0 > best:
					best = k0
					_door = d
		var fy: float = float(_door.get("floor_y", c.y))
		var n: Vector2 = _door["normal"]
		var tg: Vector2 = _door["tangent"]
		var ap: Vector2 = _door["approach"]
		var at2 := ap + n * 4.5 + tg * 2.6
		var cp2 := Vector3(at2.x, fy + 1.25, at2.y)
		var dp: Vector2 = _door["pos"]
		var mean := Vector3.ZERO
		var k := 0
		for p in runners:
			var q := _ppos(mc, p.id)
			if Vector2(q.x, q.z).distance_to(dp) < 14.0:
				mean += q
				k += 1
		var look2 := Vector3(dp.x, fy + 1.1, dp.y)
		if k > 0:
			look2 = look2.lerp(mean / float(k) + Vector3(0, 1.0, 0), 0.6)
		_place(cp2, look2, delta, 0.6, 0.25, cut)
		cam.fov = 56.0
	_focus(mc, c)


# ---------------------------------------------------------------- the round
const MIN_SHOT := 3.2
const MAX_SHOT := 6.8


## Only moments are rendered: between them the 3D view is switched off
## ("skip": black, cheap frames the edit drops), which keeps a software
## render of a whole round affordable.  An ambient shot (a runner or a
## cart travelling, a wide view) is let in every AMBIENT_EVERY seconds.
const AMBIENT_EVERY := 16.0
var _last_ambient := -100.0


func _set_skip(on: bool) -> void:
	get_viewport().disable_3d = on


func _take_hot(hot: Dictionary) -> void:
	_cut(String(hot["shot"]), int(hot["subj"]), int(hot.get("aux", -1)))
	if hot.has("fixed"):
		_fixed = hot["fixed"]
	if hot.has("door"):
		_door = hot["door"]
	_set_skip(false)


func _direct(mc: MatchController, delta: float) -> void:
	var age := _t - _shot_t
	var hot := _hot(mc)
	var is_hot := not hot.is_empty() and float(hot["score"]) >= 3.0
	if _shot == "skip":
		if _ended_t >= 0.0:
			printerr("FILM t=%.2f quit" % _t)
			get_tree().quit()
		elif is_hot:
			_take_hot(hot)
			_frame(mc, delta, true)
		elif _t - _last_ambient > AMBIENT_EVERY:
			_last_ambient = _t
			_cut_ambient(mc)
			_set_skip(false)
			_frame(mc, delta, true)
		return
	var need := _shot in ["", "dorm", "door_out"] or age > MAX_SHOT or not _valid(mc)
	if not need and age > MIN_SHOT and is_hot and float(hot["score"]) > _shot_score() + 0.5:
		need = true
	if not need and _shot in ["water", "home"] and age > MIN_SHOT and _done_fixed(mc):
		need = true
	if need:
		if is_hot:
			_take_hot(hot)
		elif _shot in ["", "dorm", "door_out"] or (_t - _last_ambient > AMBIENT_EVERY):
			_last_ambient = _t
			_cut_ambient(mc)
			_set_skip(false)
		else:
			_cut("skip", -1)
			_set_skip(true)
			return
		_frame(mc, delta, true)
	else:
		_frame(mc, delta, false)


func _shot_score() -> float:
	match _shot:
		"chase", "cart_chase":
			return 5.0
		"home":
			return 4.5
		"water":
			return 4.0
		"rift":
			return 3.5
	return 1.0


func _valid(mc: MatchController) -> bool:
	if _subj < 0 or mc.sim.player(_subj) == null:
		return false
	var p := mc.sim.player(_subj)
	if p.state == TC.PState.OUT or p.state == TC.PState.FINISHED:
		return _t - _shot_t < 2.2   # hold the moment, then move on
	if _shot in ["chase", "cart_chase"] and _aux >= 0:
		var r := mc.sim.player(_aux)
		if r == null or r.state in [TC.PState.FINISHED, TC.PState.OUT]:
			return _t - _shot_t < 2.0
		if _ppos(mc, _subj).distance_to(_ppos(mc, _aux)) > 22.0:
			return false
	return true


## Water / home shots end a moment after the moment.
func _done_fixed(mc: MatchController) -> bool:
	var p := mc.sim.player(_subj)
	if p == null:
		return true
	if _shot == "water":
		return p.state == TC.PState.ACTIVE and _fixed != Vector3.INF and _ppos(mc, _subj).distance_to(_fixed) > 16.0
	return p.state == TC.PState.FINISHED and _t - _shot_t > 1.5


## The most interesting thing happening now: {shot, subj, aux, score, ...}.
func _hot(mc: MatchController) -> Dictionary:
	var best := {}
	var s := mc.sim
	for w in s.players:
		if not w.is_patrol():
			continue
		var wp := _ppos(mc, w.id)
		var in_cart := w.cart_id >= 0
		for r in s.players:
			if not r.is_runner() or r.state != TC.PState.ACTIVE:
				continue
			var rp := _ppos(mc, r.id)
			var d := wp.distance_to(rp)
			var lim := 16.0 if in_cart else 10.0
			if d < lim:
				var closing := (rp - wp).normalized().dot(w.vel.normalized()) if w.vel.length() > 1.0 else 0.0
				var sc := 5.0 + (lim - d) * 0.15 + closing
				if _subj == w.id or _aux == r.id:
					sc += 0.3
				if best.is_empty() or sc > float(best["score"]):
					best = {"shot": "cart_chase" if in_cart else "chase", "subj": w.id, "aux": r.id, "score": sc}
	for r in s.players:
		if not r.is_runner() or r.state != TC.PState.ACTIVE:
			continue
		var rp := _ppos(mc, r.id)
		var all_in := true
		for i in mc.targets.size():
			if (r.stamps >> i) & 1 == 0:
				all_in = false
				var wd: Dictionary = mc.layout.waters[int(mc.targets[i])]
				var c2: Vector2 = wd["center"]
				var rad := _water_r(wd)
				var to := Vector2(c2.x - rp.x, c2.y - rp.z)
				var dist := to.length() - rad
				if dist < 11.0 and dist > 1.5 and r.vel.length() > 2.0:
					var dot := to.normalized().dot(Vector2(r.vel.x, r.vel.z).normalized())
					if dot > 0.75:
						var sc := 4.0 + (11.0 - dist) * 0.05
						if best.is_empty() or sc > float(best["score"]):
							# the far shore, a little to the side, looking back at the runner
							var away := to.normalized()
							var side := Vector2(-away.y, away.x) * (rad * 0.55 + 1.5) * (1.0 if r.id % 2 == 0 else -1.0)
							var spot := c2 + away * (rad + 2.6) + side
							var sy := float(wd.get("surface_y", 0.0))
							best = {"shot": "water", "subj": r.id, "score": sc, "fixed": Vector3(spot.x, sy + 1.15, spot.y)}
		if all_in:
			for d in s.home_doors:
				var dp: Vector2 = d["pos"]
				var dist2 := Vector2(rp.x, rp.z).distance_to(dp)
				if dist2 < 24.0 and dist2 > 4.0:
					var sc2 := 4.5 + (24.0 - dist2) * 0.03
					if best.is_empty() or sc2 > float(best["score"]):
						var ins: Vector2 = d["inside"]
						var tg: Vector2 = d["tangent"]
						var at := ins + tg * 1.0
						best = {"shot": "home", "subj": r.id, "score": sc2, "door": d,
							"fixed": Vector3(at.x, float(d.get("floor_y", 0.0)) + 1.2, at.y)}
	return best


func _water_r(wd: Dictionary) -> float:
	var r := float(wd.get("radius", 0.0))
	if r > 0.0:
		return r
	var rect: Variant = wd.get("rect", null)
	if rect is Rect2:
		return minf(12.0, minf((rect as Rect2).size.x, (rect as Rect2).size.y) * 0.5)
	return 5.0


## No action: a runner (or a Night Watch) in one of the travelling shots.
func _cut_ambient(mc: MatchController) -> void:
	var cands: Array = []
	for p in mc.sim.players:
		if p.state in [TC.PState.OUT, TC.PState.FINISHED, TC.PState.WAITING]:
			continue
		if p.id in _last_subj and _rng.randf() < 0.7:
			continue
		var w := 1.0
		if p.is_runner():
			w = 2.0 + float(_bits(p.stamps))
		elif p.cart_id >= 0:
			w = 1.6
		cands.append([p.id, w])
	if cands.is_empty():
		for p in mc.sim.players:
			if p.state != TC.PState.OUT:
				cands.append([p.id, 1.0])
	var tot := 0.0
	for c in cands:
		tot += float(c[1])
	var pick := _rng.randf() * tot
	var subj := int(cands[0][0])
	for c in cands:
		pick -= float(c[1])
		if pick <= 0.0:
			subj = int(c[0])
			break
	var kinds := ["follow", "side", "lead", "crane", "orbit", "low"]
	if mc.sim.player(subj).cart_id >= 0:
		kinds = ["cart_side", "cart_follow", "crane", "lead"]
	var k: String = kinds[_rng.randi() % kinds.size()]
	if k == _shot:
		k = kinds[(kinds.find(k) + 1) % kinds.size()]
	_cut(k, subj)


func _bits(v: int) -> int:
	var n := 0
	while v > 0:
		n += v & 1
		v >>= 1
	return n


## Places the camera for the current shot.
func _frame(mc: MatchController, delta: float, cut: bool) -> void:
	if _subj < 0 or mc.sim.player(_subj) == null:
		return
	var p := _ppos(mc, _subj)
	var f := _heading(mc, _subj, delta)
	var r := f.cross(Vector3.UP).normalized()
	var up := Vector3.UP
	var age := _t - _shot_t
	var pos: Vector3
	var look: Vector3
	var tp := 0.28
	var tl := 0.16
	match _shot:
		"follow":
			pos = p - f * 4.6 + r * 1.1 + up * 1.7
			look = p + f * 3.0 + up * 1.0
			cam.fov = 56.0
		"low":
			pos = p - f * 3.4 - r * 0.9 + up * 0.55
			look = p + f * 2.0 + up * 1.25
			cam.fov = 60.0
		"side":
			pos = p + r * 5.2 + up * 1.25 + f * 0.6
			look = p + f * 1.2 + up * 0.95
			cam.fov = 48.0
			tp = 0.35
		"lead":
			pos = p + f * 5.6 + r * 1.0 + up * 1.15
			look = p - f * 1.5 + up * 1.0
			cam.fov = 50.0
			tp = 0.3
		"crane":
			var lift := 7.0 + age * 1.6
			pos = p - f * (9.0 + age * 0.8) + r * 3.0 + up * lift
			look = p + f * 4.0
			cam.fov = 50.0
			tp = 0.5
			tl = 0.3
		"orbit":
			_orbit += delta * 0.32
			pos = p + Vector3(cos(_orbit), 0, sin(_orbit)) * 4.8 + up * 1.5
			look = p + up * 0.95
			cam.fov = 50.0
			tp = 0.18
		"cart_side":
			pos = p + r * 6.0 + up * 1.4 + f * 1.5
			look = p + f * 2.0 + up * 0.9
			cam.fov = 50.0
			tp = 0.3
		"cart_follow":
			pos = p - f * 7.0 + up * 2.6 + r * 1.2
			look = p + f * 5.0 + up * 0.9
			cam.fov = 56.0
		"chase", "cart_chase":
			var q := _ppos(mc, _aux) if _aux >= 0 else p + f * 5.0
			var dir := (q - p)
			dir.y = 0.0
			var dl := maxf(0.5, dir.length())
			dir = dir / dl
			var sd := dir.cross(Vector3.UP).normalized()
			var back := 6.5 if _shot == "cart_chase" else 4.2
			pos = p - dir * back + sd * 1.6 + up * (2.4 if _shot == "cart_chase" else 1.7)
			look = p.lerp(q, 0.62) + up * 0.9
			cam.fov = clampf(46.0 + dl * 1.4, 48.0, 66.0)
			tp = 0.22
		"water", "home", "rift":
			if _fixed == Vector3.INF:
				_fixed = p - f * 5.0 + up * 1.4
			pos = _fixed
			look = p + up * 0.9
			cam.fov = 50.0 if _shot == "water" else 54.0
			tl = 0.12
		_:
			pos = p - f * 4.6 + up * 1.7
			look = p + up * 1.0
	pos = _clear(mc, look, pos)
	_place(pos, look, delta, tp, tl, cut)
	_focus(mc, p)
