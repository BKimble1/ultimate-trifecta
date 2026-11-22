extends RefCounted
## Crash sweep: the Game Center side of inviting and adding friends
## (src/autoload/social_service.gd), against stand-ins for the GameKit
## classes (Social.kit and a scripted matchmaker; no GameKit on desktop).
## What a device crash report would have needed, made checkable here:
##   - one Apple sheet at a time: a double tap on "Invite with Game Center"
##     opens one sheet; "Game Center friends" never opens over it; the sheet
##     is released only after its own signal has finished
##   - GameKit answers arriving on a background thread reach the game on the
##     main thread (transports bound, signals the UI listens to)
##   - answers for a party that ended meanwhile are dropped, not bound
##   - a failing add_players backs off instead of re-asking from inside its
##     own answer (unbounded recursion)
##   - authentication answering again (back from the background) registers
##     the invite listener once; the same accepted invite is handled once,
##     never with a second sheet over the first, never while signed out
##   - an invite answered during a round, or while another is asking, ends
##     cleanly
##   - in-game invites sent quickly one after another go out one at a time
var t


class Obj:
	extends RefCounted
	var props := {}

	func _set(property: StringName, value: Variant) -> bool:
		props[String(property)] = value
		return true

	func _get(property: StringName) -> Variant:
		return props.get(String(property))


class FakeVC:
	extends Obj
	signal did_find_match(m: Object)
	signal cancelled(detail: String)
	signal failed_with_error(message: String)
	var presented := 0
	var request: Object

	func present() -> void:
		presented += 1

	func add_players_to_match(_m: Object) -> void:
		pass


class FakeMatch:
	extends RefCounted
	signal data_received(data: PackedByteArray, player: Object)
	signal player_changed(player: Object, connected: bool)
	signal did_fail_with_error(message: String)
	var players: Array = []


class FakeErr:
	extends RefCounted
	var message := "The requested operation could not be completed."
	var code := 3


class FakeMM:
	extends RefCounted
	var finds: Array = []        # [request, callback]
	var adds: Array = []         # [match, request, callback]
	var invites: Array = []      # [invite, callback]
	var cancels := 0
	var fail_adds_now := false

	func find_match(req: Object, cb: Callable) -> void:
		finds.append([req, cb])

	func add_players(m: Object, req: Object, cb: Callable) -> void:
		adds.append([m, req, cb])
		if fail_adds_now:
			cb.call(FakeErr.new())     # (GameKit can answer at once, on the caller's stack)

	func match_for_invite(invite: Object, cb: Callable) -> void:
		invites.append([invite, cb])

	func cancel() -> void:
		cancels += 1


class FakeKit:
	extends RefCounted
	var vcs: Array = []
	var shows := 0
	var dropped: Array = []
	var mm := FakeMM.new()

	func new_request() -> Object:
		return Obj.new()

	func create_controller(req: Object) -> Object:
		var vc := FakeVC.new()
		vc.request = req
		vcs.append(vc)
		return vc

	func create_controller_from_invite(_invite: Object) -> Object:
		return create_controller(null)

	func show_type(_n: int) -> void:
		shows += 1

	func new_matchmaker() -> Object:
		return mm

	func drop(m: Object) -> void:
		dropped.append(m)


class FakeLP:
	extends Obj
	signal invite_accepted(player: Object, invite: Object)
	var registered := 0

	func _init() -> void:
		props = {"game_player_id": "G:me", "team_player_id": "T:me", "display_name": "Quiet Duck", "is_multiplayer_gaming_restricted": false}

	func register_listener() -> void:
		registered += 1


class FakeGC:
	extends Obj

	func _init() -> void:
		props = {"local_player": FakeLP.new()}


var kit: FakeKit
var _saved := {}
var _events: Array = []


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin() -> void:
	_saved = {"gc": [Social.available, Social.authenticated, Social.multiplayer_restricted, Social.gc, Social.matchmaker, Social._listening]}
	kit = FakeKit.new()
	Social.kit = kit
	Social.available = true
	Social.authenticated = true
	Social.multiplayer_restricted = false
	Social.matchmaker = kit.mm
	Social.reset_for_tests()
	_events = []
	Social.room_matched.connect(_on_matched)
	Social.room_failed.connect(_on_failed)


