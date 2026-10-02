extends RefCounted
## V6 Shop and Season 1 character content: every advertised key exists with
## real parts in the shared asset, the outfits' own headwear/footwear rules,
## the new emotes (clips, wire order, icons, lobby timing), the triangle
## budgets, motion through gameplay-like scenarios for every new outfit, and
## that no appearance changes anything in the simulation.
var t

## The keys agreed with the commerce workstream (its tables reference them).
const SHOP_OUTFITS := ["moonlight_runner", "starry_sleeper", "varsity_sprinter", "raincoat_explorer", "campus_courier", "lantern_scout"]
const SEASON := {
	"outfit": ["after_hours_hoodie", "night_owl", "glow_jogger", "library_cardigan"],
	"hat": ["headlamp", "pompom_beanie", "glow_headband", "owl_ears"],
	"shoes": ["glow_sneakers", "moon_boots"],
	"emote": ["stargaze", "victory_lap", "shush", "moon_shuffle"],
}
## LOD0 triangle budgets (V5 typical look: base + pajamas + nightcap +
## slippers = 23.4k; tools/character/README.md)
const OUTFIT_TRIS := 12500
const HAT_TRIS := 4500
const SHOE_TRIS := 3500
## the heaviest V6 look may not exceed the heaviest V5 look (robe + body +
## curls + headphones + slippers, ~29.8k)
const V5_OUTFITS := ["pj", "swim", "robe", "duck", "frog"]
const V5_HATS := ["none", "nightcap", "swimcap", "party", "headphones", "crown"]
const V5_SHOES := ["slippers", "sneakers", "flippers"]


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))


func _view() -> CharacterView:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false)
	return v


func test_every_v6_key_ships_with_real_parts() -> void:
	var m := _manifest()
	var meshes: Dictionary = m["meshes"]
	var keys := {"outfit": SHOP_OUTFITS + SEASON["outfit"], "hat": SEASON["hat"], "shoes": SEASON["shoes"], "emote": SEASON["emote"]}
	for f in keys:
		for k in keys[f]:
			var e := Cosmetics.entry(f, k)
			t.check(not e.is_empty(), "%s:%s is in the catalog" % [f, k])
			if e.is_empty():
				continue
			t.check(String(e.get("name", "")).length() >= 4, "%s:%s has a display name (%s)" % [f, k, e.get("name", "")])
			t.check(int(e.get("cost", 0)) > 0, "%s:%s is not free to everyone" % [f, k])
			var ps: Array = Cosmetics.OUTFIT_PARTS.get(k, []) if f == "outfit" else e.get("parts", [])
			if f != "emote":
				t.check(not ps.is_empty(), "%s:%s names its parts" % [f, k])
			for p in ps:
				t.check(meshes.has(p) and int(meshes[p]["tris"]) > 500, "%s:%s part %s is real geometry in runner.glb" % [f, k, p])
			if f == "outfit":
				var inc: Array = e.get("includes", [])
				t.check(inc.size() >= 2, "%s lists exactly what it includes (%d lines)" % [k, inc.size()])
			if SEASON.get(f, []).has(k):
				t.eq(int(e.get("season", 0)), 1, "%s:%s is marked as a Season 1 reward" % [f, k])
	for hw in Cosmetics.OUTFIT_HEADWEAR.values():
		for p in hw["parts"]:
			t.check(meshes.has(p), "outfit headwear %s is in runner.glb" % p)
	t.check(meshes.has("hair_hat"), "the tuft's hat variant is in runner.glb")


