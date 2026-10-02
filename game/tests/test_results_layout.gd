extends RefCounted
## V5 results sheet: the actions (Play again, Scoreboard, Menu / Leave) are
## always on screen, never below the fold of the scrolling summary, and the
## summary is as tall as its content when the screen has room (iPad).
var t


func _results_screen(practice: bool) -> ResultsScreen:
	var me := Save.player_uid()
	var rows := [
		{"slot": 0, "uid": me, "name": "Tester", "is_bot": false, "role": TC.Role.RUNNER, "stamps": 3, "finished": true,
			"present": true, "away_s": 0.0},
		{"slot": 1, "uid": "bot-1", "name": "Snooze", "is_bot": true, "role": TC.Role.PATROL, "captures": 2, "unique_captures": 2,
			"present": true, "away_s": 0.0},
	]
	var r := ResultsScreen.new()
	r.results = {"match_id": "layout-r", "outcome": TC.Outcome.RUNNERS_WIN, "players": rows, "finished": 4, "needed": 4,
		"round_time": 150.0, "practice": practice}
	r.reward = {"coins": 33, "xp": 40, "level": 2, "lines": [["Played the round", 20], ["Splashes x3", 15], ["Made it home", 15]]}
	return r


func test_actions_are_always_on_screen() -> void:
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	Save.data["onboarded"] = true
	for sz in [Vector2i(2532, 1170), Vector2i(1334, 750), Vector2i(2048, 1536)]:
		root.size = sz
		await t.get_tree().process_frame
		var off := NetSession.new()
		t.add_child(off)
		off.start_offline(Save.player_uid(), "Tester", {}, "runner")
		var r := _results_screen(true)
		r.session = off
		App._ensure_background()
		App._show(r)
		for i in 20:
			await t.get_tree().process_frame
		var view := r.get_viewport().get_visible_rect()
		var scroll := r.find_children("*", "ScrollContainer", true, false)
		t.check(scroll.size() >= 1, "%s: the summary scrolls" % str(sz))
		for b in [r._primary, r.leave_btn]:
			var btn := b as Button
			var inside_scroll := false
			for sc in scroll:
				if (sc as Node).is_ancestor_of(btn):
					inside_scroll = true
			t.check(not inside_scroll, "%s: '%s' is outside the scrolling summary" % [str(sz), btn.text])
			var g := btn.get_global_rect()
			t.check(view.encloses(g), "%s: '%s' is on screen (%s in %s)" % [str(sz), btn.text, str(g), str(view)])
		var sc0 := scroll[0] as ScrollContainer
		var content := sc0.get_child(0) as Control
		if sz.y == 1536:
			t.check(sc0.size.y >= content.get_combined_minimum_size().y - 0.5, "iPad: the whole summary shows (%d of %d)" % [sc0.size.y, content.get_combined_minimum_size().y])
		r.queue_free()
		App.screen = null
		App._clear_background()
		off.queue_free()
		await t.get_tree().process_frame
	root.size = saved_size