func _end() -> void:
	if Social.room_matched.is_connected(_on_matched):
		Social.room_matched.disconnect(_on_matched)
	if Social.room_failed.is_connected(_on_failed):
		Social.room_failed.disconnect(_on_failed)
	# (fake matches can't be disconnected like GameKit's: unbind them)
	if Social._pending_transport != null:
		Social._pending_transport.gk_match = null
	Social._pending_transport = null
	Social._room_request = null
	Social.reset_for_tests()
	Social.kit = null
	var g: Array = _saved["gc"]
	Social.available = g[0]
	Social.authenticated = g[1]
	Social.multiplayer_restricted = g[2]
	Social.gc = g[3]
	Social.matchmaker = g[4]
	Social._listening = g[5]
	await _frames(2)


func _on_matched(tr: GameKitTransport) -> void:
	_events.append(["matched", tr, OS.get_thread_caller_id() == OS.get_main_thread_id()])


func _on_failed(message: String) -> void:
	_events.append(["failed", message, OS.get_thread_caller_id() == OS.get_main_thread_id()])


## Runs `cb` on a background thread (as a GameKit completion handler can).
func _off_main(cb: Callable) -> void:
	var th := Thread.new()
	th.start(cb)
	th.wait_to_finish()


func test_one_sheet_at_a_time_and_released_after_its_signal() -> void:
	await _begin()
	var tr := Social.host_code_room("ACDEFG")
	t.check(Social.invite_friends(tr, "ACDEFG"), "Invite with Game Center opens Apple's sheet")
	t.check(not Social.invite_friends(tr, "ACDEFG"), "a second tap while it is up opens nothing")
	t.eq(kit.vcs.size(), 1, "one controller")
	t.eq((kit.vcs[0] as FakeVC).presented, 1, "presented once")
	t.check(Social.sheet_open(), "the sheet is known to be up")
	t.check(Social.show_friends_list(), "Game Center friends while it is up: nothing breaks")
	t.eq(kit.shows, 0, "and no second screen over it")
	# Cancel: released only after the signal (deferred), then a new one may open
	var vc: FakeVC = kit.vcs[0]
	vc.cancelled.emit("")
	t.check(Social._invite_vc == vc, "still held while its own signal runs")
	await _frames(2)
	t.check(not Social.sheet_open() and Social._invite_vc == null, "closed and released afterwards")
	t.check(Social.invite_friends(tr, "ACDEFG"), "a new sheet can open")
	# a match found on a background thread binds on the main thread
	var m := FakeMatch.new()
	var vc2: FakeVC = kit.vcs[1]
	_off_main(func() -> void: vc2.did_find_match.emit(m))
	await _frames(3)
	t.check(tr.bound() and tr.gk_match == m, "the party's match")
	var hit: Array = _events.filter(func(e: Array) -> bool: return e[0] == "matched")
	t.check(hit.size() == 1 and bool(hit[0][2]), "announced on the main thread")
	# the party ends while a sheet is up: its late match is dropped, never bound
	tr.gk_match = null
	t.check(Social.invite_friends(tr, "ACDEFG"), "another sheet")
	var vc3: FakeVC = kit.vcs[2]
	Social.stop_matchmaking()
	var late := FakeMatch.new()
	vc3.did_find_match.emit(late)
	await _frames(2)
	t.check(not tr.bound(), "a dead party's transport stays unbound")
	t.check(kit.dropped.has(late), "and the late match is disconnected")
	# signed out: nothing opens
	Social.authenticated = false
	t.check(not Social.invite_friends(tr, "ACDEFG"), "signed out: no sheet")
	t.check(not Social.show_friends_list(), "and no Game Center screen")
	await _end()


func test_game_center_friends_double_tap_opens_one() -> void:
	await _begin()
	t.check(Social.show_friends_list() and Social.show_friends_list(), "two taps")
	t.eq(kit.shows, 1, "one Game Center screen")
	await _end()


