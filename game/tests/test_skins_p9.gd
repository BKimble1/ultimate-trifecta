extends RefCounted
## Pass 9 complete skins (Record Breaker, Dr. Doom): registration with new,
## never-reused wire ids; the complete-skin override (its own head, hair,
## body and footwear replace the modular base head, hair, hat, shoes and
## marks) that keeps the saved modular choices and restores them exactly;
## expressions and face presets on the active head (each head carries the
## face shape keys and they move its features); the wire round trip and
## safe decoding of unknown ids; the Night Watch keeps its uniform and the
## player's own face; budgets; portrait-cache invalidation; every gameplay
## scenario shows the skin's parts (and only they); nothing changes the
## simulation; Locker and Shop copy say what a skin replaces.
## (tools/character/skins_check.py measures the garment layers, the tie,
## the wristband and sandals, and the arms against both heads in every
## clip on the generator's output.)
var t

const SKINS := {"record_breaker": 22, "dr_doom": 23}
const PARTS := {"record_breaker": ["rb_head", "rb_hair", "rb_body"], "dr_doom": ["dd_head", "dd_fringe", "dd_suit"]}
const HEADS := {"record_breaker": "rb_head", "dr_doom": "dd_head"}
const INCLUDES := {
	"record_breaker": "Signature tousled curls, white athletic shorts, green wristband, and brown sandals.",
	"dr_doom": "Signature bald crown and side fringe, brown suit, striped shirt, gold striped tie, and formal shoes.",
}
const TAGLINES := {"record_breaker": "The clock has a new problem.", "dr_doom": "Office hours are over. His rounds aren't."}
## the heaviest complete look before Pass 9 (LOD0 triangles, draw calls)
const HEAVIEST_TRIS := 32834
const MAX_DRAW_CALLS := 7
const FACE_KEYS := ["blink", "squint", "smile", "open", "brow_up", "brow_angry", "face_bright", "face_sleepy", "brow_flat"]
const GLB := "res://assets/characters/runner.glb"


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))


func _view(role: int = TC.Role.RUNNER, look: Dictionary = Cosmetics.DEFAULT) -> CharacterView:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(role, look, 0, "", false)
	return v


func _shown(v: CharacterView) -> Array:
	var out: Array = []
	for n in v.parts:
		if (v.parts[n] as MeshInstance3D).visible:
			out.append(n)
	out.sort()
	return out


func test_skins_are_registered_with_new_ids() -> void:
	var meshes: Dictionary = _manifest()["meshes"]
	var seen := {}
	var before_max := 0
	for k in Cosmetics.CATALOG["outfit"]:
		var id := int(Cosmetics.entry("outfit", k)["id"])
		t.check(not seen.has(id), "outfit id %d is used once (%s)" % [id, k])
		seen[id] = k
		if not SKINS.has(k):
			before_max = maxi(before_max, id)
	for k in SKINS:
		var e := Cosmetics.entry("outfit", k)
		t.eq(int(e.get("id", -1)), int(SKINS[k]), "%s has wire id %d" % [k, SKINS[k]])
		t.check(int(e["id"]) > before_max, "%s's id is above every earlier outfit id (%d): never reused" % [k, before_max])
		t.check(Cosmetics.cost("outfit", k) > 0, "%s is not a free base option (owned only once earned)" % k)
		t.eq(int(e.get("season", 0)), 1, "%s is a Season 1 reward" % k)
		t.eq(e.get("includes", []), [INCLUDES[k]], "%s says exactly what it includes" % k)
		t.eq(String(e.get("tagline", "")), String(TAGLINES[k]), "%s carries its description" % k)
		t.check(Cosmetics.is_complete_skin(k), "%s is a complete skin" % k)
		t.eq(Cosmetics.OUTFIT_PARTS[k], PARTS[k], "%s's parts" % k)
		for p in PARTS[k]:
			t.check(meshes.has(p) and int(meshes[p]["tris"]) > 2500, "%s part %s is real geometry in runner.glb (%d tris)" % [
				k, p, int(meshes.get(p, {}).get("tris", 0))])
		t.eq(Cosmetics.head_part(Cosmetics.sanitize({"outfit": k})), HEADS[k], "%s shows its own head" % k)
		t.eq(Cosmetics.migrate_owned(["outfit:" + k]), ["outfit:" + k], "an owned %s stays owned through the save migration" % k)
		t.check(Catalogue.has_art("outfit:" + k), "the catalogue sees art for outfit:%s" % k)
	t.eq(Cosmetics.head_part(Cosmetics.DEFAULT), "base", "an ordinary look keeps the stock head")


