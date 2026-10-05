extends RefCounted
## Pass 9 garment fit, on the real imported runner.glb (docs/pass9/fit.md).
##
## tools/character/fit_check.py measures the exported asset offline (skin,
## inverse binds, 4 exported influences, every authored clip) and writes
## tests/data/fit_anchors.json: per look, vertex pairs that must stay together
## (a hem ring and the leg under it, a cuff and the wrist that comes out of
## it, a cap and its sleeve) with their bounds, and the skinned positions of
## those vertices in five clips as the asset defines them.  Here the game:
##   * checks the imported scene's skinning setup: every part's skeleton
##     path (explicit: Godot 4.6 changed MeshInstance3D's default), one skin
##     whose binds name the skeleton's bones and invert their rest exactly,
##     identity transforms, at most 4 normalised influences per vertex;
##   * re-skins the anchors on the CPU from the imported meshes and the
##     skeleton the AnimationPlayer poses, and compares with the asset's
##     own evaluation (imported vs runtime deformation);
##   * runs the gameplay motion scenarios (tests/motion_rig.gd: the 60 Hz
##     mini-motor -> interpolation -> CharacterView, AnimationTree blends,
##     pose fade, secondary motion, foot lock, springs) and measures every
##     anchor pair in the final pose of every frame (Skeleton3D's
##     skeleton_updated: after the last modifier, unlike pose_updated):
##     starts, stops, 180-degree reversals, a ramp, jumps and dive landings,
##     the Night Watch's tag overlays and cart, an emote interrupted by a
##     run, and a cosmetic swap mid-run;
##   * checks no blend layer is left latched after those interruptions.
## Regenerate the fixture after a character rebuild (tools/character/build.sh
## does it): python3 tools/character/fit_check.py --anchors game/tests/data/fit_anchors.json
var t

const GLB := "res://assets/characters/runner.glb"
const ANCHORS := "res://tests/data/fit_anchors.json"
## the shoe part -> the Cosmetics shoe key that shows it
const SHOE_OF := {"shoe_slippers": "slippers", "shoe_hightops": "sneakers", "shoe_flippers": "flippers", "shoe_glow": "glow_sneakers",
	"shoe_moonboots": "moon_boots"}
## the runtime matches the asset's own skinning to (m)
const IMPORT_TOL := 0.002
## runner scenarios and Night Watch scenarios run on every checked look
const RUNNER_SCENARIOS := ["start", "stop", "reverse", "ramp", "jump_run", "dive", "emote"]
const WATCH_SCENARIOS := ["nw_run", "tag_miss", "tag_hit", "cart"]
## the looks run through the motion scenarios: the Pass 8 Shop outfits, the
## Season 1 pass outfits and the default pajamas
const MOTION_LOOKS := ["midnight_mechanic", "moonwalk_cadet", "pumpkin_pajamas", "arcade_sprinter", "cloud_nine", "bedtime_bandit",
	"after_hours_hoodie", "night_owl", "glow_jogger", "library_cardigan", "pj", "record_breaker", "dr_doom"]


var _fixture: Dictionary = {}


func _data() -> Dictionary:
	if _fixture.is_empty():
		_fixture = JSON.parse_string(FileAccess.get_file_as_string(ANCHORS))
	return _fixture


## The look (Cosmetics) that shows a fixture look's parts.
func _cosmetic(key: String) -> Dictionary:
	var c := {"outfit": key if key != "night_watch" else "pj", "hat": "none"}
	for p in (_data()["looks"][key]["parts"] as Array):
		if SHOE_OF.has(p):
			c["shoes"] = SHOE_OF[p]
	return Cosmetics.sanitize(c)


