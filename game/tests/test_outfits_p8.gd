extends RefCounted
## Pass 8 rotating Shop outfits: each of the six keys ships with real parts in
## the shared asset and a stable new ID; the included footwear, headwear and
## hoods follow their rules for every hat, shoe and hair choice; triangle and
## draw-call budgets against the heaviest look that shipped before; the head
## pieces sit outside the head and never cover the face; no outfit is darker
## than the night outfits already sold (no concealment advantage) or as dark
## as the Night Watch's uniform; every outfit keeps its parts through the
## gameplay motion scenarios; and no appearance changes the simulation.
## Geometry is measured on the imported runner.glb (rest pose: the head
## pieces are rigid on the head bone; tools/character/outfit_check.py checks
## them, the tail and the pack against the limbs through every clip).
var t

## the keys and Coin prices agreed with the Shop workstream (catalogue.json)
const OUTFITS := {"midnight_mechanic": 900, "moonwalk_cadet": 1200, "pumpkin_pajamas": 800, "arcade_sprinter": 900,
	"cloud_nine": 1000, "bedtime_bandit": 1000}
const IDS := {"midnight_mechanic": 16, "moonwalk_cadet": 17, "pumpkin_pajamas": 18, "arcade_sprinter": 19, "cloud_nine": 20,
	"bedtime_bandit": 21}
const HEADWEAR := {"moonwalk_cadet": "acc_cadet_cap", "pumpkin_pajamas": "acc_pumpkin_cap"}
const HOODS := ["cloud_nine", "bedtime_bandit"]
const OLD_SHOP := ["moonlight_runner", "starry_sleeper", "varsity_sprinter", "raincoat_explorer", "campus_courier", "lantern_scout"]
## LOD0 triangles: an outfit part with its own footwear, an outfit's headwear
const OUTFIT_TRIS := 13000
const HEADWEAR_TRIS := 4500
## visible parts (one draw call each) of the heaviest look before Pass 8
const MAX_DRAW_CALLS := 7
const GLB := "res://assets/characters/runner.glb"


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))


func _view() -> CharacterView:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false)
	return v


## Mesh arrays of the named parts (surface 0; checks each is one surface).
func _arrays(names: Array) -> Dictionary:
	var scene: Node = (load(GLB) as PackedScene).instantiate()
	var out := {}
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) in names:
			var mesh := (n as MeshInstance3D).mesh
			t.eq(mesh.get_surface_count(), 1, "%s is one surface (one draw call)" % n.name)
			out[String(n.name)] = mesh.surface_get_arrays(0)
	scene.free()
	return out


func test_six_outfits_ship_with_real_parts() -> void:
	var meshes: Dictionary = _manifest()["meshes"]
	var ids := {}
	for f in Cosmetics.CATALOG["outfit"]:
		var id := int(Cosmetics.entry("outfit", f)["id"])
		t.check(not ids.has(id), "outfit id %d is used once (%s)" % [id, f])
		ids[id] = f
	for k in OUTFITS:
		var e := Cosmetics.entry("outfit", k)
		t.check(not e.is_empty(), "%s is in the catalog" % k)
		if e.is_empty():
			continue
		t.eq(int(e["id"]), int(IDS[k]), "%s keeps its wire id" % k)
		t.eq(int(e.get("cost", 0)), int(OUTFITS[k]), "%s costs %d Coins" % [k, OUTFITS[k]])
		t.check(String(e.get("name", "")).length() >= 6 and not e.has("season"), "%s has a display name and is not a pass reward" % k)
		var inc: Array = e.get("includes", [])
		t.check(inc.size() >= 3, "%s lists what it includes (%d lines)" % [k, inc.size()])
		var ps: Array = Cosmetics.OUTFIT_PARTS.get(k, [])
		t.eq(ps.size(), 1, "%s is one outfit part" % k)
		for p in ps + ([HEADWEAR[k]] if HEADWEAR.has(k) else []):
			t.check(meshes.has(p) and int(meshes[p]["tris"]) > 2000, "%s part %s is real geometry in runner.glb (%d tris)" % [
				k, p, int(meshes.get(p, {}).get("tris", 0))])
		# the save and wire forms keep it
		var look := Cosmetics.sanitize({"outfit": k, "hat": "none", "shoes": "sneakers"})
		t.eq(String(Cosmetics.decode(Cosmetics.encode(look))["outfit"]), k, "%s survives the wire round trip" % k)
		t.eq(Cosmetics.own_key("outfit", k), "outfit:" + k, "%s's entitlement id is outfit:%s" % [k, k])
		t.eq(Cosmetics.migrate_owned(["outfit:" + k]), ["outfit:" + k], "an owned %s stays owned through the save migration" % k)
	# what each one replaces, and the copy that says so
	for k in OUTFITS:
		var inc_text := " ".join(PackedStringArray(Cosmetics.entry("outfit", k).get("includes", [])))
		var rep: Array = Cosmetics.outfit_replaces(k)
		t.check(rep.has("shoes") and inc_text.contains("instead of your shoes"), "%s draws its own footwear and says so" % k)
		t.eq(rep.has("hat"), k in HOODS, "%s replaces the hat only when it is a hood" % k)
		if k in HOODS:
			t.check(inc_text.contains("replaces hat and hair"), "%s says its hood replaces hat and hair" % k)
		if HEADWEAR.has(k):
			t.check(inc_text.contains("no other hat"), "%s says its cap shows with no other hat" % k)


