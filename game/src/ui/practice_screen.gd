class_name PracticeScreen
extends Screen
## Solo practice: identical rules and controls; the other seven slots are
## clearly labelled bots.  Pick Runner, Night Watch or Random (stored only
## for practice - friend parties draw roles fairly).  The runner tutorial and
## the Night Watch training add coach tips.  One recommended option is the
## primary action.


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	var row := UIKit.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var back := UIKit.icon_button("back")
	back.tooltip_text = "Back"
	back.pressed.connect(_go_back)
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(back)
	row.add_child(UIKit.spacer_h())
	var sheet := UIKit.panel(Color(UIKit.SLATE, 0.96), UIKit.R_PANEL, 28)
	sheet.custom_minimum_size = Vector2(minf(580.0, get_viewport().get_visible_rect().size.x * 0.56), 0)
	sheet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sheet)
	var v := UIKit.vbox(14)
	sheet.add_child(v)
	v.add_child(UIKit.heading("Practice", 38))
	var note := UIKit.label("Same rules and controls. Everyone else is a bot (labelled BOT). Half rewards; stats kept separately.", 18, UIKit.IVORY_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var tut_done: bool = Save.data.get("tutorial_done", false)
	var watch_done: bool = Save.data.get("watch_training_done", false)
	var cfg := PartySeries.rules_for(Rules.cfg, PartySeries.DEFAULT_WATCH)
	var last := String(Save.get_setting("practice_role", "runner"))
	var opts := [
		["Runner tutorial", "Learn to run, jump, dive and splash. The Night Watch waits 30 s.", func() -> void: App.start_practice("runner", true), not tut_done],
		["Night Watch training", "A short guided chase: find a jogging runner, wait for Tag to light up, tag them, then try cutting one off with a cart.", func() -> void: App.start_practice("patrol", true), tut_done and not watch_done],
	]
	var pick := UIKit.hbox(10)
	var first: Button = null
	for i in opts.size():
		var o: Array = opts[i]
		var b := UIKit.primary(String(o[0]), Vector2(520, 80), 26) if bool(o[3]) else UIKit.secondary(String(o[0]), Vector2(520, 72), 24)
		b.pressed.connect(o[2])
		v.add_child(b)
		var d := UIKit.label(String(o[1]), 17, UIKit.IVORY_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(500, 0)
		v.add_child(d)
		if bool(o[3]) and first == null:
			first = b
	v.add_child(UIKit.label("Play a full round as", 20, UIKit.IVORY, true))
	var desc := UIKit.label("", 17, UIKit.IVORY_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(500, 0)
	for o in [["runner", "Runner", TC.runner_card(cfg)], ["patrol", "Night Watch", TC.patrol_card(cfg)],
			["random", "Random", "A coin flip decides, like a surprise draw. Your choice here only applies to practice."]]:
		var key: String = o[0]
		var b := UIKit.secondary(String(o[1]), Vector2(166, 76), 22) if key != last or first != null else UIKit.primary(String(o[1]), Vector2(166, 80), 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			Save.set_setting("practice_role", key)
			App.start_practice(key, false))
		var info := String(o[2])
		b.focus_entered.connect(func() -> void: desc.text = info)
		b.mouse_entered.connect(func() -> void: desc.text = info)
		pick.add_child(b)
		if key == last:
			desc.text = info
			if first == null:
				first = b
	v.add_child(pick)
	v.add_child(desc)
	focus_first(first)
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_SHEET)
