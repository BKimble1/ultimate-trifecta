extends RefCounted
## Existing saves and cosmetics survive the V2 update: a V1-era profile keeps
## its progress, wardrobe and settings (new settings get defaults), and every
## V1 cosmetic combination maps onto parts of the new character asset and
## still round-trips through the network encoding.
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
	t.eq(p["cosmetic"], v1["cosmetic"], "equipped outfit kept")
	t.check("hat:crown" in p["owned"], "wardrobe kept")
	var s: Dictionary = p["settings"]
	t.near(float(s["sensitivity"]), 1.4, 1e-6, "old settings kept")
	t.eq(int(s["quality"]), 0, "Battery Saver choice kept")
	t.eq(String(s["role_pref"]), "patrol", "role preference kept")
	t.eq(String(s["stick_mode"]), "dynamic", "new setting gets its default")
	t.eq(String(s["sprint_mode"]), "edge", "new setting gets its default")
	t.check(bool(s["haptics"]), "new setting gets its default")


func test_every_v1_cosmetic_maps_onto_the_new_character() -> void:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "Test", false)
	var missing: Array = []
	for m in [CharacterView.OUTFIT_PARTS, CharacterView.HAT_PARTS, CharacterView.SHOE_PARTS]:
		for k in m:
			for part in m[k]:
				if not v.parts.has(part):
					missing.append(part)
	for part in ["base", "hair", "watch", "flashlight"]:
		if not v.parts.has(part):
			missing.append(part)
	t.eq(missing, [], "every part a V1 cosmetic needs exists in runner.glb")
	var combos := 0
	var bad: Array = []
	for o in Cosmetics.OUTFITS:
		for h in Cosmetics.HATS:
			for sh in Cosmetics.SHOES:
				var c := {"outfit": o, "hat": h, "shoes": sh, "color": combos % Cosmetics.COLORS.size(),
					"skin": combos % Cosmetics.SKINS.size()}
				combos += 1
				if Cosmetics.decode(Cosmetics.encode(c)) != c:
					bad.append("encode %s" % c)
				v.set_appearance(TC.Role.RUNNER, c)
				for part in CharacterView.OUTFIT_PARTS[o] + CharacterView.SHOE_PARTS[sh]:
					if not (v.parts[part] as MeshInstance3D).visible:
						bad.append("%s hidden for %s" % [part, c])
				var hood: bool = o in CharacterView.HOOD_OUTFITS
				for part in CharacterView.HAT_PARTS[h]:
					if (v.parts[part] as MeshInstance3D).visible == hood:
						bad.append("%s visibility wrong for %s" % [part, c])
				if (v.parts["watch"] as MeshInstance3D).visible:
					bad.append("uniform shown on a runner %s" % c)
	t.eq(combos, 6 * 6 * 3, "all outfit x hat x shoe combinations checked")
	t.eq(bad, [], "each combination shows its parts and survives the network encoding")
	v.set_appearance(TC.Role.PATROL, {"outfit": "duck", "hat": "crown", "shoes": "flippers", "color": 2, "skin": 1})
	t.check((v.parts["watch"] as MeshInstance3D).visible and (v.parts["flashlight"] as MeshInstance3D).visible
		and not (v.parts["duck"] as MeshInstance3D).visible, "Night Watch wears the uniform whatever the wardrobe says")
	v.queue_free()
