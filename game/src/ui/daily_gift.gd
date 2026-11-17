class_name DailyGift
extends Control
## The daily present (2.2 build 15).  Once a day on arriving home a wrapped
## present sits in the middle of the screen.  Each tap shakes it and pumps it
## up a little bigger and brighter; the TAPS-th tap bursts it open (flash,
## the lid flies off, coins and confetti burst out) and shows today's Coins,
## which then fly into the Coin counter.  Consecutive days climb the amount
## (catalogue economy.daily_gift); the game service grants it once per UTC
## day (Wallet.claim_daily).
##
## A build without the game service shows the present once a day as a
## preview and says plainly that it adds no Coins yet.  Reduced Motion: no
## shaking, bursting or flying; the same steps.

const TAPS := 4

var screen: Screen
var present: PresentArt
var title_l: Label
var hint_l: Label
var reveal: VBoxContainer
var amount_l: Label
var note_l: Label
var collect: Button
var streak_row: HBoxContainer
var _taps := 0
var _opened := false
var _granted := 0
var _claim: Dictionary = {}
var _burst: Burst


static func today() -> String:
	return Time.get_date_string_from_unix_time(Rankings.now())


static func seen_today() -> bool:
	return String(Save.get_setting("gift_day", "")) == today()


## A present is waiting: the service says today's is unclaimed, or (a build
## without the service) the once-a-day preview hasn't been seen.
static func due() -> bool:
	if Wallet.daily_due():
		return true
	return not Cloud.configured() and not seen_today()


## What today's present holds, and the week around it: {coins, streak, list}.
static func today_info() -> Dictionary:
	var list: Array = Catalogue.data()["economy"].get("daily_gift", {}).get("coins", [20])
	var d := Wallet.daily_state()
	var streak := int(d.get("streak", 1)) if not d.is_empty() else 1
	var coins := int(d.get("coins", list[(streak - 1) % list.size()])) if not d.is_empty() else int(list[0])
	return {"coins": coins, "streak": streak, "list": list}


