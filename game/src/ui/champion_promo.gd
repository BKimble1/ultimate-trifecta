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
## (2.2 build 21) The poster is the owner's artwork (ArtPoster) with a little
## confetti and a light sweep over it.

const PROMO_EVERY_S := 20 * 3600
## (2.2 build 21) the poster artwork and its shape
const ART := preload("res://assets/promo/champion_banner.png")
const ART_ASPECT := 2.0
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
	# (2.2 build 21) the poster is the artwork (2:1); its buttons sit under
	# it, never over its words
	var row_h := 96.0
	var w := minf(minf(vis.x * 0.86, 1180.0), (vis.y * 0.92 - row_h - 14.0) * ART_ASPECT)
	var h := w / ART_ASPECT
	var poster := ArtPoster.new()
	poster.big = true
	poster.custom_minimum_size = Vector2(w, h)
	poster.size = Vector2(w, h)
	var top := (vis.y - (h + 14.0 + row_h)) * 0.5
	poster.position = Vector2((vis.x - w) * 0.5, top)
	root.add_child(poster)
	var close := func() -> void:
		if is_instance_valid(root):
			Motion.vanish(root, root.queue_free, 0.15)
	# Close: in the artwork's top-right corner (only confetti there)
	var x := UIKit.icon_button("close")
	x.accessibility_name = "Close"
	x.pressed.connect(close)
	poster.add_child(x)
	x.position = Vector2(w - x.custom_minimum_size.x - h * 0.06, h * 0.07)
	var row := UIKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2((vis.x - w) * 0.5, top + h + 14.0)
	row.size = Vector2(w, row_h)
	row.custom_minimum_size = Vector2(w, row_h)
	var ends := UIKit.chip(_when(), Color(UIKit.NAVY, 0.9), UIKit.IVORY, UIKit.T_LABEL)
	ends.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ends.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ends)
	var go := UIKit.primary("View Rankings", Vector2(300, 84), 28)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void:
		close.call()
		App.goto(RankingsScreen))
	row.add_child(go)
	var rules := UIKit.quiet("Official rules", Vector2(0, UIKit.touch_min()), UIKit.T_LABEL)
	rules.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rules.accessibility_name = "Official rules"
	rules.pressed.connect(func() -> void: open_rules(screen))
	row.add_child(rules)
	root.add_child(row)
	poster.accessibility_name = _a11y()
	screen.add_child(root)
	UIKit.soft_focus.call_deferred(go)
	if not UIKit.reduced_motion():
		for n: Control in [poster, row]:
			n.pivot_offset = Vector2(w * 0.5, (h if n == poster else row_h) * 0.5)
			n.scale = Vector2.ONE * 0.86
			n.modulate.a = 0.0
			var tw := n.create_tween().set_parallel(true)
			tw.tween_property(n, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(n, "modulate:a", 1.0, 0.18)
	screen.push_modal(root, close)
	Sfx.play("pickup")
	return root


## The small poster for the Rankings screen: the artwork (tap it for the
## full poster) and, under it, when the season ends and the rules.
static func banner(screen: Screen) -> Control:
	var v := UIKit.vbox(8)
	var poster := ArtPoster.new()
	poster.custom_minimum_size = Vector2(380, 380.0 / ART_ASPECT)
	poster.accessibility_name = _a11y()
	poster.tooltip_text = "Season Champion prize"
	# (2.3) tap the banner for the full poster
	poster.gui_input.connect(func(ev: InputEvent) -> void:
		var tap := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
		if tap and is_instance_valid(screen) and not screen.has_modal():
			popup(screen))
	v.add_child(poster)
	var row := UIKit.hbox(10)
	var ends := UIKit.chip(_when(), Color(UIKit.NAVY, 0.75), UIKit.IVORY, UIKit.T_CAPTION)
	ends.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ends.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ends)
	row.add_child(UIKit.spacer_h())
	var rules := UIKit.quiet("Rules", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	rules.accessibility_name = "Official rules"
	rules.pressed.connect(func() -> void: open_rules(screen))
	row.add_child(rules)
	v.add_child(row)
	return v


static func _a11y() -> String:
	return "%s champion prize. %s %s %s." % [Rankings.season_name(Rankings.contest_period()), HEAD.capitalize(), BODY, _when()]


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


## (2.2 build 21) The poster is the owner's artwork (assets/promo/
## champion_banner.png, 2:1): "Season 1 · Winter Break", "Champion prize",
## "Design next season's skin", the line about tier 100, the "your skin"
## card and the trophy.  GlamPoster still brings it to life: a few pieces of
## confetti tumbling on the trophy's side, twinkles there, and the light
## sweep across it now and then (Reduced Motion: slower, no sweep).
class ArtPoster:
	extends GlamPoster

	## the trophy's middle in the artwork (fractions of its size)
	const TROPHY := Vector2(0.815, 0.5)

	func _ready() -> void:
		# confetti falls all down the trophy's side, bigger and livelier
		confetti_x = Vector2(0.5, 0.98)
		confetti_n = 34 if big else 16
		confetti_speed = Vector2(0.12, 0.26)
		sparkles_n = 9 if big else 5
		focus = TROPHY
		super._ready()
		# the glow and the turning light rays behind the trophy: added light
		# over the artwork (its own overlay, so the picture keeps its colours)
		var g := Glow.new()
		g.poster = self
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(g)
		move_child(g, 0)

	## the artwork's own rounded frame
	func corner() -> float:
		return size.y * 0.05

	func _draw() -> void:
		draw_texture_rect(ART, Rect2(Vector2.ZERO, size), false)
		# the confetti tumbles over the art (the glow overlay adds its light
		# on top)
		_draw_confetti()

	## The turning rays, the breathing glow behind the trophy, a shine
	## running round the frame and the twinkles: added light over the art.
	class Glow:
		extends Control
		var poster: ArtPoster

		func _ready() -> void:
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			material = m

		func _process(_d: float) -> void:
			if is_visible_in_tree():
				queue_redraw()

		func _draw() -> void:
			if poster == null:
				return
			var t := poster.t
			var c := Vector2(size.x * TROPHY.x, size.y * TROPHY.y)
			var L := size.length()
			# slowly turning rays from behind the trophy
			var n := 14
			for i in n:
				var a := TAU * float(i) / float(n) + t * 0.12
				var a2 := a + TAU / float(n) * 0.4
				var ray := PackedVector2Array([c, c + Vector2.from_angle(a) * L, c + Vector2.from_angle(a2) * L])
				for piece in Geometry2D.intersect_polygons(ray, poster.shape()):
					if piece.size() >= 3:
						draw_colored_polygon(piece, Color(1.0, 0.82, 0.4, 0.045))
			# a warm glow that breathes
			var pulse := 1.0 + 0.08 * sin(t * 1.8)
			for k in 7:
				var r := size.y * 0.42 * pulse * (1.0 - float(k) * 0.12)
				draw_circle(c, r, Color(1.0, 0.78, 0.36, 0.035), true, -1.0, true)
			# a shine that runs round the gold frame
			var u := fposmod(t * 0.12, 1.0)
			var per := 2.0 * (size.x + size.y)
			var d := u * per
			var fp := Vector2.ZERO
			if d < size.x:
				fp = Vector2(d, 0)
			elif d < size.x + size.y:
				fp = Vector2(size.x, d - size.x)
			elif d < 2.0 * size.x + size.y:
				fp = Vector2(size.x - (d - size.x - size.y), size.y)
			else:
				fp = Vector2(0, size.y - (d - 2.0 * size.x - size.y))
			fp = fp.lerp(size * 0.5, 0.012)
			for k in 4:
				draw_circle(fp, size.y * (0.05 - 0.01 * k), Color(1.0, 0.9, 0.55, 0.06), true, -1.0, true)
			poster.draw_twinkles(self)

	## the twinkles, drawn in the glow overlay's added light
	func draw_twinkles(on: CanvasItem) -> void:
		var s0 := size.y * (0.03 if big else 0.045)
		for q in _sparkles:
			var tw := 0.5 + 0.5 * sin(t * 2.4 * float(q["f"]) + float(q["ph"]))
			if tw < 0.15:
				continue
			var p: Vector2 = q["p"]
			Icons.draw_shape(on, "star", Vector2(p.x * size.x, p.y * size.y), s0 * float(q["s"]) * tw, Color(1, 1, 0.9, 0.85 * tw))
