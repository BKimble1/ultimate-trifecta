extends RefCounted
## Build 18 rotating Shop outfits (two Thanksgiving, three Christmas, one
## winter): each key ships with real parts in the shared asset and a stable
## new ID; the included footwear, the elf cap and the three hoods follow
## their rules for every hat, shoe and hair choice; triangle and draw-call
## budgets against the heaviest look that shipped before; the head pieces
## sit outside the head and never cover the face; no outfit is darker than
## the night outfits already sold or as dark as the Night Watch's uniform;
## every outfit keeps its parts through the gameplay motion scenarios; the
## Shop catalogue sells each one only through the rotation, for Coins.
## Geometry is measured on the imported runner.glb (rest pose);
## tools/character/outfit_check.py checks the hoods, antlers, cap and the
## turkey's fan against the limbs through every clip.
var t

const OUTFITS := {"turkey_trot": 900, "harvest_flannel": 800, "reindeer_onesie": 1000, "gingerbread_buddy": 900, "elf_helper": 1100,
	"snow_day": 1200}
const IDS := {"turkey_trot": 24, "harvest_flannel": 25, "reindeer_onesie": 26, "gingerbread_buddy": 27, "elf_helper": 28, "snow_day": 29}
const HEADWEAR := {"elf_helper": "acc_elf_cap"}
const HOODS := ["turkey_trot", "reindeer_onesie", "snow_day"]
const OLD_SHOP := ["moonlight_runner", "starry_sleeper", "varsity_sprinter", "raincoat_explorer", "campus_courier", "lantern_scout",
	"midnight_mechanic", "moonwalk_cadet", "pumpkin_pajamas", "arcade_sprinter", "cloud_nine", "bedtime_bandit"]
## LOD0 triangles: an outfit part with its own footwear (the Pass 8 outfits
## are 10.1k-12.6k), an outfit's headwear
const OUTFIT_TRIS := 11500
const HEADWEAR_TRIS := 4500
## visible parts (one draw call each) of the heaviest look before
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
		var look := Cosmetics.sanitize({"outfit": k, "hat": "none", "shoes": "sneakers"})
		t.eq(String(Cosmetics.decode(Cosmetics.encode(look))["outfit"]), k, "%s survives the wire round trip" % k)
		t.eq(Cosmetics.migrate_owned(["outfit:" + k]), ["outfit:" + k], "an owned %s stays owned through the save migration" % k)
		# the Shop sells it only through the rotation, at the same Coin price
		var id: String = "outfit:" + k
		t.eq(Catalogue.kind(id), "coin_item", "%s is a Coin item" % id)
		t.check(Catalogue.is_rotation(id), "%s rotates" % id)
		t.eq(Catalogue.price(id), int(OUTFITS[k]), "%s: the catalogue and Cosmetics agree on the price" % id)
		t.check(Catalogue.has_art(id), "%s has art" % id)
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
				else:
					t.check(s2.has(Cosmetics.OUTFIT_PARTS[k][0]), "%s keeps the player's hat %s and hair %s" % [k, h, hair])
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
	t.check(int(new[0]) <= int(old[0]), "heaviest look with a build 18 outfit: %d triangles (heaviest look before: %d)" % [new[0], old[0]])
	t.check(int(new[1]) <= MAX_DRAW_CALLS, "at most %d parts (draw calls) on any build 18 look (%d)" % [MAX_DRAW_CALLS, new[1]])
	for k in OUTFITS:
		var p: String = Cosmetics.OUTFIT_PARTS[k][0]
		t.check(tri.call(p) <= OUTFIT_TRIS, "%s: %d triangles with its footwear (budget %d)" % [k, tri.call(p), OUTFIT_TRIS])
		if HEADWEAR.has(k):
			t.check(tri.call(HEADWEAR[k]) <= HEADWEAR_TRIS, "%s headwear: %d triangles (budget %d)" % [k, tri.call(HEADWEAR[k]), HEADWEAR_TRIS])
	var v := _view()
	var shared: Material = (v.parts["base"] as MeshInstance3D).material_override
	for k in OUTFITS:
		for p in [Cosmetics.OUTFIT_PARTS[k][0], HEADWEAR.get(k, "")]:
			if p != "":
				t.check((v.parts[p] as MeshInstance3D).material_override == shared, "%s uses the shared character material" % p)
	v.queue_free()
	_arrays(["turkey", "flannel", "reindeer", "gingerbread", "elf", "snowday"] + HEADWEAR.values())


## The head surface (rig.py via the manifest), Godot axes, as test_outfits_p8.
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


## The elf cap and the three hoods (with their antlers, beak, nose, ears
## and fur rim) lie outside the head, never in it, and nothing of them is in
## front of an eye, a brow or the mouth (looking at the face straight on).
func test_head_pieces_fit_and_keep_the_face_open() -> void:
	var head := Head.new(_manifest()["head"])
	var arrs := _arrays(["base", "acc_elf_cap", "turkey", "reindeer", "snowday", "hat_headphones"])
	var phones := INF
	for p in (arrs["hat_headphones"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
		phones = minf(phones, head.offset(p))
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
	for part in ["acc_elf_cap", "turkey", "reindeer", "snowday"]:
		var vs: PackedVector3Array = arrs[part][Mesh.ARRAY_VERTEX]
		var lo := INF
		var front := {}
		for p in vs:
			if p.y < 1.0:
				continue   # (the suit or parka body, the hood's neck skirt)
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


## Mean albedo (area-weighted, the fixed colours) of each new outfit against
## the outfits already sold and the Night Watch's uniform (as test_outfits_p8).
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


## Each outfit through the gameplay scenarios: its parts stay shown (and only
## they) through every state and teleport, and the pose is the default look's.
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