# ---------------------------------------------------------------- CPU skinning
## Per part of a skeleton: arrays and the bind -> bone map.
class Skinner:
	var sk: Skeleton3D
	var parts := {}          # name -> {v, b, w, binds: PackedInt32Array, bind_pose: Array[Transform3D], index: Dictionary}

	func _init(skeleton: Skeleton3D) -> void:
		sk = skeleton
		for c in sk.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				var arr := mi.mesh.surface_get_arrays(0)
				var skin := mi.skin
				var binds := PackedInt32Array()
				var poses: Array[Transform3D] = []
				for i in skin.get_bind_count():
					var bn := String(skin.get_bind_name(i))
					binds.append(sk.find_bone(bn) if bn != "" else skin.get_bind_bone(i))
					poses.append(skin.get_bind_pose(i))
				parts[String(mi.name)] = {"v": arr[Mesh.ARRAY_VERTEX], "b": arr[Mesh.ARRAY_BONES], "w": arr[Mesh.ARRAY_WEIGHTS],
					"binds": binds, "bind_pose": poses, "index": {}}

	## The vertex of `part` at rest position p (exact float positions from the
	## asset), or -1.
	func find(part: String, p: Vector3) -> int:
		var e: Dictionary = parts.get(part, {})
		if e.is_empty():
			return -1
		var idx: Dictionary = e["index"]
		var v: PackedVector3Array = e["v"]
		if idx.is_empty():
			for i in v.size():
				idx[_key(v[i])] = i
		# (the fixture rounds to 0.01 mm: look in the neighbouring cells too)
		var k := _key(p)
		var best := -1
		var bd := 3e-4
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var i := int(idx.get(k + Vector3i(dx, dy, dz), -1))
					if i >= 0 and v[i].distance_to(p) < bd:
						bd = v[i].distance_to(p)
						best = i
		return best

	static func _key(p: Vector3) -> Vector3i:
		return Vector3i(roundi(p.x * 1e4), roundi(p.y * 1e4), roundi(p.z * 1e4))

	## Skinned position (skeleton space) of a vertex in the current pose.
	func skinned(part: String, i: int) -> Vector3:
		var e: Dictionary = parts[part]
		var v: Vector3 = (e["v"] as PackedVector3Array)[i]
		var b: PackedInt32Array = e["b"]
		var w: PackedFloat32Array = e["w"]
		var out := Vector3.ZERO
		for k in 4:
			var wt := w[i * 4 + k]
			if wt <= 0.0:
				continue
			var bi := b[i * 4 + k]
			out += (sk.get_bone_global_pose(int(e["binds"][bi])) * (e["bind_pose"][bi] as Transform3D) * v) * wt
		return out


## The fixture's pairs of a look resolved to vertex indices: [[part_a, ia, part_b, ib, pair]].
func _resolve(sk: Skinner, key: String) -> Array:
	var out := []
	var missing := 0
	for pr in (_data()["looks"][key]["pairs"] as Array):
		var a: Array = pr["a"]
		var b: Array = pr["b"]
		var ia := sk.find(String(a[0]), Vector3(a[1][0], a[1][1], a[1][2]))
		var ib := sk.find(String(b[0]), Vector3(b[1][0], b[1][1], b[1][2]))
		if ia < 0 or ib < 0:
			missing += 1
			continue
		out.append([String(a[0]), ia, String(b[0]), ib, pr])
	t.eq(missing, 0, "%s: every fit anchor is in the imported meshes (else regenerate %s)" % [key, ANCHORS])
	return out


