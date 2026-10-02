extends RefCounted
## V5 motion layer (src/ui/motion.gd) and UIKit press feedback.
## The V4 defect: UIKit._scale_to started a new tween per press/release and
## never stopped the previous one, so tap-release-tap left the release spring
## running under the new press and a held button sprang back to full size.
var t


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _ctl() -> Control:
	var c := Control.new()
	c.size = Vector2(200, 80)
	t.add_child(c)
	return c


## V4's code path, reproduced verbatim: two unowned tweens fight.
func _v4_scale_to(c: Control, s: float, spring: bool) -> void:
	var tw := c.create_tween()
	if spring:
		tw.tween_property(c, "scale", Vector2(s, s), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(c, "scale", Vector2(s, s), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func test_v4_press_race_is_reproduced_and_fixed() -> void:
	# tap, release after ~1 frame, press again ~2 frames later and hold
	var old := _ctl()
	_v4_scale_to(old, 0.96, false)
	await _frames(1)
	_v4_scale_to(old, 1.0, true)
	await _frames(2)
	_v4_scale_to(old, 0.96, false)
	await _frames(24)   # 0.4 s, finger still down
	t.check(old.scale.x > 0.99, "V4 reproduction: the held button has sprung back to full size (scale %.3f)" % old.scale.x)
	old.queue_free()
	var c := _ctl()
	var most := 0
	Motion.press(c, true)
	await _frames(1)
	Motion.press(c, false)
	most = maxi(most, Motion.running(c).size())
	await _frames(2)
	Motion.press(c, true)
	for i in 24:
		await _frames(1)
		most = maxi(most, Motion.running(c).size())
	t.check(absf(c.scale.x - Motion.PRESS_SCALE) < 0.002, "V5: the held button stays pressed (scale %.3f)" % c.scale.x)
	t.eq(most, 1, "one animation owns the scale at any time")
	Motion.press(c, false)
	await _frames(20)
	t.check(absf(c.scale.x - 1.0) < 0.002, "release settles at full size")
	t.eq(Motion.running(c).size(), 0, "nothing left running after release")
	c.queue_free()


func test_press_scales_the_face_not_the_hit_region() -> void:
	var b := UIKit.primary("Play with Friends")
	t.add_child(b)
	b.position = Vector2(100, 100)
	await _frames(2)
	var rect := b.get_global_rect()
	var f := UIKit.face_of(b)
	t.check(f != null and f.get_parent() == b, "the button has a face")
	b.button_down.emit()
	await _frames(4)
	t.check(f.scale.x < 0.99, "the face sinks on press (%.3f)" % f.scale.x)
	t.eq(b.scale, Vector2.ONE, "the hit region never scales")
	t.eq(b.get_global_rect(), rect, "the hit region never moves")
	t.check(f.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the face never takes touches")
	b.button_up.emit()
	await _frames(16)
	t.check(absf(f.scale.x - 1.0) < 0.003, "and settles back")
	# press responds in ~85 ms, release settles in ~190 ms
	t.check(Motion.PRESS_IN >= 0.07 and Motion.PRESS_IN <= 0.1, "press duration in the 70-100 ms range")
	t.check(Motion.PRESS_OUT >= 0.15 and Motion.PRESS_OUT <= 0.22, "release duration in the 150-220 ms range")
	b.queue_free()


func test_hidden_while_held_resets_and_free_mid_animation_is_clean() -> void:
	var b := UIKit.secondary("Wardrobe")
	t.add_child(b)
	await _frames(2)
	var f := UIKit.face_of(b)
	b.button_down.emit()
	await _frames(3)
	b.visible = false
	await _frames(1)
	t.eq(f.scale, Vector2.ONE, "hidden while held: no shrunken face left behind")
	b.visible = true
	b.button_down.emit()
	await _frames(1)
	b.queue_free()     # freed mid-animation: the tween goes with it
	await _frames(5)
	t.check(not is_instance_valid(b), "freed")
	# a node freed during a fade-out with a callback: no errors, no call
	var c := _ctl()
	var called := {"n": 0}
	Motion.vanish(c, func() -> void: called["n"] += 1, 0.2)
	await _frames(2)
	c.queue_free()
	await _frames(20)
	t.eq(int(called["n"]), 0, "a freed node's callback never runs")


func test_retarget_cancels_the_old_callback() -> void:
	var c := _ctl()
	var called := {"n": 0}
	Motion.vanish(c, func() -> void: called["n"] += 1, 0.2)
	await _frames(3)
	Motion.settle_in(c, 0.1)    # takes over modulate:a
	await _frames(30)
	t.eq(int(called["n"]), 0, "the interrupted fade-out never calls back")
	t.check(c.modulate.a > 0.99, "ends visible")
	c.queue_free()


func test_reduced_motion_keeps_state_feedback_only() -> void:
	var prev: Variant = Save.get_setting("reduced_motion", false)
	Save.set_setting("reduced_motion", true)
	var b := UIKit.primary("Ready")
	t.add_child(b)
	await _frames(2)
	var f := UIKit.face_of(b)
	b.button_down.emit()
	await _frames(1)
	t.eq(f.scale, Vector2.ONE, "no scale with Reduced Motion")
	t.eq(f.state(), "normal", "a signal alone isn't a real press (state follows the button)")
	var c := _ctl()
	Motion.appear(c, 12.0, 0.2)
	t.eq(c.position, Vector2.ZERO, "no rise with Reduced Motion")
	UIKit.set_selected(b, true)
	t.eq(f.glow, 0.0, "no selection sheen with Reduced Motion")
	t.eq(f.state(), "selected", "the selected state still shows at once")
	Save.set_setting("reduced_motion", prev)
	b.queue_free()
	c.queue_free()


func test_focus_ring_and_disabled_state_stay_readable() -> void:
	var b := UIKit.primary("Apply")
	t.add_child(b)
	await _frames(1)
	var ring := b.get_theme_stylebox("focus") as StyleBoxFlat
	t.check(ring != null and not ring.draw_center and ring.expand_margin_left >= 4.0, "focus is a ring outside the control")
	b.disabled = true
	var f := UIKit.face_of(b)
	t.eq(f.state(), "disabled", "disabled state")
	var dis := f.styles["disabled"] as StyleBoxFlat
	t.check(dis.bg_color.a > 0.95, "a disabled button stays solid, not faded")
	var fg: Color = f.color_for("disabled")
	var lum_bg := dis.bg_color.get_luminance()
	t.check(absf(fg.get_luminance() * fg.a + lum_bg * (1.0 - fg.a) - lum_bg) > 0.25, "disabled text keeps contrast")
	b.queue_free()


func test_tabular_digits() -> void:
	var f := UIKit.font_num(700)
	var w1 := f.get_string_size("1:11", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var w8 := f.get_string_size("8:88", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	t.check(absf(w1 - w8) < 0.5, "timer digits have equal widths (%.1f vs %.1f)" % [w1, w8])
	var p := UIKit.font_w(700)
	var pw1 := p.get_string_size("1:11", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var pw8 := p.get_string_size("8:88", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	t.check(absf(pw1 - pw8) > 1.0, "(the proportional face differs, so the feature is really on)")
