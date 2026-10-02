class_name LoadingScreen
extends Screen
## Loading (V4): a calm deep-night screen with the Trifecta motif - three
## droplets landing in turn and rippling out - the wordmark, and the real
## state underneath ("Getting campus ready…", then "Waiting for players ·
## 3/4 ready" when that is what is happening).  No percentage is invented:
## the stage text follows the match's actual preparation steps.
##
## The motif's resting frame is the same drawing as the boot splash and the
## iOS launch image (assets/icon/launch.png, rendered from this code by
## tools/make_launch_art.sh), so launch -> boot -> loading has no jump.
## Reduced Motion: the resting frame with a slow fade, nothing falls.

const BG := Color("0c1324")
## layout in canvas units of a 720-unit-high screen (shared with the launch art)
const MOTIF_Y := 0.40          # motif centre, fraction of screen height
const WORDMARK_Y := 0.585      # wordmark top
const LOOP_S := 2.6

signal done

var info: Dictionary = {}
var session: NetSession
## The round being prepared underneath; the screen goes once it is live.
var match_ctrl: MatchController
var motif: LoadingMotif
var stage_lbl: Label
var wait_lbl: Label
var tip_lbl: Label
var leave_btn: Button
var _t := 0.0
var _stage_text := "Getting campus ready…"
var _closing := false


