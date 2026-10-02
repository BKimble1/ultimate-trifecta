extends RefCounted
## Party lobby presentation: the dorm stage is updated incrementally by player
## identity (no wholesale rebuilds), marks are stable, a guest who drops and
## rejoins comes back without disturbing anyone else, and outfit changes are
## applied in place.  Uses the loopback network rig for real lobby traffic.
var t


func _entries(s: NetSession) -> Array:
	var out: Array = []
	for i in 8:
		var e: Variant = s.roster[i]
		if e == null:
			continue
		var ent := {"key": String(e["uid"]), "role": TC.Role.RUNNER, "cosmetic": e["cosmetic"], "name": String(e["name"]),
			"is_bot": bool(e["is_bot"]), "local": i == s.local_slot}
		if i == s.local_slot:
			out.push_front(ent)
		else:
			out.append(ent)
	return out


func test_stage_updates_incrementally_through_drop_and_rejoin() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(30, 5, 0.0, 2)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 3, 300)
	var stage := DormStage.new()
	t.add_child(stage)
	stage.set_mode("lobby", false)
	stage.sync_party(_entries(rig.host))
	t.eq(stage.chars.size(), 3, "three characters on stage")
	var host_v: CharacterView = stage.chars["uid-host"]
	var c0_v: CharacterView = stage.chars["uid-c0"]
	var c0_mark: int = stage._mark_of["uid-c0"]
	t.eq(stage._mark_of["uid-host"], 0, "local player on the front mark")
	# guest 1 drops out of the lobby
	rig.client_ts[1].close()
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 2, 300)
	stage.sync_party(_entries(rig.host))
	t.eq(stage.chars.size(), 2, "leaver removed from the stage")
	t.check(stage.chars["uid-host"] == host_v and stage.chars["uid-c0"] == c0_v, "everyone else is the same instance (no rebuild)")
	t.eq(stage._mark_of["uid-c0"], c0_mark, "and keeps their mark")
	# the same player rejoins
	var back := rig.add_client("uid-c1", "Client1")
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 3 and back.local_slot >= 0, 300)
	stage.sync_party(_entries(rig.host))
	t.eq(stage.chars.size(), 3, "rejoined player is back on stage")
	t.check(stage.chars["uid-host"] == host_v and stage.chars["uid-c0"] == c0_v, "rejoin did not rebuild the others")
	# an outfit change is applied in place
	var c0_e: Dictionary = {}
	for e in rig.host.roster:
		if e != null and String(e["uid"]) == "uid-c0":
			c0_e = e
	var cos: Dictionary = Cosmetics.sanitize(c0_e["cosmetic"])
	cos["outfit"] = "frog"
	c0_e["cosmetic"] = cos
	stage.sync_party(_entries(rig.host))
	t.check(stage.chars["uid-c0"] == c0_v, "outfit change keeps the same character instance")
	t.eq(String(c0_v.cosmetic["outfit"]), "frog", "and shows the new outfit")
	t.check((c0_v.parts["frog"] as MeshInstance3D).visible and not (c0_v.parts["pj"] as MeshInstance3D).visible, "frog parts on, pajama parts off")
	stage.queue_free()
	rig.teardown()


func test_eight_players_fit_on_distinct_marks() -> void:
	# phone (19.5:9), iPhone SE (16:9) and iPad (4:3) aspects; looks include
	# tall hats (crowns, mascot hoods) as well as the bots' random looks
	for size in [Vector2i(2532, 1170), Vector2i(1334, 750), Vector2i(2048, 1536)]:
		for n in [1, 2, 4, 8]:
			await _check_party(n, size, false)
		await _check_party(8, size, true)