static func open(on: Screen) -> DailyGift:
	var g := DailyGift.new()
	g.screen = on
	g.name = "DailyGift"
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	on.add_child(g)
	on.push_modal(g, g._close)
	return g


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.09, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var info := today_info()
	var vis := get_viewport().get_visible_rect().size
	# the present, centred a little high, with its glow behind
	present = PresentArt.new()
	present.name = "Present"
	var ps := minf(vis.y * 0.5, 420.0)
	present.size = Vector2(ps, ps)
	present.position = Vector2(vis.x * 0.5 - ps * 0.5, vis.y * 0.5 - ps * 0.56)
	present.pivot_offset = present.size * Vector2(0.5, 0.78)
	present.tapped.connect(_on_tap)
	add_child(present)
	_burst = Burst.new()
	_burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_burst)
	# the words above and below
	var top := UIKit.vbox(4)
	top.position = Vector2(vis.x * 0.5 - 400, vis.y * 0.04)
	top.custom_minimum_size = Vector2(800, 0)
	top.size = Vector2(800, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var ov := UIKit.styled("DAILY GIFT · DAY %d" % int(info["streak"]), "overline", UIKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(ov)
	title_l = UIKit.outlined(UIKit.label("A present for you!", 46, UIKit.IVORY, true), 9)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title_l)
	hint_l = UIKit.styled("Tap the present to open it", "label", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint_l.position = Vector2(vis.x * 0.5 - 400, present.position.y + ps * 1.02)
	hint_l.custom_minimum_size = Vector2(800, 0)
	hint_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_l)
	# the week: seven little coins, today's lit
	streak_row = _streak_row(info)
	streak_row.position = Vector2(vis.x * 0.5 - streak_row.get_combined_minimum_size().x * 0.5, vis.y - streak_row.get_combined_minimum_size().y - vis.y * 0.05)
	add_child(streak_row)
	# the reveal (shown after the burst)
	reveal = UIKit.vbox(10)
	reveal.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal.custom_minimum_size = Vector2(800, 0)
	reveal.position = Vector2(vis.x * 0.5 - 400, vis.y * 0.3)
	reveal.visible = false
	add_child(reveal)
	var coin_row := UIKit.hbox(16)
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_child(CommerceArt.Pic.new("coin", "", Color.WHITE, 96))
	amount_l = UIKit.outlined(UIKit.label("+0", 84, UIKit.AMBER_HI, true), 10)
	coin_row.add_child(amount_l)
	reveal.add_child(coin_row)
	var coins_word := UIKit.styled("Coins", "headline", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	reveal.add_child(coins_word)
	note_l = UIKit.styled("", "label", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_l.custom_minimum_size.x = 760
	reveal.add_child(note_l)
	collect = UIKit.primary("Collect", Vector2(320, 88), 30)
	collect.name = "Collect"
	collect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	collect.pressed.connect(_on_collect)
	reveal.add_child(collect)
	present.focus_mode = Control.FOCUS_ALL
	UIKit.soft_focus.call_deferred(present)
	Sfx.play("whoosh")
	if not UIKit.reduced_motion():
		present.scale = Vector2.ONE * 0.2
		var tw := present.create_tween()
		tw.tween_property(present, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _streak_row(info: Dictionary) -> HBoxContainer:
	var row := UIKit.hbox(10)
	row.name = "Week"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var list: Array = info["list"]
	var today_i := (int(info["streak"]) - 1) % list.size()
	for i in list.size():
		var cell := PanelContainer.new()
		var on := i == today_i
		var past := i < today_i
		cell.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.AMBER, 0.22) if on else Color(UIKit.SLATE, 0.9), 14,
			3 if on else 1, UIKit.AMBER if on else Color(UIKit.IVORY, 0.14), 8))
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := UIKit.vbox(2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.custom_minimum_size = Vector2(76, 0)
		v.add_child(UIKit.styled("Day %d" % (i + 1), "caption", UIKit.AMBER if on else UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		var ic := Icons.IconRect.new("check" if past else "coin", UIKit.TEAL if past else (UIKit.AMBER if on else Color(UIKit.AMBER, 0.55)), 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(UIKit.styled(str(int(list[i])), "num", UIKit.IVORY if on else UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		cell.add_child(v)
		row.add_child(cell)
	return row


func _on_tap() -> void:
	if _opened:
		return
	_taps += 1
	present.pump(float(_taps) / float(TAPS))
	Sfx.play("pop", null, -2.0, 0.9 + 0.12 * _taps)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(20 + 10 * _taps)
	if _taps == 1:
		hint_l.text = "Keep tapping!"
	elif _taps == TAPS - 1:
		hint_l.text = "One more!"
	if _taps >= TAPS:
		_open()


func _open() -> void:
	_opened = true
	hint_l.visible = false
	var center := present.global_position + present.size * Vector2(0.5, 0.55)
	# ask the service now; the burst covers the wait
	var info := today_info()
	_granted = int(info["coins"])
	if Cloud.configured():
		_claim = await Wallet.claim_daily()
	else:
		_claim = {"ok": false, "preview": true}
	if bool(_claim.get("ok", false)) or bool(_claim.get("preview", false)):
		Save.set_setting("gift_day", today())
	if bool(_claim.get("ok", false)):
		_granted = int(_claim.get("granted", 0))
	Sfx.play("pickup", null, 0.0, 1.2)
	Sfx.play("cheer", null, -6.0)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(80)
	present.burst()
	_burst.go(center, present.size.y)
	await get_tree().create_timer(0.05 if UIKit.reduced_motion() else 0.55).timeout
	if not is_inside_tree():
		return
	title_l.text = "Your daily gift"
	reveal.visible = true
	if bool(_claim.get("ok", false)) and _granted > 0:
		note_l.text = "Come back tomorrow for %s more. Coins go toward the Season Pass and the Shop." % _next_text()
	elif bool(_claim.get("ok", false)):
		note_l.text = "Today's gift is already in your Coins. Come back tomorrow!"
	elif bool(_claim.get("preview", false)):
		note_l.text = "Preview only: no Coins added in this test build."
		collect.text = "Got it"
	else:
		note_l.text = "Couldn't reach the game service, so no Coins were added. Your gift waits: it opens again later today. (%s)" % String(_claim.get("message", ""))
		collect.text = "OK"
	if not UIKit.reduced_motion():
		reveal.pivot_offset = reveal.size * 0.5
		reveal.scale = Vector2.ONE * 0.6
		reveal.modulate.a = 0.0
		var tw := reveal.create_tween().set_parallel(true)
		tw.tween_property(reveal, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(reveal, "modulate:a", 1.0, 0.2)
		var shown := _granted
		var ctw := create_tween()
		ctw.tween_method(func(v: float) -> void: amount_l.text = "+%s" % Catalogue.format_coins(int(v)), 0.0, float(shown), 0.7)
	amount_l.text = "+%s" % Catalogue.format_coins(_granted)
	UIKit.soft_focus.call_deferred(collect)


func _next_text() -> String:
	var d := Wallet.daily_state()
	var n := int(d.get("next_coins", 0))
	return ("%s Coins" % Catalogue.format_coins(n)) if n > 0 else "another gift"


func _on_collect() -> void:
	var from := amount_l.global_position + amount_l.size * 0.5
	var ok := bool(_claim.get("ok", false)) and _granted > 0
	_close()
	if ok and screen is LobbyScreen:
		var chip: Variant = (screen as LobbyScreen).wallet_chip
		if chip is WalletChip and is_instance_valid(chip) and (chip as WalletChip).is_inside_tree():
			(chip as WalletChip).visible = true
			(chip as WalletChip).fly_in(_granted, from)


func _close() -> void:
	if is_queued_for_deletion():
		return
	# a closed preview counts as seen; a failed claim tries again later
	if not Cloud.configured():
		Save.set_setting("gift_day", today())
	Motion.vanish(self, queue_free, 0.15)


func _gui_input(ev: InputEvent) -> void:
	# a tap anywhere opens it too (big target)
	var tap := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if tap and not _opened:
		_on_tap()
		accept_event()


## The wrapped present: a box, a lid, a ribbon cross and a bow, with a glow
## behind it.  Idle it bobs and breathes; pump() shakes it and makes it
## bigger and brighter; burst() throws the lid off and fades the box.
class PresentArt:
	extends Control
	signal tapped
	var t := 0.0
	var energy := 0.0       # 0..1, how pumped up it is
	var _shake := 0.0
	var _lid_off := 0.0     # 0..1 the lid flying
	var _gone := 0.0        # 0..1 the box fading
	const BOX := Color("e8435a")
	const BOX_D := Color("b52a44")
	const RIB := Color("ffd25a")
	const RIB_D := Color("e0a62a")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		accessibility_name = "Present. Tap to open."

	func _process(delta: float) -> void:
		t += delta
		_shake = maxf(0.0, _shake - delta * 2.6)
		if _lid_off > 0.0 and _lid_off < 1.0:
			_lid_off = minf(1.0, _lid_off + delta * 1.6)
		if _gone > 0.0 and _gone < 1.0:
			_gone = minf(1.0, _gone + delta * 3.0)
		if not UIKit.reduced_motion():
			var wob := sin(t * 38.0) * 0.16 * _shake
			rotation = wob
			var breathe := 1.0 + 0.025 * sin(t * 3.2) * (1.0 + energy)
			var s := (1.0 + 0.2 * energy) * breathe + 0.08 * _shake
			scale = Vector2(s * (1.0 + 0.05 * _shake * sin(t * 30.0)), s * (1.0 - 0.05 * _shake * sin(t * 30.0)))
		queue_redraw()

	func pump(e: float) -> void:
		energy = clampf(e, 0.0, 1.0)
		_shake = 1.0

	func burst() -> void:
		_lid_off = 0.01
		_gone = 0.01
		_shake = 0.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _gui_input(ev: InputEvent) -> void:
		var tap := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed) or ev.is_action_pressed("ui_accept")
		if tap:
			tapped.emit()
			accept_event()

	func _rect(p: Vector2, s: Vector2, col: Color, a: float = 1.0) -> void:
		draw_rect(Rect2(p, s), Color(col, col.a * a))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var a := 1.0 - _gone
		# glow behind, stronger as it pumps
		var gc := Vector2(w * 0.5, h * 0.55)
		for k in 8:
			var r := w * (0.62 + 0.06 * energy) * (1.0 - float(k) * 0.11)
			var d := PackedVector2Array()
			for j in 40:
				d.append(gc + Vector2.from_angle(TAU * j / 40.0) * r)
			draw_colored_polygon(d, Color(1.0, 0.82, 0.4, (0.035 + 0.035 * energy) * (1.0 - _gone * 0.5)))
		# rays behind when pumped
		if energy > 0.3 and _gone < 1.0:
			for i in 12:
				var an := TAU * i / 12.0 + t * 0.6
				var L := w * (0.55 + 0.25 * energy)
				draw_colored_polygon(PackedVector2Array([gc, gc + Vector2.from_angle(an) * L, gc + Vector2.from_angle(an + 0.12) * L]),
					Color(1.0, 0.9, 0.6, 0.08 * energy * a))
		if a <= 0.0:
			return
		# shadow
		var sh := PackedVector2Array()
		for j in 32:
			var an2 := TAU * j / 32.0
			sh.append(Vector2(w * 0.5 + cos(an2) * w * 0.34, h * 0.93 + sin(an2) * h * 0.04))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.3 * a))
		# the box
		var bx := Vector2(w * 0.2, h * 0.42)
		var bs := Vector2(w * 0.6, h * 0.5)
		_rect(bx, bs, BOX, a)
		_rect(bx + Vector2(bs.x * 0.62, 0), Vector2(bs.x * 0.38, bs.y), BOX_D, a)   # the shaded side
		_rect(bx + Vector2(bs.x * 0.44, 0), Vector2(bs.x * 0.12, bs.y), RIB, a)
		_rect(bx + Vector2(bs.x * 0.44 + bs.x * 0.09, 0), Vector2(bs.x * 0.03, bs.y), RIB_D, a)
		# polka dots
		for i in 6:
			var dp := bx + Vector2(bs.x * (0.12 + 0.17 * (i % 3)) + (bs.x * 0.5 if i % 3 == 2 else 0.0), bs.y * (0.3 + 0.38 * float(i / 3)))
			if absf(dp.x - (bx.x + bs.x * 0.5)) > bs.x * 0.1:
				draw_circle(dp, w * 0.022, Color(1, 1, 1, 0.22 * a))
		# the lid (flies up and spins away when it bursts)
		var lid_up := _lid_off * h * 0.9
		var lid_rot := _lid_off * 2.4
		var lc := Vector2(w * 0.5, h * 0.4 - lid_up)
		draw_set_transform(lc, lid_rot, Vector2.ONE)
		var ls := Vector2(w * 0.68, h * 0.13)
		var lp := -ls * 0.5
		_rect(lp, ls, BOX, a)
		_rect(lp + Vector2(ls.x * 0.62, 0), Vector2(ls.x * 0.38, ls.y), BOX_D, a)
		_rect(lp + Vector2(ls.x * 0.44, 0), Vector2(ls.x * 0.12, ls.y), RIB, a)
		_rect(lp + Vector2(0, ls.y * 0.82), Vector2(ls.x, ls.y * 0.18), Color(0, 0, 0, 0.15), a)
		# the bow: two tilted loops with shaded centres, two tails, a knot
		var bc := Vector2(0, lp.y)
		for side in [-1.0, 1.0]:
			var tail := PackedVector2Array([bc + Vector2(side * w * 0.01, 0), bc + Vector2(side * w * 0.05, 0),
				bc + Vector2(side * w * 0.13, h * 0.1), bc + Vector2(side * w * 0.09, h * 0.115)])
			draw_colored_polygon(tail, Color(RIB_D, a))
			for layer in 2:
				var loop := PackedVector2Array()
				var rx := w * (0.13 if layer == 0 else 0.07)
				var ry := h * (0.065 if layer == 0 else 0.03)
				var lc2 := bc + Vector2(side * w * 0.12, -h * 0.055)
				for j in 28:
					var an3 := TAU * j / 28.0
					var q := Vector2(cos(an3) * rx, sin(an3) * ry).rotated(side * -0.45)
					loop.append(lc2 + q + Vector2(side * (w * 0.01 if layer == 1 else 0.0), 0))
				draw_colored_polygon(loop, Color(RIB if layer == 0 else RIB_D, a))
		draw_circle(bc + Vector2(0, -h * 0.03), w * 0.05, Color(RIB, a))
		draw_circle(bc + Vector2(-w * 0.012, -h * 0.042), w * 0.018, Color(1, 1, 1, 0.35 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The burst: a flash ring, then coins and confetti thrown out from the
## present and falling.
class Burst:
	extends Control
	var parts: Array = []
	var flash := 0.0
	var at := Vector2.ZERO
	var r0 := 100.0

	func go(center: Vector2, sz: float) -> void:
		at = center - global_position
		r0 = sz
		flash = 1.0
		if UIKit.reduced_motion():
			return
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in 70:
			var coin := i < 22
			var an := rng.randf() * TAU
			var sp := rng.randf_range(380.0, 980.0)
			parts.append({"p": at, "v": Vector2.from_angle(an) * sp + Vector2(0, -380), "coin": coin, "r": rng.randf() * TAU,
				"w": rng.randf_range(-9, 9), "life": rng.randf_range(1.1, 1.8), "age": 0.0,
				"c": [UIKit.AMBER, UIKit.TEAL, Color("ff7aa2"), Color("8fd3ff"), UIKit.IVORY][i % 5], "s": rng.randf_range(10, 18)})

	func _process(delta: float) -> void:
		if flash <= 0.0 and parts.is_empty():
			return
		flash = maxf(0.0, flash - delta * 2.2)
		for q in parts:
			q["age"] = float(q["age"]) + delta
			q["v"] = (q["v"] as Vector2) * (1.0 - 1.6 * delta) + Vector2(0, 1300) * delta
			q["p"] = (q["p"] as Vector2) + (q["v"] as Vector2) * delta
			q["r"] = float(q["r"]) + float(q["w"]) * delta
		parts = parts.filter(func(q: Dictionary) -> bool: return float(q["age"]) < float(q["life"]))
		queue_redraw()

	func _draw() -> void:
		if flash > 0.0:
			var rr := r0 * (0.4 + (1.0 - flash) * 1.4)
			for k in 5:
				var d := PackedVector2Array()
				for j in 48:
					d.append(at + Vector2.from_angle(TAU * j / 48.0) * rr * (1.0 - 0.15 * k))
				draw_colored_polygon(d, Color(1, 0.95, 0.75, 0.12 * flash))
		for q in parts:
			var fade := clampf(1.0 - (float(q["age"]) / float(q["life"]) - 0.7) / 0.3, 0.0, 1.0)
			var p: Vector2 = q["p"]
			if bool(q["coin"]):
				var sx := absf(cos(float(q["r"])))
				draw_set_transform(p, 0.0, Vector2(maxf(0.2, sx), 1.0))
				draw_circle(Vector2.ZERO, 16.0, Color(UIKit.AMBER, fade))
				draw_circle(Vector2.ZERO, 11.0, Color(UIKit.AMBER_HI, fade))
			else:
				var col: Color = q["c"]
				draw_set_transform(p, float(q["r"]), Vector2(absf(cos(float(q["r"]) * 1.7)) + 0.2, 1.0))
				draw_rect(Rect2(-float(q["s"]) * 0.5, -float(q["s"]) * 0.25, float(q["s"]), float(q["s"]) * 0.5), Color(col, fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
