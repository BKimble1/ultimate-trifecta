class_name ChampionPromo
extends RefCounted
## The Season Champion prize (2.2): whoever finishes the season #1 in Season
## Points designs the next season's tier 100 skin (their concept and name,
## made into the game by the developer).
##
##   popup    a poster over Home, at most once every PROMO_EVERY_S (X to
##            close), with View Rankings and Official Rules
##   banner   the same poster, smaller, at the top of the Rankings screen
##   rules    the Official Rules sheet (App Store Review Guideline 5.3:
##            sponsored by the developer, Apple not involved, free to enter)
## The poster is drawn (no image files): a deep night gradient, slowly
## turning light rays behind a gold trophy, falling confetti, the "your
## skin here" card.  Reduced Motion: still.

const PROMO_EVERY_S := 20 * 3600
const HEAD := "DESIGN NEXT SEASON'S SKIN"
const BODY := "Finish the season #1 in Season Points and your idea becomes the tier 100 skin of next season's Season Pass: your concept, your name, in the game."
const SHORT := "Finish #1 in Season Points to design next season's tier 100 skin."


## Shows the popup when it's due (once per PROMO_EVERY_S, never during
## automation or before onboarding).  Returns true if shown.
static func maybe_show(screen: Screen, force: bool = false) -> bool:
	if not force:
		if App.dev_automation or not bool(Save.data.get("onboarded", false)):
			return false
		var seen := int(Save.get_setting("promo_seen_at", 0))
		if Rankings.now() - seen < PROMO_EVERY_S:
			return false
	Save.set_setting("promo_seen_at", Rankings.now())
	popup(screen)
	return true


## (2.3) On arriving home: wait until the launch curtain has gone and home
## has been on screen a moment, then maybe show the poster (it used to
## appear under the fading Idlery logo, before home was ever seen).
static func show_when_settled(screen: Screen) -> void:
	var tree := screen.get_tree()
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(screen) and screen.is_inside_tree() and BootCurtain.live > 0 and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame
	if not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	await tree.create_timer(SETTLE_S).timeout
	if not is_instance_valid(screen) or not screen.is_inside_tree() or App.screen != screen or screen.has_modal():
		return
	maybe_show(screen)


const SETTLE_S := 0.9


