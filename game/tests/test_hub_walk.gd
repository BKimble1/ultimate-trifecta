extends RefCounted
## V6 Walk around in the party room, on the real stage and lobby screen:
## menu input never moves the runner; walk mode moves it with collision and
## the other device sees it; the chat drawer or a sheet takes input
## ownership and nothing moves while it is open (and nothing sticks after);
## a guest's walk shows on the host's stage with a nameplate and strolls
## back to its mark; leaving the screen or starting the round ends it all.
var t
var _stage: DormStage


func _setup(rig: NetRig) -> LobbyScreen:
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	_stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = rig.host
	t.add_child(l)
	return l


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func test_walk_mode_input_ownership_and_sync() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	var l := _setup(rig)
	await rig.frames(10)
	var hv: CharacterView = _stage.chars["uid-host"]
	var mark := hv.position
	# menu mode: movement keys don't move anyone
	_press("move_forward", true)
	await rig.frames(20)
	t.check(hv.position.distance_to(mark) < 0.01, "menu input never moves the runner")
	t.eq(l.hub.moved_frames, 0, "(no movement read in menu mode)")
	_press("move_forward", false)
	# walk mode
	l._set_walk(true)
	await rig.frames(2)
	t.check(l.hub.walking and _stage.mode == "walk", "walk mode: the follow camera")
	t.check(l.stick.visible and not l.roster_col.visible, "the stick shows and the roster folds away")
	_press("move_forward", true)
	await rig.frames(40)
	_press("move_forward", false)
	t.check(hv.position.z < mark.z - 0.5, "walking forward moves the runner away from the camera (%s -> %s)" % [str(mark), str(hv.position)])
	await rig.frames(20)
	var seen: Dictionary = guest.social.hub.sample(0)
	t.check(not seen.is_empty() and int(seen["mode"]) == HubSync.MODE_WALK, "the guest sees the host walking")
	t.check((seen["pos"] as Vector2).distance_to(Vector2(hv.position.x, hv.position.z)) < 0.3, "where the host is")
	# walls and furniture: a long walk into the couch stops at it
	_press("move_left", true)
	_press("move_forward", true)
	await rig.frames(240)
	_press("move_left", false)
	_press("move_forward", false)
	t.check(HubRoom.is_free(Vector2(hv.position.x, hv.position.z)), "never inside furniture or a wall (%s)" % str(hv.position))
	# the chat drawer owns input: holding a key does nothing while it is open
	l._open_chat()
	await rig.frames(2)
	t.check(InputOwner.menu_owns(), "the chat drawer takes input ownership")
	var before := hv.position
	var mf := l.hub.moved_frames
	_press("move_right", true)
	await rig.frames(30)
	t.check(hv.position.distance_to(before) < 0.05, "nothing moves while chat is open")
	t.eq(l.hub.moved_frames, mf, "(no movement read)")
	# a message arriving while the drawer is open isn't counted as unread
	rig.host.social.chat.unread = 3
	l._on_chat()
	t.check(not UIKit.face_of(l.chat_btn).caption.contains("·") and (l._chat_dot == null or not l._chat_dot.visible), "no unread count while the drawer is open")
	Controls.touch_move = Vector2(1, 0)   # a finger that was on the stick when the drawer opened
	var drawer: ChatDrawer = l.find_children("*", "ChatDrawer", true, false)[0]
	drawer.close()
	await rig.frames(2)
	t.check(not InputOwner.menu_owns(), "closing it gives input back")
	t.eq(Controls.touch_move, Vector2.ZERO, "and clears stuck touch state")
	_press("move_right", false)
	# a sheet over the room (has_modal) blocks too
	l.dialog("A sheet", [["OK", Callable()]])
	before = hv.position
	_press("move_back", true)
	await rig.frames(20)
	_press("move_back", false)
	t.check(hv.position.distance_to(before) < 0.05, "no walking under a sheet")
	for d in l.find_children("*", "PanelContainer", false, false):
		d.queue_free()
	await rig.frames(4)
	# the guest walks: their runner leaves its mark on the host's stage, with a nameplate
	var gv: CharacterView = _stage.chars["uid-c0"]
	var gmark := gv.position
	for i in 12:
		guest.social.hub.set_local(HubSync.MODE_WALK, Vector2(gmark.x + 0.15 * i, gmark.z - 0.1 * i), 0.0, 2.0)
		await rig.frames(4)
	await rig.frames(20)
	t.check(gv.position.distance_to(gmark) > 0.8, "the guest's walk shows on the host's stage")
	t.check(_stage.free_roam.has("uid-c0"), "(walking freely)")
	t.check(gv.name_label != null and gv.name_label.visible, "with a nameplate over them")
	guest.social.hub.set_local(HubSync.MODE_MARK, Vector2(gmark.x + 1.8, gmark.z - 1.2), 0.0, 0.0)
	await rig.wait_until(func() -> bool: return not _stage.free_roam.has("uid-c0"), 400)
	t.check(gv.position.distance_to(gmark) < 0.1, "they stroll back to their mark when they stop")
	t.eq((_stage.chars["uid-c0"] as Node).get_instance_id(), gv.get_instance_id(), "the same character the whole time (no rebuild)")
	# Back leaves walk mode first (not the party)
	l.back_action.call()
	await rig.frames(2)
	t.check(not l.hub.walking and _stage.mode == "lobby" and l.roster_col.visible, "Back returns to the menu composition")
	t.check(not l.has_modal(), "without asking to leave the party")
	await rig.wait_until(func() -> bool: return not _stage.free_roam.has("uid-host"), 400)
	t.check(hv.position.distance_to(mark) < 0.1, "the host is back on their mark")
	# leaving the screen (wardrobe/Locker, shop) ends walk mode at once
	l._set_walk(true)
	await rig.frames(3)
	l.queue_free()
	await rig.frames(3)
	t.check(rig.host.social.hub.local_mode == HubSync.MODE_MARK, "leaving the party room screen stops the walk for everyone")
	_stage.queue_free()
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_round_start_cancels_walking_everywhere() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	var l := _setup(rig)
	await rig.frames(10)
	l._set_walk(true)
	guest.social.hub.set_local(HubSync.MODE_WALK, Vector2(1.0, 0.0), 0.0, 1.0)
	_press("move_forward", true)
	await rig.frames(20)
	t.check(not _stage.free_roam.is_empty(), "people are walking")
	guest.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	l._on_primary()
	await rig.frames(3)
	_press("move_forward", false)
	t.check(not l.hub.walking, "starting the round ends walk mode at once")
	t.check(_stage.free_roam.is_empty(), "everyone is back on their mark")
	t.check(rig.host.social.hub.poses.is_empty(), "no poses carry into the round")
	await rig.frames(6)
	t.check(guest.social.hub.samples.is_empty(), "on the guest too")
	l.queue_free()
	_stage.queue_free()
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


