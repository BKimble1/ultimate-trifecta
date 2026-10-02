extends RefCounted
## V4 touch layout: sizes in points, safe-area anchoring, mirroring, custom
## anchors on another device, non-overlapping hit padding, role transitions,
## repeated taps, vanished buttons and no per-frame layout rebuilding.
var t

## [name, view (canvas units), canvas->px, point scale, safe insets in points (L,T,R,B)]
const DEVICES := [
	["iPhone 14 Pro (Dynamic Island)", Vector2(1558, 720), 1.625, 3.0, [59.0, 0.0, 59.0, 21.0]],
	["iPhone SE (16:9)", Vector2(1280, 720), 1.0417, 2.0, [0.0, 0.0, 0.0, 0.0]],
	["iPhone 15 Pro Max", Vector2(1558, 720), 1.7889, 3.0, [59.0, 0.0, 59.0, 21.0]],
	["iPad 11-inch (4:3-ish)", Vector2(1031, 720), 2.3167, 2.0, [0.0, 24.0, 0.0, 20.0]],
]


func _safe(view: Vector2, upp: float, ins: Array) -> Rect2:
	var l := maxf(float(ins[0]) * upp, 16.0)
	var tp := maxf(float(ins[1]) * upp, 12.0)
	var r := maxf(float(ins[2]) * upp, 16.0)
	var b := maxf(float(ins[3]) * upp, 12.0)
	return Rect2(Vector2(l, tp), view - Vector2(l + r, tp + b))


func _all(dev: Array, layout: Dictionary, ctx: String) -> Dictionary:
	var upp := TouchLayout.units_per_point(float(dev[2]), float(dev[3]))
	var view: Vector2 = dev[1]
	return TouchLayout.resolve(layout, ctx, view, _safe(view, upp, dev[4]), upp, [Rect2(view.x - 260, 0, 260, 200)])


func test_targets_are_at_least_44_points_and_the_same_size_everywhere() -> void:
	for dev in DEVICES:
		var res := _all(dev, TouchLayout.default_layout(), "patrol")
		var upp: float = res["upp"]
		for name in res["buttons"]:
			var b: Dictionary = res["buttons"][name]
			t.check(float(b["r"]) * 2.0 / upp >= 44.0 - 0.01, "%s %s is >= 44 pt (%.0f pt)" % [dev[0], name, float(b["r"]) * 2.0 / upp])
		var tag_pt := float(res["buttons"]["tag"]["r"]) * 2.0 / upp
		t.near(tag_pt, 88.0, 0.5, "%s: Tag is 88 pt across on every device" % dev[0])
		t.check(tag_pt > float(res["buttons"]["jump"]["r"]) * 2.0 / upp, "%s: the primary chase action is the largest" % dev[0])


func test_everything_stays_inside_the_safe_area_standard_and_mirrored() -> void:
	for dev in DEVICES:
		for mirror in [false, true]:
			var l := TouchLayout.default_layout()
			l["mirror"] = mirror
			for ctx in TouchLayout.CONTEXTS:
				var upp := TouchLayout.units_per_point(float(dev[2]), float(dev[3]))
				var safe := _safe(dev[1], upp, dev[4])
				var res := TouchLayout.resolve(l, ctx, dev[1], safe, upp)
				for name in res["buttons"]:
					var b: Dictionary = res["buttons"][name]
					var box := Rect2(b["c"] - Vector2.ONE * float(b["r"]), Vector2.ONE * float(b["r"]) * 2.0)
					t.check(safe.encloses(box), "%s %s %s %s inside the safe area" % [dev[0], "mirrored" if mirror else "standard", ctx, name])
				var sc: Vector2 = res["stick_c"]
				var sr: float = res["stick_r"]
				t.check(safe.encloses(Rect2(sc - Vector2.ONE * sr, Vector2.ONE * sr * 2.0)), "%s stick ring inside the safe area" % dev[0])
				t.check((sc.x < dev[1].x * 0.5) != mirror, "%s stick on the %s" % [dev[0], "right" if mirror else "left"])


func test_hit_padding_never_overlaps_and_never_shrinks_a_target() -> void:
	for dev in DEVICES:
		for ctx in TouchLayout.CONTEXTS:
			var res := _all(dev, TouchLayout.default_layout(), ctx)
			var names: Array = res["buttons"].keys()
			for i in names.size():
				var a: Dictionary = res["buttons"][names[i]]
				t.check(float(a["hit"]) >= float(a["r"]), "hit area covers the drawn button")
				for j in range(i + 1, names.size()):
					var b: Dictionary = res["buttons"][names[j]]
					var d := (a["c"] as Vector2).distance_to(b["c"])
					t.check(d >= float(a["hit"]) + float(b["hit"]) - 0.01, "%s %s: %s and %s hit areas do not overlap" % [dev[0], ctx, names[i], names[j]])


