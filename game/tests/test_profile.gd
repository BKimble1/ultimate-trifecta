extends RefCounted
## Existing saves survive the V3 update and the schema-2 appearance holds up:
## V1/V2 profiles keep progress and their look, every appearance maps onto
## parts of the character asset with the hair/hat rules applied, the
## versioned wire format round-trips and rejects junk safely, catalog IDs are
## explicit and pinned, and the creator's Apply is atomic and idempotent.
var t


func test_v1_profile_loads_with_progress_and_new_defaults() -> void:
	# shape of a profile written by the V1 build (no V2 touch settings)
	var v1 := {
		"version": 2, "uid": "local-0123456789abcdef", "name": "Sleepy Otter 42",
		"settings": {"sensitivity": 1.4, "invert_y": true, "reduced_motion": false, "sfx": 0.5, "music": 0.2,
			"quality": 0, "sprint_threshold": 0.88, "touch_sprint": false, "role_pref": "patrol"},
		"cosmetic": {"outfit": "frog", "hat": "crown", "shoes": "flippers", "color": 5, "skin": 3},
		"owned": ["outfit:pj_stripes", "outfit:frog", "hat:crown", "shoes:flippers"],
		"coins": 345, "level": 4, "xp": 120,
		"stats": {"online": {"matches": 7, "wins": 3}, "practice": {"matches": 2}},
		"rewarded": ["m-1", "m-2"], "recent": [], "tutorial_done": true, "muted": ["uid-x"],
	}
	var p: Dictionary = Save.migrate(v1)
	t.eq(String(p["uid"]), "local-0123456789abcdef", "identity kept")
	t.eq(int(p["coins"]), 345, "coins kept")
	t.eq(int(p["level"]), 4, "level kept")
	t.eq(int(p["stats"]["online"]["wins"]), 3, "stats kept")
	t.eq((p["rewarded"] as Array).size(), 2, "paid match IDs kept (no double rewards)")
	var a: Dictionary = p["cosmetic"]
	t.eq(int(a["schema"]), 2, "appearance migrated to schema 2")
	t.eq([a["outfit"], a["hat"], a["shoes"], a["color"], a["skin"]], ["frog", "crown", "flippers", "teal", "tone7"],
		"same outfit, hat, shoes, colour (index 5 = Teal) and skin tone (index 3)")
	t.eq(String(a["hair_color"]), "black", "hair colour V2 derived from that skin tone is kept")
	t.check("hat:crown" in p["owned"] and "outfit:frog" in p["owned"] and "shoes:flippers" in p["owned"], "paid items stay owned")
	t.check(not "outfit:pj_stripes" in p["owned"], "V1 item keys are rewritten (pajamas are free in schema 2)")
	var s: Dictionary = p["settings"]
	t.near(float(s["sensitivity"]), 1.4, 1e-6, "old settings kept")
	t.eq(int(s["quality"]), 0, "Battery Saver choice kept")
	t.eq(String(s["role_pref"]), "patrol", "role preference kept")
	t.eq(String(s["stick_mode"]), "dynamic", "new setting gets its default")
	t.eq(String(s["sprint_mode"]), "edge", "new setting gets its default")
	t.check(bool(s["haptics"]), "new setting gets its default")


func test_v2_striped_and_plain_pajamas_keep_their_pattern() -> void:
	var a := Cosmetics.sanitize({"outfit": "pj_stripes", "hat": "nightcap", "shoes": "slippers", "color": 0, "skin": 0})
	t.eq([a["outfit"], a["pattern"], a["color"], a["skin"], a["hair_color"]], ["pj", "stripes", "sky", "tone2", "brown"], "V2 default look")
	var b := Cosmetics.sanitize({"outfit": "pj_plain", "hat": "none", "shoes": "sneakers", "color": 7, "skin": 4})
	t.eq([b["outfit"], b["pattern"], b["color"], b["skin"], b["hair_color"]], ["pj", "plain", "cloud", "tone3", "ginger"], "plain pajamas")
	var again := Cosmetics.sanitize(a)
	t.eq(again, a, "sanitize is idempotent on schema 2")