## The party room's bottom bar after V6 navigation joined it (Play · Locker
## · Shop · Season Pass, then Emote, Walk, Chat and the primary action):
## everything is on screen, a full touch target, and nothing overlaps, on a
## phone, an iPhone SE and an iPad.
func test_bottom_bar_fits_with_navigation() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	for sz in [Vector2i(2532, 1170), Vector2i(1334, 750), Vector2i(2048, 1536)]:
		root.size = sz
		await rig.frames(2)
		var l := _setup(rig)
		await rig.frames(12)
		var view := l.get_viewport().get_visible_rect()
		# (2.3) the navigation lives in the top bar; Emote, Walk and Chat in the
		# bottom bar: every one on screen, whole, and apart from the rest
		var items: Array = []
		for bar in [l.top_bar, l.bottom_bar]:
			for c in (bar as Control).get_children():
				if c is NavShell:
					for k in (c as NavShell).buttons:
						items.append([String(k), (c as NavShell).buttons[k]])
				elif c is Button and (c as Button).visible:
					items.append([UIKit.face_of(c).caption if UIKit.face_of(c) != null else (c as Button).text, c])
		items.append(["primary", l.primary_btn])
		t.check(items.size() >= 8, "%s: navigation, Emote, Walk, Chat and the primary action (%d)" % [str(sz), items.size()])
		for i in items.size():
			var r: Rect2 = (items[i][1] as Control).get_global_rect()
			t.check(view.grow(0.5).encloses(r), "%s: '%s' on screen (%s)" % [str(sz), items[i][0], str(r)])
			t.check(r.size.x >= UIKit.touch_min() - 0.5 and r.size.y >= UIKit.touch_min() - 0.5, "%s: '%s' a full touch target" % [str(sz), items[i][0]])
			for j in range(i + 1, items.size()):
				var r2: Rect2 = (items[j][1] as Control).get_global_rect()
				t.check(not r.grow(-0.5).intersects(r2.grow(-0.5)), "%s: '%s' and '%s' don't overlap" % [str(sz), items[i][0], items[j][0]])
		l.queue_free()
		_stage.queue_free()
		await rig.frames(2)
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	root.size = saved_size
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


