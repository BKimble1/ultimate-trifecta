extends RefCounted
## Lobby music ("Night Campus Loop", music_menu.ogg): an intro, then a 12-bar
## loop that the mixer wraps sample for sample (no gap, no click). One track
## runs on through home, wardrobe and settings without restarting, fades out
## when a round starts and back in afterwards, follows the music volume and
## mute, holds its place in the background, and never doubles up.
var t

const SR := 44100


func _menu_stream() -> AudioStreamOggVorbis:
	return load("res://assets/audio/music_menu.ogg") as AudioStreamOggVorbis


func _render(pb: AudioStreamPlayback, frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	while out.size() < frames:
		out.append_array(pb.mix_audio(1.0, mini(4096, frames - out.size())))
	return out


func _max_d2(buf: PackedVector2Array, from: int, to: int) -> float:
	var m := 0.0
	for i in range(maxi(from, 2), mini(to, buf.size())):
		var d := (buf[i] + buf[i - 2] - buf[i - 1] * 2.0)
		m = maxf(m, maxf(absf(d.x), absf(d.y)))
	return m


func _playback_id() -> int:
	var pb: AudioStreamPlayback = Sfx._music.player.get_stream_playback()
	return pb.get_instance_id() if pb else 0


## Fades as the game runs them, without waiting real time.
func _step(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		Sfx._process(1.0 / 60.0)


func _voices_holding(track: String) -> int:
	var n := 0
	for v: Variant in [Sfx._music, Sfx._music_out]:
		if v.track == track:
			n += 1
	return n


## From silence at the default levels, whatever this machine has saved.
func _begin() -> void:
	Sfx._resume_music()
	Sfx.stop_music()
	Sfx.set_volumes(0.9, 0.6)


func _reset() -> void:
	Sfx._resume_music()
	Sfx.stop_music()
	Save._apply_settings()


func test_lobby_track_loops_sample_for_sample() -> void:
	var s := _menu_stream()
	t.check(s != null, "music_menu.ogg imports as Ogg Vorbis")
	if s == null:
		return
	t.check(s.loop, "imported as a loop")
	t.near(s.loop_offset, 20.3274, 0.001, "the loop starts after the intro (bar 4 of the main section)")
	t.near(s.get_length(), 54.613, 0.01, "intro + one 12-bar loop")
	t.eq(s.bpm, 0.0, "no beat-count looping (the file end is the loop end)")
	var lap := int(round(s.get_length() * SR)) - int(s.loop_offset * SR)
	t.eq(lap, 12 * 126000 - 4, "the loop is 12 bars at 84 BPM")
	var pb := s.instantiate_playback()
	pb.start(s.loop_offset)
	var buf := _render(pb, lap + SR)
	var worst := 0.0
	# from frame 2: a fresh start() opens with two silent frames (the mixer's
	# resampler warming up); a wrap doesn't, so the lap is exact from there on
	for i in range(2, SR):
		var d := buf[lap + i] - buf[i]
		worst = maxf(worst, maxf(absf(d.x), absf(d.y)))
	t.check(worst < 1e-6, "one lap later the mixer plays the loop start again, sample for sample (max diff %s)" % str(worst))
	t.eq(pb.get_loop_count(), 1, "by looping the stream (not a restart)")
	var quiet := 0
	var longest := 0
	for i in range(lap - SR / 4, lap + SR / 4):
		quiet = quiet + 1 if maxf(absf(buf[i].x), absf(buf[i].y)) < 1e-5 else 0
		longest = maxi(longest, quiet)
	t.check(longest < 8, "no gap at the wrap (longest near-silent run %d samples)" % longest)
	var at_wrap := _max_d2(buf, lap - 512, lap + 512)
	var music := _max_d2(buf, lap - 10 * SR, lap - SR)
	t.check(at_wrap <= music, "no click at the wrap (edge %.4f, the music itself %.4f)" % [at_wrap, music])


func test_one_track_runs_on_through_home_wardrobe_and_settings() -> void:
	var was_onboarded: Variant = Save.data.get("onboarded", false)
	Save.data["onboarded"] = true
	_begin()
	App.goto_title()
	await t.get_tree().process_frame
	t.eq(Sfx.current_music(), "menu", "home plays the lobby music")
	t.check(Sfx._music.rate > 0.0 and Sfx._music.level < 1.0, "fading in")
	var id := _playback_id()
	var player: AudioStreamPlayer = Sfx._music.player
	App.goto(CreatorScreen)
	await t.get_tree().process_frame
	App.goto(SettingsScreen)
	await t.get_tree().process_frame
	App.goto_title()
	Sfx.music("menu")          # what the party room does on entry
	await t.get_tree().process_frame
	t.eq(Sfx.current_music(), "menu", "still the lobby music")
	t.check(Sfx._music.player == player and _playback_id() == id, "the same playback, never restarted")
	t.eq(_voices_holding("menu"), 1, "on one player")
	_reset()
	Save.data["onboarded"] = was_onboarded


func test_a_round_fades_the_lobby_out_and_it_comes_back() -> void:
	MatchController.drop_campus_cache()
	var was_onboarded: Variant = Save.data.get("onboarded", false)
	Save.data["onboarded"] = true
	_begin()
	App.goto_title()
	_step(3.0)
	App.start_practice("runner", false)
	await t.get_tree().process_frame
	var mc := App.match_ctrl
	t.check(mc != null, "practice starts")
	if mc == null:
		return
	t.eq(Sfx.current_music(), "menu", "the lobby music carries on while the round prepares")
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(mc) and not mc.prepared and Time.get_ticks_msec() - t0 < 60000:
		await t.get_tree().process_frame
	t.check(is_instance_valid(mc) and mc.prepared, "prepared")
	t.eq(Sfx.current_music(), "chase_calm", "the round's music takes over")
	t.check(Sfx._music_out.track == "menu" and Sfx._music_out.rate < 0.0, "the lobby music fades out under it")
	_step(Sfx.fade_out_time("menu") + 0.1)
	t.eq(_voices_holding("menu"), 0, "and is gone once faded")
	# back to the lobby: the track starts again from its intro, fading in
	App._close_session(false)
	App._end_match_scene()
	App.goto_title()
	await t.get_tree().process_frame
	t.eq(Sfx.current_music(), "menu", "the lobby music returns")
	t.check(Sfx._music.level < 0.2 and Sfx._music.rate > 0.0, "fading in")
	t.check(Sfx._music_out.track == "chase_calm" and Sfx._music_out.rate < 0.0, "under the round's music fading out")
	t.near(Sfx.fade_out_time("chase_calm"), 0.4, 0.001, "which clears quickly (as for the results sting)")
	var vols: Array[float] = []
	for i in 5:
		_step(0.5)
		vols.append(Sfx._music.player.volume_db)
	t.check(vols[0] < vols[1] and vols[1] < vols[2] and vols[2] < vols[3], "rising smoothly %s" % [vols])
	t.near(Sfx._music.level, 1.0, 0.001, "to full level")
	# a round left within the fade brings the same playback back, no restart
	App.start_practice("runner", false)
	await t.get_tree().process_frame
	var mc2 := App.match_ctrl
	t0 = Time.get_ticks_msec()
	while is_instance_valid(mc2) and not mc2.prepared and Time.get_ticks_msec() - t0 < 60000:
		await t.get_tree().process_frame
	var fading_id: int = Sfx._music_out.player.get_stream_playback().get_instance_id() \
			if Sfx._music_out.track == "menu" else 0
	App._close_session(false)
	App._end_match_scene()
	App.goto_title()
	t.check(fading_id != 0 and _playback_id() == fading_id, "a quick return picks the lobby music up where it is")
	t.eq(_voices_holding("menu"), 1, "on one player")
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	_reset()
	Save.data["onboarded"] = was_onboarded


func test_music_volume_and_mute_are_respected() -> void:
	_begin()
	Sfx.music("menu")
	_step(3.0)
	var id := _playback_id()
	Sfx.set_volumes(0.9, 0.6)
	t.near(Sfx._music.player.volume_db, linear_to_db(0.6) - 6.0, 0.01, "the music setting sets the level")
	Sfx.set_volumes(0.9, 0.0)
	t.check(Sfx._music.player.stream_paused, "muted music holds its place (not decoding silence)")
	t.eq(Sfx.current_music(), "menu", "and is still the lobby music")
	Sfx.music("menu")
	t.eq(_voices_holding("menu"), 1, "asking again while muted adds nothing")
	Sfx.set_volumes(0.9, 0.3)
	t.check(not Sfx._music.player.stream_paused and _playback_id() == id, "unmuted, the same playback continues")
	t.near(Sfx._music.player.volume_db, linear_to_db(0.3) - 6.0, 0.01, "at the new level")
	t.near(Sfx.sfx_volume, 0.9, 0.0001, "sound effects keep their own level")
	_reset()


func test_backgrounding_and_interruptions_hold_and_resume() -> void:
	_begin()
	Sfx.music("menu")
	_step(3.0)
	var id := _playback_id()
	Sfx.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)    # call, Siri, Control Center
	Sfx.notification(Node.NOTIFICATION_APPLICATION_PAUSED)       # then the background
	t.check(Sfx._music.player.stream_paused, "the music holds while the app is away")
	_step(2.0)
	t.near(Sfx._music.level, 1.0, 0.001, "nothing moves while away")
	Sfx.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	t.check(not Sfx._music.player.stream_paused and _playback_id() == id, "back: the same playback continues")
	t.check(Sfx._music.level == 0.0 and Sfx._music.rate > 0.0, "fading back in, not at full volume at once")
	Sfx.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(Sfx._music.level == 0.0, "focus after resume doesn't start the fade again")
	_step(Sfx.MUSIC_RESUME_FADE + 0.05)
	t.near(Sfx._music.level, 1.0, 0.001, "back to full")
	# interrupted mid cross-fade: the outgoing track just ends
	Sfx.music("chase_calm")
	_step(0.3)
	Sfx.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.eq(_voices_holding("menu"), 0, "an interrupted fade-out finishes")
	t.check(Sfx._music.player.stream_paused, "the new track holds")
	Sfx.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(not Sfx._music.player.stream_paused and Sfx.current_music() == "chase_calm", "and resumes")
	# muted, then away and back: still muted
	Sfx.set_volumes(0.9, 0.0)
	Sfx.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	Sfx.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(Sfx._music.player.stream_paused, "mute outlasts a trip to the background")
	_reset()


func test_rapid_switches_never_double_up() -> void:
	_begin()
	var players := 0
	for c in Sfx.get_children():
		if c is AudioStreamPlayer:
			players += 1
	for name: String in ["menu", "menu", "chase_calm", "menu", "results", "menu", "chase_calm", "chase_calm", "menu"]:
		Sfx.music(name)
		_step(0.2)
	var after := 0
	var sounding := 0
	for c in Sfx.get_children():
		if c is AudioStreamPlayer:
			after += 1
	for v: Variant in [Sfx._music, Sfx._music_out]:
		if v.sounding():
			sounding += 1
	t.eq(after, players, "no players are created by switching")
	t.check(sounding <= 2, "at most the current track and one fading out")
	t.eq(_voices_holding("menu"), 1, "the lobby music on one player")
	t.eq(Sfx.current_music(), "menu", "and it is the current track")
	_reset()
