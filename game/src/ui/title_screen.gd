class_name TitleScreen
extends Screen
## Launch / main menu. No long intro: straight to play.

var _msg := ""


func show_message(m: String) -> void:
	_msg = m
	if is_inside_tree() and m != "":
		dialog(m)


func build() -> void:
	var row := UIKit.hbox(40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var left := UIKit.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)
	var logo := LogoText.new()
	logo.custom_minimum_size = Vector2(620, 220)
	left.add_child(logo)
	left.add_child(UIKit.outlined(UIKit.label("Moonbrook College  ·  3:00 a.m.", 28, UIKit.MUTED, true), 8))
	var badge := UIKit.hbox(16)
	badge.add_child(UIKit.outlined(UIKit.label("Level %d" % int(Save.data["level"]), 26, UIKit.ACCENT, true), 8))
	badge.add_child(UIKit.outlined(UIKit.label("%d coins" % int(Save.data["coins"]), 26, UIKit.ACCENT, true), 8))
	badge.add_child(UIKit.outlined(UIKit.label(Save.player_name(), 26, UIKit.TEXT, false), 8))
	left.add_child(badge)
	var gc := UIKit.outlined(UIKit.label(Social.status_text(), 20, UIKit.MUTED), 6)
	gc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gc.custom_minimum_size = Vector2(560, 0)
	left.add_child(gc)
	Social.auth_changed.connect(func(_ok: bool) -> void:
		if is_instance_valid(gc):
			gc.text = Social.status_text())

	var menu := UIKit.vbox(14)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(menu)
	var tut_done: bool = Save.data.get("tutorial_done", false)
	var play := UIKit.button("Play with Friends", Color(1.0, 0.72, 0.25), Vector2(380, 84), 32)
	play.pressed.connect(func() -> void: App.goto(OnlineScreen))
	menu.add_child(play)
	var prac := UIKit.button("Practice" if tut_done else "Practice  (start here!)", Color(0.35, 0.75, 0.95), Vector2(380, 76))
	prac.pressed.connect(func() -> void: App.goto(PracticeScreen))
	menu.add_child(prac)
	var ward := UIKit.button("Wardrobe", Color(0.75, 0.5, 0.95), Vector2(380, 70))
	ward.pressed.connect(func() -> void: App.goto(WardrobeScreen))
	menu.add_child(ward)
	var how := UIKit.button("How to Play", Color(0.3, 0.38, 0.7), Vector2(380, 64))
	how.pressed.connect(func() -> void: App.goto(HowToScreen))
	menu.add_child(how)
	var set_b := UIKit.button("Settings", Color(0.3, 0.38, 0.7), Vector2(380, 64))
	set_b.pressed.connect(func() -> void: App.goto(SettingsScreen))
	menu.add_child(set_b)
	focus_first(play if tut_done else prac)
	if _msg != "":
		call_deferred("dialog", _msg)


func _go_back() -> void:
	pass  # title is the root


class LogoText:
	extends Control
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var f := UIKit.font(true)
		var lines := ["ULTIMATE", "TRIFECTA"]
		var sizes := [92, 112]
		var y := 96.0
		for i in 2:
			var txt: String = lines[i]
			var fs: int = sizes[i]
			var x := 0.0
			for ci in txt.length():
				var ch := txt[ci]
				var wob := sin(t * 2.2 + float(ci) * 0.6) * 4.0
				var col := Color(1.0, 0.82, 0.3) if i == 0 else Color(0.45, 0.88, 1.0)
				if i == 1 and ci % 3 == 0:
					col = Color(1.0, 0.55, 0.7)
				draw_string_outline(f, Vector2(x, y + wob), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, Color(0.05, 0.06, 0.18))
				draw_string(f, Vector2(x, y + wob), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0
			y += float(fs) * 0.95
		# three splash drops
		for k in 3:
			var dc := Vector2(470 + k * 44, 30 + sin(t * 3.0 + k) * 6.0)
			Icons.draw_shape(self, "drop", dc, 16, [Color(1.0, 0.82, 0.3), Color(0.45, 1.0, 0.5), Color(0.3, 0.85, 1.0)][k])