## (build 29) A full party on an iPad keeps the two-column roster (four
## rows fit), so the stage keeps its width and the camera stays inside the
## room; a phone takes three columns.  And in Walk the icon-only bottom row
## (iPad) shows no caption: "Done" used to spill past the check button.
func test_full_party_and_walk_on_ipad() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 7)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 8, 600)
	var saved_session := App.session
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	App.session = rig.host
	for sz in [Vector2i(2048, 1536), Vector2i(2532, 1170)]:
		root.size = sz
		await rig.frames(2)
		var l := _setup(rig)
		await rig.frames(20)
		var ipad: bool = sz.x < sz.y * 1.6
		t.eq(l._grid.columns, 2 if ipad else 3, "%s: eight players in %d columns" % [str(sz), 2 if ipad else 3])
		if ipad:
			t.check(_stage.lobby_free_frac >= 0.45, "%s: the stage keeps half the width (%.2f)" % [str(sz), _stage.lobby_free_frac])
		l._set_walk(true)
		await rig.frames(4)
		var cap := UIKit.face_of(l.walk_btn).caption
		t.eq(cap, "" if l._compact else "Done", "%s: the Walk button's caption in Walk ('%s')" % [str(sz), cap])
		l._set_walk(false)
		await rig.frames(2)
		t.eq(UIKit.face_of(l.walk_btn).caption, "" if l._compact else "Walk", "%s: and back" % str(sz))
		l.queue_free()
		_stage.queue_free()
		await rig.frames(2)
	App.stage = null
	App.session = saved_session
	root.size = saved_size
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame


## (build 30) The Coins counter is in the lobby's top bar in a party room
## too (home is a party room on a device), on screen and clear of the other
## top-bar items at phone, SE and iPad sizes; a round's Coins fly into it.
func test_coins_counter_in_a_party_room() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 2, 300)
	var saved_session := App.session
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	App.session = rig.host
	for sz in [Vector2i(2868, 1320), Vector2i(1334, 750), Vector2i(2048, 1536)]:
		root.size = sz
		await rig.frames(2)
		var l := _setup(rig)
		await rig.frames(14)
		t.check(not l._solo(), "%s: a party room (not solo)" % str(sz))
		var chip: Control = l.wallet_chip
		t.check(chip.visible and chip.is_visible_in_tree(), "%s: the Coins counter shows" % str(sz))
		var view := l.get_viewport().get_visible_rect()
		var r := chip.get_global_rect()
		t.check(view.grow(0.5).encloses(r) and r.size.x > 40.0, "%s: whole and on screen (%s)" % [str(sz), str(r)])
		for c in (l.top_bar as Control).get_children():
			if c == chip or not (c is Control) or not (c as Control).visible:
				continue
			var r2 := (c as Control).get_global_rect()
			t.check(not r.grow(-0.5).intersects(r2.grow(-0.5)), "%s: clear of %s" % [str(sz), (c as Control).name])
		l.queue_free()
		_stage.queue_free()
		await rig.frames(2)
	# a round's Coins: they fly into the counter
	root.size = Vector2i(2868, 1320)
	await rig.frames(2)
	App.coin_fly_pending = 120
	var l2 := _setup(rig)
	await rig.frames(10)
	t.eq(App.coin_fly_pending, 0, "the pending Coins are taken by the lobby")
	await t.get_tree().create_timer(0.9).timeout
	t.check((l2.wallet_chip as WalletChip)._flying, "and fly into the counter")
	l2.queue_free()
	_stage.queue_free()
	await rig.frames(2)
	App.stage = null
	App.session = saved_session
	root.size = saved_size
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame



