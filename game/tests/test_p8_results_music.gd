extends RefCounted
## Pass 8 RESULTS music state (AudioService.results / results_screen_shown):
## one owner, started once per round result, never restarted by reopening the
## results screen; without the owner's results track the V5 sting plays once
## and the lobby music carries on under the results screen; a cancelled round
## plays no finish flourish.
var t


func _begin() -> void:
	Sfx._resume_music()
	Sfx.stop_music()
	Sfx._results_key = ""
	Sfx._cache.erase("music_" + Sfx.RESULTS_BED)
	Sfx.set_volumes(0.9, 0.6)


func _reset() -> void:
	Sfx._resume_music()
	Sfx.stop_music()
	Sfx._results_key = ""
	Sfx._cache.erase("music_" + Sfx.RESULTS_BED)
	Save._apply_settings()


func _playback_id() -> int:
	var pb: AudioStreamPlayback = Sfx._music.player.get_stream_playback()
	return pb.get_instance_id() if pb else 0


func _step(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		Sfx._process(1.0 / 60.0)


func test_this_build_has_no_results_bed_and_no_placeholder() -> void:
	_begin()
	t.check(not ResourceLoader.exists("res://assets/audio/music_results_bed.ogg"), "no results track is shipped until the owner supplies one")
	t.check(not Sfx.has_results_bed(), "so the RESULTS state has no bed")
	_reset()


func test_without_a_bed_the_sting_plays_once_then_lobby_music() -> void:
	_begin()
	Sfx.music("match")
	Sfx.results("m1:1")
	t.eq(Sfx.current_music(), "results", "a decided round plays the results sting")
	var sting := _playback_id()
	Sfx.results("m1:1")
	t.eq(_playback_id(), sting, "the same round result again does not restart it")
	Sfx.results_screen_shown()
	t.eq(Sfx.current_music(), "menu", "the results screen brings the lobby music back, as before")
	_step(1.0)
	var lobby := _playback_id()
	Sfx.results_screen_shown()
	Sfx.results("m1:1")
	t.eq(Sfx.current_music(), "menu", "reopening the results screen keeps the lobby music")
	t.eq(_playback_id(), lobby, "without restarting it")
	_reset()


func test_cancelled_round_plays_no_flourish() -> void:
	_begin()
	Sfx.music("match")
	Sfx.results("m2:1", true)
	t.eq(Sfx.current_music(), "menu", "a cancelled round goes straight to the lobby music")
	_reset()


func test_owner_bed_starts_once_and_loops_under_results() -> void:
	_begin()
	# Stand-in for the owner's file, only inside this test: the lobby track
	# under the bed's name (the shipped build has no bed; see the test above).
	var bed := (load("res://assets/audio/music_menu.ogg") as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	Sfx._cache["music_" + Sfx.RESULTS_BED] = bed
	Sfx.music("match")
	Sfx.results("m3:2")
	t.eq(Sfx.current_music(), Sfx.RESULTS_BED, "with the bed in the build, a decided round starts it")
	t.check(bed.loop, "and it loops (from its import loop_offset)")
	var id := _playback_id()
	_step(2.0)
	Sfx.results_screen_shown()
	Sfx.results("m3:2")
	Sfx.results_screen_shown()
	t.eq(Sfx.current_music(), Sfx.RESULTS_BED, "the results screen keeps the bed under rewards and standings")
	t.eq(_playback_id(), id, "reopening the screen never restarts it")
	Sfx.results("m3:3")
	t.eq(Sfx.current_music(), Sfx.RESULTS_BED, "the next round's result keeps the same state")
	Sfx.music("menu")
	t.eq(Sfx.current_music(), "menu", "back to the lobby: the lobby music")
	Sfx.results("m4:1", true)
	t.eq(Sfx.current_music(), "menu", "a cancelled round never plays the bed's flourish")
	_reset()