func test_answers_from_background_threads_reach_the_main_thread() -> void:
	await _begin()
	var tr := Social.join_code_room("ACDEFG")
	t.eq(kit.mm.finds.size(), 1, "a code join asks Game Center")
	var m := FakeMatch.new()
	var cb: Callable = kit.mm.finds[0][1]
	_off_main(func() -> void: cb.call(m, null))
	t.check(not tr.bound(), "nothing is bound on the background thread")
	await _frames(2)
	t.check(tr.bound(), "bound on the main thread")
	var hit: Array = _events.filter(func(e: Array) -> bool: return e[0] == "matched")
	t.check(hit.size() == 1 and bool(hit[0][2]), "room_matched on the main thread")
	# an error from a background thread: room_failed (the app may change screens) on the main thread
	tr.gk_match = null
	_events.clear()
	var tr2 := Social.join_code_room("ACDEFG")
	var cb2: Callable = kit.mm.finds[1][1]
	_off_main(func() -> void: cb2.call(null, FakeErr.new()))
	await _frames(2)
	var fail: Array = _events.filter(func(e: Array) -> bool: return e[0] == "failed")
	t.check(fail.size() == 1 and bool(fail[0][2]), "room_failed on the main thread (%s)" % str(fail))
	t.check(not tr2.bound(), "nothing bound")
	# a join cancelled before Game Center answers: the answer is dropped
	_events.clear()
	var tr3 := Social.join_code_room("ACDEFG")
	var cb3: Callable = kit.mm.finds[2][1]
	Social.stop_matchmaking()
	var late := FakeMatch.new()
	cb3.call(late, null)
	await _frames(2)
	t.check(not tr3.bound() and _events.is_empty(), "a cancelled join stays cancelled")
	t.check(kit.dropped.has(late), "its match is disconnected")
	# Quick Match from a background thread
	var got := {"m": null, "main": false}
	var on_found := func(qm: Object) -> void:
		got["m"] = qm
		got["main"] = OS.get_thread_caller_id() == OS.get_main_thread_id()
	Social.quick_found.connect(on_found)
	t.check(Social.quick_match_start(), "Quick Match asks")
	var qcb: Callable = kit.mm.finds[3][1]
	var qm := FakeMatch.new()
	_off_main(func() -> void: qcb.call(qm, null))
	await _frames(2)
	t.check(got["m"] == qm and bool(got["main"]), "found on the main thread")
	Social.quick_found.disconnect(on_found)
	await _end()


func test_failing_add_players_backs_off() -> void:
	await _begin()
	var tr := Social.host_code_room("ACDEFG")
	var cb: Callable = kit.mm.finds[0][1]
	cb.call(FakeMatch.new(), null)
	kit.mm.fail_adds_now = true
	await _frames(2)        # bound, then add_players
	await _frames(60)       # one second
	t.check(tr.bound(), "the host's match")
	t.check(kit.mm.adds.size() >= 1 and kit.mm.adds.size() <= 2, "a failing add_players waits before asking again (%d in 1 s)" % kit.mm.adds.size())
	kit.mm.fail_adds_now = false
	await _end()


func test_auth_again_registers_the_listener_once() -> void:
	await _begin()
	var g := FakeGC.new()
	var lp: FakeLP = g.get("local_player")
	Social.gc = g
	Social.matchmaker = null
	Social._listening = false
	for i in 3:
		Social._on_auth(true)     # (GameKit answers again on every return from the background)
	t.eq(lp.registered, 1, "the invite listener is registered once")
	t.eq(lp.get_signal_connection_list("invite_accepted").size(), 1, "and connected once")
	var mm: Object = Social.matchmaker
	Social._on_auth(true)
	t.check(Social.matchmaker == mm and mm != null, "the matchmaker is kept")
	t.eq(Social.team_player_id, "T:me", "the player's IDs")
	# signed out meanwhile: nothing calls GameKit
	Social._on_auth(false)
	t.check(not Social.online_ready(), "signed out")
	# (Social.gc without a local player)
	Social.gc = Obj.new()
	Social._on_auth(true)
	t.check(not Social.authenticated, "no local player: not signed in")
	lp.invite_accepted.disconnect(Social._on_invite_accepted)
	await _end()


func test_accepted_invite_handled_once_and_never_over_a_sheet() -> void:
	await _begin()
	var inv := Obj.new()
	Social._on_invite_accepted(null, inv)
	Social._on_invite_accepted(null, inv)
	t.eq(kit.mm.invites.size(), 1, "the same invite twice: joined once")
	var other := Obj.new()
	Social._on_invite_accepted(null, other)
	t.eq(kit.mm.invites.size(), 1, "another one while the first is joining: ignored")
	# the straight join fails while Apple's invite sheet is up: no second sheet
	var tr := Social.host_code_room("ACDEFG")
	t.check(Social.invite_friends(tr, "ACDEFG"), "a sheet is up")
	var cb: Callable = kit.mm.invites[0][1]
	_off_main(func() -> void: cb.call(null, FakeErr.new()))
	await _frames(2)
	t.eq(kit.vcs.size(), 1, "no invite sheet over the open sheet")
	t.check(_events.any(func(e: Array) -> bool: return e[0] == "failed" and String(e[1]).contains("Close the Game Center screen")), "says what to do")
	# a joined invite arrives on the main thread
	(kit.vcs[0] as FakeVC).cancelled.emit("")
	await _frames(2)
	var ready := {"t": null, "main": false}
	var on_ready := func(x: GameKitTransport) -> void:
		ready["t"] = x
		ready["main"] = OS.get_thread_caller_id() == OS.get_main_thread_id()
	Social.invite_ready.connect(on_ready)
	# (App's own handler is tested on its own below)
	Social.invite_ready.disconnect(App._on_invite_ready)
	var inv2 := Obj.new()
	Social._on_invite_accepted(null, inv2)
	t.eq(kit.mm.invites.size(), 2, "a new invite after the first finished")
	var cb2: Callable = kit.mm.invites[1][1]
	var m := FakeMatch.new()
	_off_main(func() -> void: cb2.call(m, null))
	await _frames(2)
	t.check(ready["t"] != null and bool(ready["main"]), "invite_ready on the main thread")
	t.check(ready["t"] != null and (ready["t"] as GameKitTransport).gk_match == m, "with the invited match")
	Social.invite_ready.disconnect(on_ready)
	Social.invite_ready.connect(App._on_invite_ready)
	if ready["t"] != null:
		(ready["t"] as GameKitTransport).gk_match = null
	# signed out: an invite is ignored
	Social.authenticated = false
	Social._on_invite_accepted(null, Obj.new())
	t.eq(kit.mm.invites.size(), 2, "signed out: ignored")
	await _end()


