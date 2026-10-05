extends Node
## Sound effects (pooled, optionally positional) and music loops.
## Gameplay cues always have a visual equivalent in the HUD, so the game is
## readable in silent mode or without headphones.
##
## Music plays on two voices so a change of track is a cross-fade. Asking for
## the track that is already playing never restarts it (the lobby music runs on
## through home, party, Locker, Shop, Season Pass and settings), and asking for
## a track that is still fading out brings it back from where it is. Loops
## are gapless: the stream itself loops in the mixer (Ogg Vorbis loop +
## loop_offset from the import), never a timer. The lobby track ("menu") plays
## its intro once, then loops 12 bars (tools/make_lobby_music.py); the round's
## track ("match", Pass 9) its intro, then 16 bars (tools/make_match_music.py).
##
## Pass 9 blend: going from the lobby to a round, the round's music starts on
## a beat of the lobby music (both are on known beat grids, MUSIC_GRID), fades
## in over two of its beats, and the lobby music fades out under it while a
## low-pass filter closes on it, so its drums and its tempo (84 against 100
## BPM) leave first and only its warm pad (G major, next to the round's D
## major) is left under the new groove.  Nothing waits: the new track starts
## at once, from the point in its pickup that lines its next beat up.

const SFX_DIR := "res://assets/audio/"
## Seconds a track takes to fade in when it starts. Tracks not listed start
## at full level (the results sting keeps its attack).
const MUSIC_FADE_IN := {"menu": 2.5, "match": 1.2}
## Seconds the outgoing track takes to fade out under the next one: the lobby
## music eases out as a round starts; the round's music clears quickly for the
## results sting, as it used to (cut) but without a click.
const MUSIC_FADE_OUT := {"match": 0.4}
const MUSIC_FADE_OUT_DEFAULT := 1.2
## After backgrounding or an audio interruption (a call, Siri), music resumes
## where it stopped and fades back in over this many seconds.
const MUSIC_RESUME_FADE := 0.8
## The owner's tracks' beat grids: [a downbeat (seconds into the file), the
## beat (seconds)].  menu: 84 BPM, the loop starts on a downbeat
## (make_lobby_music.py); match: 100 BPM, the file opens on the pickup beat,
## one beat before the first downbeat (make_match_music.py).
const MUSIC_GRID := {"menu": [896439.0 / 44100.0, 60.0 / 84.0], "match": [0.6, 0.6]}
## A blend between two gridded tracks: the outgoing one fades over BLEND_OUT
## seconds while its low-pass filter closes from 20 kHz to BLEND_CUTOFF_HZ
## over BLEND_SWEEP seconds (exponentially, like a DJ filter).
const BLEND_OUT := 2.0
const BLEND_SWEEP := 1.4
const BLEND_CUTOFF_HZ := 260.0
const OPEN_CUTOFF_HZ := 20500.0
const _SILENT_DB := -80.0

var sfx_volume := 0.9
var music_volume := 0.6
## The one music trim under Settings › Music (all tracks).  V7: -6 -> -3 dB,
## about 3 dB louder at every slider position (saved values are untouched).
## Headroom: the tracks' true peaks are -5.0 dBFS (chase, results) and
## -10.9 (lobby), so music peaks at -8 dBFS at the top of the slider.
const MUSIC_TRIM_DB := -3.0
## Effects (peaks to -1.3 dBFS) and music sum on Master: a hard limiter there
## (ceiling -0.3 dB) only acts on a rare coincident peak instead of clipping.
const MASTER_CEILING_DB := -0.3
var _cache: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: MusicVoice          # the current track
var _music_out: MusicVoice      # the previous track, fading out
var _suspended := false         # app in the background or audio interrupted
var last_blend_from := -1.0     # where the last blended track started (tests, diagnostics)