func test_every_appearance_maps_onto_the_character() -> void:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "Test", false)
	var missing: Array = []
	for f in ["outfit", "hat", "shoes", "hair", "marks"]:
		for k in Cosmetics.keys_of(f):
			var ps: Array = Cosmetics.entry(f, k).get("parts", Cosmetics.OUTFIT_PARTS.get(k, []))
			for part in ps:
				if not v.parts.has(part):
					missing.append(part)
	for part in ["base", "watch", "flashlight", "mustache"]:
		if not v.parts.has(part):
			missing.append(part)
	t.eq(missing, [], "every part the catalog names exists in runner.glb")
	for n in ["face_bright", "face_sleepy", "brow_flat", "blink", "smile"]:
		t.check(v._face_idx.has(n), "face shape key %s exists" % n)
	var combos := 0
	var bad: Array = []
	for o in Cosmetics.keys_of("outfit"):
		for h in Cosmetics.keys_of("hat"):
			for sh in Cosmetics.keys_of("shoes"):
				for hair in Cosmetics.keys_of("hair"):
					var c := Cosmetics.sanitize({"outfit": o, "hat": h, "shoes": sh, "hair": hair})
					combos += 1
					v.set_appearance(TC.Role.RUNNER, c)
					var shown := {}
					for n in v.parts:
						if (v.parts[n] as MeshInstance3D).visible:
							shown[n] = true
					# (V6: an outfit with its own footwear draws that instead of the shoes)
					var shoe_parts: Array = [] if o in Cosmetics.OUTFIT_OWN_SHOES else Cosmetics.entry("shoes", sh)["parts"]
					for part in Cosmetics.OUTFIT_PARTS[o] + shoe_parts:
						if not shown.has(part):
							bad.append("%s hidden for %s" % [part, c])
					var hood: bool = o in Cosmetics.HOOD_OUTFITS
					for part in Cosmetics.entry("hat", h)["parts"]:
						if shown.has(part) == hood:
							bad.append("%s visibility wrong for %s" % [part, c])
					var hidden: Array = []
					for k in Cosmetics.head_rules(c):
						hidden.append_array(Cosmetics.HAT_HIDES_HAIR.get(k, []))
					for part in Cosmetics.entry("hair", hair)["parts"]:
						var want: bool = not hood and not part in hidden
						# V5: under a crown or headphones the curly crop is drawn
						# as its smooth-band variant (CharacterView, parts.py)
						# (V6: or its `_low` variant under a cap or beanie)
						var drawn: bool = shown.has(part) or shown.has(part + "_hat") or shown.has(part + "_low")
						if drawn != want:
							bad.append("hair %s visibility wrong for %s" % [part, c])
					var hair_parts := 0
					for hp in ["hair", "hair_hat", "hair_bob", "hair_curly", "hair_curly_hat", "hair_curly_low", "hair_buns"]:
						if shown.has(hp):
							hair_parts += 1
					if hair_parts > 1:
						bad.append("two hairstyles at once for %s" % c)
					if shown.has("watch"):
						bad.append("uniform shown on a runner %s" % c)
	t.eq(combos, Cosmetics.keys_of("outfit").size() * Cosmetics.keys_of("hat").size() * Cosmetics.keys_of("shoes").size()
		* Cosmetics.keys_of("hair").size(), "all outfit x hat x shoe x hair combinations checked")
	t.check(combos >= 15 * 10 * 5 * 4, "including the V6 outfits, hats and shoes (%d)" % combos)
	t.eq(bad, [], "each combination shows its parts and applies the hair/hat rules")
	v.set_appearance(TC.Role.PATROL, Cosmetics.sanitize({"outfit": "duck", "hat": "crown", "shoes": "flippers"}))
	t.check((v.parts["watch"] as MeshInstance3D).visible and (v.parts["flashlight"] as MeshInstance3D).visible
		and not (v.parts["duck"] as MeshInstance3D).visible, "Night Watch wears the uniform whatever the appearance says")
	v.queue_free()


func test_wire_format_round_trips_every_value() -> void:
	var bad: Array = []
	var n := 0
	for f in Cosmetics.ORDER:
		for k in Cosmetics.keys_of(f):
			var c := Cosmetics.DEFAULT.duplicate()
			c[f] = k
			n += 1
			var back := Cosmetics.decode(Cosmetics.encode(c))
			if back != Cosmetics.sanitize(c):
				bad.append("%s=%s" % [f, k])
	t.check(n > 60, "every catalog value tried (%d)" % n)
	t.eq(bad, [], "encode -> decode is lossless for every field value")
	var bytes := Cosmetics.encode(Cosmetics.DEFAULT)
	t.eq(int(bytes[0]), Cosmetics.WIRE_MAGIC, "wire format starts with its magic byte")
	t.eq(int(bytes[1]), Cosmetics.SCHEMA, "and the schema version")
	t.check(bytes.size() <= Cosmetics.max_wire_size(), "and fits the bounded read")


func test_wire_format_rejects_junk_safely() -> void:
	# legacy 5-byte V2 format (old captures/saves) still decodes to the same look
	var legacy := PackedByteArray([0, 1, 0, 0, 0])
	var a := Cosmetics.decode(legacy)
	t.eq([a["outfit"], a["pattern"], a["hat"], a["color"]], ["pj", "stripes", "nightcap", "sky"], "legacy bytes decode")
	t.eq(Cosmetics.decode(PackedByteArray()), Cosmetics.DEFAULT, "empty -> default")
	t.eq(Cosmetics.decode(PackedByteArray([1, 2, 3])), Cosmetics.DEFAULT, "wrong magic -> default")
	# unknown field IDs are skipped, unknown value IDs fall back per field
	var b := PackedByteArray([Cosmetics.WIRE_MAGIC, 2, 3, 99, 7, 11, 200, 1, 5])
	var d := Cosmetics.decode(b)
	t.eq(String(d["outfit"]), "frog", "known field decodes")
	t.eq(String(d["hat"]), String(Cosmetics.DEFAULT["hat"]), "unknown value -> default for that field")
	# a count larger than the bytes present is bounded by the data
	var trunc := PackedByteArray([Cosmetics.WIRE_MAGIC, 2, 200, 1, 3])
	t.eq(String(Cosmetics.decode(trunc)["outfit"]), "robe", "truncated list reads only what is there")
	# hostile dictionaries
	var h := Cosmetics.sanitize({"outfit": 5, "hat": ["x"], "color": "nope", "schema": 99, "extra": "x"})
	t.eq(h, Cosmetics.DEFAULT, "wrong types and unknown keys -> default")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok := true
	for i in 300:
		var junk := PackedByteArray()
		for j in rng.randi_range(0, 40):
			junk.append(rng.randi() % 256)
		if i % 3 == 0 and junk.size() > 1:
			junk[0] = Cosmetics.WIRE_MAGIC
		var out := Cosmetics.decode(junk)
		if out != Cosmetics.sanitize(out):
			ok = false
	t.check(ok, "300 random byte strings all decode to valid appearances")


