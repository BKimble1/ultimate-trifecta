extends RefCounted
## (build 23) The season premiere (SeasonPremiere) and first-run setup:
## once per season per profile, independent of onboarding; seen only at the
## end (natural or a completed hold), exactly once; the destination built in
## silence under the film; hold to skip; failures fall through to the game;
## setup finishes only through "Enter the dorm".
var t

var _data: Dictionary
var _path := ""
const TMP := "user://test_premiere_profile.json"


func _begin() -> void:
	_data = Save.data.duplicate(true)
	_path = Save.path
	Save.path = TMP   # nothing here touches the real profile file


func _end() -> void:
	for n in t.get_tree().root.get_children():
		if n is SeasonPremiere or n.name == "PremiereSwallow":
			n.free()
	SeasonPremiere.active = false
	SeasonPremiere.current = null
	SeasonPremiere.films.erase("s2")
	Save.data = _data
	Save.path = _path
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	await t.get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _premiere() -> SeasonPremiere:
	var p := SeasonPremiere.new("s1")
	t.get_tree().root.add_child(p)
	return p


func _until(p: SeasonPremiere, st: int, frames: int = 240) -> void:
	for i in frames:
		if not is_instance_valid(p) or p.state >= st:
			return
		await t.get_tree().process_frame


func _on_disk() -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(TMP))
	return v if v is Dictionary else {}


## A save from before the premiere (no film fields) is eligible, whatever
## its onboarding; the migration adds empty fields.
func test_upgraded_save_is_eligible() -> void:
	_begin()
	var old := Save.default_profile()
	old.erase("season_film_seen")
	old.erase("season_film_fails")
	old["onboarded"] = true
	old["version"] = 3
	Save.data = Save.migrate(old)
	t.eq(Save.data["season_film_seen"], [], "migrated with an empty seen list")
	t.check(bool(Save.data["onboarded"]), "onboarding kept")
	t.check(SeasonPremiere.eligible("s1"), "an existing player who hasn't seen Season 1 gets the film")
	t.check(SeasonPremiere.film_exists("s1"), "the Season 1 film is in the app")
	await _end()


## Seen is per season: Season 1 watched, Season 2 still due (once its film
## ships); a film that isn't in the app is never due.
func test_season_rollover() -> void:
	_begin()
	Save.data["season_film_seen"] = ["s1"]
	t.check(not SeasonPremiere.eligible("s1"), "Season 1 seen")
	t.check(SeasonPremiere.eligible("s2"), "a new season is unseen")
	t.check(not SeasonPremiere.film_exists("s2"), "no Season 2 film shipped")
	SeasonPremiere.films["s2"] = SeasonPremiere.films["s1"]
	t.check(SeasonPremiere.film_exists("s2") and SeasonPremiere.eligible("s2"), "once it ships, the new season's film plays")
	SeasonPremiere.mark_seen("s2")
	t.eq(Save.data["season_film_seen"], ["s1", "s2"], "each season remembered")
	await _end()


## Watched but setup not finished (the app closed in between): the next
## launch goes to setup, without the film; goto_title never starts a film.
func test_interrupted_setup_reopens_setup_without_the_film() -> void:
	_begin()
	Save.data["onboarded"] = false
	Save.data["season_film_seen"] = ["s1"]
	t.check(not SeasonPremiere.eligible("s1"), "film already seen")
	App.goto_title()
	await _frames(2)
	t.check(App.screen is CreatorScreen and (App.screen as CreatorScreen).first_run, "setup again")
	t.check(not (App.screen as CreatorScreen).await_reveal, "shown at once (no film to wait for)")
	t.check(not SeasonPremiere.active, "no film")
	# normal navigation never plays it either, even when unseen
	Save.data["season_film_seen"] = []
	Save.data["onboarded"] = true
	App.goto_title()
	await _frames(2)
	t.check(not SeasonPremiere.active, "returning home doesn't start the film")
	await _end()