func test_included_footwear_headwear_and_hoods() -> void:
	var v := _view()
	var shown := func(c: Dictionary) -> Array:
		v.set_appearance(TC.Role.RUNNER, Cosmetics.sanitize(c))
		var out: Array = []
		for n in v.parts:
			if (v.parts[n] as MeshInstance3D).visible:
				out.append(n)
		return out
	var hat_parts: Array = []
	for h in Cosmetics.keys_of("hat"):
		hat_parts.append_array(Cosmetics.entry("hat", h)["parts"])
	var hair_parts := ["hair", "hair_hat", "hair_bob", "hair_curly", "hair_curly_hat", "hair_curly_low", "hair_buns", "hair_buns_knots"]
	for k in OUTFITS:
		for sh in Cosmetics.keys_of("shoes"):
			var s: Array = shown.call({"outfit": k, "shoes": sh, "hat": "none"})
			t.check(s.has(Cosmetics.OUTFIT_PARTS[k][0]), "%s is drawn with %s chosen" % [k, sh])
			for p in Cosmetics.entry("shoes", sh)["parts"]:
				t.check(not s.has(p), "%s: its own footwear instead of %s" % [k, sh])
		for h in Cosmetics.keys_of("hat"):
			for hair in Cosmetics.keys_of("hair"):
				var s2: Array = shown.call({"outfit": k, "hat": h, "hair": hair})
				if k in HOODS:
					var leak: Array = s2.filter(func(p: String) -> bool: return p in hat_parts or p in hair_parts)
					t.eq(leak, [], "%s hood hides hat %s and hair %s" % [k, h, hair])
				elif HEADWEAR.has(k):
					t.eq(s2.has(HEADWEAR[k]), h == "none", "%s: its cap shows only with no hat (%s)" % [k, h])
					if h == "none":
						t.check(not s2.has("hair") and not s2.has("hair_curly") and not s2.has("hair_buns_knots"),
							"%s: no forelock, top curls or bun knots through the cap (%s)" % [k, hair])
	# the Night Watch wears its uniform whatever the outfit
	for k in OUTFITS:
		v.set_appearance(TC.Role.PATROL, Cosmetics.sanitize({"outfit": k, "hat": "none"}))
		var on: Array = []
		for p in [Cosmetics.OUTFIT_PARTS[k][0], HEADWEAR.get(k, "")]:
			if p != "" and (v.parts[p] as MeshInstance3D).visible:
				on.append(p)
		t.eq(on, [], "%s is never drawn on the Night Watch" % k)
		t.check((v.parts["watch"] as MeshInstance3D).visible, "the Night Watch keeps its uniform over %s" % k)
	v.queue_free()


