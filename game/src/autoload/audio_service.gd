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
## its intro once, then loops 12 bars (tools/make_lobby_music.py).

const SFX_DIR := "res://assets/audio/"
## Seconds a track takes to fade in when it starts. Tracks not listed start
## at full level (the results sting keeps its attack).
const MUSIC_FADE_IN := {"menu": 2.5}
## Seconds the outgoing track takes to fade out under the next one: the lobby
## music eases out as a round starts; the chase music clears quickly for the
## results sting, as it used to (cut) but without a click.
const MUSIC_FADE_OUT := {"chase_calm": 0.4}
const MUSIC_FADE_OUT_DEFAULT := 1.2
## After backgrounding or an audio interruption (a call, Siri), music resumes
## where it stopped and fades back in over this many seconds.
const MUSIC_RESUME_FADE := 0.8
const _SILENT_DB := -80.0

var sfx_volume := 0.9
var music_volume := 0.6
var _cache: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: MusicVoice          # the current track
var _music_out: MusicVoice      # the previous track, fading out
var _suspended := false         # app in the background or audio interrupted


## One music player and its fade. level runs 0 (silent) .. 1 (full) and is
## heard through an equal-power curve, so a cross-fade keeps the loudness.
class MusicVoice:
	var player: AudioStreamPlayer
	var track := ""
	var level := 0.0
	var rate := 0.0             # level per second: > 0 fading in, < 0 fading out

	func _init(p: AudioStreamPlayer) -> void:
		player = p

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		_fade_out_previous()
		_apply_music_volume()
		return
	var s := _stream("music_" + name)
	if s == null:
		stop_music()
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = name != "results"
	var next := _music_out
	_music_out = _music
	_music = next
	_music.clear()
	_fade_out_previous()
	_music.track = name
	_music.player.stream = s
	var fade: float = MUSIC_FADE_IN.get(name, 0.0)
	_music.level = 0.0 if fade > 0.0 else 1.0
	_music.rate = 1.0 / fade if fade > 0.0 else 0.0
	_apply_music_volume()
	_music.player.play()
	_apply_music_pause()


func stop_music() -> void:
	_music.clear()
	_music_out.clear()


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


func _apply_music_volume() -> void:
	var base := linear_to_db(maxf(music_volume, 0.0001)) - 6.0
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