func test_catalog_ids_are_explicit_unique_and_pinned() -> void:
	var dup: Array = []
	for f in Cosmetics.CATALOG:
		var seen := {}
		for k in Cosmetics.CATALOG[f]:
			var id := int(Cosmetics.CATALOG[f][k]["id"])
			if seen.has(id) or id <= 0 or id > 255:
				dup.append("%s:%s" % [f, k])
			seen[id] = true
	t.eq(dup, [], "IDs are unique per field and fit a byte")
	var fids := {}
	for f in Cosmetics.FIELDS:
		fids[int(Cosmetics.FIELDS[f])] = true
	t.eq(fids.size(), Cosmetics.FIELDS.size(), "field IDs unique")
	t.eq(Cosmetics.ORDER.size(), Cosmetics.FIELDS.size(), "every field is in the creator order")
	# pinned: renumbering any of these would silently change other players' looks
	var pins := [["outfit", "pj", 1], ["outfit", "frog", 5], ["hat", "crown", 6], ["shoes", "flippers", 3],
		["color", "sky", 1], ["color", "plum", 12], ["skin", "tone8", 8], ["hair", "buns", 4], ["hair_color", "pink", 10],
		["face", "sleepy", 3], ["emote", "dance", 5]]
	for p in pins:
		t.eq(int(Cosmetics.entry(p[0], p[1])["id"]), int(p[2]), "%s:%s keeps ID %d" % p)
	t.eq([int(Cosmetics.FIELDS["outfit"]), int(Cosmetics.FIELDS["hair_color"]), int(Cosmetics.FIELDS["emote"])], [1, 10, 13], "field IDs pinned")


func test_apply_is_atomic_and_idempotent() -> void:
	var saved: Dictionary = Save.data.duplicate(true)
	Save.data["coins"] = 300
	Save.data["owned"] = []
	Save.data["cosmetic"] = Cosmetics.DEFAULT.duplicate()
	var look := Cosmetics.sanitize({"hat": "crown", "color": "plum"})
	t.eq(Save.price_of(look), 240 + 30, "price = crown + plum (both unowned)")
	var short := Save.apply_appearance(Cosmetics.sanitize({"outfit": "frog", "hat": "crown"}))
	t.check(not bool(short["ok"]) and int(short["short"]) == 140, "too expensive: refused, with the shortfall")
	t.eq(int(Save.data["coins"]), 300, "nothing was charged")
	t.eq(Save.data["cosmetic"], Cosmetics.DEFAULT, "and nothing changed")
	var r := Save.apply_appearance(look)
	t.check(bool(r["ok"]) and int(r["spent"]) == 270, "apply buys and equips in one step")
	t.eq(int(Save.data["coins"]), 30, "coins charged once")
	var r2 := Save.apply_appearance(look)
	t.check(bool(r2["ok"]) and int(r2["spent"]) == 0, "applying again costs nothing")
	t.eq(int(Save.data["coins"]), 30, "idempotent")
	t.check(Save.owns("hat", "crown") and Save.owns("color", "plum") and Save.owns("hair", "curly"), "owned: bought + free items")
	Save.data = saved


func test_generated_and_old_names_always_fit_the_name_rules() -> void:
	var rng := RandomNumberGenerator.new()
	var bad: Array = []
	for i in 2000:
		rng.seed = i
		var n := Save.generated_name(rng)
		if NameRules.shape_error(n) != "":
			bad.append(n)
	t.eq(bad, [], "every generated default name is valid (3-16 characters)")
	t.eq(Save.fit_name("Splashy Walrus 56"), "Splashy Walrus", "a 17-character V2 name keeps its words")
	t.eq(Save.fit_name("Sleepy Otter 42"), "Sleepy Otter 42", "a valid name is unchanged")
	t.check(NameRules.shape_error(Save.fit_name("!!!")) == "", "an unusable old name becomes a fresh valid one")
	var p: Dictionary = Save.migrate({"version": 2, "name": "Splashy Walrus 56"})
	t.eq(String(p["name"]), "Splashy Walrus", "migration fixes it, so it's never shown as \"Player\"")