func test_budgets_against_the_heaviest_look() -> void:
	var meshes: Dictionary = _manifest()["meshes"]
	var tri := func(p: String) -> int: return int(meshes.get(p, {}).get("tris", 0))
	var heaviest := func(outfits: Array) -> Array:
		var worst := 0
		var most := 0
		for o in outfits:
			for h in Cosmetics.keys_of("hat"):
				for sh in Cosmetics.keys_of("shoes"):
					for hair in Cosmetics.keys_of("hair"):
						for mk in Cosmetics.keys_of("marks"):
							var ps: Array = Cosmetics.runner_parts({"outfit": o, "hat": h, "shoes": sh, "hair": hair, "marks": mk})
							var n := 0
							for p in ps:
								n += tri.call(p)
							worst = maxi(worst, n)
							most = maxi(most, ps.size())
		return [worst, most]
	var before: Array = []
	for o in Cosmetics.keys_of("outfit"):
		if not OUTFITS.has(o):
			before.append(o)
	var old: Array = heaviest.call(before)
	var new: Array = heaviest.call(OUTFITS.keys())
	t.check(int(new[0]) <= int(old[0]), "heaviest look with a Pass 8 outfit: %d triangles (heaviest look before: %d)" % [new[0], old[0]])
	t.check(int(new[1]) <= MAX_DRAW_CALLS, "at most %d parts (draw calls) on any Pass 8 look (%d)" % [MAX_DRAW_CALLS, new[1]])
	for k in OUTFITS:
		var p: String = Cosmetics.OUTFIT_PARTS[k][0]
		t.check(tri.call(p) <= OUTFIT_TRIS, "%s: %d triangles with its footwear (budget %d)" % [k, tri.call(p), OUTFIT_TRIS])
		if HEADWEAR.has(k):
			t.check(tri.call(HEADWEAR[k]) <= HEADWEAR_TRIS, "%s headwear: %d triangles (budget %d)" % [k, tri.call(HEADWEAR[k]), HEADWEAR_TRIS])
	# one shared material (the visor is a material class inside it, like the goggles)
	var v := _view()
	var shared: Material = (v.parts["base"] as MeshInstance3D).material_override
	for k in OUTFITS:
		for p in [Cosmetics.OUTFIT_PARTS[k][0], HEADWEAR.get(k, "")]:
			if p != "":
				t.check((v.parts[p] as MeshInstance3D).material_override == shared, "%s uses the shared character material" % p)
	v.queue_free()
	_arrays(["mechanic", "cadet", "pumpkin", "arcade", "cloud", "bandit"] + HEADWEAR.values())


## The head surface (rig.py via the manifest), Godot axes, as test_characters_v7.
class Head:
	var c: Vector3
	var r: Vector3
	var pw: float

	func _init(h: Dictionary) -> void:
		var a: Array = h["center"]
		c = Vector3(a[0], a[1], a[2])
		var rr: Array = h["radii"]
		r = Vector3(rr[0], rr[1], rr[2])
		pw = float(h["power"])

	static func scale_at(zn: float) -> Vector2:
		var cheek := exp(-pow((zn + 0.30) / 0.42, 2.0))
		var top := clampf((zn - 0.25) / 0.75, 0.0, 1.0)
		top = top * top * (3.0 - 2.0 * top)
		return Vector2(1.0 + 0.075 * cheek - 0.045 * top, 1.0 + 0.035 * cheek - 0.02 * top)

	func f(p: Vector3, grow: float) -> float:
		var d := p - c
		var zn := d.y / (r.z + grow)
		var s := scale_at(clampf(zn, -1.0, 1.0))
		return pow(absf(d.x / ((r.x + grow) * s.x)), pw) + pow(absf(-d.z / ((r.y + grow) * s.y)), pw) + pow(absf(zn), pw)

	func offset(p: Vector3) -> float:
		var lo := -0.2
		var hi := 0.4
		for i in 36:
			var m := (lo + hi) * 0.5
			if f(p, m) > 1.0:
				lo = m
			else:
				hi = m
		return (lo + hi) * 0.5