## One music player and its fade. level runs 0 (silent) .. 1 (full) and is
## heard through an equal-power curve, so a cross-fade keeps the loudness.
class MusicVoice:
	var player: AudioStreamPlayer
	var track := ""
	var level := 0.0
	var rate := 0.0             # level per second: > 0 fading in, < 0 fading out
	var bus := -1               # its own bus (a low-pass filter for blends)
	var sweep := -1.0           # seconds into a filter sweep (< 0: open)

	func _init(p: AudioStreamPlayer) -> void:
		player = p

	func cutoff() -> float:
		if sweep < 0.0:
			return OPEN_CUTOFF_HZ
		var k := clampf(sweep / BLEND_SWEEP, 0.0, 1.0)
		return exp(lerpf(log(OPEN_CUTOFF_HZ), log(BLEND_CUTOFF_HZ), k * k * (3.0 - 2.0 * k)))

	func apply_filter() -> void:
		if bus < 0:
			return
		var lp := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
		if lp:
			lp.cutoff_hz = cutoff()
		AudioServer.set_bus_effect_enabled(bus, 0, sweep >= 0.0)

	func gain() -> float:
		return sin(clampf(level, 0.0, 1.0) * PI * 0.5)

	func sounding() -> bool:
		return track != "" and player.playing

	func clear() -> void:
		player.stop()
		player.stream = null
		track = ""
		level = 0.0
		rate = 0.0
		sweep = -1.0
		apply_filter()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_master_limiter()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool2d.append(p)
	for i in 16:
		var p3 := AudioStreamPlayer3D.new()
		p3.max_distance = 45.0
		p3.unit_size = 6.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool3d.append(p3)
	var a := AudioStreamPlayer.new()
	a.name = "MusicA"
	add_child(a)
	var b := AudioStreamPlayer.new()
	b.name = "MusicB"
	add_child(b)
	_music = MusicVoice.new(a)
	_music_out = MusicVoice.new(b)
	for v: MusicVoice in [_music, _music_out]:
		v.bus = _music_bus(v.player.name)
		v.player.bus = AudioServer.get_bus_name(v.bus)
		v.apply_filter()


## A bus per music voice, sent to Master, with a low-pass filter that is
## bypassed except during a blend.
func _music_bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = OPEN_CUTOFF_HZ
		AudioServer.add_bus_effect(i, lp, 0)
	return i


## Where to start a gridded track so that one of its beats lands on the next
## beat of the outgoing track: out_pos is the outgoing playback position
## (seconds into its file), grids are [downbeat, beat].  The earliest such
## start at or after the file start (so at most one beat of the new track's
## pickup is skipped).
static func blend_start(out_pos: float, out_grid: Array, in_grid: Array) -> float:
	var lag := float(out_grid[1]) - fposmod(out_pos - float(out_grid[0]), float(out_grid[1]))
	var first := float(in_grid[0])
	var beat := float(in_grid[1])
	var k := ceili((lag - first) / beat - 1e-9)
	return maxf(0.0, first + float(k) * beat - lag)


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	for ext: String in [".wav", ".ogg"]:
		var path := SFX_DIR + name + ext
		if ResourceLoader.exists(path):
			s = load(path)
			break
	_cache[name] = s
	return s


