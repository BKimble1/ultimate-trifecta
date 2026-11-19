class_name SeasonPremiere
extends CanvasLayer
## (2.2 build 23) The season premiere: the first cold launch of a new season
## plays the season's film between the Idlery Games curtain and the game,
## once per season per player (Save "season_film_seen"), on its own clock.
##
##   cold launch  App._boot sees SeasonPremiere.due() and builds this layer
##                under the curtain: the film decodes its first frame and
##                holds it, paused at 0:00 with no sound, while the
##                destination (setup or the party lobby) is built under it.
##                The curtain waits for that frame (gate) instead of the
##                lobby's runner, then fades straight onto the film.
##   playing      the film fills the screen keeping its 16:9 picture whole
##                (dark bars where the screen is wider or taller).  After a
##                breath a quiet "Hold to skip" appears in the lower-right
##                safe corner; holding it (touch, or Space / A with its
##                glyph) for HOLD_S fills its ring.  Release, sliding off or
##                losing focus cancels; a tap does nothing but wake the hint.
##   the end      natural end or a completed hold, exactly once: the seen
##                flag is saved at that moment, then picture and sound fade
##                together over FADE_S onto the destination (`ending`), the
##                lobby track starts as it appears, and the layer goes
##                (`ended`).  A hold that skips is swallowed until its
##                release, so it can't press anything on the next screen.
##   failure      no film, no first frame, or a stall: the player is
##                released and the destination shows; nothing is marked seen,
##                and after MAX_FAILS failures this season the film is not
##                tried again (no slow launch every time).
## Backgrounding pauses the film and drops a partial hold; coming back
## resumes the same player.  All input is taken while the layer is up.

signal ending(how: String)
signal ended(how: String)

## the season films shipped in the app (only the runtime movie is bundled);
## a var so tests can stage a next season
static var films := {"s1": "res://assets/video/season_s1.ogv"}
const FILM_SIZE := Vector2(1280, 720)
## the authored running time (s1: 33.0 s); an end well before it is a failure
const FILM_S := 33.0
## the title card (0:29.8 in s1): the hint steps aside so it reads clean
## (a hold already under way still completes)
const TITLE_CARD_S := 29.8
## a decoder that has produced no frame by now isn't going to
const NO_FRAME_S := 1.5
const LAYER := 90
## the opening shot gets a breath before the hint appears
const HINT_DELAY_S := 1.6
const HOLD_S := 0.8
const FADE_S := 0.33
const STALL_S := 2.5
const MAX_FAILS := 2

enum State { PREPARING, READY, PLAYING, ENDING, DONE }

static var active := false
static var current: SeasonPremiere = null
## off under the automated tests (their runner boots the app with a fresh
## profile: a film there would take every tap for 33 s)
static var enabled := true

var season := ""
var state := State.PREPARING
var how := ""
var bg: ColorRect
var video: VideoStreamPlayer
var hint: SkipHint
var hold := 0.0
## what is holding: "" (nothing), "touch:<index>" or "key:<action>"
var holder := ""
var _t := 0.0
var _play_t := 0.0
var _last_pos := 0.0
var _stalled := 0.0
var _prep_t := 0.0
var _decoded := false
var _focus_paused := false
var _gain := 1.0
var _fade := 1.0


# ---------------------------------------------------------------- the rule
## The film has the soundtrack: until it starts fading out, the game's
## music and sounds hold (Sfx asks).
static func holds_audio() -> bool:
	return current != null and is_instance_valid(current) and current.state < State.ENDING


