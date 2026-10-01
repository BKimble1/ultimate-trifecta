class_name TitleScreen
extends Screen
## Home: the player's character in the dorm (3D stage behind the UI, front
## three-quarter), a compact wordmark, one primary action ("Play with
## Friends"), a quiet Practice, a small Outfit control, a compact profile
## chip and Settings.  Game Center status is shown only where it matters
## (the Play with Friends sheet).

var _msg := ""


func show_message(m: String) -> void:
	_msg = m
	if is_inside_tree() and m != "":
		dialog(m)


func build() -> void:
	if App.stage:
		App.stage.set_mode("home", false)
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# soft vignette on the right so the menu reads over the room
	var shade := TextureRect.new()
	shade.texture = _side_gradient()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 0)

	var top := UIKit.hbox(16)
	content.add_child(top)
	var mark := Wordmark.new()
	mark.custom_minimum_size = Vector2(330, 112)
	top.add_child(mark)
	top.add_child(UIKit.spacer_h())
	var prof := UIKit.panel(Color(UIKit.SLATE, 0.86), 999, 18)
	var pv := UIKit.hbox(14)
	var nm := UIKit.label(Save.player_name(), 22, UIKit.IVORY, true)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(200, 0)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.add_child(nm)
	var lv := UIKit.label("Lv %d" % int(Save.data["level"]), 20, UIKit.TEAL, true)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.add_child(lv)
	var coins := UIKit.label("%d ¢" % int(Save.data["coins"]), 20, UIKit.AMBER, true)
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.add_child(coins)
	prof.add_child(pv)
	prof.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(prof)
	var gear := UIKit.icon_button("gear")
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.tooltip_text = "Settings"
	gear.pressed.connect(func() -> void: App.goto(SettingsScreen))
	top.add_child(gear)

	content.add_child(UIKit.spacer_v())
	var bottom := UIKit.hbox(16)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(bottom)
	var outfit := UIKit.icon_button("shirt", "Outfit")
	outfit.pressed.connect(func() -> void: App.goto(WardrobeScreen))
	outfit.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(outfit)
	bottom.add_child(UIKit.spacer_h())
	var col := UIKit.vbox(14)
	col.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(col)
	var play := UIKit.primary("Play with Friends", Vector2(400, 104), 34)
	play.pressed.connect(func() -> void: App.goto(OnlineScreen))
	col.add_child(play)
	var tut_done: bool = Save.data.get("tutorial_done", false)
	var prac := UIKit.quiet("Practice", Vector2(400, 80), 26)
	prac.pressed.connect(func() -> void: App.goto(PracticeScreen))
	col.add_child(prac)
	if not tut_done:
		var hint := UIKit.label("New here? Practice starts with a short tutorial.", 18, UIKit.IVORY_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		col.add_child(hint)
	focus_first(play)
	if _msg != "":
		call_deferred("dialog", _msg)
	elif App.stage and App.stage.local_character():
		# a quick hello wave when the home screen opens
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			if App.stage and is_instance_valid(App.stage):
				App.stage.emote(Save.player_uid(), 0, 1.6))


func _go_back() -> void:
	pass  # home is the root


static func _side_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(UIKit.NAVY, 0.0))
	g.set_color(1, Color(UIKit.NAVY, 0.62))
	g.add_point(0.55, Color(UIKit.NAVY, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0.5)
	t.fill_to = Vector2(1, 0.5)
	t.width = 256
	t.height = 4
	return t


## Compact two-line wordmark, static (no wobble), with three splash drops.
class Wordmark:
	extends Control

	func _draw() -> void:
		var f := UIKit.font_w(700)
		draw_string_outline(f, Vector2(0, 46), "ULTIMATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, 10, UIKit.NAVY)
		draw_string(f, Vector2(0, 46), "ULTIMATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, UIKit.AMBER)
		draw_string_outline(f, Vector2(0, 102), "TRIFECTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, 12, UIKit.NAVY)
		draw_string(f, Vector2(0, 102), "TRIFECTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, UIKit.IVORY)
		var w := f.get_string_size("ULTIMATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		for k in 3:
			Icons.draw_shape(self, "drop", Vector2(w + 22 + k * 24, 26), 10, [UIKit.AMBER, UIKit.TEAL, UIKit.IVORY][k])