func test_override_replaces_the_modular_head_and_keeps_the_choices() -> void:
	var modular := ["base", "freckles"]
	for f in ["hair", "hat", "shoes"]:
		for k in Cosmetics.keys_of(f):
			modular.append_array(Cosmetics.entry(f, k)["parts"])
	for h in Cosmetics.HAT_HAIR_VARIANT.values():
		modular.append_array((h as Dictionary).values())
	for o in Cosmetics.OUTFIT_HEADWEAR.values():
		modular.append_array(o["parts"])
	var bad: Array = []
	var n := 0
	for k in SKINS:
		for h in Cosmetics.keys_of("hat"):
			for sh in Cosmetics.keys_of("shoes"):
				for hair in Cosmetics.keys_of("hair"):
					for mk in Cosmetics.keys_of("marks"):
						var c := {"outfit": k, "hat": h, "shoes": sh, "hair": hair, "marks": mk, "face": "sleepy", "brows": "flat",
							"skin": "tone8", "hair_color": "pink", "color": "lime"}
						n += 1
						var ps: Array = Cosmetics.runner_parts(c)
						if ps != PARTS[k]:
							bad.append("%s draws %s" % [c, ps])
						for p in ps:
							if p in modular:
								bad.append("%s draws modular %s" % [c, p])
						var a := Cosmetics.sanitize(c)
						for f in c:
							if String(a[f]) != String(c[f]):
								bad.append("%s lost %s" % [c, f])
	t.check(n >= 2 * 10 * 5 * 4 * 2, "every hat, shoe, hair and marks choice tried with both skins (%d)" % n)
	t.eq(bad, [], "a complete skin draws only its own parts and the saved choices stay in the appearance")
	# its own tones and resting face; the modular ones are untouched
	for k in SKINS:
		var c := Cosmetics.sanitize({"outfit": k, "skin": "tone8", "hair_color": "pink", "face": "sleepy", "brows": "raised"})
		t.eq(Cosmetics.look_skin_color(c), Cosmetics.COMPLETE_SKINS[k]["skin_rgb"], "%s shows its own skin tone" % k)
		t.eq(Cosmetics.look_hair_color(c), Cosmetics.COMPLETE_SKINS[k]["hair_rgb"], "%s shows its own hair tone" % k)
		t.eq(Cosmetics.look_face_keys(c), {}, "%s shows its own resting face (no modular face preset)" % k)
		t.eq(Cosmetics.skin_color(c), Cosmetics.entry("skin", "tone8")["rgb"], "the player's own tone stays saved (%s)" % k)
		t.check(not Cosmetics.face_keys(c).is_empty(), "the player's own face preset stays saved (%s)" % k)
		var rep: Array = Cosmetics.outfit_replaces(k)
		for f in ["hat", "hair", "shoes", "face", "skin", "marks"]:
			t.check(rep.has(f), "%s replaces %s while worn" % [k, f])
		t.check(Cosmetics.override_note(k).contains("stay saved"), "%s's preview copy says the choices stay saved" % k)
	# switching to a skin and back restores the ordinary look exactly (view and save)
	var look := Cosmetics.sanitize({"outfit": "pj", "hat": "crown", "shoes": "sneakers", "hair": "curly", "marks": "freckles",
		"face": "bright", "skin": "tone6"})
	var v := _view(TC.Role.RUNNER, look)
	var before := _shown(v)
	var tint_before: Color = v.parts["base"].get_instance_shader_parameter("tint_skin")
	for k in SKINS:
		var worn := look.duplicate()
		worn["outfit"] = k
		v.set_appearance(TC.Role.RUNNER, worn)
		var s := _shown(v)
		s.sort()
		var want: Array = PARTS[k].duplicate()
		want.sort()
		t.eq(s, want, "%s: only its own parts are drawn (no stock head underneath)" % k)
		t.eq(String(v.face_mesh.name), HEADS[k], "%s: expressions drive its own head" % k)
		v.set_appearance(TC.Role.RUNNER, look)
		t.eq(_shown(v), before, "back from %s: the ordinary look is restored exactly" % k)
		t.eq(String(v.face_mesh.name), "base", "back from %s: expressions drive the stock head again" % k)
	t.eq(v.parts["base"].get_instance_shader_parameter("tint_skin"), tint_before, "the player's skin tone is back")
	v.queue_free()
	# the Locker's save keeps the modular choices while a skin is worn
	var saved_owned: Array = (Save.data.get("owned", []) as Array).duplicate()
	var saved_cos: Dictionary = (Save.data.get("cosmetic", {}) as Dictionary).duplicate()
	(Save.data["owned"] as Array).append_array(["outfit:record_breaker", "hat:crown", "shoes:sneakers"])
	var r := Save.apply_appearance({"outfit": "record_breaker", "hat": "crown", "shoes": "sneakers", "hair": "curly"})
	t.check(bool(r["ok"]), "an owned skin can be saved (dev fixture: device ownership)")
	t.eq(String(Save.data["cosmetic"]["hat"]), "crown", "the saved hat is kept while the skin is worn")
	Save.equip("outfit", "pj")
	t.eq([String(Save.data["cosmetic"]["hat"]), String(Save.data["cosmetic"]["shoes"]), String(Save.data["cosmetic"]["hair"])],
		["crown", "sneakers", "curly"], "taking the skin off brings the saved hat, shoes and hair back")
	var r2 := Save.apply_appearance({"outfit": "dr_doom"})
	t.check(not bool(r2["ok"]) and (r2["missing"] as Array).has("outfit:dr_doom"), "an unowned skin can't be saved")
	Save.data["owned"] = saved_owned
	Save.data["cosmetic"] = saved_cos