# ---------------------------------------------------------------- tests
func test_imported_skinning_setup() -> void:
	var scene: Node3D = (load(GLB) as PackedScene).instantiate()
	t.add_child(scene)
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	t.check(sk.transform.is_equal_approx(Transform3D.IDENTITY), "the skeleton node sits at the scene origin")
	var rest_scale := 0.0
	for b in sk.get_bone_count():
		rest_scale = maxf(rest_scale, (sk.get_bone_rest(b).basis.get_scale() - Vector3.ONE).abs().length())
	t.check(rest_scale < 1e-4, "bone rests are unscaled (%.6f)" % rest_scale)
	var skins := {}
	var bad: Array = []
	var n := 0
	var max_err := 0.0
	var worst_sum := 0.0
	var zero := 0
	for c in sk.get_children():
		if not c is MeshInstance3D:
			continue
		var mi := c as MeshInstance3D
		n += 1
		var nm := String(mi.name)
		# (Godot 4.6 changed MeshInstance3D.skeleton's default from ".." to an
		# empty path: the importer must set it, or the part is drawn unskinned)
		if mi.skeleton == NodePath("") or mi.get_node_or_null(mi.skeleton) != sk:
			bad.append(nm + ": skeleton path " + str(mi.skeleton))
		if not mi.transform.is_equal_approx(Transform3D.IDENTITY):
			bad.append(nm + ": transform")
		if mi.skin == null:
			bad.append(nm + ": no skin")
			continue
		skins[mi.skin] = true
		if mi.skin.get_bind_count() != sk.get_bone_count():
			bad.append(nm + ": %d binds" % mi.skin.get_bind_count())
		for i in mi.skin.get_bind_count():
			var bone := sk.find_bone(mi.skin.get_bind_name(i))
			if bone < 0:
				bad.append(nm + ": bind " + String(mi.skin.get_bind_name(i)))
				continue
			var prod := sk.get_bone_global_rest(bone) * mi.skin.get_bind_pose(i)
			var e := prod.origin.length() + (prod.basis.x - Vector3.RIGHT).length() + (prod.basis.y - Vector3.UP).length() \
				+ (prod.basis.z - Vector3.BACK).length()
			max_err = maxf(max_err, e)
		var fmt: int = mi.mesh.surface_get_format(0)
		if (fmt & Mesh.ARRAY_FORMAT_BONES) == 0 or (fmt & Mesh.ARRAY_FORMAT_WEIGHTS) == 0 or (fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0:
			bad.append(nm + ": not 4 bone weights")
		var w: PackedFloat32Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]
		for i in range(0, w.size(), 4):
			var s := w[i] + w[i + 1] + w[i + 2] + w[i + 3]
			worst_sum = maxf(worst_sum, absf(s - 1.0))
			if s <= 1e-6:
				zero += 1
	t.check(n >= 53, "%d skinned parts" % n)
	t.eq(bad, [], "every part: an explicit skeleton path to the one skeleton, identity transform, a full named skin, 4 weights")
	t.eq(skins.size(), 1, "one Skin shared by every part (one armature)")
	t.check(max_err < 1e-4, "bind poses invert the bone rests (worst %.5f)" % max_err)
	t.check(worst_sum < 2e-3, "weights sum to 1 (worst off by %.5f)" % worst_sum)
	t.eq(zero, 0, "no unweighted vertex")
	scene.queue_free()
	# and on a live CharacterView: its parts keep the skeleton after setup
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false)
	var lost := 0
	for p in v.parts:
		var mi: MeshInstance3D = v.parts[p]
		if mi.get_node_or_null(mi.skeleton) != v.skeleton:
			lost += 1
	t.eq(lost, 0, "CharacterView's parts are all skinned to its skeleton")
	v.queue_free()


func test_runtime_deformation_matches_the_asset() -> void:
	var scene: Node3D = (load(GLB) as PackedScene).instantiate()
	t.add_child(scene)
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var skinner := Skinner.new(sk)
	var looks := 0
	var worst := 0.0
	var worst_at := ""
	for key in _data()["looks"]:
		var ref: Array = _data()["looks"][key].get("reference", [])
		if ref.is_empty():
			continue
		looks += 1
		var pairs := _resolve(skinner, key)
		if pairs.size() * 2 != (ref[0]["pos"] as Array).size():
			continue      # (_resolve reported the missing anchors)
		for r in ref:
			ap.play(String(r["clip"]))
			ap.seek(float(r["t"]), true)
			ap.pause()
			var pos: Array = r["pos"]
			for k in pairs.size():
				var pr: Array = pairs[k]
				for s in 2:
					var want: Array = pos[k * 2 + s]
					var got := skinner.skinned(String(pr[s * 2]), int(pr[s * 2 + 1]))
					var e := got.distance_to(Vector3(want[0], want[1], want[2]))
					if e > worst:
						worst = e
						worst_at = "%s %s %.2f %s" % [key, r["clip"], r["t"], pr[s * 2]]
	t.check(looks >= 6, "%d looks carry reference poses" % looks)
	t.check(worst < IMPORT_TOL, "the imported skeleton and skin deform the anchors as the asset does: worst %.2f mm (%s)" % [
		worst * 1000.0, worst_at])
	scene.queue_free()


