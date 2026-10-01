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
	var stage := DormStage.new()
	t.add_child(stage)
	stage.set_mode("lobby", false)
	var entries: Array = []
	for i in 8:
		entries.append({"key": "p%d" % i, "role": TC.Role.RUNNER, "cosmetic": Cosmetics.bot_cosmetic(i), "name": "Player %d" % i,
			"is_bot": false, "local": i == 0})
	stage.sync_party(entries)
	var marks := {}
	for k in stage._mark_of:
		marks[stage._mark_of[k]] = true
	t.eq(marks.size(), 8, "eight distinct stage marks")
	# everyone is inside the camera frustum
	await t.get_tree().process_frame
	var cam := stage.cam
	var inside := 0
	for k in stage.chars:
		var v: CharacterView = stage.chars[k]
		if cam.is_position_in_frustum(v.global_position + Vector3(0, 0.8, 0)) and cam.is_position_in_frustum(v.global_position + Vector3(0, 1.5, 0)):
			inside += 1
		else:
			print("OUT ", k, " mark=", stage._mark_of[k], " pos=", v.global_position, " screen=", cam.unproject_position(v.global_position + Vector3(0, 0.8, 0)), " vp=", stage.get_viewport().get_visible_rect().size)
	t.eq(inside, 8, "all eight characters are in view")
	stage.queue_free()