func test_expressions_play_on_the_active_head() -> void:
	# each head carries every face key, and each key moves its features
	var scene: Node = (load(GLB) as PackedScene).instantiate()
	var meshes := {}
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		meshes[String(n.name)] = (n as MeshInstance3D).mesh
	for k in SKINS:
		var m: ArrayMesh = meshes[HEADS[k]]
		var names: Array = []
		for i in m.get_blend_shape_count():
			names.append(String(m.get_blend_shape_name(i)))
		t.eq(names, FACE_KEYS, "%s's head has the face keys, in the stock order" % k)
		var basis: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var shapes: Array = m.surface_get_blend_shape_arrays(0)
		for i in names.size():
			var sv: PackedVector3Array = shapes[i][Mesh.ARRAY_VERTEX]
			var moved := 0
			var most := 0.0
			for j in mini(sv.size(), basis.size()):
				var d := sv[j].distance_to(basis[j])
				if d > 0.001:
					moved += 1
				most = maxf(most, d)
			t.check(moved > 20 and most > 0.003, "%s: %s moves its features (%d vertices, up to %.1f mm)" % [k, names[i], moved, most * 1000.0])
	scene.free()
	# in play: blinks, the idle smile and the movement face reach the shown head
	for k in SKINS:
		var v := _view(TC.Role.RUNNER, Cosmetics.sanitize({"outfit": k}))
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
		var head: MeshInstance3D = v.parts[HEADS[k]]
		var base: MeshInstance3D = v.parts["base"]
		var blinked := 0.0
		for i in 360:
			v._process(1.0 / 60.0)
			blinked = maxf(blinked, head.get_blend_shape_value(v._face_idx["blink"]))
		t.check(blinked > 0.5, "%s blinks on its own head (%.2f)" % [k, blinked])
		t.check(head.get_blend_shape_value(v._face_idx["smile"]) > 0.2, "%s: the idle smile is on its own head" % k)
		var stock_moved := 0.0
		for i in base.mesh.get_blend_shape_count():
			stock_moved = maxf(stock_moved, base.get_blend_shape_value(i))
		t.eq(stock_moved, 0.0, "%s: the hidden stock head is not animated" % k)
		# running: a focused face (brows down, no smile); captured: surprise
		for i in 30:
			# (the render state's full-speed flag: "sprinting", renamed "fast" by the movement stream)
			v.apply_state({"pos": Vector3(0, 0, -0.1 * i), "yaw": 0.0, "vel": Vector3(0, 0, -6.0), "state": TC.PState.ACTIVE, "on_floor": true,
				"sprinting": true, "fast": true}, 1.0 / 60.0)
			v._process(1.0 / 60.0)
		t.check(head.get_blend_shape_value(v._face_idx["brow_angry"]) > 0.5, "%s looks focused at full speed" % k)
		for i in 20:
			v.apply_state({"pos": Vector3(0, 0, -3.0), "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.CAPTURED, "on_floor": true,
				"state_t": 0.05 * i}, 1.0 / 60.0)
			v._process(1.0 / 60.0)
		t.check(head.get_blend_shape_value(v._face_idx["open"]) > 0.5 and head.get_blend_shape_value(v._face_idx["brow_up"]) > 0.5,
			"%s looks surprised when tagged" % k)
		# a face preset on the visible head (portraits and captures use show_face)
		v.show_face({"smile": 0.5})
		t.near(head.get_blend_shape_value(v._face_idx["smile"]), 0.5, 0.001, "%s: show_face sets the shown head" % k)
		v.queue_free()