func build() -> void:
	Diag.context("loading")
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)
	motif = LoadingMotif.new()
	motif.set_anchors_preset(Control.PRESET_FULL_RECT)
	motif.animate = not UIKit.reduced_motion()
	add_child(motif)
	move_child(motif, 1)
	var col := UIKit.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(col)
	stage_lbl = UIKit.label(_stage_text, 24, UIKit.IVORY, true, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(stage_lbl)
	wait_lbl = UIKit.label("", 20, UIKit.TEAL, false, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(wait_lbl)
	tip_lbl = UIKit.label(_tip(), 18, UIKit.IVORY_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(tip_lbl)
	leave_btn = UIKit.quiet("Leave party", Vector2(240, 64), 20)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.visible = false
	leave_btn.pressed.connect(func() -> void: App.leave_room())
	col.add_child(leave_btn)


## The match reports what it is doing (known steps only).
func set_stage(text: String) -> void:
	_stage_text = text
	if is_instance_valid(stage_lbl):
		stage_lbl.text = text


func _process(delta: float) -> void:
	_t += delta
	if _closing:
		return
	if match_ctrl != null and is_instance_valid(match_ctrl) and match_ctrl.round_live():
		_close()
		return
	var online := session != null and is_instance_valid(session) and session.mode != NetSession.Mode.OFFLINE
	if match_ctrl != null and is_instance_valid(match_ctrl) and match_ctrl.prepared:
		set_stage("Starting…" if not online else "Ready")
	if not online:
		return
	var lp: Array = session.load_progress()
	if int(lp[1]) > 1:
		wait_lbl.text = "Waiting for players · %d/%d ready" % [lp[0], lp[1]] if int(lp[0]) < int(lp[1]) else "Everyone's ready"
	# a real, recoverable state: a long wait for a slow or lost player
	leave_btn.visible = _t > 25.0


## A short fade into the round (no fade with Reduced Motion).
func _close() -> void:
	_closing = true
	Diag.mark("loading_closed")
	Diag.context("match")
	if UIKit.reduced_motion():
		done.emit()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void: done.emit())


func _tip() -> String:
	var watch := int((info.get("settings", {}) as Dictionary).get("watch", PartySeries.DEFAULT_WATCH))
	var cfg := PartySeries.rules_for(Rules.cfg, watch)
	return [
		"Diving into water from a run is faster than climbing in.",
		"Carts can't climb stairs, pass bollards or go into the woods.",
		"A splash marks that spot for the Night Watch for %d seconds, never you." % int(cfg.splash_marker_s),
		"Caught? You keep your splashes and you're back in %d seconds near your last one." % int(cfg.capture_penalty_s),
		"%d runners home before time runs out wins it for every runner." % cfg.runners_needed,
		"Night Watch: Tag lights up when a runner is in reach. Wait for it, then tap.",
	][randi() % 6]


func _go_back() -> void:
	pass


## The droplet motif.  Drawn in canvas units relative to the screen height,
## so the resting frame lines up with the launch image on any aspect.
class LoadingMotif:
	extends Control
	var animate := true
	var _t := 0.0
	const DROP_X := [-64.0, 0.0, 64.0]
	const DROP_COL := [Color("6fd8cc"), Color("f4f2ec"), Color("ffc668")]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		# laid out like the launch image: a square fitted to the screen
		var side := minf(size.x, size.y)
		var top := (size.y - side) * 0.5
		var c := Vector2(size.x * 0.5, top + side * LoadingScreen.MOTIF_Y)
		var k := side / 720.0
		LoadingMotif.draw_resting(self, c, k, 1.0 if animate else 0.85 + 0.15 * sin(_t * 1.3))
		if animate:
			_draw_cycle(c, k)
		LoadingMotif.draw_wordmark(self, Vector2(size.x * 0.5, top + side * LoadingScreen.WORDMARK_Y), k)

	## Animated part: each droplet falls in turn, touches the water line and
	## rings out; the resting frame stays underneath as the calm base.
	func _draw_cycle(c: Vector2, k: float) -> void:
		var u := fmod(_t, LoadingScreen.LOOP_S)
		for i in 3:
			var land := 0.35 + 0.55 * float(i)
			var fall_t := u - (land - 0.42)
			if fall_t >= 0.0 and fall_t < 0.42:
				var e := fall_t / 0.42
				var y := lerpf(-150.0, -34.0, e * e)
				LoadingMotif.droplet(self, c + Vector2(DROP_X[i], y) * k, 11.0 * k, Color(DROP_COL[i], 0.9))
			var r_t := u - land
			if r_t >= 0.0 and r_t < 1.3:
				var e2 := r_t / 1.3
				for ring in 2:
					var rr := (10.0 + 70.0 * (e2 - 0.18 * ring)) * k
					if rr <= 6.0 * k:
						continue
					var a := (1.0 - e2) * (0.55 - 0.2 * ring)
					LoadingMotif.ellipse(self, c + Vector2(DROP_X[i], 22.0) * k, rr, 0.32, Color(DROP_COL[i], a), 2.5 * k)

	## The resting frame (also the launch image): three drops above three
	## soft ripples on a moonlit water line.
	static func draw_resting(ci: CanvasItem, c: Vector2, k: float, alpha: float = 1.0) -> void:
		# moon glow (many faint discs: no visible rings)
		for g in 24:
			ci.draw_circle(c + Vector2(0, 8) * k, (150.0 - g * 5.5) * k, Color(0.30, 0.42, 0.72, 0.0095 * alpha))
		for i in 3:
			var x: float = DROP_X[i]
			LoadingMotif.ellipse(ci, c + Vector2(x, 22.0) * k, 26.0 * k, 0.32, Color(DROP_COL[i], 0.42 * alpha), 2.5 * k)
			LoadingMotif.ellipse(ci, c + Vector2(x, 22.0) * k, 44.0 * k, 0.32, Color(DROP_COL[i], 0.18 * alpha), 2.0 * k)
			LoadingMotif.droplet(ci, c + Vector2(x, -18.0 - (6.0 if i == 1 else 0.0)) * k, 15.0 * k, Color(DROP_COL[i], alpha))

	static func droplet(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
		# round bottom, soft point on top: the arc runs between the two
		# tangent points seen from the tip, so the outline never crosses
		var tip := 1.85
		var half := acos(1.0 / tip)
		var pts := PackedVector2Array()
		for s in 25:
			var a := PI + half + (TAU - 2.0 * half) * float(s) / 24.0
			pts.append(p + Vector2(sin(a), cos(a)) * r)
		pts.append(p + Vector2(0, -r * tip))
		ci.draw_colored_polygon(pts, col)
		ci.draw_circle(p + Vector2(-r * 0.35, -r * 0.1), r * 0.24, Color(1, 1, 1, 0.55 * col.a))

	static func ellipse(ci: CanvasItem, c: Vector2, r: float, flat: float, col: Color, width: float) -> void:
		var pts := PackedVector2Array()
		for s in 49:
			var a := TAU * float(s) / 48.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * flat))
		ci.draw_polyline(pts, col, width, true)

	## "ULTIMATE TRIFECTA", compact and centred (the title's letterforms).
	static func draw_wordmark(ci: CanvasItem, top_center: Vector2, k: float) -> void:
		var f := UIKit.font_w(700)
		var s1 := int(22 * k)
		var s2 := int(46 * k)
		var w1 := f.get_string_size("ULTIMATE", HORIZONTAL_ALIGNMENT_LEFT, -1, s1).x + 7 * 2.0 * k
		var x := top_center.x - w1 * 0.5
		for ch in "ULTIMATE":
			var cw := f.get_char_size(ch.unicode_at(0), s1).x
			ci.draw_char_outline(f, Vector2(x, top_center.y + 22 * k), ch, s1, int(6 * k), UIKit.NAVY)
			ci.draw_char(f, Vector2(x, top_center.y + 22 * k), ch, s1, UIKit.AMBER)
			x += cw + 2.0 * k
		var w2 := 0.0
		for ch in "TRIFECTA":
			w2 += f.get_char_size(ch.unicode_at(0), s2).x - 1.0 * k
		x = top_center.x - w2 * 0.5
		var i := 0
		for ch in "TRIFECTA":
			var cw := f.get_char_size(ch.unicode_at(0), s2).x
			var bob := (-3.0 if i % 2 == 0 else 2.0) * k
			var base := Vector2(x, top_center.y + 74 * k + bob)
			ci.draw_char_outline(f, base + Vector2(0, 4 * k), ch, s2, int(10 * k), UIKit.NAVY)
			ci.draw_char(f, base + Vector2(0, 4 * k), ch, s2, UIKit.TEAL.darkened(0.25))
			ci.draw_char_outline(f, base, ch, s2, int(9 * k), UIKit.NAVY)
			ci.draw_char(f, base, ch, s2, UIKit.IVORY)
			x += cw - 1.0 * k
			i += 1