## One scenario on a look, every pair measured in the final pose of every
## frame.  Returns {worst growth over bound (m), worst pair, frames}.
func _measure(key: String, sc: String, role_override := -1) -> Dictionary:
	var rig := MotionRig.new()
	t.add_child(rig)
	rig.start(sc, _cosmetic(key), 0.0)
	var skinner := Skinner.new(rig.view.skeleton)
	var pairs := _resolve(skinner, key)
	var st := {"over": -1.0, "worst": "", "frames": 0, "grow": 0.0}
	var fn := func() -> void:
		st["frames"] = int(st["frames"]) + 1
		for pr in pairs:
			var a := skinner.skinned(String(pr[0]), int(pr[1]))
			var b := skinner.skinned(String(pr[2]), int(pr[3]))
			var e: Dictionary = pr[4]
			var grow := a.distance_to(b) - float(e["rest"])
			var over := grow - float(e["bound"])
			if over > float(st["over"]):
				st["over"] = over
				st["grow"] = grow
				st["worst"] = "%s %s->%s at %.2f s (%s)" % [e["kind"], pr[0], pr[2], rig._sim_t, rig.view._mode]
	# the final pose: after the AnimationTree, the pose fade, secondary motion,
	# the foot lock and the springs (pose_updated fires before them)
	rig.view.skeleton.skeleton_updated.connect(fn)
	while rig.running:
		await t.get_tree().process_frame
	rig.view.skeleton.skeleton_updated.disconnect(fn)
	rig.cleanup()
	rig.queue_free()
	return st


func test_garments_stay_on_the_body_in_final_poses() -> void:
	var rows: Array = []
	for key in MOTION_LOOKS:
		var worst := {"over": -1.0}
		var at := ""
		for sc in RUNNER_SCENARIOS:
			var st: Dictionary = await _measure(key, sc)
			if float(st["over"]) > float(worst["over"]):
				worst = st
				at = sc
			t.check(int(st["frames"]) > 60, "%s %s: measured %d final poses" % [key, sc, st["frames"]])
		t.check(float(worst["over"]) <= 0.0, "%s: every anchor pair within its bound in every final pose (worst %s: %.1f cm parted, %s)" % [
			key, at, float(worst.get("grow", 0.0)) * 100.0, worst.get("worst", "")])
		rows.append("%s %.1f cm (%s)" % [key, float(worst.get("grow", 0.0)) * 100.0, at])
	# the Night Watch's uniform through its own states
	var nw := {"over": -1.0}
	var nw_at := ""
	for sc in WATCH_SCENARIOS:
		var st: Dictionary = await _measure("night_watch", sc)
		if float(st["over"]) > float(nw["over"]):
			nw = st
			nw_at = sc
	t.check(float(nw["over"]) <= 0.0, "night_watch: within bounds through run, tag overlays and the cart (worst %s: %.1f cm, %s)" % [
		nw_at, float(nw.get("grow", 0.0)) * 100.0, nw.get("worst", "")])
	print("FIT_P9 worst pair growth: ", ", ".join(PackedStringArray(rows)), "; night_watch %.1f cm (%s)" % [float(nw.get("grow", 0.0)) * 100.0, nw_at])