## n players on stage: distinct marks, all in view, every face clear of the
## heads and caps in front (V3: checked at 1, 2, 4 and 8).
func _check_party(n: int, size: Vector2i = Vector2i(2532, 1170), tall_hats: bool = false) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.add_child(vp)
	var stage := DormStage.new()
	vp.add_child(stage)
	stage.set_mode("lobby", false)
	var entries: Array = []
	for i in n:
		var look := Cosmetics.bot_cosmetic(i)
		if tall_hats:
			look["hat"] = ["crown", "party", "headphones", "nightcap"][i % 4]
			if i % 3 == 1:
				look["outfit"] = "frog"
		entries.append({"key": "p%d" % i, "role": TC.Role.RUNNER, "cosmetic": Cosmetics.sanitize(look), "name": "Player %d" % i,
			"is_bot": false, "local": i == 0})
	stage.sync_party(entries)
	var marks := {}
	for k in stage._mark_of:
		marks[stage._mark_of[k]] = true
	t.eq(marks.size(), n, "%d distinct stage marks" % n)
	# everyone is inside the camera frustum (after the reframe eases in)
	await t.get_tree().process_frame
	var guard := 0
	while stage._cam_t < 1.0 and guard < 120:
		await t.get_tree().process_frame
		guard += 1
	var cam := stage.cam
	var inside := 0
	for k in stage.chars:
		var v: CharacterView = stage.chars[k]
		var pts := [Vector3(0, 0.8, 0), Vector3(0, 1.5, 0), Vector3(-0.5, 0.9, 0), Vector3(0.5, 0.9, 0)]   # body, head, both shoulders/arms
		if pts.all(func(p: Vector3) -> bool: return cam.is_position_in_frustum(v.global_position + cam.global_transform.basis * Vector3(p.x, 0, 0) + Vector3(0, p.y, 0))):
			inside += 1
	t.eq(inside, n, "%d players: all in view" % n)
	# readable: no face is covered by a nearer character's head or cap
	var hidden: Array = []
	for a in stage.chars:
		var va: CharacterView = stage.chars[a]
		var right := cam.global_transform.basis.x
		# eyes, centre, mouth and forehead; hidden if an eye or two points are covered
		var samples := [[-0.1, 1.2, true], [0.1, 1.2, true], [0.0, 1.15, false], [0.0, 1.05, false], [0.0, 1.3, false]]
		var covered := 0
		var eye_covered := false
		for smp: Array in samples:
			var fa := cam.unproject_position(va.global_position + right * float(smp[0]) + Vector3(0, float(smp[1]), 0))
			var blocked := false
			for b in stage.chars:
				if a == b:
					continue
				var vb: CharacterView = stage.chars[b]
				if cam.global_position.distance_to(vb.global_position) >= cam.global_position.distance_to(va.global_position):
					continue
				for blob: Array in [[1.18, 0.34], [1.45, 0.3], [1.68, 0.22]]:   # head, cap, tall hat (nightcap / party hat / crown)
					var c := vb.global_position + Vector3(0, blob[0], 0)
					var cp := cam.unproject_position(c)
					var r := cp.distance_to(cam.unproject_position(c + right * float(blob[1])))
					if fa.distance_to(cp) < r:
						blocked = true
			if blocked:
				covered += 1
				eye_covered = eye_covered or bool(smp[2])
		if eye_covered or covered >= 2:
			hidden.append("%s (%d/5 covered)" % [a, covered])
	t.eq(hidden, [], "%d players at %s%s: every face is visible (none behind a nearer head or cap)" % [n, size, " (tall hats)" if tall_hats else ""])
	# the local player stands front and centre, facing the camera
	var lv: CharacterView = stage.chars["p0"]
	var to_cam := (cam.global_position - lv.global_position) * Vector3(1, 0, 1)
	var fwd := -lv.global_transform.basis.z
	t.check(fwd.normalized().dot(to_cam.normalized()) > 0.8, "%d players: local player faces the camera" % n)
	vp.queue_free()


func test_slot_cell_contents_stay_inside_the_cell() -> void:
	var box := HBoxContainer.new()
	t.add_child(box)
	var cell := LobbyScreen.SlotCell.new()
	box.add_child(cell)
	box.size = Vector2(cell.custom_minimum_size.x, cell.custom_minimum_size.y)
	cell.show_entry({"slot": 0, "uid": "u", "name": "Supercalifragilis", "cosmetic": Cosmetics.DEFAULT, "is_bot": false,
		"connected": true, "ready": true, "role": TC.Role.RUNNER, "pref": "any"}, true, true, {}, false)
	for i in 3:
		await t.get_tree().process_frame
	var r := cell.get_global_rect().grow(0.5)
	for c in [cell.badge, cell.face, cell.name_l]:
		t.check(r.encloses((c as Control).get_global_rect()), "%s inside the slot cell at its minimum width" % (c as Control).get_class())
	box.queue_free()
