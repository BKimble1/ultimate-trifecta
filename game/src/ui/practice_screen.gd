class_name PracticeScreen
extends Screen
## Solo practice: identical rules and controls, the other seven slots are
## clearly labelled bots. The tutorial adds coach tips and a longer head start.


func build() -> void:
	header("Practice")
	var note := UIKit.label("Same rules, same controls. All other players are bots (labelled BOT). Practice rewards are reduced and recorded separately from online stats.", 24, UIKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	var row := UIKit.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var cards := [
		["Tutorial Run", "Learn to run, jump, dive and splash. The Night Watch waits 30 seconds before chasing.", Color(0.45, 0.9, 0.6), func() -> void: App.start_practice("runner", true)],
		["Practice as Runner", TC.RUNNER_CARD, UIKit.RUNNER, func() -> void: App.start_practice("runner", false)],
		["Practice as Night Watch", TC.PATROL_CARD, UIKit.PATROL, func() -> void: App.start_practice("patrol", false)],
	]
	var first: Button = null
	for c in cards:
		var p := UIKit.panel(Color(0.12, 0.15, 0.32, 0.92), 26, 20)
		p.custom_minimum_size = Vector2(340, 330)
		var v := UIKit.vbox(12)
		v.add_child(UIKit.label(String(c[0]), 30, c[2], true))
		var d := UIKit.label(String(c[1]), 22, UIKit.TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 150)
		v.add_child(d)
		var b := UIKit.button("Start", c[2], Vector2(300, 70))
		b.pressed.connect(c[3])
		v.add_child(b)
		p.add_child(v)
		row.add_child(p)
		if first == null:
			first = b
	focus_first(first)