func test_outfit_headwear_and_footwear_rules() -> void:
	var v := _view()
	var shown := func(c: Dictionary) -> Array:
		v.set_appearance(TC.Role.RUNNER, Cosmetics.sanitize(c))
		var out: Array = []
		for n in v.parts:
			if (v.parts[n] as MeshInstance3D).visible:
				out.append(n)
		return out
	# the sleep mask: with no hat and small hats; hidden under hats on the forehead
	for h in ["none", "party", "headphones", "crown", "owl_ears"]:
		var s: Array = shown.call({"outfit": "starry_sleeper", "hat": h, "hair": "tuft"})
		t.check(s.has("acc_sleepmask"), "sleep mask worn with %s" % h)
		t.check(not s.has("hair") and s.has("hair_hat"), "the tuft's forelock is tucked away under the mask (%s)" % h)
	for h in ["nightcap", "swimcap", "pompom_beanie", "glow_headband", "headlamp"]:
		var s2: Array = shown.call({"outfit": "starry_sleeper", "hat": h})
		t.check(not s2.has("acc_sleepmask"), "sleep mask hidden under %s" % h)
	# the courier cap: only without another hat; the chosen hat always wins
	t.check((shown.call({"outfit": "campus_courier", "hat": "none"}) as Array).has("acc_courier_cap"), "courier cap with no hat")
	for h in Cosmetics.keys_of("hat"):
		if h == "none":
			continue
		var s3: Array = shown.call({"outfit": "campus_courier", "hat": h})
		t.check(not s3.has("acc_courier_cap"), "courier cap gives way to %s" % h)
	var cap: Array = shown.call({"outfit": "campus_courier", "hat": "none", "hair": "curly"})
	t.check(cap.has("hair_curly_hat") and not cap.has("hair_curly"), "curls use their smooth-band variant under the cap")
	var knots: Array = shown.call({"outfit": "campus_courier", "hat": "none", "hair": "buns"})
	t.check(knots.has("hair_buns") and not knots.has("hair_buns_knots"), "space buns' knots hidden under the cap")
	# the raincoat's own boots replace the chosen shoes, for every shoe
	for sh in Cosmetics.keys_of("shoes"):
		var s4: Array = shown.call({"outfit": "raincoat_explorer", "shoes": sh})
		for p in Cosmetics.entry("shoes", sh)["parts"]:
			t.check(not s4.has(p), "rain boots instead of %s" % sh)
	# the owl hood replaces hat and hair, like the duck and frog
	var owl: Array = shown.call({"outfit": "night_owl", "hat": "crown", "hair": "buns"})
	t.check(owl.has("owl") and not owl.has("hat_crown") and not owl.has("hair_buns"), "owl hood replaces hat and hair")
	# headwear never shows on the Night Watch (it wears the uniform)
	v.set_appearance(TC.Role.PATROL, Cosmetics.sanitize({"outfit": "campus_courier", "hat": "none"}))
	t.check(not (v.parts["acc_courier_cap"] as MeshInstance3D).visible and (v.parts["watch"] as MeshInstance3D).visible,
		"Night Watch wears its uniform and cap whatever the outfit")
	v.queue_free()


func test_v6_emotes() -> void:
	t.eq(TC.EMOTES.slice(0, 6), ["wave", "cheer", "laugh", "shrug", "dance", "point"], "the V4 emotes keep their wire values")
	var m := _manifest()
	for e in SEASON["emote"]:
		var i := TC.EMOTES.find(e)
		t.check(i >= 6, "%s is appended to TC.EMOTES" % e)
		t.eq(int(Cosmetics.entry("emote", e)["id"]), i + 1, "%s catalog id follows its wire value" % e)
		t.check((m["clips"] as Dictionary).has("emote_" + e), "clip emote_%s is in the asset" % e)
		t.check(bool(m["clips"]["emote_" + e]["loop"]), "emote_%s loops" % e)
		t.check(CharacterView.STATES.has("emote_" + e), "CharacterView has the emote_%s state" % e)
		t.check(DormStage.EMOTE_S.has(e) and float(DormStage.EMOTE_S[e]) >= float(m["clips"]["emote_" + e]["length"]),
			"the lobby plays %s at least once through" % e)
		t.check(TC.EMOTE_LABELS.has(e), "%s has a bubble label" % e)
		t.eq(Icons.emote_icon(i), "e_" + e, "%s has its own icon" % e)
	# each plays on a runner through the same state change as the V4 emotes
	var v := _view()
	for e in SEASON["emote"]:
		var id := TC.EMOTES.find(e)
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true,
			"emote": id, "emote_t": 1.0})
		v._process(1.0 / 60.0)
		t.eq(v._mode, "emote_" + e, "%s plays" % e)
		for i in 30:
			v._process(1.0 / 60.0)
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true,
			"emote": -1, "emote_t": 0.0})
		v._process(1.0 / 60.0)
		t.eq(v._mode, "ground", "%s returns to idle" % e)
	v.queue_free()