func play(name: String, pos: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _stream(name)
	if s == null or sfx_volume <= 0.001:
		return
	var vol := volume_db + linear_to_db(sfx_volume)
	if pos is Vector3:
		for p in _pool3d:
			if not p.playing:
				p.stream = s
				p.global_position = pos
				p.volume_db = vol
				p.pitch_scale = pitch * randf_range(0.95, 1.05)
				p.play()
				return
		return
	for p2 in _pool2d:
		if not p2.playing:
			p2.stream = s
			p2.volume_db = vol
			p2.pitch_scale = pitch
			p2.play()
			return


## Switches to a music track: the current one fades out under it. The same
## track again is a no-op (no restart); a track that is fading out comes back.
func music(name: String) -> void:
	if name == _music.track and (_music.sounding() or _held()):
		return
	if name == _music_out.track and _music_out.sounding():
		var back := _music_out
		_music_out = _music
		_music = back
		_music.rate = 1.0 / fade_out_time(name)
		_music.sweep = -1.0          # back from a blend: the filter opens again
		_music.apply_filter()
		_fade_out_previous()
		_apply_music_volume()
		return
	var s := _stream("music_" + name)
	if s == null:
		stop_music()
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = name != "results"
	# a blend between two gridded tracks (lobby -> round): on the beat, the
	# outgoing one filtered out
	var blend := MUSIC_GRID.has(name) and MUSIC_GRID.has(_music.track) and _music.sounding() \
			and not _held() and not _suspended and music_volume > 0.001
	var from := 0.0
	if blend:
		from = blend_start(_music.player.get_playback_position(), MUSIC_GRID[_music.track], MUSIC_GRID[name])
	var next := _music_out
	_music_out = _music
	_music = next
	_music.clear()
	_fade_out_previous()
	if blend:
		_music_out.rate = -1.0 / BLEND_OUT
		_music_out.sweep = 0.0
		_music_out.apply_filter()
		last_blend_from = from
	_music.track = name
	_music.player.stream = s
	var fade: float = MUSIC_FADE_IN.get(name, 0.0)
	_music.level = 0.0 if fade > 0.0 else 1.0
	_music.rate = 1.0 / fade if fade > 0.0 else 0.0
	_apply_music_volume()
	_music.player.play(from)
	_apply_music_pause()


func stop_music() -> void:
	_music.clear()
	_music_out.clear()


# ---------------------------------------------------------------- results
## Pass 8: RESULTS is one music state with one owner. The match controller
## calls results() as a round's result is decided; the results screen calls
## results_screen_shown(); going back to the lobby asks for "menu" as before.
##   * With the owner's results track in the build (music_results_bed.ogg:
##     a short finish flourish, then a bar-aligned loop from its import
##     loop_offset) it starts once per round result and keeps looping under
##     rewards, final standings and Ready, never restarted by reopening the
##     screen or changing its page.
##   * Without it (this build: the track hasn't been supplied), the V5
##     results sting plays once and the lobby music continues under the
##     results screen, exactly as before.
##   * A cancelled round or a lost host plays no finish flourish.
const RESULTS_BED := "results_bed"
var _results_key := ""


func results(round_key: String, cancelled: bool = false) -> void:
	if round_key != "" and round_key == _results_key:
		return
	_results_key = round_key
	if cancelled:
		music("menu")
	elif has_results_bed():
		music(RESULTS_BED)
	else:
		music("results")


func results_screen_shown() -> void:
	if current_music() == RESULTS_BED:
		return
	music("menu")


func has_results_bed() -> bool:
	return _stream("music_" + RESULTS_BED) != null


func set_volumes(sfx: float, mus: float) -> void:
	sfx_volume = sfx
	music_volume = mus
	if _music:
		_apply_music_volume()
		_apply_music_pause()


## The track playing (or held paused by mute/backgrounding), "" for none.
func current_music() -> String:
	return _music.track if (_music.sounding() or _held()) else ""


func fade_out_time(track: String) -> float:
	return MUSIC_FADE_OUT.get(track, MUSIC_FADE_OUT_DEFAULT)


func _fade_out_previous() -> void:
	if _music_out.track == "":
		return
	if _suspended or music_volume <= 0.001:
		_music_out.clear()       # nothing audible to fade
		return
	_music_out.rate = -1.0 / fade_out_time(_music_out.track)


func _held() -> bool:
	return _music.track != "" and _music.player.stream_paused


func _process(delta: float) -> void:
	if _suspended or _music == null:
		return
	# A long frame (loading, returning from the background) can't skip a fade.
	var dt := minf(delta, 0.1)
	var fading := false
	for v: MusicVoice in [_music, _music_out]:
		if v.sweep >= 0.0 and v.track != "":
			v.sweep += dt
			v.apply_filter()
		if v.rate == 0.0 or v.track == "":
			continue
		fading = true
		v.level += v.rate * dt
		if v.level >= 1.0:
			v.level = 1.0
			v.rate = 0.0
		elif v.level <= 0.0:
			v.clear()
	if fading:
		_apply_music_volume()


func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = MASTER_CEILING_DB
	AudioServer.add_bus_effect(master, lim)


func _apply_music_volume() -> void:
	var base := linear_to_db(maxf(music_volume, 0.0001)) + MUSIC_TRIM_DB
	for v: MusicVoice in [_music, _music_out]:
		var g := v.gain()
		v.player.volume_db = base + linear_to_db(g) if g > 0.0001 else _SILENT_DB


## Muted (music volume 0) or in the background: the music holds its place
## instead of decoding silence, and continues from there.
func _apply_music_pause() -> void:
	var hold := _suspended or music_volume <= 0.001
	for v: MusicVoice in [_music, _music_out]:
		if v.track != "" and v.player.stream_paused != hold:
			v.player.stream_paused = hold


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_suspend_music()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_resume_music()


func _suspend_music() -> void:
	if _suspended or _music == null:
		return
	_suspended = true
	_music_out.clear()           # a fade-out in progress just finishes
	_apply_music_pause()


func _resume_music() -> void:
	if not _suspended:
		return
	_suspended = false
	if _music.track != "":
		_music.level = 0.0
		_music.rate = 1.0 / MUSIC_RESUME_FADE
		_apply_music_volume()
	_apply_music_pause()
