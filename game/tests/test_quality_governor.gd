extends RefCounted
## V6: the render-scale governor steps down after a sustained slow pace (not
## for one hitch), never faster than its cooldown, steps back up only after a
## long steady stretch, backs off when a step up doesn't hold, and restores
## the preset's scale when the round ends.
var t


func _gov(preset: int) -> QualityGovernor:
	var saved: Variant = Save.get_setting("quality", 1)
	Save.set_setting("quality", preset)
	var g := QualityGovernor.new()
	t.add_child(g)
	Save.set_setting("quality", saved)
	g.set_process(false)       # driven by feed() here
	g.target_ms = 16.7
	g._thermal = 0
	return g


func _run(g: QualityGovernor, ms: float, seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in n:
		g.feed(ms, 1.0 / 60.0)


func test_one_hitch_changes_nothing_a_sustained_slowdown_steps_down() -> void:
	var root: Window = t.get_tree().root
	var saved_scale: float = root.scaling_3d_scale
	var g := _gov(1)
	_run(g, 16.7, 4.0)
	g.feed(250.0, 0.25)                  # one stall
	_run(g, 16.7, 3.0)
	t.eq(g.level, 0, "a single stall doesn't lower the render scale")
	_run(g, 24.0, 3.5)                   # sustained 41 fps
	t.eq(g.level, 1, "a sustained slow pace steps down once")
	t.near(root.scaling_3d_scale, 0.9, 0.001, "to 0.9")
	_run(g, 24.0, 2.0)
	t.eq(g.level, 1, "not again before the cooldown")
	_run(g, 24.0, 4.0)
	t.eq(g.level, 2, "then one more step")
	g.queue_free()
	await t.get_tree().process_frame
	t.near(root.scaling_3d_scale, 1.0, 0.001, "the preset's scale comes back when the round ends")
	root.scaling_3d_scale = saved_scale


func test_steps_up_only_after_a_steady_stretch_with_backoff() -> void:
	var root: Window = t.get_tree().root
	var saved_scale: float = root.scaling_3d_scale
	var g := _gov(1)
	_run(g, 16.7, 3.5)
	_run(g, 26.0, 3.5)
	t.eq(g.level, 1, "stepped down")
	_run(g, 16.7, 15.0)
	t.eq(g.level, 1, "15 s at budget is not enough to step up")
	_run(g, 16.7, 8.0)
	t.eq(g.level, 0, "after the steady stretch it steps back up")
	var wait0 := g._up_wait
	_run(g, 26.0, 6.0)                   # the step up didn't hold
	t.eq(g.level, 1, "slow again: down")
	t.check(g._up_wait > wait0, "and it waits longer before the next try (%.0f s)" % g._up_wait)
	g.queue_free()
	await t.get_tree().process_frame
	root.scaling_3d_scale = saved_scale


func test_battery_saver_floor_and_thermal() -> void:
	var root: Window = t.get_tree().root
	var saved_scale: float = root.scaling_3d_scale
	var g := _gov(0)
	g.target_ms = 33.3
	_run(g, 33.3, 3.5)
	g._thermal = 2                       # iOS "serious"
	_run(g, 33.3, 1.0)
	t.eq(g.level, 1, "serious thermal state steps down even at pace")
	g._thermal = 0
	_run(g, 60.0, 40.0)
	t.near(g.scale(), 0.65, 0.001, "Battery Saver never goes below its floor")
	g.queue_free()
	await t.get_tree().process_frame
	root.scaling_3d_scale = saved_scale