func test_mirrored_hit_testing_matches_the_drawn_controls() -> void:
	var dev: Array = DEVICES[0]
	var l := TouchLayout.default_layout()
	l["mirror"] = true
	var res := _all(dev, l, "runner")
	var r := TouchRouter.new()
	r.view_size = dev[1]
	r.set_buttons(res["buttons"])
	r.stick_zone = res["zone"]
	r.stick_radius = res["stick_r"]
	for name in res["buttons"]:
		var b: Dictionary = res["buttons"][name]
		t.eq(r.hit_button(b["c"]), name, "a touch on the drawn %s hits %s" % [name, name])
		t.eq(r.hit_button(b["c"] + Vector2(float(b["r"]) * 0.9, 0)), name, "its drawn edge too")
	var jump: Vector2 = res["buttons"]["jump"]["c"]
	t.check(jump.x < dev[1].x * 0.5, "mirrored: the actions are on the left")
	r.touch_down(0, Vector2(dev[1].x - 300, 560))   # right thumb, mirrored stick side
	t.check(r.stick_active(), "mirrored: the stick spawns on the right")
	r.touch_down(1, Vector2(700, 300))               # middle of the screen
	r.drag(1, Vector2(760, 300), Vector2(60, 0))
	t.eq(r.take_look_px(), Vector2(60, 0), "the camera area is untouched by the layout")


func test_custom_anchor_is_used_and_clamped_on_another_device() -> void:
	var phone: Array = DEVICES[0]
	var ipad: Array = DEVICES[3]
	var upp := TouchLayout.units_per_point(float(phone[2]), float(phone[3]))
	var safe := _safe(phone[1], upp, phone[4])
	var want := Vector2(phone[1].x - 420, 520)
	var l := TouchLayout.default_layout()
	l["action"] = {"runner": TouchLayout.normalize(want, safe)}
	var res := TouchLayout.resolve(l, "runner", phone[1], safe, upp)
	t.check((res["action_anchor"] as Vector2).distance_to(want) < 1.0, "the dragged anchor is where the primary sits")
	t.check(not bool(res["clamped"]), "nothing to clamp on the device it was made on")
	# extreme corner anchor: clamped back inside, never off screen
	l["action"] = {"runner": [1.0, 1.0]}
	var res2 := TouchLayout.resolve(l, "runner", phone[1], safe, upp)
	t.check(bool(res2["clamped"]), "an off-edge anchor is clamped")
	var jb: Dictionary = res2["buttons"]["jump"]
	t.check(safe.encloses(Rect2(jb["c"] - Vector2.ONE * float(jb["r"]), Vector2.ONE * float(jb["r"]) * 2.0)), "and Jump stays inside")
	# saved on the phone, opened on an iPad: still inside and clear of the stick
	l["action"] = {"runner": TouchLayout.normalize(want, safe)}
	var res3 := _all(ipad, l, "runner")
	var upp3: float = res3["upp"]
	var safe3 := _safe(ipad[1], upp3, ipad[4])
	for name in res3["buttons"]:
		var b: Dictionary = res3["buttons"][name]
		t.check(safe3.encloses(Rect2(b["c"] - Vector2.ONE * float(b["r"]), Vector2.ONE * float(b["r"]) * 2.0)), "iPad: %s inside" % name)
		t.check((b["c"] as Vector2).distance_to(res3["stick_c"]) > float(b["r"]) + float(res3["stick_r"]), "iPad: %s clear of the stick" % name)


func test_action_cluster_dropped_on_the_stick_is_pushed_clear() -> void:
	var dev: Array = DEVICES[1]
	var upp := TouchLayout.units_per_point(float(dev[2]), float(dev[3]))
	var safe := _safe(dev[1], upp, dev[4])
	var l := TouchLayout.default_layout()
	var base := TouchLayout.resolve(l, "runner", dev[1], safe, upp)
	l["action"] = {"runner": TouchLayout.normalize(base["stick_c"], safe)}
	var res := TouchLayout.resolve(l, "runner", dev[1], safe, upp)
	t.check(bool(res["clamped"]), "moved")
	for name in res["buttons"]:
		var b: Dictionary = res["buttons"][name]
		t.check((b["c"] as Vector2).distance_to(res["stick_c"]) > float(b["hit"]) + float(res["stick_r"]), "%s does not overlap the stick" % name)


