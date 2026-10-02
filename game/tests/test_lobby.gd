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
	for n in [1, 2, 4, 8]:
		await _check_party(n)


## n players on stage: distinct marks, all in view, every face clear of the
## heads and caps in front (V3: checked at 1, 2, 4 and 8).
func _check_party(n: int) -> void:
	var stage := DormStage.new()
	t.add_child(stage)
	stage.set_mode("lobby", false)
	var entries: Array = []
	for i in n:
		entries.append({"key": "p%d" % i, "role": TC.Role.RUNNER, "cosmetic": Cosmetics.bot_cosmetic(i), "name": "Player %d" % i,
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
		if cam.is_position_in_frustum(v.global_position + Vector3(0, 0.8, 0)) and cam.is_position_in_frustum(v.global_position + Vector3(0, 1.5, 0)):
			inside += 1
	t.eq(inside, n, "%d players: all in view" % n)
	# readable: no face is covered by a nearer character's head or cap
	var hidden: Array = []
	for a in stage.chars:
		var va: CharacterView = stage.chars[a]
		var face := va.global_position + Vector3(0, 1.15, 0)
		var fa := cam.unproject_position(face)
		for b in stage.chars:
			if a == b:
				continue
			var vb: CharacterView = stage.chars[b]
			if cam.global_position.distance_to(vb.global_position) >= cam.global_position.distance_to(va.global_position):
				continue
			for blob: Array in [[1.18, 0.34], [1.45, 0.3]]:   # head, cap
				var c := vb.global_position + Vector3(0, blob[0], 0)
				var cp := cam.unproject_position(c)
				var r := cp.distance_to(cam.unproject_position(c + cam.global_transform.basis.x * float(blob[1])))
				if fa.distance_to(cp) < r:
					hidden.append("%s behind %s" % [a, b])
	t.eq(hidden, [], "%d players: every face is visible (none behind a nearer head or cap)" % n)
	# the local player stands front and centre, facing the camera
	var lv: CharacterView = stage.chars["p0"]
	var to_cam := (cam.global_position - lv.global_position) * Vector3(1, 0, 1)
	var fwd := -lv.global_transform.basis.z
	t.check(fwd.normalized().dot(to_cam.normalized()) > 0.8, "%d players: local player faces the camera" % n)
	stage.queue_free()


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
