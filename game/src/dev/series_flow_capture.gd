extends "res://src/dev/lobby_light_capture.gd"
## (build 34) Development-only evidence (src/dev: never exported) for a
## party series that plays on by itself.  A party of three on the in-process
## loopback transport (no network; fictional names), the rounds' results
## made up from the roster (no round is simulated here):
##   01_between    round 1 of 3 over: the results with the standings and
##                 the 5-second countdown, only Leave match
##   02_final      after round 3: the final standings, Back to lobby
##   03_lobby      back in the party lobby: the people only (no bots), no
##                 series panel
## Run with tools/capture_series_flow.sh OUT_DIR [devices] (Xvfb, the Mobile
## renderer on llvmpipe: look and layout evidence only).

const PARTY := [
	["Pip", {"outfit": "pj", "pattern": "stripes", "color": "bubblegum", "skin": "tone3", "hair": "buns", "hair_color": "brown", "hat": "nightcap"}],
	["Rowan", {"outfit": "raincoat_explorer", "skin": "tone6", "hair": "curly", "hair_color": "black", "hat": "none"}],
]


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	Save.data["cosmetic"] = _look({"outfit": "moonwalk_cadet", "skin": "tone5", "hair": "tuft", "hair_color": "black"})
	App.goto_title()
	await _wait(1.0)
	_hub = LoopbackTransport.Hub.new(9)
	var ht := LoopbackTransport.new(_hub, true)
	_host = NetSession.new()
	_host.name = "SeriesCaptureHost"
	add_child(_host)
	_host.start_host(ht, "MOON42", Save.player_uid(), Save.party_name(), Save.data["cosmetic"], "any")
	_host.settings["rounds"] = 3
	App.session = _host
	for i in PARTY.size():
		var g: Array = PARTY[i]
		var ct := LoopbackTransport.new(_hub, false)
		var c := NetSession.new()
		c.name = "SeriesCaptureGuest%d" % i
		add_child(c)
		c.start_client(ct, "MOON42", "guest-%d" % i, String(g[0]), _look(g[1]), "any")
		_clients.append(c)
		_hub.link(ht.id, ct.id)
		await _wait(0.3)
	await _wait(1.0)
	# round 1 of 3 (made-up results), its results and the countdown
	_host.next_round_wait_s = 600.0   # (held: the countdown is set below)
	_host.host_start_match(11)
	_host.host_match_finished(_results(1, TC.Outcome.RUNNERS_WIN))
	_show_results()
	await _wait(1.0)
	_host._next_round_at = _host._clock + 3.4   # the countdown at "3"
	await _wait(0.9)
	await _portraits_idle()
	await snap("01_between")
	_host._next_round_at = -1.0
	# rounds 2 and 3, then the final standings
	for k in [2, 3]:
		_host.host_return_to_lobby(true, false)
		_host.host_start_match(11 + k)
		_host.host_match_finished(_results(k, TC.Outcome.PATROL_WIN if k == 2 else TC.Outcome.RUNNERS_WIN))
	_show_results()
	await _wait(1.5)
	var r := App.screen as ResultsScreen
	if r:
		r._on_primary()   # Final standings
	await _wait(2.0)
	await _portraits_idle()
	await snap("02_final")
	if r:
		r._on_primary()   # Back to lobby
	await _wait(3.0)
	await _portraits_idle()
	await snap("03_lobby")
	printerr("CAPTURE-DONE")
	get_tree().quit()


func _show_results() -> void:
	App._ensure_background()
	var r := ResultsScreen.new()
	r.results = _host.last_results
	r.reward = {"coins": 36, "xp": 120, "level": 3, "lines": [["Played the round", 20], ["Made it home", 16]]}
	r.session = _host
	App._show(r)


## A round's results from the roster as it stands (fictional numbers).
func _results(k: int, oc: int) -> Dictionary:
	var rows: Array = []
	var order := 0
	for e in _host.roster:
		if e == null:
			continue
		var runner := int(e["role"]) == TC.Role.RUNNER
		var home := runner and (int(e["slot"]) + k) % 3 != 0
		if home:
			order += 1
		rows.append({"slot": int(e["slot"]), "uid": String(e["uid"]), "name": String(e["name"]), "is_bot": bool(e["is_bot"]),
			"role": int(e["role"]), "stamps": 3 if home else 2, "finished": home, "finish_order": order if home else 0,
			"finish_time": 95.0 + 17.0 * order if home else -1.0, "times_captured": 0 if home else 1,
			"captures": 0 if runner else 2, "unique_captures": 0 if runner else 2, "present": true, "away_s": 0.0,
			"cosmetic": e["cosmetic"]})
	return {"match_id": "%s-%d" % [_host.room_code, k], "outcome": oc, "players": rows, "finished": order, "needed": 4,
		"round_time": 190.0, "watch": 2, "home_dorm": ""}
