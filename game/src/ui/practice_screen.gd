class_name PracticeScreen
extends Screen
## Solo practice: identical rules and controls; the other seven slots are
## clearly labelled bots.  The tutorial adds coach tips and a longer head
## start.  One recommended option is the primary action.


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
	var opts := [
		["Tutorial run", "Learn to run, jump, dive and splash. The Night Watch waits 30 s.", func() -> void: App.start_practice("runner", true)],
		["As a Runner", TC.RUNNER_CARD, func() -> void: App.start_practice("runner", false)],
		["As the Night Watch", TC.PATROL_CARD, func() -> void: App.start_practice("patrol", false)],
	]
	var first: Button = null
	for i in opts.size():
		var o: Array = opts[i]
		var recommended := (i == 0 and not tut_done) or (i == 1 and tut_done)
		var b := UIKit.primary(String(o[0]), Vector2(520, 84), 28) if recommended else UIKit.secondary(String(o[0]), Vector2(520, 76), 24)
		b.pressed.connect(o[2])
		v.add_child(b)
		var d := UIKit.label(String(o[1]), 17, UIKit.IVORY_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(500, 0)
		v.add_child(d)
		if recommended:
			first = b
	focus_first(first)
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_SHEET)