func test_cosmetic_swap_mid_run_keeps_the_gait_and_the_fit() -> void:
	var rig := MotionRig.new()
	t.add_child(rig)
	rig.start("sprint", _cosmetic("pj"), 0.0)
	# (shared with the signal callback: lambdas capture locals by value)
	var s := {"skinner": null, "pairs": [], "over": -1.0, "frames": 0}
	var fn := func() -> void:
		var sk: Skinner = s["skinner"]
		if sk == null:
			return
		s["frames"] = int(s["frames"]) + 1
		for pr in (s["pairs"] as Array):
			var a := sk.skinned(String(pr[0]), int(pr[1]))
			var b := sk.skinned(String(pr[2]), int(pr[3]))
			s["over"] = maxf(float(s["over"]), a.distance_to(b) - float(pr[4]["rest"]) - float(pr[4]["bound"]))
	rig.view.skeleton.skeleton_updated.connect(fn)
	var swapped := false
	var phase_before := 0.0
	var phase_after := 0.0
	while rig.running:
		await t.get_tree().process_frame
		if not swapped and rig._sim_t > 0.9:
			phase_before = rig.view._phase
			rig.view.set_appearance(TC.Role.RUNNER, _cosmetic("arcade_sprinter"))
			swapped = true
			var sk := Skinner.new(rig.view.skeleton)
			s["pairs"] = _resolve(sk, "arcade_sprinter")
			s["skinner"] = sk
			await t.get_tree().process_frame
			phase_after = rig.view._phase
			var want := Cosmetics.runner_parts(_cosmetic("arcade_sprinter"))
			var wrong := 0
			for n in rig.view.parts:
				if (rig.view.parts[n] as MeshInstance3D).visible != want.has(n):
					wrong += 1
			t.eq(wrong, 0, "after the swap exactly the new look's parts show")
	rig.view.skeleton.skeleton_updated.disconnect(fn)
	var m := rig.metrics()
	t.check(phase_after > phase_before and phase_after - phase_before < 0.1, "the gait carries on through the swap (phase %.3f -> %.3f)" % [
		phase_before, phase_after])
	t.check(float(m["pop_cm"]) < 6.0, "no pose snap at the swap (%.1f cm)" % m["pop_cm"])
	t.check(int(s["frames"]) > 30 and float(s["over"]) <= 0.0,
		"the swapped-in outfit fits from its first frame (%d frames, worst over bound %.1f cm)" % [s["frames"], float(s["over"]) * 100.0])
	rig.cleanup()
	rig.queue_free()


func test_interruptions_leave_no_layer_latched() -> void:
	# a reversal is not a stop; a stop plays once and lets go
	for sc in ["reverse", "stop", "tag_miss", "tag_hit", "emote", "dive", "jump_run"]:
		var rig := MotionRig.new()
		t.add_child(rig)
		rig.start(sc, Cosmetics.DEFAULT, 0.0)
		while rig.running:
			await t.get_tree().process_frame
		var v := rig.view
		# let the last overlays finish (0.6 s of standing or running on)
		for i in 36:
			v.apply_state(v.rs.merged({"emote_t": 0.0}, true), 1.0 / 60.0)
			await t.get_tree().process_frame
		if sc == "reverse":
			t.eq(v.stat_stops, 0, "reverse: a 180-degree reversal at full speed never plays the planted stop")
		if sc == "stop":
			t.eq(v.stat_stops, 1, "stop: one planted stop")
		t.check(not bool(v.tree.get("parameters/stop/active")), "%s: the planted stop is not left playing" % sc)
		t.near(float(v.tree.get("parameters/act/blend_amount")), 0.0, 1e-4, "%s: the tag action layer is released" % sc)
		t.eq(v._act, "", "%s: no action latched" % sc)
		t.check(v._brake_w < 0.05 and v._lead_w < 0.05 and v._accel_w < 0.3, "%s: drive/brake/lead layers ease off (%.2f %.2f %.2f)" % [
			sc, v._accel_w, v._brake_w, v._lead_w])
		t.check(not v.pose_fade.fading(), "%s: no pose fade left running" % sc)
		rig.cleanup()
		rig.queue_free()