func test_wire_round_trip_and_unknown_ids_degrade_safely() -> void:
	for k in SKINS:
		var look := Cosmetics.sanitize({"outfit": k, "hat": "crown", "hair": "bob", "shoes": "flippers"})
		var back := Cosmetics.decode(Cosmetics.encode(look))
		t.eq(back, look, "%s survives the wire round trip with the saved choices" % k)
		var b := Cosmetics.encode(look)
		t.eq(int(b[4]), int(SKINS[k]), "%s's outfit value on the wire is its id" % k)
	# an older client's catalogue: an outfit id it doesn't know falls back to
	# the default outfit and keeps the rest of the look
	var future := Cosmetics.encode(Cosmetics.sanitize({"outfit": "pj", "hat": "crown"}))
	future[4] = 99
	var d := Cosmetics.decode(future)
	t.eq(String(d["outfit"]), "pj", "an unknown outfit id decodes to the default outfit")
	t.eq(String(d["hat"]), "crown", "and the rest of the look survives")
	# an unknown field id is skipped
	var extra := PackedByteArray(Cosmetics.encode(Cosmetics.sanitize({"outfit": "dr_doom"})))
	extra[2] = extra[2] + 1
	extra.append(77)
	extra.append(5)
	t.eq(String(Cosmetics.decode(extra)["outfit"]), "dr_doom", "an unknown field id is skipped")
	t.check(Cosmetics.encode(Cosmetics.sanitize({"outfit": "dr_doom"})).size() <= Cosmetics.max_wire_size(), "the wire form stays in bounds")
	# hostile input never selects a skin by accident
	t.eq(String(Cosmetics.sanitize({"outfit": "Dr. Doom"})["outfit"]), "pj", "only the exact key selects a skin")


func test_night_watch_keeps_the_uniform_and_the_players_face() -> void:
	for k in SKINS:
		var look := Cosmetics.sanitize({"outfit": k, "skin": "tone7", "marks": "freckles"})
		var v := _view(TC.Role.PATROL, look)
		var s := _shown(v)
		t.check(s.has("watch") and s.has("base") and s.has("flashlight"), "the Night Watch wears its uniform over %s" % k)
		for p in PARTS[k]:
			t.check(not s.has(p), "%s's %s is never drawn on the Night Watch" % [k, p])
		t.eq(String(v.face_mesh.name), "base", "the Night Watch's face is the stock head (%s)" % k)
		t.eq(v.parts["base"].get_instance_shader_parameter("tint_skin"), Cosmetics.entry("skin", "tone7")["rgb"],
			"the Night Watch keeps the player's own skin tone (%s)" % k)
		v.queue_free()
	for seed_v in 400:
		var b := Cosmetics.bot_cosmetic(seed_v)
		if Cosmetics.is_complete_skin(String(b["outfit"])):
			t.check(false, "bot %d wears a Season Premium skin" % seed_v)
			break


func test_budgets_and_one_shared_material() -> void:
	var meshes: Dictionary = _manifest()["meshes"]
	for k in SKINS:
		var tris := 0
		for p in Cosmetics.runner_parts({"outfit": k}):
			tris += int(meshes[p]["tris"])
		t.check(tris <= HEAVIEST_TRIS, "%s: %d LOD0 triangles (the heaviest earlier look: %d)" % [k, tris, HEAVIEST_TRIS])
		t.check(Cosmetics.runner_parts({"outfit": k}).size() <= MAX_DRAW_CALLS, "%s: %d parts (draw calls)" % [k,
			Cosmetics.runner_parts({"outfit": k}).size()])
	var v := _view()
	var shared: Material = (v.parts["base"] as MeshInstance3D).material_override
	for k in SKINS:
		for p in PARTS[k]:
			var mi: MeshInstance3D = v.parts[p]
			t.eq(mi.mesh.get_surface_count(), 1, "%s is one surface (one draw call)" % p)
			t.check(mi.material_override == shared, "%s uses the shared character material" % p)
	v.queue_free()