func test_contextual_buttons_never_shuffle_the_others() -> void:
	var dev: Array = DEVICES[0]
	var res := _all(dev, TouchLayout.default_layout(), "patrol")
	var s := TouchControls.TouchSurface.new()
	s.layout = TouchLayout.default_layout()
	s.size = dev[1]
	var c := {"st": TC.PState.ACTIVE, "role": TC.Role.PATROL, "in_cart": false, "near_cart": false, "gadget": 0,
		"phase": TC.Phase.PLAYING, "airborne": false, "watching": false}
	s._layout_buttons(c)
	var tag1: Vector2 = s.router.buttons["tag"]["c"]
	var jump1: Vector2 = s.router.buttons["jump"]["c"]
	t.check(not s.router.buttons.has("cart"), "no Drive away from carts")
	c["st"] = TC.PState.WAITING
	s._layout_buttons(c)
	t.check(s.router.buttons.has("tag"), "Tag stays (greyed) during the head start")
	t.eq(s.router.buttons["tag"]["c"], tag1, "in the same place")
	Controls.clear_edges()
	s.router.touch_down(0, tag1)
	s._apply(c)
	t.eq(Controls.pending_edges(), 0, "a greyed Tag sends nothing")
	s.router.touch_up(0)
	Controls.reset_touch()
	c["st"] = TC.PState.ACTIVE
	c["near_cart"] = true
	s._layout_buttons(c)
	t.check(s.router.buttons.has("cart"), "Drive appears near a cart")
	t.eq(s.router.buttons["tag"]["c"], tag1, "Tag did not move")
	t.eq(s.router.buttons["jump"]["c"], jump1, "Jump did not move")
	t.check(res["buttons"]["tag"]["r"] > res["buttons"]["jump"]["r"], "Night Watch: Tag is the primary")
	s.free()


func test_role_transition_releases_holds_but_keeps_movement() -> void:
	var dev: Array = DEVICES[0]
	var s := TouchControls.TouchSurface.new()
	s.layout = TouchLayout.default_layout()
	s.size = dev[1]
	s.router.view_size = dev[1]
	var c := {"st": TC.PState.ACTIVE, "role": TC.Role.PATROL, "in_cart": false, "near_cart": true, "gadget": 0,
		"phase": TC.Phase.PLAYING, "airborne": false, "watching": false}
	s._layout_buttons(c)
	var zone: Rect2 = s.router.stick_zone
	s.router.touch_down(0, zone.get_center())                 # walking
	s.router.drag(0, zone.get_center() + Vector2(0, -80), Vector2(0, -80))
	s.router.touch_down(1, s.router.buttons["jump"]["c"])    # holding Jump
	t.check(s.router.is_held("jump"), "jump held")
	c["in_cart"] = true                                       # Drive pressed: now driving
	s._layout_buttons(c)
	t.check(not s.router.is_held("jump"), "the vanished Jump hold is released")
	t.check(s.router.stick_active() and s.router.move_vector().y > 0.5, "movement continues (now steering)")
	s.router.drag(1, Vector2(800, 200), Vector2(-300, -100))
	t.eq(s.router.take_look_px(), Vector2.ZERO, "the old Jump finger does not become a camera drag")
	t.check(not s.router.is_held("gas"), "nor presses Gas")
	s.free()


func test_repeated_taps_each_count_once_in_order() -> void:
	var dev: Array = DEVICES[0]
	var res := _all(dev, TouchLayout.default_layout(), "patrol")
	var r := TouchRouter.new()
	r.view_size = dev[1]
	r.set_buttons(res["buttons"])
	var tag: Vector2 = res["buttons"]["tag"]["c"]
	var jump: Vector2 = res["buttons"]["jump"]["c"]
	for i in 5:
		r.touch_down(i, tag)
		r.touch_up(i)
	r.touch_down(9, jump)
	r.touch_down(10, tag)
	t.eq(r.take_edges(), ["tag", "tag", "tag", "tag", "tag", "jump", "tag"] as Array[String], "every tap, once, in order")
	t.eq(r.take_edges().size(), 0, "consumed")