static func popup(screen: Screen) -> Control:
	var root := Control.new()
	root.name = "ChampionPromo"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vis := screen.get_viewport().get_visible_rect().size
	var poster := Poster.new()
	poster.big = true
	var w := minf(vis.x * 0.86, 1180.0)
	var h := minf(vis.y * 0.84, w * 0.56)
	poster.custom_minimum_size = Vector2(w, h)
	poster.size = Vector2(w, h)
	poster.position = (vis - Vector2(w, h)) * 0.5
	root.add_child(poster)
	var close := func() -> void:
		if is_instance_valid(root):
			Motion.vanish(root, root.queue_free, 0.15)
	_fill(poster, screen, close, true)
	screen.add_child(root)
	if not UIKit.reduced_motion():
		poster.pivot_offset = poster.size * 0.5
		poster.scale = Vector2.ONE * 0.86
		poster.modulate.a = 0.0
		var tw := poster.create_tween().set_parallel(true)
		tw.tween_property(poster, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(poster, "modulate:a", 1.0, 0.18)
	screen.push_modal(root, close)
	Sfx.play("pickup")
	return root


## The small poster for the Rankings screen.
static func banner(screen: Screen) -> Control:
	var poster := Poster.new()
	poster.custom_minimum_size = Vector2(380, 230)
	_fill(poster, screen, Callable(), false)
	# (2.3) tap the banner for the full poster
	poster.gui_input.connect(func(ev: InputEvent) -> void:
		var tap := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
		if tap and is_instance_valid(screen) and not screen.has_modal():
			popup(screen))
	return poster


static func _fill(poster: Poster, screen: Screen, close: Callable, big: bool) -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 30 if big else 18
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	poster.add_child(m)
	var v := UIKit.vbox(8 if big else 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top := UIKit.hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the small banner: "SEASON 1 · CHAMPION PRIZE" (the full name doesn't fit)
	var sname := Rankings.season_name(Rankings.contest_period())
	var ov := UIKit.chip("%s · CHAMPION PRIZE" % (sname if big else sname.get_slice(" · ", 0)).to_upper(), UIKit.AMBER, UIKit.NAVY, UIKit.T_OVERLINE + (3 if big else 0))
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(ov)
	top.add_child(UIKit.spacer_h())
	if close.is_valid():
		var x := UIKit.icon_button("close")
		x.accessibility_name = "Close"
		x.pressed.connect(close)
		top.add_child(x)
	v.add_child(top)
	# the words keep to the left; the art has the right
	var text_w := poster.custom_minimum_size.x * (0.46 if big else 0.64)
	var title := UIKit.outlined(UIKit.label(HEAD, 50 if big else 24, UIKit.AMBER_HI, true), 10 if big else 6)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = text_w
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(title)
	if big:
		# (2.3) the small banner keeps just the headline: the poster explains
		var body := UIKit.label(BODY, 24, UIKit.IVORY, false)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = text_w
		body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(body)
	v.add_child(UIKit.spacer_v())
	var row := UIKit.hbox(12)
	var ends := UIKit.chip(_when(), Color(UIKit.NAVY, 0.75), UIKit.IVORY, UIKit.T_LABEL if big else UIKit.T_CAPTION)
	ends.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ends.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ends)
	if big:
		var go := UIKit.primary("View Rankings", Vector2(300, 84), 28)
		go.pressed.connect(func() -> void:
			close.call()
			App.goto(RankingsScreen))
		row.add_child(go)
		UIKit.soft_focus.call_deferred(go)
	var rules := UIKit.quiet("Official rules", Vector2(0, UIKit.touch_min()), UIKit.T_LABEL if big else UIKit.T_CAPTION)
	rules.pressed.connect(func() -> void: open_rules(screen))
	row.add_child(rules)
	v.add_child(row)
	poster.accessibility_name = "%s champion prize. %s %s %s." % [Rankings.season_name(Rankings.contest_period()), HEAD.capitalize(), BODY, _when()]


## "Ends in 12d 4h", or in the preseason "Starts in 14d 23h".
static func _when() -> String:
	if Rankings.boards_open():
		return "Ends in %s" % Rankings.time_left_text()
	return "Starts in %s" % Rankings.time_to_start_text()


static func open_rules(screen: Screen) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vis := screen.get_viewport().get_visible_rect().size
	var p := UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 24)
	p.position = vis * 0.06
	p.size = vis * 0.88
	p.custom_minimum_size = vis * 0.88
	var v := UIKit.vbox(10)
	p.add_child(v)
	var close := func() -> void:
		if is_instance_valid(root):
			root.queue_free()
	var head := UIKit.hbox(10)
	head.add_child(UIKit.styled("Season Champion · Official Rules", "headline"))
	head.add_child(UIKit.spacer_h())
	var done := UIKit.secondary("Close", Vector2(180, UIKit.touch_min()))
	done.pressed.connect(close)
	head.add_child(done)
	v.add_child(head)
	var sc := UIKit.scroll_area()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var t := UIKit.label(rules_text(), UIKit.T_CAPTION + 1, UIKit.IVORY)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = vis.x * 0.8
	sc.add_child(t)
	root.add_child(p)
	screen.add_child(root)
	screen.push_modal(root, close)
	UIKit.soft_focus.call_deferred(done)


## The rules as shown in the game (docs/release22/CONTEST_RULES.md keeps the
## same text for the owner's review).
static func rules_text() -> String:
	var b := Rankings.period_bounds(Rankings.contest_period())
	var s := Time.get_date_string_from_unix_time(b[0])
	var e := Time.get_date_string_from_unix_time(b[1] - 1)
	return "\n\n".join(PackedStringArray([
		"1. Sponsor. This contest is run by Idlery Games, the developer of Ultimate Trifecta. Apple is not a sponsor of, and is not involved in, this contest in any way.",
		"2. No purchase necessary. Entry is free: you take part by playing online rounds. Buying anything in the game does not improve your chances.",
		"3. Season. %s runs from %s 00:00 UTC to %s 23:59 UTC (30 days). Each season is a separate contest." % [Rankings.season_name(Rankings.contest_period()), s, e],
		"4. How the winner is decided. The player at #1 on the Season Points leaderboard in Game Center when the season ends. Season Points come only from online rounds with at least one other real player (Rankings explains how points are earned). Before announcing a winner, the developer reviews the top scores and removes any it reasonably believes were cheated, made with a modified game, or earned against these rules; the next eligible player then moves up.",
		"5. Eligibility. Open to players with a Game Center account who are 13 or older (younger players need a parent or guardian's permission). Employees of the developer and their households can't win. Void where prohibited by law.",
		"6. The prize. The winner may send the developer a concept (a drawing, a description or both) and a name for a cosmetic outfit. The developer will make an outfit inspired by it, as the tier 100 reward of a following season's Season Pass, adapting it to the game's style and content rules (it must be suitable for all ages and must not copy anyone else's work, brand or likeness). The prize has no cash value, can't be transferred and can't be exchanged. The outfit is cosmetic only.",
		"7. Contact. The developer announces the winner's Game Center name in the game and on its support page; the winner contacts the developer through the support page within 14 days, or the next eligible player is chosen.",
		"8. Rights. By sending a concept the winner confirms it is their own original work and allows the developer to use, adapt and publish it in the game and its promotion, with credit to the winner's chosen name.",
		"9. General. The developer may cancel or change the contest if it can't run as planned (for example because of cheating or a technical failure), and will say so in the game. Questions: the support page in Settings.",
	]))


## The poster's painting: gradient, rays, trophy, confetti, the skin card.
class Poster:
	extends Control
	var big := false
	var t := 0.0
	var confetti: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in (40 if big else 22):
			confetti.append({"x": rng.randf_range(0.5, 1.0) if big else rng.randf(), "y": rng.randf(), "s": rng.randf_range(0.04, 0.12), "c": [UIKit.AMBER, UIKit.TEAL, Color("ff7aa2"), Color("8fd3ff"), UIKit.IVORY][i % 5],
				"r": rng.randf() * TAU, "w": rng.randf_range(-2.0, 2.0)})

	func _process(delta: float) -> void:
		if UIKit.reduced_motion():
			return
		t += delta
		queue_redraw()

	## The poster's rounded outline (everything painted stays inside it:
	## 2.3 fixes the square gradient and the rays and confetti that spilled
	## past the rounded frame).
	var _shape := PackedVector2Array()
	var _shape_for := Vector2.ZERO

	func shape() -> PackedVector2Array:
		if _shape_for == size and not _shape.is_empty():
			return _shape
		_shape_for = size
		_shape = PackedVector2Array()
		var rad := minf(30.0 if big else 20.0, minf(size.x, size.y) * 0.5)
		var corners := [[Vector2(size.x - rad, rad), -PI * 0.5], [Vector2(size.x - rad, size.y - rad), 0.0],
			[Vector2(rad, size.y - rad), PI * 0.5], [Vector2(rad, rad), PI]]
		for cr in corners:
			for k in 9:
				_shape.append((cr[0] as Vector2) + Vector2.from_angle(float(cr[1]) + PI * 0.5 * float(k) / 8.0) * rad)
		return _shape

	## A polygon cut to the poster's outline.
	func _fill_clipped(poly: PackedVector2Array, col: Color) -> void:
		for piece in Geometry2D.intersect_polygons(poly, shape()):
			if piece.size() >= 3:
				draw_colored_polygon(piece, col)

	func _draw() -> void:
		var outline := shape()
		# night gradient, purple at the top to deep blue at the bottom
		var top := Color("3a1c7a")
		var bot := Color("0b1a46")
		var cols := PackedColorArray()
		for v in outline:
			cols.append(top.lerp(bot, clampf(v.y / maxf(size.y, 1.0), 0.0, 1.0)))
		draw_polygon(outline, cols)
		# light rays from behind the trophy (right side)
		var c := Vector2(size.x * (0.8 if big else 0.86), size.y * (0.52 if big else 0.5))
		var n := 14
		for i in n:
			var a := TAU * float(i) / float(n) + t * 0.15
			var a2 := a + TAU / float(n) * 0.45
			var L := size.length()
			_fill_clipped(PackedVector2Array([c, c + Vector2.from_angle(a) * L, c + Vector2.from_angle(a2) * L]), Color(1.0, 0.85, 0.45, 0.07))
		# glow
		for k in 6:
			var gr := (size.y * 0.42) * (1.0 - float(k) * 0.14)
			var disc := PackedVector2Array()
			for j in 40:
				disc.append(c + Vector2.from_angle(TAU * float(j) / 40.0) * gr)
			_fill_clipped(disc, Color(1.0, 0.78, 0.36, 0.05))
		# the "your skin here" card behind the trophy
		var cw := size.y * (0.42 if big else 0.24)
		var card := Rect2(c + Vector2(-cw * 1.05, -cw * 0.7), Vector2(cw * 0.72, cw * 1.08))
		if not big:
			# small: the trophy alone in its corner
			Icons.draw_shape(self, "trophy", c + Vector2(0, sin(t * 1.6) * 3.0), cw * 0.6, Color("ffcf4a"))
			_draw_confetti()
			return
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(UIKit.NAVY, 0.85)
		csb.set_corner_radius_all(14)
		csb.border_color = Color(UIKit.TEAL, 0.9)
		csb.set_border_width_all(3)
		draw_set_transform(card.get_center(), -0.12, Vector2.ONE)
		draw_style_box(csb, Rect2(-card.size * 0.5, card.size))
		var f := UIKit.font_w(800)
		var fs := int(cw * 0.42)
		draw_string(f, Vector2(-card.size.x * 0.5, fs * 0.35), "?", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, fs, Color(UIKit.TEAL, 0.95))
		var f2 := int(clampf(cw * 0.085, 10.0, 22.0))
		draw_string(f, Vector2(-card.size.x * 0.5, card.size.y * 0.38), "YOUR SKIN", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, f2, UIKit.IVORY)
		draw_string(f, Vector2(-card.size.x * 0.5, card.size.y * 0.38 + f2 * 1.2), "TIER 100", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, f2, UIKit.AMBER)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# trophy
		var bob := sin(t * 1.6) * size.y * 0.01
		Icons.draw_shape(self, "trophy", c + Vector2(cw * 0.15, bob), cw * 0.62, Color("ffcf4a"))
		# sparkles
		for i in 5:
			var sp := c + Vector2.from_angle(float(i) * 1.3 + t * 0.4) * cw * (0.9 + 0.1 * sin(t * 2.0 + i))
			Icons.draw_shape(self, "star", sp, cw * 0.06 * (1.0 + 0.4 * sin(t * 3.0 + float(i))), Color(1, 1, 0.85, 0.9))
		_draw_confetti()

	func _draw_confetti() -> void:
		var m := 0.05
		for q in confetti:
			var y := m + fmod(float(q["y"]) + t * float(q["s"]), 1.0) * (1.0 - m * 2.0)
			var x := m + float(q["x"]) * (1.0 - m * 2.0)
			var p := Vector2(x * size.x, y * size.y)
			var rot := float(q["r"]) + t * float(q["w"])
			var s := size.y * 0.012
			# fade in at the top and out at the bottom: never cut by the edge
			var fade := clampf(minf(y - m, 1.0 - m - y) / 0.08, 0.0, 1.0)
			var col: Color = q["c"]
			col.a *= fade
			draw_set_transform(p, rot, Vector2.ONE)
			draw_rect(Rect2(-s, -s * 0.5, s * 2.0, s), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_frame()

	## The gold frame, drawn last so nothing paints over it.
	func _draw_frame() -> void:
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_corner_radius_all(int(minf(30.0 if big else 20.0, minf(size.x, size.y) * 0.5)))
		sb.border_color = Color(UIKit.AMBER, 0.9)
		sb.set_border_width_all(3 if big else 2)
		sb.anti_aliasing = true
		sb.corner_detail = 12
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
