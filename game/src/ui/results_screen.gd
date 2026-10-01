class_name ResultsScreen
extends Screen
## Team outcome first, then individual splash/finish contribution, Fastest
## Trifecta where applicable, and clearly earned cosmetic rewards.

var results: Dictionary
var reward: Dictionary
var session: NetSession


func build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.18, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)
	var oc := int(results.get("outcome", 0))
	var my_slot := session.local_slot if session else -1
	var my_role := -1
	for r in results.get("players", []):
		if int(r["slot"]) == my_slot:
			my_role = int(r["role"])
	var won := (oc == TC.Outcome.RUNNERS_WIN and my_role == TC.Role.RUNNER) or (oc == TC.Outcome.PATROL_WIN and my_role == TC.Role.PATROL)
	var title := "RUNNERS WIN!" if oc == TC.Outcome.RUNNERS_WIN else ("NIGHT WATCH WINS!" if oc == TC.Outcome.PATROL_WIN else "ROUND CANCELLED")
	var t := UIKit.outlined(UIKit.label(title, 64, UIKit.RUNNER if oc == TC.Outcome.RUNNERS_WIN else UIKit.PATROL, true, HORIZONTAL_ALIGNMENT_CENTER), 14)
	content.add_child(t)
	var sub := "%d of %d runners made it home" % [int(results.get("finished", 0)), int(results.get("needed", 4))]
	if oc == TC.Outcome.RUNNERS_WIN:
		sub += " in %d:%02d" % [int(results.get("round_time", 0)) / 60, int(results.get("round_time", 0)) % 60]
	content.add_child(UIKit.label(sub + ("  —  your team won!" if won else ""), 28, UIKit.TEXT, false, HORIZONTAL_ALIGNMENT_CENTER))
	var fastest := int(results.get("fastest_slot", -1))
	if fastest >= 0:
		for r in results.get("players", []):
			if int(r["slot"]) == fastest:
				var ftime := float(results.get("fastest_time", r.get("finish_time", 0.0)))
				content.add_child(UIKit.label("★ Fastest Trifecta: %s  (%d:%02d)" % [String(r["name"]), int(ftime) / 60, int(ftime) % 60], 22, UIKit.ACCENT, true, HORIZONTAL_ALIGNMENT_CENTER))
	var row := UIKit.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	# players table
	var tp := UIKit.panel(Color(0.12, 0.15, 0.32, 0.92), 24, 16)
	tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	for h in ["Player", "Role", "Contribution"]:
		grid.add_child(UIKit.label(h, 18, UIKit.ACCENT, true))
	var rows: Array = results.get("players", []).duplicate()
	rows.sort_custom(func(a, b): return [int(a["role"]), -int(a.get("stamps", 0)) - (10 if bool(a.get("finished", false)) else 0)] < [int(b["role"]), -int(b.get("stamps", 0)) - (10 if bool(b.get("finished", false)) else 0)])
	for r in rows:
		var me := int(r["slot"]) == my_slot
		var col := UIKit.ACCENT if me else UIKit.TEXT
		var star := "★ " if int(r["slot"]) == fastest else ""
		grid.add_child(UIKit.label(star + String(r["name"]) + (" [BOT]" if bool(r["is_bot"]) else "") + (" (you)" if me else ""), 19, col, me))
		grid.add_child(UIKit.label("Runner" if int(r["role"]) == TC.Role.RUNNER else "Night Watch", 19, UIKit.RUNNER if int(r["role"]) == TC.Role.RUNNER else UIKit.PATROL))
		var contrib := ""
		if int(r["role"]) == TC.Role.RUNNER:
			contrib = "%d/3 splashes" % int(r.get("stamps", 0))
			if bool(r.get("finished", false)):
				var ft := float(r.get("finish_time", 0.0))
				contrib += " · home #%d at %d:%02d" % [int(r.get("finish_order", 0)), int(ft) / 60, int(ft) % 60]
			if int(r.get("times_captured", 0)) > 0:
				contrib += " · caught %dx" % int(r["times_captured"])
		else:
			contrib = "%d different runner%s caught" % [int(r.get("unique_captures", 0)), "" if int(r.get("unique_captures", 0)) == 1 else "s"]
		grid.add_child(UIKit.label(contrib, 19, col))
	tp.add_child(grid)
	row.add_child(tp)
	# rewards
	var rp := UIKit.panel(Color(0.14, 0.2, 0.38, 0.95), 24, 18)
	rp.custom_minimum_size = Vector2(280, 0)
	var rv := UIKit.vbox(6)
	rv.add_child(UIKit.label("Rewards", 26, UIKit.ACCENT, true))
	if reward.is_empty():
		rv.add_child(UIKit.label("No rewards for this round.", 22, UIKit.MUTED))
	else:
		for line in reward.get("lines", []):
			rv.add_child(UIKit.label("%s   +%d" % [line[0], int(line[1])] if int(line[1]) >= 0 else "%s   %d" % [line[0], int(line[1])], 19))
		rv.add_child(UIKit.label("+%d coins" % int(reward.get("coins", 0)), 30, UIKit.ACCENT, true))
		if bool(reward.get("level_up", false)):
			rv.add_child(UIKit.label("LEVEL UP! Now level %d" % int(reward.get("level", 1)), 26, UIKit.GOOD, true))
		rv.add_child(UIKit.label("Coins buy outfits in the Wardrobe.", 18, UIKit.MUTED))
	if bool(results.get("practice", false)):
		rv.add_child(UIKit.label("Practice round (with bots).", 18, UIKit.MUTED))
	rp.add_child(rv)
	row.add_child(rp)
	var btns := UIKit.hbox(18)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var practice := session != null and session.mode == NetSession.Mode.OFFLINE
	var again := UIKit.button("Play again" if practice else "Rematch", Color(1.0, 0.72, 0.25), Vector2(300, 74))
	again.pressed.connect(func() -> void: App.rematch())
	btns.add_child(again)
	var leave := UIKit.button("Leave" if not practice else "Menu", Color(0.3, 0.38, 0.7), Vector2(220, 74))
	leave.pressed.connect(func() -> void:
		if practice:
			App.goto_title()
		else:
			App.leave_room())
	btns.add_child(leave)
	content.add_child(btns)
	focus_first(again)
	Sfx.play("cheer" if won else "pop")


func _go_back() -> void:
	if session == null or session.mode == NetSession.Mode.OFFLINE:
		App.goto_title()
	else:
		App.leave_room()