## The film decodes its first frame silently and holds it at 0:00; nothing
## is marked seen until the end; a completed skip saves at once; a second
## end (natural racing the skip) or a failure after it does nothing.
func test_skip_racing_natural_end_runs_once() -> void:
	_begin()
	Save.data["season_film_seen"] = []
	var p := _premiere()
	var endings: Array = []
	var ends: Array = []
	p.ending.connect(func(how: String) -> void: endings.append(how))
	p.ended.connect(func(how: String) -> void: ends.append(how))
	await _until(p, SeasonPremiere.State.READY)
	t.eq(p.state, SeasonPremiere.State.READY, "first frame ready")
	t.check(p.video.paused and is_equal_approx(p.video.stream_position, 0.0), "held at 0:00")
	t.check(p.video.volume_db <= -79.0, "silent until shown")
	t.check(not SeasonPremiere.has_seen("s1"), "not seen when prepared")
	p.begin()
	await _frames(5)
	t.check(not p.video.paused, "playing")
	t.check(not SeasonPremiere.has_seen("s1"), "not seen while playing")
	t.check(SeasonPremiere.holds_audio(), "the game's music waits")
	p.finish("skipped")
	t.check(SeasonPremiere.has_seen("s1"), "seen at the skip")
	t.eq(_on_disk().get("season_film_seen"), ["s1"], "saved to disk immediately")
	t.check(not SeasonPremiere.holds_audio(), "music may start as the film fades")
	p.finish("natural")
	p.fail("stall")
	await _frames(40)
	t.eq(endings, ["skipped"], "one ending")
	t.eq(ends, ["skipped"], "one exit")
	t.check(not is_instance_valid(p) or not p.is_inside_tree(), "the layer has gone")
	t.check(not SeasonPremiere.active, "no film any more")
	await _end()


## Natural playback to the end marks it seen (the end of the real film).
func test_natural_end_marks_seen() -> void:
	_begin()
	Save.data["season_film_seen"] = []
	var p := _premiere()
	await _until(p, SeasonPremiere.State.READY)
	p.begin()
	p.video.stream_position = SeasonPremiere.FILM_S - 0.4
	p._last_pos = SeasonPremiere.FILM_S - 0.4
	await _until(p, SeasonPremiere.State.ENDING, 600)
	t.eq(p.how if is_instance_valid(p) else "natural", "natural", "it ran out on its own")
	t.check(SeasonPremiere.has_seen("s1"), "seen")
	await _end()


## Hold to skip: a tap or an early release does nothing; a full hold skips
## and the finger is swallowed until it lifts; nothing reaches the screen.
func test_hold_to_skip() -> void:
	_begin()
	Save.data["season_film_seen"] = []
	var p := _premiere()
	await _until(p, SeasonPremiere.State.READY)
	p.begin()
	p.hint.show_hint()
	await _frames(2)
	var at: Vector2 = p.hint.target().get_center()
	var down := InputEventScreenTouch.new()
	down.position = at
	down.pressed = true
	var up := InputEventScreenTouch.new()
	up.position = at
	p._input(down)
	await _frames(2)
	p._input(up)
	t.eq(p.holder, "", "a tap lets go")
	t.eq(p.state, SeasonPremiere.State.PLAYING, "a tap doesn't skip")
	p._input(down)
	p.hold = 0.5
	p._input(up)
	t.eq(p.hold, 0.0, "an early release drains the ring")
	t.eq(p.state, SeasonPremiere.State.PLAYING, "an early release doesn't skip")
	p._input(down)
	var drag := InputEventScreenDrag.new()
	drag.position = at + Vector2(0, -400)
	p._input(drag)
	t.eq(p.holder, "", "sliding off cancels")
	p._input(down)
	p.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.eq(p.holder, "", "losing focus cancels")
	t.check(p.video.paused, "and pauses the film")
	p.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(not p.video.paused, "focus back: the same film carries on")
	t.eq(p.find_children("*", "VideoStreamPlayer", true, false).size(), 1, "one player")
	p._input(down)
	for i in 120:
		await t.get_tree().process_frame
		if p.state != SeasonPremiere.State.PLAYING:
			break
	t.eq(p.state, SeasonPremiere.State.ENDING, "a full hold skips")
	t.eq(p.how, "skipped", "skipped")
	t.check(t.get_tree().root.has_node("PremiereSwallow"), "the held finger is swallowed")
	var sw: Node = t.get_tree().root.get_node("PremiereSwallow")
	sw._input(up)
	await _frames(2)
	t.check(not t.get_tree().root.has_node("PremiereSwallow"), "until it lifts")
	await _end()


