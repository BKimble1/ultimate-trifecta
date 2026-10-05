extends RefCounted
## Pass 9 round music ("Soft Bounce Loop", music_match.ogg) and the lobby ->
## round blend: an intro, then a 16-bar loop at 100 BPM that the mixer wraps
## sample for sample (no gap, no click); level-matched to the lobby track; the
## round's music starts on a beat of the lobby music and fades in over two of
## its beats while the lobby music fades out under a closing low-pass filter;
## the filter opens again whenever a voice is reused or brought back.
var t

const SR := 44100
const BEAT := 26460          # 100 BPM
const BAR := 4 * BEAT


func _stream() -> AudioStreamOggVorbis:
	return load("res://assets/audio/music_match.ogg") as AudioStreamOggVorbis


func _render(pb: AudioStreamPlayback, frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var sizes := [127, 2048, 511, 1024, 333]
	var i := 0
	while out.size() < frames:
		out.append_array(pb.mix_audio(1.0, mini(int(sizes[i % sizes.size()]), frames - out.size())))
		i += 1
	return out


func _step(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		Sfx._process(1.0 / 60.0)


func _begin() -> void:
	Sfx._resume_music()
	Sfx.stop_music()
	Sfx.set_volumes(0.9, 0.6)


func _reset() -> void:
	Sfx._resume_music()
	Sfx.stop_music()
	Save._apply_settings()


func _rms_db(buf: PackedVector2Array, from: int, to: int) -> float:
	var s := 0.0
	for i in range(from, to):
		s += buf[i].x * buf[i].x + buf[i].y * buf[i].y
	return 10.0 * log(s / (2.0 * float(to - from)) + 1e-20) / log(10.0)


func test_round_track_loops_sample_for_sample() -> void:
	var s := _stream()
	t.check(s != null, "music_match.ogg imports as Ogg Vorbis")
	if s == null:
		return
	t.check(s.loop, "imported as a loop")
	t.near(s.loop_offset, 12.6, 0.001, "the loop starts after the intro (bar 5's downbeat)")
	t.near(s.get_length(), 51.0, 0.01, "intro + one 16-bar loop")
	var lap := int(round(s.get_length() * SR)) - int(s.loop_offset * SR)
	t.eq(lap, 16 * BAR, "the loop is 16 bars at 100 BPM")
	var pb := s.instantiate_playback()
	pb.start(s.loop_offset)
	var buf := _render(pb, lap + 2 * SR)
	# a fresh start() opens with two silent frames (the resampler warming up);
	# a wrap doesn't: from frame 2 one lap later is the same sample
	var worst := 0.0
	for i in range(2, SR):
		var dd := buf[lap + i] - buf[i]
		worst = maxf(worst, maxf(absf(dd.x), absf(dd.y)))
	t.check(worst < 1e-6, "one lap later the mixer plays the loop start again, sample for sample (max diff %s)" % str(worst))
	t.eq(pb.get_loop_count(), 1, "by looping the stream (not a restart)")
	# across the wrap: no gap and no click
	var w := lap + 2
	var max_d2 := 0.0
	for i in range(w - 441, w + 441):
		var d := buf[i] + buf[i - 2] - buf[i - 1] * 2.0
		max_d2 = maxf(max_d2, maxf(absf(d.x), absf(d.y)))
	var music_d2 := 0.0
	for i in range(lap - 10 * SR, lap - SR):
		var d2 := buf[i] + buf[i - 2] - buf[i - 1] * 2.0
		music_d2 = maxf(music_d2, maxf(absf(d2.x), absf(d2.y)))
	t.check(max_d2 <= music_d2, "no click at the wrap (%.4f, the music's own peak %.4f)" % [max_d2, music_d2])
	var quiet := 0
	var run := 0
	for i in range(w - 4410, w + 4410):
		run = run + 1 if buf[i].length() < 1e-4 else 0
		quiet = maxi(quiet, run)
	t.check(quiet < 44, "no gap at the wrap (longest near-silent run %d samples)" % quiet)
	var before := _rms_db(buf, w - SR, w)
	var after := _rms_db(buf, w, w + SR)
	t.check(absf(after - before) < 3.0, "the level carries across the wrap (%.1f -> %.1f dB)" % [before, after])


func test_level_matches_the_lobby_track() -> void:
	var m := _stream()
	var l := load("res://assets/audio/music_menu.ogg") as AudioStreamOggVorbis
	var a := m.instantiate_playback()
	a.start(m.loop_offset)
	var b := l.instantiate_playback()
	b.start(l.loop_offset)
	var la := _rms_db(_render(a, 10 * SR), 0, 10 * SR)
	var lb := _rms_db(_render(b, 10 * SR), 0, 10 * SR)
	t.check(absf(la - lb) < 2.0, "the round track sits at the lobby track's level (%.1f vs %.1f dB RMS)" % [la, lb])


func test_blend_start_lands_a_beat_on_the_lobby_beat() -> void:
	var menu: Array = Sfx.MUSIC_GRID["menu"]
	var match_grid: Array = Sfx.MUSIC_GRID["match"]
	t.near(float(menu[1]), 60.0 / 84.0, 1e-9, "lobby beat")
	t.near(float(match_grid[1]), 0.6, 1e-9, "round beat")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 200:
		var pos := rng.randf_range(0.0, 54.6)
		var from := Sfx.blend_start(pos, menu, match_grid)
		var lag := float(menu[1]) - fposmod(pos - float(menu[0]), float(menu[1]))
		t.check(from >= 0.0 and from < float(match_grid[1]) + 1e-6, "starts inside the pickup or first beat (%.3f)" % from)
		# the round track's beat lands where the lobby beat is
		var beat_phase := fposmod(from + lag - float(match_grid[0]), float(match_grid[1]))
		t.check(beat_phase < 1e-6 or beat_phase > float(match_grid[1]) - 1e-6, "on the beat (pos %.3f -> from %.3f)" % [pos, from])


func test_lobby_to_round_is_a_filtered_beat_blend() -> void:
	_begin()
	Sfx.music("menu")
	_step(3.0)
	Sfx.music("match")
	t.eq(Sfx.current_music(), "match", "the round's music is current")
	t.check(Sfx.last_blend_from >= 0.0, "started at a beat-aligned point (%.3f s)" % Sfx.last_blend_from)
	t.check(Sfx._music.level < 0.05 and Sfx._music.rate > 0.0, "fading in")
	t.near(1.0 / Sfx._music.rate, 1.2, 0.001, "over two beats")
	t.eq(Sfx._music_out.track, "menu", "the lobby music fades out under it")
	t.near(-1.0 / Sfx._music_out.rate, Sfx.BLEND_OUT, 0.001, "over the blend time")
	var bus := Sfx._music_out.bus
	t.check(bus >= 0 and AudioServer.get_bus_effect(bus, 0) is AudioEffectLowPassFilter, "on its own bus with a low-pass filter")
	var cut: Array[float] = []
	for i in 5:
		_step(0.35)
		cut.append(Sfx._music_out.cutoff())
		t.check(AudioServer.is_bus_effect_enabled(bus, 0), "the filter is in while it closes")
	t.check(cut[0] > cut[1] and cut[1] > cut[2] and cut[2] > cut[3], "closing %s" % [cut])
	t.check(cut[4] < 400.0, "down to the warm pad (%.0f Hz)" % cut[4])
	t.near(Sfx._music.level, 1.0, 0.001, "the round's music is at full level")
	_step(Sfx.BLEND_OUT)
	t.eq(Sfx._music_out.track, "", "the lobby music is gone")
	t.check(not AudioServer.is_bus_effect_enabled(bus, 0), "and its voice's filter is open again")
	t.near(Sfx._music_out.cutoff(), Sfx.OPEN_CUTOFF_HZ, 0.1, "fully open")
	_reset()


func test_back_to_the_lobby_mid_blend_opens_the_filter() -> void:
	_begin()
	Sfx.music("menu")
	_step(3.0)
	Sfx.music("match")
	_step(0.5)
	var bus := Sfx._music_out.bus
	Sfx.music("menu")
	t.eq(Sfx.current_music(), "menu", "the lobby music comes back from where it is")
	t.eq(Sfx._music.bus, bus, "the same voice")
	t.check(Sfx._music.sweep < 0.0 and not AudioServer.is_bus_effect_enabled(bus, 0), "unfiltered at once")
	_reset()


func test_no_blend_without_a_lobby_track_or_when_muted() -> void:
	_begin()
	Sfx.last_blend_from = -1.0
	Sfx.music("match")
	t.eq(Sfx.last_blend_from, -1.0, "from silence the round's music simply starts")
	t.eq(Sfx.current_music(), "match", "playing")
	Sfx.stop_music()
	Sfx.set_volumes(0.9, 0.0)
	Sfx.music("menu")
	Sfx.music("match")
	t.eq(Sfx.last_blend_from, -1.0, "muted: no blend (nothing to hear)")
	t.check(Sfx._music_out.sweep < 0.0, "and no filter")
	_reset()


func test_results_and_lobby_transitions_are_unchanged() -> void:
	_begin()
	Sfx.music("match")
	_step(2.0)
	Sfx.music("results")
	t.near(Sfx.fade_out_time("match"), 0.4, 0.001, "the round's music clears quickly for the results sting")
	t.check(Sfx._music_out.sweep < 0.0, "no filter on that change (results has no grid)")
	_reset()