func test_triangle_budgets() -> void:
	var meshes: Dictionary = _manifest()["meshes"]
	var tri := func(p: String) -> int: return int(meshes.get(p, {}).get("tris", 0))
	var worst := 0
	var worst_look := ""
	for o in SHOP_OUTFITS + SEASON["outfit"]:
		var n := 0
		for p in Cosmetics.OUTFIT_PARTS[o]:
			n += tri.call(p)
		t.check(n <= OUTFIT_TRIS, "%s: %d triangles (budget %d; V5 pajamas %d)" % [o, n, OUTFIT_TRIS, tri.call("pj")])
		# the heaviest look that can be worn with it
		for h in Cosmetics.keys_of("hat"):
			for sh in Cosmetics.keys_of("shoes"):
				for hair in Cosmetics.keys_of("hair"):
					var total := 0
					for p in Cosmetics.runner_parts({"outfit": o, "hat": h, "shoes": sh, "hair": hair}):
						total += tri.call(p)
					if total > worst:
						worst = total
						worst_look = "%s + %s + %s + %s" % [o, h, sh, hair]
	for h in SEASON["hat"]:
		var p: String = Cosmetics.entry("hat", h)["parts"][0]
		t.check(tri.call(p) <= HAT_TRIS, "%s: %d triangles (budget %d)" % [h, tri.call(p), HAT_TRIS])
	for sh in SEASON["shoes"]:
		var p2: String = Cosmetics.entry("shoes", sh)["parts"][0]
		t.check(tri.call(p2) <= SHOE_TRIS, "%s: %d triangles (budget %d)" % [sh, tri.call(p2), SHOE_TRIS])
	var v5 := 0
	for o in V5_OUTFITS:
		for h in V5_HATS:
			for sh in V5_SHOES:
				for hair in Cosmetics.keys_of("hair"):
					var total := 0
					for p in Cosmetics.runner_parts({"outfit": o, "hat": h, "shoes": sh, "hair": hair}):
						total += tri.call(p)
					v5 = maxi(v5, total)
	t.check(worst <= v5, "heaviest V6 look %s: %d triangles at LOD0 (heaviest V5 look %d; V5 typical 23.4k)" % [worst_look, worst, v5])


## Run / stop / reverse / turn / jump and land / tagged (capture and
## respawn) / splash / emote for every new outfit, through the same rig as
## the V5 motion tests.  The pose comes from the shared skeleton, so the
## bounds are the V5 ones; what this guards is that each outfit's parts stay
## shown (and nothing else appears) through every state and teleport.
func test_every_new_outfit_moves() -> void:
	var bounds := {"start": 9.0, "stop": 9.0, "reverse": 10.0, "turn90": 9.0, "jump_run": 14.0, "respawn": 12.0, "splash": 20.0,
		"emote": 10.0}
	for o in SHOP_OUTFITS + SEASON["outfit"]:
		var look := Cosmetics.sanitize({"outfit": o, "hat": "none", "shoes": "sneakers"})
		var want: Array = Cosmetics.runner_parts(look)
		var worst := {}
		var wrong: Array = []
		for sc in bounds:
			var rig := MotionRig.new()
			t.add_child(rig)
			rig.start(sc, look, 0.0)
			while rig.running:
				await t.get_tree().process_frame
				for n in rig.view.parts:
					var vis := (rig.view.parts[n] as MeshInstance3D).visible
					if vis != want.has(n) and not wrong.has("%s %s" % [sc, n]):
						wrong.append("%s %s" % [sc, n])
			var m := rig.metrics()
			worst[sc] = float(m["pop_cm"])
			rig.cleanup()
			rig.queue_free()
		var over: Array = []
		for sc in bounds:
			if float(worst[sc]) >= float(bounds[sc]):
				over.append("%s %.1f cm" % [sc, worst[sc]])
		t.eq(over, [], "%s: every scenario within the V5 snap bounds" % o)
		t.eq(wrong, [], "%s: its parts stay shown (and only they) through every state" % o)


## Cosmetics are presentation only: the same inputs give the same
## simulation whatever everyone wears.
func test_appearance_changes_nothing_in_the_sim() -> void:
	var runs: Array = []
	for look in [Cosmetics.DEFAULT, {"outfit": "raincoat_explorer", "hat": "headlamp", "shoes": "moon_boots"},
			{"outfit": "night_owl", "shoes": "glow_sneakers"}]:
		var sim := MatchSim.new()
		t.add_child(sim)
		var roster: Array = []
		for i in 3:
			roster.append({"slot": i, "uid": "u%d" % i, "name": "P%d" % i, "is_bot": false, "role": TC.Role.RUNNER if i < 2 else TC.Role.PATROL,
				"cosmetic": Cosmetics.sanitize(look)})
		sim.setup(Rules.cfg, CampusLayout.shared(), roster, 7, [0, 1, 2], "outfit-sim", {})
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
	t.eq(runs[1], runs[0], "a raincoat, headlamp and moon boots move exactly like the default look")
	t.eq(runs[2], runs[0], "an owl onesie moves exactly like the default look")
