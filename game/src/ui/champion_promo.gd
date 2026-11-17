class_name ChampionPromo
extends RefCounted
## The Season Champion prize (2.2): whoever finishes the season #1 in Season
## Points designs the next season's tier 100 skin (their concept and name,
## made into the game by the developer).
##
##   popup    a poster over Home (LoginFlow: every PROMO_EVERY_LAUNCHES
##            launches, after LoginFlow.AWAY_S away, or once a day; X to
##            close), with View Rankings and Official Rules
##   banner   the same poster, smaller, at the top of the Rankings screen
##   rules    the Official Rules sheet (App Store Review Guideline 5.3:
##            sponsored by the developer, Apple not involved, free to enter)
## The poster is drawn (no image files): a deep night gradient, slowly
## turning light rays behind a gold trophy, falling confetti, the "your
## skin here" card.  Reduced Motion: still.

const PROMO_EVERY_S := 20 * 3600
const PROMO_EVERY_LAUNCHES := 3
## never twice within this (a resume right after a launch)
const PROMO_MIN_GAP_S := 30 * 60
const HEAD := "DESIGN NEXT SEASON'S SKIN"
const BODY := "Finish #1 in Season Points and your idea becomes next season's tier 100 skin, with your name on it."
const SHORT := "Finish #1 in Season Points to design next season's tier 100 skin."


## Due: never seen; or every few launches since it was last shown; or
## after time away; or a day since it was last shown.  Never twice within
## PROMO_MIN_GAP_S.
static func due() -> bool:
	var seen := int(Save.get_setting("promo_seen_at", 0))
	if seen == 0:
		return true
	var since := Rankings.now() - seen
	if since < PROMO_MIN_GAP_S:
		return false
	var launches := int(Save.get_setting("launches", 0)) - int(Save.get_setting("promo_seen_launch", 0))
	return launches >= PROMO_EVERY_LAUNCHES or LoginFlow.away_s >= LoginFlow.AWAY_S or since >= PROMO_EVERY_S


## Shows the popup when it's due (never during automation or before
## onboarding).  Returns true if shown.
static func maybe_show(screen: Screen, force: bool = false) -> bool:
	if not force:
		if App.dev_automation or not bool(Save.data.get("onboarded", false)):
			return false
		if not due():
			return false
	Save.set_setting("promo_seen_at", Rankings.now())
	Save.set_setting("promo_seen_launch", int(Save.get_setting("launches", 0)))
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
	var ov := UIKit.chip("%s · CHAMPION PRIZE" % (sname if big else sname.get_slice(" · ", 0)).to_upper(), UIKit.AMBER, UIKit.NAVY, UIKit.T_OVERLINE)
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
	var rules := UIKit.quiet("Official rules" if big else "Rules", Vector2(0, UIKit.touch_min()), UIKit.T_LABEL if big else UIKit.T_CAPTION)
	rules.accessibility_name = "Official rules"
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