static func film_path(sid: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--premiere-film="):
			return a.substr(a.find("=") + 1)   # dev: a missing / broken film
	return String(films.get(sid, ""))


static func has_seen(sid: String) -> bool:
	var seen: Variant = Save.data.get("season_film_seen", [])
	return seen is Array and (seen as Array).has(sid)


static func failures(sid: String) -> int:
	var f: Variant = Save.data.get("season_film_fails", {})
	return int((f as Dictionary).get(sid, 0)) if f is Dictionary else 0


## Should this cold launch play the season's film?  Unseen this season, the
## film is in the app, it hasn't failed repeatedly, and this isn't an
## automation run (those pass --premiere to see it on purpose).
static func due(sid: String = "") -> bool:
	if sid == "":
		sid = Catalogue.current_season_id()
	var args := OS.get_cmdline_user_args()
	if not enabled or args.has("--no-premiere"):
		return false
	if App.dev_automation and not args.has("--premiere"):
		return false
	return film_exists(sid) and eligible(sid)


## This profile hasn't watched (or skipped) this season's film, and it
## hasn't failed to play repeatedly.  Independent of "onboarded".
static func eligible(sid: String) -> bool:
	return not has_seen(sid) and failures(sid) < MAX_FAILS


static func film_exists(sid: String) -> bool:
	var path := film_path(sid)
	return path != "" and ResourceLoader.exists(path)


## The film finished or was skipped: never again this season (saved now).
static func mark_seen(sid: String) -> void:
	var seen: Variant = Save.data.get("season_film_seen", [])
	var list: Array = (seen as Array).duplicate() if seen is Array else []
	if not list.has(sid):
		list.append(sid)
	Save.data["season_film_seen"] = list
	Save.save_now()


static func _note_failure(sid: String) -> void:
	var f: Variant = Save.data.get("season_film_fails", {})
	var d: Dictionary = (f as Dictionary).duplicate() if f is Dictionary else {}
	d[sid] = int(d.get(sid, 0)) + 1
	Save.data["season_film_fails"] = d
	Save.save_now()


# ---------------------------------------------------------------- setup
func _init(sid: String = "") -> void:
	season = sid if sid != "" else Catalogue.current_season_id()
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "SeasonPremiere"


func _enter_tree() -> void:
	active = true
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
		active = false


func _ready() -> void:
	bg = ColorRect.new()
	bg.name = "Backdrop"
	# the curtain's own black: the bars around the picture continue it
	bg.color = Brand.STARTUP_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var stream: Variant = load(film_path(season)) if ResourceLoader.exists(film_path(season)) else null
	if not stream is VideoStream:
		fail("missing")
		return
	video = VideoStreamPlayer.new()
	video.name = "Film"
	video.stream = stream
	video.expand = true
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.volume_db = -80.0
	video.bus = "Master"
	bg.add_child(video)
	video.finished.connect(func() -> void:
		# a file that runs out early (damaged) is a failure, not "watched"
		# (the decoder measures a cut-short file by its own end: compare with
		# the authored length instead)
		if _last_pos < FILM_S - 1.5:
			fail("ended_early")
		else:
			finish("natural"))
	hint = SkipHint.new()
	hint.name = "HoldToSkip"
	hint.modulate.a = 0.0
	bg.add_child(hint)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_gain = film_gain()
	# decode the first frame now (silently); it is held at 0:00 until shown
	video.play()


## The film's loudness: the soundtrack follows the louder of the music and
## effects settings (the Master volume applies on top, through its bus).
static func film_gain() -> float:
	return clampf(maxf(float(Save.get_setting("music", 0.6)), float(Save.get_setting("sfx", 0.9))), 0.0, 1.0)


## The picture: as large as fits, centred, never cropped (the end card stays
## whole on every phone and iPad).
func _layout() -> void:
	if not is_instance_valid(video):
		return
	var vs := get_viewport().get_visible_rect().size
	var s := minf(vs.x / FILM_SIZE.x, vs.y / FILM_SIZE.y)
	var sz := (FILM_SIZE * s).round()
	video.position = ((vs - sz) * 0.5).round()
	video.size = sz
	if is_instance_valid(hint):
		var safe := UIKit.safe_rect(get_viewport(), vs)
		hint.place(safe)


## True once the first frame is decoded and held (the curtain's gate).
func frame_ready() -> bool:
	return state == State.READY or (state != State.PREPARING and _decoded)


## The curtain is going: start the film from its first frame, with sound.
func begin() -> void:
	if state != State.READY:
		return
	state = State.PLAYING
	_play_t = 0.0
	_last_pos = 0.0
	_stalled = 0.0
	video.volume_db = linear_to_db(maxf(_gain, 0.0001)) if _gain > 0.001 else -80.0
	video.paused = _focus_paused
	Diag.mark("premiere_play")


## The curtain gave up waiting (no first frame in time): no film.
func abandon() -> void:
	if state == State.PREPARING or state == State.READY:
		fail("first_frame")


func _process(delta: float) -> void:
	_t += delta
	match state:
		State.PREPARING:
			_prep_t += delta
			if video and video.is_playing() and video.stream_position > 0.0:
				# decoded: hold it at the start, silent
				video.paused = true
				video.stream_position = 0.0
				_decoded = true
				state = State.READY
			elif video == null or (_prep_t > 0.4 and not video.is_playing()):
				fail("decode")        # the decoder gave up: don't wait for it
			elif _prep_t > NO_FRAME_S:
				fail("first_frame")
		State.PLAYING:
			if video.paused:
				return
			_play_t += delta
			var pos := video.stream_position
			if pos > _last_pos + 0.0001:
				_last_pos = pos
				_stalled = 0.0
			else:
				_stalled += delta
				if _stalled > STALL_S:
					fail("stall" if video.is_playing() else "stopped")
					return
			if pos >= TITLE_CARD_S:
				if hint.shown and holder == "" and not hint.gone:
					hint.leave()
			elif _play_t >= HINT_DELAY_S and hint.modulate.a < 0.01 and not hint.shown:
				hint.show_hint()
			if holder != "":
				hold += delta / HOLD_S
				hint.progress = clampf(hold, 0.0, 1.0)
				if hold >= 1.0:
					finish("skipped")
		State.ENDING:
			pass


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if state == State.DONE:
		return
	get_viewport().set_input_as_handled()   # nothing beneath sees anything
	if state != State.PLAYING or video.paused:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var key := "touch:%d" % t.index
		if t.pressed:
			if holder == "" and hint.shown and not hint.gone and hint.target().has_point(t.position):
				_start_hold(key)
			elif not hint.shown and _play_t >= 0.3 and video.stream_position < TITLE_CARD_S:
				hint.show_hint()   # a tap wakes the hint early; it never skips
		elif holder == key:
			cancel_hold()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if holder == "touch:%d" % d.index and not hint.target().grow(24.0).has_point(d.position):
			cancel_hold()   # slid off the button
	elif event is InputEventKey or event is InputEventJoypadButton:
		for action in ["jump", "ui_accept"]:
			if event.is_action(action):
				if event.is_pressed() and not event.is_echo():
					if hint.gone:
						return
					if not hint.shown:
						hint.show_hint()
					if holder == "":
						_start_hold("key:" + action)
				elif not event.is_pressed() and holder == "key:" + action:
					cancel_hold()
				return


func _start_hold(key: String) -> void:
	holder = key
	hold = 0.0
	hint.holding = true
	Haptics.tick()


func cancel_hold() -> void:
	if holder == "":
		return
	holder = ""
	hold = 0.0
	hint.holding = false
	hint.release()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focus_paused = true
			cancel_hold()
			if is_instance_valid(video) and state == State.PLAYING:
				video.paused = true
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_focus_paused = false
			if is_instance_valid(video) and state == State.PLAYING:
				# the same player carries on from where it stopped
				_stalled = 0.0
				video.paused = false


# ---------------------------------------------------------------- the end
## Natural end or a completed hold: once.  Saves "seen" at once, then fades
## the picture and the sound together onto the destination.
func finish(why: String) -> void:
	if state == State.ENDING or state == State.DONE:
		return
	var swallow := holder if why == "skipped" else ""
	state = State.ENDING
	how = why
	SeasonPremiere.mark_seen(season)
	Diag.mark("premiere_" + why)
	holder = ""
	if swallow != "":
		InputSwallow.until_release(get_tree(), swallow)
	Controls.clear_edges()
	hint.leave()
	ending.emit(why)
	_fade_out(FADE_S)


## The film can't be shown (missing, no first frame, stalled): release the
## player and get out of the way at once.
func fail(why: String) -> void:
	if state == State.ENDING or state == State.DONE:
		return
	var was_preparing := state == State.PREPARING or state == State.READY
	state = State.ENDING
	how = "failed"
	push_warning("Season film not shown (%s)" % why)
	Diag.mark("premiere_failed_" + why)
	if why != "missing":
		SeasonPremiere._note_failure(season)
	holder = ""
	if is_instance_valid(video):
		video.stop()
		video.queue_free()
		video = null
	if is_instance_valid(hint):
		hint.visible = false
	ending.emit("failed")
	# under the curtain nothing is visible yet: go now; on screen, a short fade
	_fade_out(0.0 if was_preparing else 0.2)


func _fade_out(dur: float) -> void:
	if dur <= 0.0 or not is_inside_tree():
		_done()
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bg, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_set_fade, 1.0, 0.0, dur)
	tw.chain().tween_callback(_done)