## (build 33) The walk camera follows you and only you: holding the ball
## (it used to lean halfway to the hoop, over the room's middle where the
## others stand, which read as the camera tracking the group), with 2 and 4
## people in the party walking around near you, its point stays on your
## runner as you walk, and your runner stays in the middle of the screen.
func test_walk_camera_stays_on_you_with_the_ball() -> void:
	for n in [2, 4]:
		var rig := NetRig.new()
		t.add_child(rig)
		rig.setup(30, 5, 0.0, n - 1)
		await rig.wait_until(func() -> bool:
			for c in rig.clients:
				if c.local_slot < 0:
					return false
			return rig.host.human_count() == n and rig.host.social.ball.spawned, 400)
		var saved_uid: Variant = Save.data["uid"]
		var saved_session := App.session
		var root: Window = t.get_tree().root
		var saved_size: Vector2i = root.size
		root.size = Vector2i(2868, 1320)
		Save.data["uid"] = "uid-host"
		App.session = rig.host
		var l := _setup(rig)
		await rig.frames(12)
		l._set_walk(true)
		await rig.frames(4)
		# far from the hoop, the others walking about the middle of the room
		l.hub._pos = Vector2(-2.6, 0.9)
		l.hub._vel = Vector2.ZERO
		var hb := rig.host.social.ball
		hb.sim.place(Vector3(-2.2, HubBall.R, 0.9))
		hb._dirty = true
		await rig.frames(60)
		l.hub.interact()
		await rig.wait_until(func() -> bool: return hb.holder == rig.host.local_slot, 60)
		t.check(hb.local_has(), "%d players: holding the ball" % n)
		var v: CharacterView = _stage.chars["uid-host"]
		var worst := 0.0
		var sum := 0.0
		var cnt := 0
		var worst_screen := 0.0
		var dirs := [Vector2(1, 0), Vector2(1, -0.6), Vector2(0.2, 1), Vector2(-1, 0.2), Vector2(1, 0.4), Vector2.ZERO]
		var f := 0
		for d in dirs:
			l.hub.stick = Vector2(d.x, -d.y).limit_length(1.0)
			for i in 34:
				f += 1
				for ci in rig.clients.size():
					var c: NetSession = rig.clients[ci]
					var a := float(f) * 0.05 + float(ci) * 2.1
					c.social.hub.set_local(HubSync.MODE_WALK, Vector2(0.2 + cos(a) * 1.3, 0.2 + sin(a) * 0.9), a, 1.5)
				await rig.frames(1)
				if f < 20:
					continue
				var p := Vector2(v.position.x, v.position.z)
				var at := _stage._walk_at
				var off := Vector2(at.x, at.z + 0.8).distance_to(p)
				worst = maxf(worst, off)
				sum += off
				cnt += 1
				var sp := _stage.cam.unproject_position(v.global_position + Vector3(0, 0.6, 0))
				var vs := l.get_viewport().get_visible_rect().size
				worst_screen = maxf(worst_screen, absf(sp.x / vs.x - 0.5))
		l.hub.stick = Vector2.ZERO
		t.check(hb.local_has(), "%d players: still holding it" % n)
		t.check(worst < 0.3, "%d players: the camera's point stays on your runner as you walk with the ball (worst %.2f m)" % [n, worst])
		t.check(sum / maxf(1.0, float(cnt)) < 0.12, "%d players: on average right on them (%.3f m)" % [n, sum / maxf(1.0, float(cnt))])
		t.check(worst_screen < 0.08, "%d players: your runner stays in the middle of the screen (at most %.0f%% off)" % [n, worst_screen * 100.0])
		# and while your shot flies (it used to swing over to the hoop)
		var at0 := Vector2(v.position.x, v.position.z)
		var rc := HubBall.rim_center()
		var to := Vector2(rc.x, rc.z) - at0
		l.hub._yaw = atan2(-to.x, -to.y)
		await rig.frames(6)
		l.hub.interact()
		var fly := 0.0
		for i in 90:
			await rig.frames(1)
			var p2 := Vector2(v.position.x, v.position.z)
			fly = maxf(fly, Vector2(_stage._walk_at.x, _stage._walk_at.z + 0.8).distance_to(p2))
		t.check(not hb.local_has(), "%d players: shot" % n)
		t.check(fly < 0.1, "%d players: the camera stays on you while the shot flies (%.2f m)" % [n, fly])
		l.queue_free()
		_stage.queue_free()
		await rig.frames(2)
		App.stage = null
		App.session = saved_session
		Save.data["uid"] = saved_uid
		root.size = saved_size
		rig.teardown()
		await t.get_tree().process_frame
		await t.get_tree().process_frame