## The poster's painting: GlamPoster's backdrop (gradient, rays, glow,
## tumbling confetti, sparkles, the light sweep, the frame) with the trophy
## on a glowing pedestal and the "your skin here" card.
class Poster:
	extends GlamPoster

	func _ready() -> void:
		focus = Vector2(0.79, 0.5) if big else Vector2(0.86, 0.5)
		if big:
			confetti_x = Vector2(0.5, 1.0)
		super._ready()

	## (2.2 build 18) A shaded gold trophy: a cup lit from the left with a
	## moving shine, its rim and handles, a star on it, the stem and knot,
	## and a two-step base with a "#1" plate.  s ~ its half-height.
	func gold_trophy(c: Vector2, s: float) -> void:
		var dark := Color("9a5a0c")
		var mid := Color("f0b42a")
		var hi := Color("fff2b0")
		var shine := fposmod(t * 0.3, 2.2) - 1.1
		var gold := func(u: float) -> Color:
			var col: Color = dark.lerp(mid, clampf(1.0 - u * u, 0.0, 1.0))
			col = col.lerp(hi, clampf(exp(-pow((u + 0.42) / 0.16, 2.0)) * 0.85, 0.0, 1.0))
			col = col.lerp(Color.WHITE, clampf(exp(-pow((u - shine) / 0.08, 2.0)) * 0.55, 0.0, 1.0))
			return col
		# base: a dark block with a gold plate, a gold plinth on it
		var blk := Rect2(c + Vector2(-s * 0.48, s * 0.56), Vector2(s * 0.96, s * 0.32))
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color("3b2650")
		bsb.set_corner_radius_all(int(s * 0.06))
		bsb.border_color = Color("6a4a8a")
		bsb.set_border_width_all(2)
		draw_style_box(bsb, blk)
		var plate := Rect2(blk.position + Vector2(blk.size.x * 0.24, blk.size.y * 0.22), Vector2(blk.size.x * 0.52, blk.size.y * 0.56))
		var psb := StyleBoxFlat.new()
		psb.bg_color = mid
		psb.set_corner_radius_all(int(s * 0.03))
		draw_style_box(psb, plate)
		var f := UIKit.font_w(800)
		var pfs := int(plate.size.y * 0.78)
		draw_string(f, Vector2(plate.position.x, plate.get_center().y + pfs * 0.36), "#1", HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, pfs, Color("5a3206"))
		var pl := Rect2(c + Vector2(-s * 0.36, s * 0.43), Vector2(s * 0.72, s * 0.14))
		_gold_rect(pl, gold)
		# stem and knot
		_gold_rect(Rect2(c + Vector2(-s * 0.08, s * 0.06), Vector2(s * 0.16, s * 0.38)), gold)
		draw_circle(c + Vector2(0, s * 0.16), s * 0.12, mid, true, -1.0, true)
		draw_circle(c + Vector2(-s * 0.04, s * 0.13), s * 0.04, Color(hi, 0.8), true, -1.0, true)
		# handles (behind the cup's edges)
		for side in [-1.0, 1.0]:
			var hc := c + Vector2(side * s * 0.6, -s * 0.5)
			var a0 := -PI * 0.5 if side > 0.0 else PI * 0.5
			draw_arc(hc, s * 0.27, a0, a0 + PI * side, 24, dark, s * 0.12, true)
			draw_arc(hc, s * 0.27, a0, a0 + PI * side, 24, mid, s * 0.07, true)
		# the cup in vertical strips: width narrows towards the stem
		var n := 26
		var top_y := -0.88 * s
		var bot_y := 0.08 * s
		var half := func(y: float) -> float:
			var k := clampf((y - top_y) / (bot_y - top_y), 0.0, 1.0)
			return lerpf(0.66, 0.1, pow(k, 1.7)) * s
		for i in n:
			var u0 := -1.0 + 2.0 * float(i) / float(n)
			var u1 := -1.0 + 2.0 * float(i + 1) / float(n)
			var pts := PackedVector2Array()
			for j in 9:
				var y := lerpf(top_y, bot_y, float(j) / 8.0)
				pts.append(c + Vector2(u0 * float(half.call(y)), y))
			for j in range(8, -1, -1):
				var y2 := lerpf(top_y, bot_y, float(j) / 8.0)
				pts.append(c + Vector2(u1 * float(half.call(y2)) + 0.6, y2))
			draw_colored_polygon(pts, gold.call((u0 + u1) * 0.5))
		# the rim: the opening and its lip
		var rim := PackedVector2Array()
		for j in 40:
			var a := TAU * float(j) / 40.0
			rim.append(c + Vector2(cos(a) * 0.66 * s, top_y + sin(a) * 0.12 * s))
		draw_colored_polygon(rim, Color("7a4508"))
		rim.append(rim[0])
		draw_polyline(rim, hi, maxf(2.0, s * 0.03), true)
		# a star on the cup
		Icons.draw_shape(self, "star", c + Vector2(0, -0.42 * s), s * 0.2, Color("fff6c8"))
		Icons.draw_shape(self, "star", c + Vector2(0, -0.42 * s), s * 0.13, Color("e9a020"))

	func _gold_rect(r: Rect2, gold: Callable) -> void:
		var n := 12
		for i in n:
			var u0 := -1.0 + 2.0 * float(i) / float(n)
			var x0 := r.position.x + r.size.x * float(i) / float(n)
			var x1 := r.position.x + r.size.x * float(i + 1) / float(n) + 0.6
			draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), gold.call(u0 + 1.0 / float(n)))

	func _paint_art(c: Vector2) -> void:
		var cw := size.y * (0.42 if big else 0.24)
		var bob := sin(t * 1.6) * size.y * 0.012
		if not big:
			# small: the trophy alone in its corner, on a halo
			fill_clipped(disc(c + Vector2(0, cw * 0.05), cw * 0.62), Color(1.0, 0.86, 0.4, 0.12))
			Icons.draw_shape(self, "trophy", c + Vector2(0, bob), cw * 0.6, Color("ffcf4a"))
			return
		# the "your skin here" card behind the trophy, swaying a little
		var card := Rect2(c + Vector2(-cw * 1.08, -cw * 0.72), Vector2(cw * 0.74, cw * 1.1))
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(UIKit.NAVY, 0.88)
		csb.set_corner_radius_all(16)
		csb.border_color = Color(UIKit.TEAL, 0.95)
		csb.set_border_width_all(3)
		csb.shadow_color = Color(UIKit.TEAL, 0.35)
		csb.shadow_size = 14
		draw_set_transform(card.get_center(), -0.12 + sin(t * 0.9) * 0.025, Vector2.ONE)
		draw_style_box(csb, Rect2(-card.size * 0.5, card.size))
		var f := UIKit.font_w(800)
		var fs := int(cw * 0.3)
		var q_a := 0.75 + 0.25 * sin(t * 2.2)
		# (2.2 build 18) a runner's outline waiting for its look, a ? on it,
		# and a holographic shimmer crossing the card
		var sil := Color(UIKit.TEAL, 0.32)
		var hcy := -card.size.y * 0.24
		draw_circle(Vector2(0, hcy), card.size.x * 0.17, sil, false, 3.0, true)
		var body := Rect2(Vector2(-card.size.x * 0.2, hcy + card.size.x * 0.2), Vector2(card.size.x * 0.4, card.size.y * 0.3))
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0, 0, 0, 0)
		bsb.border_color = sil
		bsb.set_border_width_all(3)
		bsb.set_corner_radius_all(int(card.size.x * 0.12))
		draw_style_box(bsb, body)
		draw_string(f, Vector2(-card.size.x * 0.5, body.get_center().y + fs * 0.35), "?", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, fs, Color(UIKit.TEAL, q_a))
		var sh := fposmod(t * 0.35, 1.6) - 0.3
		var sx := lerpf(-card.size.x * 0.7, card.size.x * 0.7, sh)
		draw_colored_polygon(PackedVector2Array([Vector2(sx - 10, -card.size.y * 0.5 + 6), Vector2(sx + 14, -card.size.y * 0.5 + 6),
			Vector2(sx - 6, card.size.y * 0.5 - 6), Vector2(sx - 30, card.size.y * 0.5 - 6)]), Color(0.7, 1.0, 0.95, 0.10))
		var f2 := int(clampf(cw * 0.085, 10.0, 22.0))
		draw_string(f, Vector2(-card.size.x * 0.5, card.size.y * 0.36), "YOUR SKIN", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, f2, UIKit.IVORY)
		draw_string(f, Vector2(-card.size.x * 0.5, card.size.y * 0.36 + f2 * 1.25), "TIER 100", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, f2, UIKit.AMBER)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# the pedestal: a lit ellipse under the trophy
		var ped := c + Vector2(cw * 0.15, cw * 0.62)
		for k in 4:
			var e := PackedVector2Array()
			var rx := cw * (0.62 - 0.1 * k)
			for j in 32:
				var a := TAU * float(j) / 32.0
				e.append(ped + Vector2(cos(a) * rx, sin(a) * rx * 0.22))
			fill_clipped(e, Color(1.0, 0.85, 0.45, 0.10 + 0.04 * k))
		# the trophy with a halo ring
		var tc := c + Vector2(cw * 0.15, bob)
		for k in 3:
			var ring := PackedVector2Array()
			var rr := cw * (0.58 + 0.06 * k + 0.02 * sin(t * 2.0 + k))
			for j in 48:
				ring.append(tc + Vector2.from_angle(TAU * float(j) / 48.0) * rr)
			ring.append(ring[0])
			draw_polyline(ring, Color(1.0, 0.86, 0.45, 0.16 - 0.04 * k), 2.0, true)
		gold_trophy(tc, cw * 0.64)
		# orbiting stars
		for i in 6:
			var sp := tc + Vector2.from_angle(float(i) * 1.05 + t * 0.45) * cw * (0.86 + 0.1 * sin(t * 2.0 + i))
			Icons.draw_shape(self, "star", sp, cw * 0.06 * (1.0 + 0.45 * sin(t * 3.0 + float(i))), Color(1, 1, 0.85, 0.92))
