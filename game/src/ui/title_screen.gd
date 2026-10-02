class_name TitleScreen
extends Screen
## Home (V5): the dorm common room with the player's own runner as the focus.
##   upper left   the Ultimate Trifecta title graphic, modest
##   upper right  a compact profile chip (name, level, coins) and Settings
##   lower left   Wardrobe and Emote, always within reach
##   lower right  Play with Friends (the one gold action) and Practice
## Nothing else: no store, pass, news or empty tabs.  Game Center status is
## shown only where it matters (the Play with Friends sheet).

var _msg := ""
var play_btn: Button
var practice_btn: Button
var wardrobe_btn: Button
var emote_btn: Button
var title_art: TextureRect


func show_message(m: String) -> void:
	_msg = m
	if is_inside_tree() and m != "":
		dialog(m)


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_shades(self)
	var view := get_viewport().get_visible_rect().size

	# --- top: title (left), profile + settings (right)
	var top := UIKit.hbox(14)
	content.add_child(top)
	title_art = Brand.title(clampf(view.x * 0.27, 340.0, 470.0))
	title_art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(title_art)
	top.add_child(UIKit.spacer_h())
	top.add_child(profile_chip())
	var gear := UIKit.icon_button("gear")
	gear.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	gear.tooltip_text = "Settings"
	gear.accessibility_name = "Settings"
	gear.pressed.connect(func() -> void: App.goto(SettingsScreen))
	top.add_child(gear)

	content.add_child(UIKit.spacer_v())

	# --- bottom: wardrobe + emote (left), play + practice (right)
	var bottom := UIKit.hbox(14)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(bottom)
	wardrobe_btn = UIKit.icon_button("shirt", "Wardrobe")
	wardrobe_btn.pressed.connect(func() -> void: App.goto(CreatorScreen))
	wardrobe_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(wardrobe_btn)
	emote_btn = UIKit.icon_button("smile", "Emote")
	emote_btn.pressed.connect(func() -> void: emote_picker(emote_btn, _emote))
	emote_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(emote_btn)
	bottom.add_child(UIKit.spacer_h())
	var col := UIKit.vbox(12)
	col.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(col)
	var tut_done: bool = Save.data.get("tutorial_done", false)
	if not tut_done:
		var hint := UIKit.styled("New here? Practice starts with a short tutorial.", "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		col.add_child(hint)
	play_btn = UIKit.primary("Play with Friends", Vector2(400, 100), 31)
	play_btn.pressed.connect(func() -> void: App.goto(OnlineScreen))
	col.add_child(play_btn)
	practice_btn = UIKit.secondary("Practice", Vector2(400, 76))
	practice_btn.pressed.connect(func() -> void: App.goto(PracticeScreen))
	col.add_child(practice_btn)
	focus_first(play_btn)
	if _msg != "":
		call_deferred("dialog", _msg)
	elif App.stage and App.stage.local_character():
		# a quick hello wave when the home screen opens
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			if App.stage and is_instance_valid(App.stage) and is_inside_tree():
				App.stage.emote(Save.player_uid(), 0, 1.6))


func _emote(id: int) -> void:
	if App.stage and App.stage.emote(Save.player_uid(), id):
		Sfx.play("pop")


func _go_back() -> void:
	pass  # home is the root


## Name, level and coins in one compact chip (tap: Settings, Profile first).
func profile_chip() -> Button:
	var b := UIKit.card_button(Vector2(0, UIKit.touch_min()), Color(UIKit.SLATE, 0.92))
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var f := UIKit.face_of(b)
	var h := UIKit.hbox(14)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -18
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UIKit.styled(Save.player_name(), "label")
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.size_flags_vertical = Control.SIZE_FILL
	h.add_child(nm)
	var lv := UIKit.styled("Lv %d" % int(Save.data["level"]), "num", UIKit.TEAL)
	lv.add_theme_font_size_override("font_size", UIKit.T_CAPTION)
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.size_flags_vertical = Control.SIZE_FILL
	h.add_child(lv)
	var coins := UIKit.styled("%d ¢" % int(Save.data["coins"]), "num", UIKit.AMBER)
	coins.add_theme_font_size_override("font_size", UIKit.T_CAPTION)
	coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coins.size_flags_vertical = Control.SIZE_FILL
	h.add_child(coins)
	f.add_child(h)
	# the chip sizes itself to its content (names up to 16 characters)
	UIKit.fit_card(b, h, 36.0)
	b.accessibility_name = "%s, level %d, %d coins" % [Save.player_name(), int(Save.data["level"]), int(Save.data["coins"])]
	b.pressed.connect(func() -> void: App.goto(SettingsScreen))
	return b


## Soft gradients behind the title (upper left) and the actions (right),
## so text reads over the room without a slab.
static func add_shades(parent: Control, right: float = 0.5, top_left: float = 0.4) -> void:
	for spec in [[Vector2(1.0, 0.5), Vector2(0.0, 0.5), right, 0.5], [Vector2(0.0, 0.0), Vector2(0.55, 0.6), top_left, 0.0]]:
		var a: float = spec[2]
		if a <= 0.0:
			continue
		var g := Gradient.new()
		g.set_color(0, Color(UIKit.NAVY, a))
		g.set_color(1, Color(UIKit.NAVY, 0.0))
		g.add_point(float(spec[3]) * 0.5, Color(UIKit.NAVY, a * 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_LINEAR if spec[3] > 0.0 else GradientTexture2D.FILL_RADIAL
		t.fill_from = spec[0]
		t.fill_to = spec[1]
		t.width = 256
		t.height = 128
		var shade := TextureRect.new()
		shade.texture = t
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(shade)
		parent.move_child(shade, 0)


## V4 compatibility: the old gradient helper (results and online screens).
static func _side_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(UIKit.NAVY, 0.0))
	g.set_color(1, Color(UIKit.NAVY, 0.55))
	g.add_point(0.55, Color(UIKit.NAVY, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0.5)
	t.fill_to = Vector2(1, 0.5)
	t.width = 256
	t.height = 4
	return t