## (build 33) The ball's buttons (Shoot / Dunk with Pass and Drop above it,
## Block) on iPhone SE (667x375 pt), a 6.9" iPhone (956x440 pt) and an iPad
## (1024x768 pt): each on screen, a full touch target, apart from each other,
## the stick's half of the screen and both bars.
func test_ball_buttons_fit_every_screen() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 2)
	await rig.wait_until(func() -> bool:
		for c in rig.clients:
			if c.local_slot < 0:
				return false
		return rig.host.human_count() == 3 and rig.host.social.ball.spawned, 400)
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	var hb := rig.host.social.ball
	var rc := HubBall.rim_center()
	var rim := Vector2(rc.x, rc.z)
	var c0: NetSession = rig.clients[0]
	for sz in [Vector2i(1334, 750), Vector2i(2868, 1320), Vector2i(2048, 1536)]:
		root.size = sz
		await rig.frames(2)
		var l := _setup(rig)
		await rig.frames(12)
		l._set_walk(true)
		await rig.frames(6)
		# a friend walking (Pass is offered)
		c0.social.hub.set_local(HubSync.MODE_MARK, Vector2(0.5, 1.0), 0.0, 0.0)
		await rig.frames(3)
		c0.social.hub.set_local(HubSync.MODE_WALK, Vector2(0.5, 1.0), 0.0, 0.0)
		var at := rim + HubBall.HOOP_DIR * 2.6
		l.hub._pos = at
		l.hub._yaw = atan2(-(rim - at).x, -(rim - at).y)
		await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.FREE and hb.holder < 0, 200)
		hb.sim.place(Vector3(at.x + 0.3, HubBall.R, at.y))
		hb._dirty = true
		await rig.frames(14)
		l.hub.interact()
		await rig.wait_until(func() -> bool: return hb.local_has(), 60)
		await rig.frames(30)
		_check_ball_buttons(l, sz, "Shoot", ["pass", "drop"])
		# in dunk range: the same slot says Dunk
		var near := rim + HubBall.HOOP_DIR * 1.2
		l.hub._pos = near
		l.hub._yaw = atan2(-(rim - near).x, -(rim - near).y)
		await rig.frames(30)
		_check_ball_buttons(l, sz, "Dunk", ["pass", "drop"])
		# Block: the friend shoots next to you
		l.hub.ball_action("drop")
		await rig.frames(40)
		var shoot_at := rim + HubBall.HOOP_DIR * 2.6
		c0.social.hub.set_local(HubSync.MODE_WALK, shoot_at, 0.0, 0.0)
		l.hub._pos = shoot_at + Vector2(0.4, -1.1)
		await rig.frames(20)
		hb.sim.place(Vector3(shoot_at.x + 0.3, HubBall.R, shoot_at.y))
		hb._dirty = true
		await rig.frames(14)
		c0.social.ball.request(BallSync.ACT_PICKUP)
		await rig.wait_until(func() -> bool: return hb.holder == c0.local_slot, 60)
		await rig.frames(12)
		c0.social.ball.request(BallSync.ACT_SHOOT, -1, atan2(-(rim - shoot_at).x, -(rim - shoot_at).y))
		await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.SHOT, 30)
		hb._wind = 99.0   # (a long windup, to look at the button)
		await rig.frames(16)
		_check_ball_buttons(l, sz, "Block", [])
		# it goes away smoothly once the chance has gone
		hb._wind = 0.0
		await rig.frames(60)
		t.check(not l.act_btn.visible or UIKit.face_of(l.act_btn).caption != "Block", "%s: Block goes away after the shot" % str(sz))
		await rig.frames(60)
		l.queue_free()
		_stage.queue_free()
		await rig.frames(2)
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	root.size = saved_size
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame


func _check_ball_buttons(l: LobbyScreen, sz: Vector2i, caption: String, extras: Array) -> void:
	var tag := "%s %s" % [str(sz), caption]
	t.check(l.act_btn.visible and UIKit.face_of(l.act_btn).caption == caption, "%s: the button says %s ('%s')" % [tag, caption, UIKit.face_of(l.act_btn).caption])
	t.check(l.act_btn.modulate.a > 0.99 and l.act_btn.scale.distance_to(Vector2.ONE) < 0.01, "%s: (settled after its pop)" % tag)
	var items: Array = [[caption, l.act_btn]]
	for id in extras:
		var b: Button = l._ball_btns[id]
		t.check(b.visible, "%s: %s shows" % [tag, id])
		items.append([id, b])
	for id in l._ball_btns:
		if not extras.has(id):
			t.check(not (l._ball_btns[id] as Button).visible, "%s: no %s" % [tag, id])
	var view := l.get_viewport().get_visible_rect()
	var others: Array = [["the stick", l.stick]]
	for bar in [l.top_bar, l.bottom_bar]:
		for c in (bar as Control).get_children():
			if c is Control and (c as Control).visible and (c as Control).get_global_rect().size.x > 1.0:
				others.append([String((c as Control).name), c])
	for i in items.size():
		var r: Rect2 = (items[i][1] as Control).get_global_rect()
		t.check(view.grow(0.5).encloses(r), "%s: '%s' on screen (%s)" % [tag, items[i][0], str(r)])
		t.check(r.size.x >= UIKit.touch_min() - 0.5 and r.size.y >= UIKit.touch_min() - 0.5, "%s: '%s' a full touch target (%s)" % [tag, items[i][0], str(r.size)])
		for j in range(i + 1, items.size()):
			var r2: Rect2 = (items[j][1] as Control).get_global_rect()
			t.check(not r.grow(-0.5).intersects(r2.grow(-0.5)), "%s: '%s' and '%s' apart" % [tag, items[i][0], items[j][0]])
		for o in others:
			var r3: Rect2 = (o[1] as Control).get_global_rect()
			t.check(not r.grow(-0.5).intersects(r3.grow(-0.5)), "%s: '%s' clear of %s (%s / %s)" % [tag, items[i][0], o[0], str(r), str(r3)])
