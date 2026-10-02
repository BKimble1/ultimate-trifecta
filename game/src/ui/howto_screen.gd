class_name HowToScreen
extends Screen


## Rules and controls on one readable sheet over the dorm; "Got it" sits in
## the header so it is reachable without scrolling.
func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	var h := header("How to Play")
	h.add_child(UIKit.spacer_h())
	var done := UIKit.primary("Got it", Vector2(220, maxf(72.0, UIKit.touch_min())), 26)
	done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(func() -> void: App.goto_title())
	h.add_child(done)
	focus_first(done)
	var sc := UIKit.scroll_area()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	content.add_child(sc)
	var body := UIKit.panel(Color(UIKit.SLATE, 0.96), UIKit.R_PANEL, 26)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var v := UIKit.vbox(16)
	body.add_child(v)
	var cards := UIKit.hbox(20)
	var cfg := PartySeries.rules_for(Rules.cfg, PartySeries.DEFAULT_WATCH)
	for c in [["RUNNERS", TC.runner_card(cfg), UIKit.RUNNER], ["NIGHT WATCH", TC.patrol_card(cfg), UIKit.PATROL]]:
		var p := UIKit.panel(Color(UIKit.NAVY, 0.6), UIKit.R_SMALL, 18)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pv := UIKit.vbox(8)
		pv.add_child(UIKit.label(String(c[0]), 26, c[2], true))
		var l := UIKit.label(String(c[1]), 21)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(360, 0)
		pv.add_child(l)
		p.add_child(pv)
		cards.add_child(p)
	v.add_child(cards)
	var mins := int(cfg.match_duration_s) / 60
	var secs := int(cfg.match_duration_s) % 60
	var needs: Array[String] = []
	for w in PartySeries.WATCH_CHOICES:
		var r := PartySeries.runners(w)
		needs.append("%d Night Watch: %d of %d runners" % [w, PartySeries.required_home(w), r])
	var rules := [
		"Every runner gets the same three marked splash spots (glowing beams). Visit them in any order — jump or dive in to earn a stamp.",
		"After three splashes, run home through any of Puddlesworth Hall's four doors.",
		"Get enough runners home before the %d:%02d clock runs out and every runner wins; otherwise the Night Watch wins. How many depends on the party: %s." % [mins, secs, "; ".join(needs)],
		"Caught? You keep every splash and stay a runner. After %d seconds you're back near your last splash (or the dorm before your first), protected for %d seconds." % [int(cfg.capture_penalty_s), int(cfg.respawn_protect_s)],
		"Night Watch: a ring marks the runner you'd tag; Tag lights up when a press would land. Pressing early just misses and needs a moment to recover.",
		"Carts are fast on roads but can't climb stairs, pass bollards or enter the woods, gardens, pool deck or quad. Hop out to tag. A cart bump only makes runners stumble.",
		"A splash marks that spot for the Night Watch for %d seconds — not the runner. Break line of sight behind buildings to lose a chaser." % int(cfg.splash_marker_s),
		"Gadgets (one at a time): Turbo Sneakers (short speed burst), Squeaky Decoy (fake footsteps), Splash Bomb (briefly slows a cart).",
		"Friend parties play a series of 1, 3 or 5 rounds; roles are drawn fairly each round. Solo practice lets you pick Runner or Night Watch.",
	]
	for r in rules:
		var l2 := UIKit.label("•  " + r, 20)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l2)
	v.add_child(UIKit.label("Controls", 26, UIKit.TEAL, true))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for row in [["Action", "Touch", "Controller", "Keyboard (desktop)"],
		["Move", "Left thumb: stick appears where you touch (or fixed, in Settings)", "Left stick", "WASD"],
		["Camera", "Drag anywhere that isn't a button", "Right stick", "Right-mouse drag / IJKL"],
		["Jump / Dive", "Jump (it becomes Dive in the air)", "A / Cross", "Space"],
		["Sprint", "Push the stick to its edge (or hold Sprint, in Settings)", "Hold LB or RB", "Shift"],
		["Gadget", "Gadget button (when holding one)", "B / Circle", "Q"],
		["Tag (Night Watch)", "Tag button", "X / Square", "F"],
		["Cart in/out", "Drive near a cart; small Exit while driving", "Y / Triangle", "E"],
		["Drive", "Stick steers, Gas / Brake on the right", "RT gas, LT brake, left stick steer", "W/S + A/D"]]:
		for cell in row:
			var gl := UIKit.label(String(cell), 18, UIKit.IVORY if row[0] != "Action" else UIKit.TEAL, row[0] == "Action")
			gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gl.custom_minimum_size = Vector2(180, 0)
			gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(gl)
	v.add_child(grid)
