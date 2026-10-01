class_name HowToScreen
extends Screen


func build() -> void:
	header("How to Play")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	content.add_child(sc)
	var v := UIKit.vbox(16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var cards := UIKit.hbox(20)
	for c in [["RUNNERS (6)", TC.RUNNER_CARD, UIKit.RUNNER], ["NIGHT WATCH (2)", TC.PATROL_CARD, UIKit.PATROL]]:
		var p := UIKit.panel(Color(0.12, 0.15, 0.32, 0.92), 24, 18)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pv := UIKit.vbox(8)
		pv.add_child(UIKit.label(String(c[0]), 30, c[2], true))
		var l := UIKit.label(String(c[1]), 24)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
		pv.add_child(l)
		p.add_child(pv)
		cards.add_child(p)
	v.add_child(cards)
	var rules := [
		"Every runner gets the same three marked splash spots (glowing beams). Visit them in any order — jump or dive in to earn a stamp.",
		"After three splashes, run home through any of Puddlesworth Hall's four doors.",
		"4 runners home before the 4:00 clock runs out = runners win. Otherwise the Night Watch wins.",
		"Caught? Wait 6 seconds, then pop back near your last splash (or the dorm). You keep every splash.",
		"Night Watch: carts are fast on roads but can't climb stairs, pass bollards or enter the woods, gardens, pool deck or quad. Hop out to tag. A cart bump only makes runners stumble.",
		"A splash marks that spot for the Night Watch for 3 seconds — not the runner. Break line of sight behind buildings to lose a chaser.",
		"Gadgets (one at a time): Turbo Sneakers (short speed burst), Squeaky Decoy (fake footsteps), Splash Bomb (briefly slows a cart).",
	]
	for r in rules:
		var l2 := UIKit.label("•  " + r, 22)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l2)
	v.add_child(UIKit.label("Controls", 30, UIKit.ACCENT, true))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for row in [["Action", "Touch", "Controller", "Keyboard (desktop)"],
		["Move", "Left thumb stick (anywhere left)", "Left stick", "WASD"],
		["Camera", "Drag on the right", "Right stick", "Right-mouse drag / IJKL"],
		["Jump / Dive", "Jump button (again in the air = dive)", "A / Cross", "Space"],
		["Sprint", "Push the stick to its outer ring", "Hold LB or RB", "Shift"],
		["Gadget", "Gadget button (when holding one)", "B / Circle", "Q"],
		["Tag (Night Watch)", "TAG button", "X / Square", "F"],
		["Cart in/out", "Drive / Hop out button", "Y / Triangle", "E"],
		["Drive", "Steer stick + GAS / BRAKE", "RT gas, LT brake, left stick steer", "W/S + A/D"]]:
		for cell in row:
			grid.add_child(UIKit.label(String(cell), 20, UIKit.TEXT if row[0] != "Action" else UIKit.ACCENT, row[0] == "Action"))
	v.add_child(grid)
	var done := UIKit.button("Got it", Color(0.35, 0.75, 0.95))
	done.pressed.connect(func() -> void: App.goto_title())
	v.add_child(done)
	focus_first(done)