func test_in_game_invites_go_out_one_at_a_time() -> void:
	await _begin()
	var tr := Social.host_code_room("ACDEFG")
	var cb: Callable = kit.mm.finds[0][1]
	cb.call(FakeMatch.new(), null)
	await _frames(2)
	var adds0: int = kit.mm.adds.size()
	t.check(Social.invite_players(tr, "ACDEFG", [Obj.new()]), "first invite")
	t.check(Social.invite_players(tr, "ACDEFG", [Obj.new()]), "second, right after")
	var sent: Array = kit.mm.adds.slice(adds0).filter(func(a: Array) -> bool: return (a[1] as Obj).props.has("recipients"))
	t.eq(sent.size(), 1, "one request at a time (the second never cancels the first)")
	(sent[0][2] as Callable).call(null)
	await _frames(2)
	sent = kit.mm.adds.slice(adds0).filter(func(a: Array) -> bool: return (a[1] as Obj).props.has("recipients"))
	t.eq(sent.size(), 2, "then the second goes out")
	t.check(not Social.invite_players(tr, "ACDEFG", []), "nobody picked: nothing sent")
	await _end()


func test_app_invite_ready_during_a_round_ends_cleanly() -> void:
	var before: Variant = App.session
	App.match_ctrl = MatchController.new()
	var tr := GameKitTransport.new(false)
	App._on_invite_ready(tr)
	await t.get_tree().process_frame
	t.check(App.session == before, "a round is never interrupted by an invite")
	t.check(not App._invite_asking, "and nothing is left waiting")
	var mc := App.match_ctrl
	App.match_ctrl = null
	mc.free()
	App._on_invite_ready(null)
	t.check(App.session == before, "no transport: nothing happens")


## (build 32) Game Center called the party's request invalid (the owner's
## iPhone: "the match request is invalid"): the request asks for no more
## players than Game Center allows, and an invalid one is retried once
## without the host/joiner roles; a second refusal is reported.
func test_an_invalid_request_is_retried_once_simpler() -> void:
	await _begin()
	Social.simple_requests = false
	var tr := Social.host_code_room("ACE347")
	await _frames(2)
	t.eq(kit.mm.finds.size(), 1, "the host's room asks Game Center")
	var first: Object = kit.mm.finds[0][0]
	t.check(int(first.get("max_players")) <= 8 and int(first.get("max_players")) >= 2, "within Game Center's limit (%s)" % str(first.get("max_players")))
	t.check(first.get("player_attributes") != null, "first: with roles")
	var bad := FakeErr.new()
	bad.code = 13
	bad.message = "The requested operation could not be completed because the match request is invalid."
	(kit.mm.finds[0][1] as Callable).call(null, bad)
	await _frames(3)
	t.eq(kit.mm.finds.size(), 2, "retried once")
	var second: Object = kit.mm.finds[1][0]
	t.eq(second.get("player_attributes"), null, "the retry has no roles")
	t.eq(int(second.get("player_group")), Social.code_group("ACE347"), "same party code group")
	t.eq(_events.size(), 0, "nothing reported yet")
	(kit.mm.finds[1][1] as Callable).call(null, bad)
	await _frames(3)
	t.eq(kit.mm.finds.size(), 2, "not retried again")
	t.check(_events.size() == 1 and String((_events[0] as Array)[0]) == "failed", "then reported: %s" % str(_events))
	tr.close()
	Social.simple_requests = false
	await _end()
