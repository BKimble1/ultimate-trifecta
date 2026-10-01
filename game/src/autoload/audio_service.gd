extends Node
## Sound effects (pooled, optionally positional) and music loops.
## Gameplay cues always have a visual equivalent in the HUD, so the game is
## readable in silent mode or without headphones.

const SFX_DIR := "res://assets/audio/"

var sfx_volume := 0.9
var music_volume := 0.6
var _cache: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: AudioStreamPlayer
var _music_name := ""


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
	_music = AudioStreamPlayer.new()
	add_child(_music)


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


func music(name: String) -> void:
	if name == _music_name and _music.playing:
		return
	_music_name = name
	var s := _stream("music_" + name)
	if s == null:
		_music.stop()
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = name != "results"
	_music.stream = s
	_music.volume_db = linear_to_db(maxf(music_volume, 0.0001)) - 6.0
	_music.play()


func stop_music() -> void:
	_music.stop()
	_music_name = ""


func set_volumes(sfx: float, mus: float) -> void:
	sfx_volume = sfx
	music_volume = mus
	if _music:
		_music.volume_db = linear_to_db(maxf(music_volume, 0.0001)) - 6.0