func _set_fade(v: float) -> void:
	_fade = v
	if is_instance_valid(video):
		var g := _gain * v
		video.volume_db = linear_to_db(g) if g > 0.0001 else -80.0


func _done() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	if is_instance_valid(video):
		video.stop()
	active = false
	ended.emit(how)
	queue_free()


# ---------------------------------------------------------------- the hint
## "Hold to skip": a quiet pill in the lower-right safe corner with a ring
## that fills while held; the device's button glyph on controller/keyboard.
class SkipHint:
	extends Control
	const H := 44.0
	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()
	var holding := false:
		set(v):
			holding = v
			queue_redraw()
	var shown := false
	var _safe := Rect2()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		Controls.device_changed.connect(func(_k: String) -> void: _resize())

	func _exit_tree() -> void:
		for c in Controls.device_changed.get_connections():
			if (c["callable"] as Callable).get_object() == self:
				Controls.device_changed.disconnect(c["callable"])

	func label() -> String:
		return "Hold to skip"

	func _resize() -> void:
		var f := UIKit.font_w(700)
		var tw := f.get_string_size(label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var g := Glyphs.width("jump", 30.0)
		size = Vector2(H + 12.0 + tw + (g + 10.0 if g > 0.0 else 0.0) + 22.0, H + 12.0)
		if _safe.size != Vector2.ZERO:
			place(_safe)
		queue_redraw()

	## Lower-right of the safe area, clear of the home indicator.
	func place(safe: Rect2) -> void:
		_safe = safe
		if size.x < 2.0:
			_resize()
			return
		position = (safe.end - size - Vector2(UIKit.EDGE_X * 0.6, UIKit.EDGE_Y + 6.0)).round()
		pivot_offset = size * 0.5

	## The touch target: the pill grown to a generous 64 pt-ish area.
	func target() -> Rect2:
		var r := get_global_rect()
		var grow := maxf(0.0, (UIKit.touch_min() * 1.45 - r.size.y) * 0.5)
		return r.grow_individual(grow + 12.0, grow, grow, grow)

	func show_hint() -> void:
		if shown:
			return
		shown = true
		if UIKit.reduced_motion():
			Motion.animate(self, "modulate:a", 0.85, 0.2)
		else:
			Motion.animate(self, "modulate:a", 0.85, 0.35, Tween.TRANS_QUAD, Tween.EASE_OUT)

	func release() -> void:
		# the ring drains back quickly instead of snapping
		Motion.animate(self, "progress", 0.0, 0.18)

	var gone := false

	func leave() -> void:
		gone = true
		Motion.animate(self, "modulate:a", 0.0, 0.25)

	func _draw() -> void:
		var r := Rect2(Vector2(0, 6), Vector2(size.x, H))
		var sb := UIKit.box(Color(UIKit.NAVY, 0.55 if not holding else 0.72), int(H * 0.5), 1, Color(UIKit.IVORY, 0.18), 0)
		draw_style_box(sb, r)
		var c := Vector2(r.position.x + H * 0.5 + 2.0, r.get_center().y)
		var rad := H * 0.3
		draw_arc(c, rad, 0.0, TAU, 32, Color(UIKit.IVORY, 0.28), 3.0, true)
		if progress > 0.001:
			draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, UIKit.AMBER, 3.5, true)
		# a small "skip" mark: two chevrons
		var ink := Color(UIKit.IVORY, 0.9)
		for i in 2:
			var o := Vector2(-4.0 + 6.0 * float(i), 0.0)
			draw_polyline(PackedVector2Array([c + o + Vector2(-2.5, -5.0), c + o + Vector2(2.5, 0.0), c + o + Vector2(-2.5, 5.0)]), ink, 2.0, true)
		var x := c.x + rad + 14.0
		var g := Glyphs.draw(self, "jump", Vector2(x, r.get_center().y), 30.0, 0.95)
		if g > 0.0:
			x += g + 10.0
		var f := UIKit.font_w(700)
		draw_string(f, Vector2(x, r.get_center().y + 7.0), label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)


# ---------------------------------------------------------------- swallow
## Eats one held input (a finger, or an action's key / button) until it is
## released, then goes: the hold that skipped the film never reaches the
## screen that appears under it.
class InputSwallow:
	extends Node
	var key := ""

	static func until_release(tree: SceneTree, k: String) -> void:
		var s := InputSwallow.new()
		s.key = k
		s.name = "PremiereSwallow"
		s.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(s)

	func _input(event: InputEvent) -> void:
		if key.begins_with("touch:"):
			var idx := int(key.get_slice(":", 1))
			if (event is InputEventScreenTouch and (event as InputEventScreenTouch).index == idx) \
					or (event is InputEventScreenDrag and (event as InputEventScreenDrag).index == idx) \
					or event is InputEventMouseButton or event is InputEventMouseMotion:
				get_viewport().set_input_as_handled()
				if event is InputEventScreenTouch and not event.is_pressed():
					_end()
		else:
			var action := key.get_slice(":", 1)
			if event.is_action(action) or event.is_action("ui_accept") or event.is_action("jump"):
				get_viewport().set_input_as_handled()
				if not event.is_pressed():
					_end()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
			_end()

	func _end() -> void:
		Controls.clear_edges()
		queue_free()