## A film that can't play is released and gets out of the way; nothing is
## marked seen, and repeated failures stop it being tried.
func test_failure_releases_the_player() -> void:
	_begin()
	Save.data["season_film_seen"] = []
	Save.data["season_film_fails"] = {}
	var p := _premiere()
	var ends: Array = []
	p.ended.connect(func(how: String) -> void: ends.append(how))
	await _until(p, SeasonPremiere.State.READY)
	p.begin()
	await _frames(3)
	p.fail("stall")
	t.check(p.video == null, "the player is released")
	await _frames(30)
	t.eq(ends, ["failed"], "it ends as failed")
	t.check(not SeasonPremiere.has_seen("s1"), "not marked seen")
	t.eq(SeasonPremiere.failures("s1"), 1, "the failure is counted")
	t.check(SeasonPremiere.eligible("s1"), "tried again next launch")
	Save.data["season_film_fails"] = {"s1": SeasonPremiere.MAX_FAILS}
	t.check(not SeasonPremiere.eligible("s1"), "not after repeated failures")
	await _end()


## While the film has the soundtrack the game's music and sounds wait.
func test_music_waits_for_the_film() -> void:
	_begin()
	Save.data["season_film_seen"] = []
	Sfx.stop_music()
	var p := _premiere()
	await _until(p, SeasonPremiere.State.READY)
	Sfx.music("menu")
	t.eq(Sfx.current_music(), "", "no lobby music under the film")
	p.begin()
	p.finish("skipped")
	Sfx.music("menu")
	t.eq(Sfx.current_music(), "menu", "the lobby track starts as the film fades")
	Sfx.stop_music()
	await _end()


## First-run setup: look, then name; Back keeps both drafts; only "Enter
## the dorm" finishes onboarding.
func test_setup_finishes_only_on_enter_the_dorm() -> void:
	_begin()
	Save.data["onboarded"] = false
	Save.data["season_film_seen"] = ["s1"]
	App.goto_title()
	await _frames(2)
	var c := App.screen as CreatorScreen
	t.check(c != null and c.first_run, "setup")
	t.eq(c.setup_step, "look", "starts on the look")
	t.check(c.continue_btn.visible and c.surprise_btn.visible, "Continue and Surprise me")
	t.check(not c.has_node("NavBar"), "no Locker navigation")
	c._pick("outfit", "swim")
	t.eq(String(c.draft["outfit"]), "swim", "a pick changes the runner at once")
	t.eq(String(Save.data["cosmetic"]["outfit"]), String(Cosmetics.DEFAULT["outfit"]), "not saved yet")
	c.show_name_step()
	t.eq(c.setup_step, "name", "then the name")
	t.check(c.name_form.visible and not c.continue_btn.is_visible_in_tree(), "the name step replaces the look's controls")
	t.check(c.name_form.field.text != "", "the generated name is filled in")
	c.name_form.field.text = "Moon Pip"
	c.name_form._on_text("Moon Pip")
	c.name_form.cancel_sheet()
	t.eq(c.setup_step, "look", "Back returns to the look")
	t.eq(String(c.draft["outfit"]), "swim", "look draft kept")
	t.eq(c.name_form.field.text, "Moon Pip", "name draft kept")
	t.check(not bool(Save.data["onboarded"]), "Back doesn't finish setup")
	c.show_name_step()
	c.name_form._save()
	await _frames(3)
	t.check(bool(Save.data["onboarded"]), "Enter the dorm finishes setup")
	t.eq(String(Save.data["name"]), "Moon Pip", "name saved")
	t.eq(String(Save.data["cosmetic"]["outfit"]), "swim", "look saved")
	t.check(App.screen is LobbyScreen, "into the party lobby")
	await _end()


## Behind the film the setup controls wait; the reveal brings them in a beat
## after the runner, and nothing is pressable before.
func test_setup_waits_for_the_reveal() -> void:
	_begin()
	Save.data["onboarded"] = false
	var c := CreatorScreen.new()
	c.first_run = true
	c.await_reveal = true
	App._ensure_background()
	App._show(c)
	await _frames(2)
	t.check(c.setup_panel.modulate.a < 0.01, "controls hidden behind the film")
	t.check(c.has_node("RevealBlocker"), "and not pressable")
	c.reveal_after_film(0.0)
	await t.get_tree().create_timer(0.9).timeout
	t.check(c.setup_panel.modulate.a > 0.95, "then shown")
	t.check(not c.has_node("RevealBlocker"), "and pressable")
	await _end()