## The caps, visor, ear pads and both hoods lie outside the head, never in
## it; nothing of them is in front of an eye, a brow or the mouth (looking at
## the face straight on); the visor is lifted above the brows.
func test_head_pieces_fit_and_keep_the_face_open() -> void:
	var head := Head.new(_manifest()["head"])
	var arrs := _arrays(["base", "acc_cadet_cap", "acc_pumpkin_cap", "cloud", "bandit", "hat_headphones"])
	# the shipped headphones' cups rest on the sides of the head the way the
	# cadet cap's ear pads do (their backs a few mm in, so no gap shows)
	var phones := INF
	for p in (arrs["hat_headphones"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
		phones = minf(phones, head.offset(p))
	# the face's features on the base mesh: eye whites (lit class), brows
	# (hair tint on the face), the mouth (its dark red)
	var bv: PackedVector3Array = arrs["base"][Mesh.ARRAY_VERTEX]
	var bc: PackedColorArray = arrs["base"][Mesh.ARRAY_COLOR]
	var buv2: PackedVector2Array = arrs["base"][Mesh.ARRAY_TEX_UV2]
	var feats := PackedVector3Array()
	for i in bv.size():
		var p := bv[i]
		if p.y < 1.0 or p.z > head.c.z - 0.12:
			continue
		var cls := 1.0 - buv2[i].y
		var mouth := bc[i].r > 0.08 and bc[i].g < 0.04 and bc[i].b < 0.05 and p.y < 1.11
		if absf(cls - 0.875) < 0.01 or (absf(bc[i].a - 0.2) < 0.02 and absf(p.x) < 0.17) or mouth:
			feats.append(p)
	t.check(feats.size() > 200, "face features found (%d vertices)" % feats.size())
	for part in ["acc_cadet_cap", "acc_pumpkin_cap", "cloud", "bandit"]:
		var vs: PackedVector3Array = arrs[part][Mesh.ARRAY_VERTEX]
		var lo := INF
		var near := PackedVector3Array()
		# front-most depth of the piece per 5 mm cell of the face plane
		var front := {}
		for p in vs:
			if p.y < 1.0:
				continue   # (the hoodie / sleep suit body and the hood's neck skirt)
			lo = minf(lo, head.offset(p))
			var key := Vector2i(int(floor(p.x * 200.0)), int(floor(p.y * 200.0)))
			front[key] = minf(float(front.get(key, INF)), p.z)
		var floor_m := phones - 0.001 if part.begins_with("acc_") else 0.004
		t.check(lo > floor_m, "%s lies outside the head (closest %.1f mm off the skin, limit %.1f)" % [part, lo * 1000.0, floor_m * 1000.0])
		var covered := 0
		for q in feats:
			var k := Vector2i(int(floor(q.x * 200.0)), int(floor(q.y * 200.0)))
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if float(front.get(k + Vector2i(dx, dy), INF)) < q.z - 0.002:
						covered += 1
		t.eq(covered, 0, "%s covers none of the eyes, brows or mouth seen from the front (within 1 cm)" % part)
	# the visor: lens class vertices, lifted above the brows (raised brows top out near 1.30 m)
	var cv: PackedVector3Array = arrs["acc_cadet_cap"][Mesh.ARRAY_VERTEX]
	var cuv2: PackedVector2Array = arrs["acc_cadet_cap"][Mesh.ARRAY_TEX_UV2]
	var lens_lo := INF
	var lens_n := 0
	for i in cv.size():
		if absf((1.0 - cuv2[i].y) - 0.6875) < 0.01:
			lens_n += 1
			lens_lo = minf(lens_lo, cv[i].y)
	t.check(lens_n > 100, "the cadet cap has a visor lens (%d vertices)" % lens_n)
	t.check(lens_lo > 1.31, "the visor is lifted above the brows (lowest point %.3f m)" % lens_lo)


## Mean albedo (area-weighted, the fixed colours: player-tinted vertices left
## out) of each new outfit against the night outfits already sold and the
## Night Watch's uniform: no new outfit is darker than they are, so none hides
## a runner better at night, and none is as dark as the uniform.
func test_no_concealment_and_no_uniform() -> void:
	var names: Array = []
	for k in OUTFITS:
		names.append(Cosmetics.OUTFIT_PARTS[k][0])
	for k in OLD_SHOP:
		names.append(Cosmetics.OUTFIT_PARTS[k][0])
	names.append("watch")
	var arrs := _arrays(names)
	var lum := func(part: String) -> float:
		var a: Array = arrs[part]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var sum := 0.0
		var area := 0.0
		for f in ix.size() / 3:
			var i0 := ix[f * 3]
			var i1 := ix[f * 3 + 1]
			var i2 := ix[f * 3 + 2]
			if cs[i0].a > 0.1 or cs[i1].a > 0.1 or cs[i2].a > 0.1:
				continue
			var ar := (vs[i1] - vs[i0]).cross(vs[i2] - vs[i0]).length() * 0.5
			var c := (cs[i0] + cs[i1] + cs[i2]) / 3.0
			sum += ar * (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
			area += ar
		return sum / maxf(area, 1e-9)
	var darkest := INF
	var darkest_k := ""
	for k in OLD_SHOP:
		var l: float = lum.call(Cosmetics.OUTFIT_PARTS[k][0])
		if l < darkest:
			darkest = l
			darkest_k = k
	var watch: float = lum.call("watch")
	for k in OUTFITS:
		var l2: float = lum.call(Cosmetics.OUTFIT_PARTS[k][0])
		t.check(l2 >= darkest, "%s is no darker than the darkest Shop outfit before it (%.3f vs %s %.3f)" % [k, l2, darkest_k, darkest])
		t.check(l2 >= watch * 1.5, "%s is clearly lighter than the Night Watch uniform (%.3f vs %.3f)" % [k, l2, watch])


## Each outfit through the gameplay scenarios (run, sprint, turn, jump and
## land, dive, tagged and back, splash, emote): its parts stay shown (and only
## they) through every state and teleport, and the pose is the default
## look's (the outfit changes nothing in the animation).
func test_every_outfit_moves() -> void:
	var scenarios := ["start", "stop", "reverse", "turn90", "sprint", "jump_run", "dive", "respawn", "splash", "emote"]
	var ref := {}
	for sc in scenarios:
		ref[sc] = float((await _scenario(Cosmetics.sanitize({"outfit": "pj", "hat": "none"}), sc, []))[0])
	for k in OUTFITS:
		var look := Cosmetics.sanitize({"outfit": k, "hat": "none", "hair": "bob", "shoes": "sneakers"})
		var want: Array = Cosmetics.runner_parts(look)
		var off: Array = []
		var wrong: Array = []
		for sc in scenarios:
			var r: Array = await _scenario(look, sc, want)
			if absf(float(r[0]) - float(ref[sc])) > 0.5:
				off.append("%s %.1f vs %.1f cm" % [sc, r[0], ref[sc]])
			if bool(r[1]):
				wrong.append(sc)
		t.eq(off, [], "%s: every scenario moves like the default look" % k)
		t.eq(wrong, [], "%s: its parts stay shown (and only they) through every state" % k)


## One motion-rig scenario on a look: [largest upper-body snap (cm), whether
## any part's visibility left `want` (skipped when `want` is empty)].
func _scenario(look: Dictionary, sc: String, want: Array) -> Array:
	var rig := MotionRig.new()
	t.add_child(rig)
	rig.start(sc, look, 0.0)
	var wrong := false
	while rig.running:
		await t.get_tree().process_frame
		if want.is_empty():
			continue
		for n in rig.view.parts:
			if (rig.view.parts[n] as MeshInstance3D).visible != want.has(n):
				wrong = true
	var pop := float(rig.metrics()["pop_cm"])
	rig.cleanup()
	rig.queue_free()
	return [pop, wrong]


func test_appearance_changes_nothing_in_the_sim() -> void:
	var runs: Array = []
	for look in [Cosmetics.DEFAULT, {"outfit": "bedtime_bandit", "shoes": "flippers"}, {"outfit": "moonwalk_cadet", "hat": "none"}]:
		var sim := MatchSim.new()
		t.add_child(sim)
		var roster: Array = []
		for i in 3:
			roster.append({"slot": i, "uid": "u%d" % i, "name": "P%d" % i, "is_bot": false, "role": TC.Role.RUNNER if i < 2 else TC.Role.PATROL,
				"cosmetic": Cosmetics.sanitize(look)})
		sim.setup(Rules.cfg, CampusLayout.shared(), roster, 7, [0, 1, 2], "outfit-sim-p8", {})
		var trace: Array = []
		for tick in 240:
			await t.get_tree().physics_frame
			var cmds := {}
			for s in 3:
				var c := InputCmd.new()
				c.move = Vector2(sin(tick * 0.05 + s), -cos(tick * 0.04 + s))
				if tick % 50 == 10 + s:
					c.pressed = TC.BTN_JUMP
					c.held = TC.BTN_JUMP
				cmds[s] = c
			sim.step(cmds)
			if tick % 20 == 0:
				for p in sim.players:
					trace.append((p as SimPlayer).pos().snapped(Vector3.ONE * 1e-4))
		runs.append(trace)
		sim.queue_free()
	t.check(runs[0].size() > 20, "positions were traced (%d)" % runs[0].size())
	t.eq(runs[1], runs[0], "a raccoon sleep suit with its tail moves exactly like the default look")
	t.eq(runs[2], runs[0], "a cadet suit with its cap and visor moves exactly like the default look")