func test_vanished_gadget_button_releases_its_finger() -> void:
	var dev: Array = DEVICES[1]
	var s := TouchControls.TouchSurface.new()
	s.layout = TouchLayout.default_layout()
	s.size = dev[1]
	s.router.view_size = dev[1]
	var c := {"st": TC.PState.ACTIVE, "role": TC.Role.RUNNER, "in_cart": false, "near_cart": false, "gadget": TC.Gadget.values()[1] if TC.Gadget.size() > 1 else 1,
		"phase": TC.Phase.PLAYING, "airborne": false, "watching": false}
	s._layout_buttons(c)
	t.check(s.router.buttons.has("gadget"), "gadget shown while carried")
	s.router.touch_down(3, s.router.buttons["gadget"]["c"])
	c["gadget"] = TC.Gadget.NONE
	s._layout_buttons(c)
	t.check(not s.router.buttons.has("gadget") and s.router.held().is_empty(), "used up: button gone, nothing held")
	s.router.drag(3, Vector2(900, 300), Vector2(-200, 0))
	t.eq(s.router.take_look_px(), Vector2.ZERO, "the finger stays inert until it lifts")
	s.free()


func test_layout_is_not_rebuilt_every_frame() -> void:
	var s := TouchControls.TouchSurface.new()
	s.layout = TouchLayout.default_layout()
	s.size = Vector2(1558, 720)
	var c := {"st": TC.PState.ACTIVE, "role": TC.Role.RUNNER, "in_cart": false, "near_cart": false, "gadget": 0,
		"phase": TC.Phase.PLAYING, "airborne": false, "watching": false}
	for i in 30:
		c["airborne"] = i % 2 == 0     # Jump <-> Dive is a label, not a layout
		s._layout_buttons(c)
	t.eq(s.layout_builds, 1, "same size, safe area, context and settings: built once")
	c["in_cart"] = true
	s._layout_buttons(c)
	t.eq(s.layout_builds, 2, "a context change rebuilds")
	t.eq(s.label_of("jump", {"airborne": true, "role": TC.Role.RUNNER}), "Dive", "Jump reads Dive in the air")
	s.free()


func test_saved_layout_migrates_and_rejects_garbage() -> void:
	var m := TouchLayout.sanitize(null, 1.2, true)
	t.eq(float(m["size"]), 1.2, "V3 button size carried over")
	t.check(bool(m["mirror"]), "V3 mirrored layout carried over")
	var g := TouchLayout.sanitize({"size": 9.0, "opacity": -1, "move": ["x", 2], "action": {"runner": [NAN, 0.5], "patrol": [0.8, 1.7], "bogus": [0.1, 0.1]}})
	t.eq(float(g["size"]), TouchLayout.SIZE_MAX, "size limited")
	t.eq(float(g["opacity"]), TouchLayout.OPACITY_MIN, "opacity limited")
	t.check((g["action"] as Dictionary).has("patrol") and not (g["action"] as Dictionary).has("runner") and not (g["action"] as Dictionary).has("bogus"),
		"bad anchors dropped, good ones clamped (%s)" % str(g["action"]))
	t.eq(g["action"]["patrol"], [0.8, 1.0], "clamped to the safe area")


func test_tiny_or_degenerate_views_never_hang() -> void:
	for view in [Vector2(64, 64), Vector2(1, 1), Vector2(300, 720)]:
		var safe := Rect2(Vector2(16, 12), view - Vector2(32, 24))
		var res := TouchLayout.resolve(TouchLayout.default_layout(), "runner", view, safe, 1.846, [Rect2(0, 0, 50, 50)])
		t.check(res.has("buttons"), "a layout comes back for %s" % str(view))


## The touch surface covers the screen on a layer above the HUD; taps on the
## HUD's Pause button and map must still reach them.  GUI picking skips a
## control whose _has_point is false, so reserved HUD regions are not the
## surface's.  (Headless test windows don't route GUI clicks; the dispatch
## itself is checked in a real window by src/dev/input_fallthrough_check.tscn.)
func test_hud_regions_fall_through_the_touch_surface() -> void:
	var s := TouchControls.TouchSurface.new()
	s.size = Vector2(1558, 720)
	var pause_r := Rect2(1440, 20, 80, 80)
	var reserved: Array[Rect2] = [pause_r.grow(12)]
	s.set_reserved(reserved)
	t.check(not s._has_point(pause_r.get_center()), "a tap on Pause is not the touch surface's")
	t.check(not s._has_point(pause_r.position + Vector2(-8, -8)), "nor its padding")
	t.check(s._has_point(Vector2(700, 400)), "the camera area is")
	t.check(s._has_point(Vector2(200, 600)), "and the stick area")
	s.free()
