extends Node
## Development-only evidence (src/dev: never exported): the Pass 9 lobby ->
## round music blend through the real AudioService and mixer.  The lobby
## track plays from its start; at --at=SECONDS the round's track is asked
## for, as MatchController does when a round is prepared; the capture ends
## --len seconds later.  Record with Movie Maker (the .avi carries the mix):
##   tools/gd.sh --path game --write-movie OUT.avi --fixed-fps 60 res://src/dev/music_blend_capture.tscn -- --at=18.3 --len=8
var at := 18.3
var length := 8.0
var _t := 0.0
var _switched := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			at = float(a.get_slice("=", 1))
		elif a.begins_with("--len="):
			length = float(a.get_slice("=", 1))
	for c in get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	Sfx.stop_music()
	Sfx.set_volumes(0.0, 1.0)     # music only, at the top of the slider
	Sfx.music("menu")
	var l := Label.new()
	l.text = "Lobby -> round music blend (audio capture)"
	l.position = Vector2(40, 40)
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	if not _switched and _t >= at:
		_switched = true
		var lobby_pos := Sfx._music.player.get_playback_position()
		Sfx.music("match")
		print("BLEND at %.3f s: lobby at %.4f s in its file, round track from %.4f s" % [_t, lobby_pos, Sfx.last_blend_from])
	if _switched and _t >= at + length:
		get_tree().quit()