func test_portraits_never_show_the_previous_face() -> void:
	var m: Dictionary = _manifest()
	t.check(CharacterArt.VERSION.begins_with("v10-"), "the art generation moved on with the new heads (%s)" % CharacterArt.VERSION)
	t.eq(CharacterArt.VERSION, String(m["art_version"]), "CharacterArt matches the manifest (rebuilt together)")
	var keys := {}
	for o in ["pj", "record_breaker", "dr_doom"]:
		var k := Portraits.key_for({"outfit": o, "hat": "none"}, TC.Role.RUNNER, "head")
		t.check(k.begins_with(CharacterArt.VERSION), "a portrait key carries the art version")
		t.check(not keys.has(k), "%s has its own portrait" % o)
		keys[k] = o
	t.check(Portraits.key_for({"outfit": "record_breaker"}, TC.Role.RUNNER, "head") != Portraits.key_for({"outfit": "record_breaker"},
		TC.Role.PATROL, "head"), "a Night Watch portrait is cached apart from the skin's")


## Gameplay scenarios (start, stop, reverse, turn, sprint, jump, dive,
## tagged and respawn, splash, emote) with each skin: its parts stay shown
## (and only they) through every state and teleport and its head stays the
## one whose face plays.  The motion rig's cart scenario is a Night Watch's
## (runners can't enter carts): there the uniform shows, never the skin.
func test_every_scenario_with_each_skin() -> void:
	var scenarios := ["start", "stop", "reverse", "turn90", "sprint", "jump_run", "dive", "respawn", "splash", "cart", "emote"]
	for k in SKINS:
		var look := Cosmetics.sanitize({"outfit": k, "hat": "crown", "shoes": "flippers"})
		var wrong: Array = []
		var heads: Array = []
		for sc in scenarios:
			var watch: bool = sc == "cart"
			var want: Array = Cosmetics.runner_parts(look) if not watch else ["base", "watch", "flashlight"]
			var head: String = HEADS[k] if not watch else "base"
			var rig := MotionRig.new()
			t.add_child(rig)
			rig.start(sc, look, 0.0)
			while rig.running:
				await t.get_tree().process_frame
				for n in rig.view.parts:
					if n == "mustache":
						continue   # (the Night Watch's mustache follows the colour id)
					if (rig.view.parts[n] as MeshInstance3D).visible != want.has(n) and not wrong.has("%s %s" % [sc, n]):
						wrong.append("%s %s" % [sc, n])
				if String(rig.view.face_mesh.name) != head and not heads.has(sc):
					heads.append(sc)
			rig.cleanup()
			rig.queue_free()
		t.eq(wrong, [], "%s: its parts stay shown (and only they) through every scenario" % k)
		t.eq(heads, [], "%s: its own head plays the face throughout" % k)


func test_appearance_changes_nothing_in_the_sim() -> void:
	var runs: Array = []
	for look in [Cosmetics.DEFAULT, {"outfit": "record_breaker"}, {"outfit": "dr_doom"}]:
		var sim := MatchSim.new()
		t.add_child(sim)
		var roster: Array = []
		for i in 3:
			roster.append({"slot": i, "uid": "u%d" % i, "name": "P%d" % i, "is_bot": false, "role": TC.Role.RUNNER if i < 2 else TC.Role.PATROL,
				"cosmetic": Cosmetics.sanitize(look)})
		sim.setup(Rules.cfg, CampusLayout.shared(), roster, 7, [0, 1, 2], "outfit-sim-p9", {})
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
	t.eq(runs[1], runs[0], "Record Breaker moves exactly like the default look (capsule, speed, jump, reach)")
	t.eq(runs[2], runs[0], "Dr. Doom moves exactly like the default look (capsule, speed, jump, reach)")


func test_locker_and_shop_copy_say_what_a_skin_replaces() -> void:
	for k in SKINS:
		var nm := String(Cosmetics.entry("outfit", k)["name"])
		t.check(CreatorScreen.skin_note("outfit", k).contains("replace"), "the Locker's outfit tab says what %s replaces" % nm)
		for tab in ["colours", "face", "hair", "hat", "shoes"]:
			var note := CreatorScreen.skin_note(tab, k)
			t.check(note.begins_with(nm) and note.contains("saved"), "the Locker's %s tab says %s covers it and the pick is kept" % [tab, nm])
		t.eq(CreatorScreen.skin_note("move", k), "", "emotes are not replaced by %s" % nm)
	t.eq(CreatorScreen.skin_note("hair", "pj"), "", "an ordinary outfit adds no note")
	var shop := ShopScreen.new()
	for k in SKINS:
		var txt := shop._includes_text("outfit:" + k)
		t.check(txt.contains(INCLUDES[k]), "the Shop's detail lists exactly what %s includes" % k)
		t.check(txt.contains("stay saved") and not txt.contains("hood"), "the Shop's detail says what %s replaces (and isn't called a hood)" % k)
	shop.free()
