extends RefCounted
## V5 party flow on the shared stage: rapid repeated emotes, a trip to the
## wardrobe and back, then the round starts - the same characters stay on
## their marks the whole time (no party rebuild), animations and timers
## don't pile up, and the start yields at once from a Try-moves preview.
var t
var _stage: DormStage


func test_emotes_wardrobe_return_and_start() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(40, 5, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	# as in the app: this device's player is the host, and App knows the session
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	_stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = rig.host
	t.add_child(l)
	await rig.frames(10)
	t.check(_stage.chars.has("uid-host") and _stage.chars.has("uid-c0"), "both runners on the stage")
	var ids := {}
	for k in _stage.chars:
		ids[k] = (_stage.chars[k] as Node).get_instance_id()
	# rapid emotes: eight presses within a few frames, alternating
	var starts0 := int(_stage.emote_starts.get("uid-host", 0))
	for i in 8:
		l._send_emote(i % TC.EMOTES.size())
		await rig.frames(1)
	await rig.frames(6)
	var hv: CharacterView = _stage.chars["uid-host"]
	t.check(int(_stage.emote_starts.get("uid-host", 0)) - starts0 >= 8, "every press started its emote (no lost input)")
	t.eq(hv._mode, "emote_" + String(TC.EMOTES[7 % TC.EMOTES.size()]), "the newest emote owns the runner")
	# a press-feedback storm on the primary button leaves one animation at most
	for i in 10:
		l.primary_btn.button_down.emit()
		l.primary_btn.button_up.emit()
	await rig.frames(2)
	t.check(Motion.running(UIKit.face_of(l.primary_btn)).size() <= 1, "one press animation owns the button face")
	# to the wardrobe and back: same characters, nothing rebuilt
	var w := CreatorScreen.new()
	w.back_action_override = func() -> void: pass
	t.add_child(w)
	l.visible = false
	await rig.frames(8)
	t.eq(_stage.mode, "wardrobe", "the stage moved to the wardrobe framing")
	w._leave()
	w.queue_free()
	l.visible = true
	_stage.set_mode("lobby")
	await rig.frames(int(Motion.CAMERA * 60.0) + 4)
	t.eq(_stage.mode, "lobby", "back in the party room")
	for k in ids:
		t.check(_stage.chars.has(k) and (_stage.chars[k] as Node).get_instance_id() == ids[k], "%s kept the same character (no rebuild)" % k)
	# an outfit change shows on the right person only
	var cos: Dictionary = Cosmetics.sanitize(guest.local_cosmetic)
	cos["outfit"] = "duck"
	guest.set_local_cosmetic(cos)
	await rig.wait_until(func() -> bool: return String((_stage.chars["uid-c0"] as CharacterView).cosmetic.get("outfit", "")) == "duck", 200)
	t.eq(String((_stage.chars["uid-c0"] as CharacterView).cosmetic["outfit"]), "duck", "the guest's new outfit is on the guest")
	t.check(String((_stage.chars["uid-host"] as CharacterView).cosmetic["outfit"]) != "duck" or String(Cosmetics.sanitize(rig.host.local_cosmetic)["outfit"]) == "duck", "and not on the host")
	t.eq((_stage.chars["uid-c0"] as Node).get_instance_id(), ids["uid-c0"], "updated in place")
	# Try moves, then Start: the preview yields at once
	l._try_move("sprint")
	await rig.frames(3)
	t.check(not _stage._preview.is_empty(), "a move preview is playing")
	guest.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	l._on_primary()
	t.check(_stage._preview.is_empty(), "starting the round stops the preview at once")
	await rig.frames(5)
	t.check(rig.host.phase != TC.Phase.LOBBY, "the round is starting")
	l.queue_free()
	_stage.queue_free()
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	rig.teardown()
