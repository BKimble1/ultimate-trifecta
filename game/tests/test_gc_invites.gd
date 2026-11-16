extends RefCounted
## 2.3: in-game invites through Game Center (no game service): each friend
## row offers Invite, then shows the invite's answer; a "sent" invite with
## no answer lapses back to Invite.
var t


class FakePlayer:
	extends RefCounted
	var team_player_id := ""
	var game_player_id := ""

	func _init(tid: String, gid: String) -> void:
		team_player_id = tid
		game_player_id = gid


func test_rows_invite_through_game_center_and_show_the_answer() -> void:
	var saved_friends := Friends.friends
	var saved_presence := Friends.presence
	var saved_service := Friends.service
	var saved_sent := Friends.gc_sent
	Friends.gc_invite_test = true
	Friends.service = "off"
	Friends.presence = {}
	Friends.gc_sent = {}
	var ada := FakePlayer.new("T:ada", "G:ada")
	Friends.friends = [{"tid": "T:ada", "gid": "G:ada", "name": "Ada Lark", "player": ada},
		{"tid": "T:bo", "gid": "G:bo", "name": "Bo Reyes", "player": FakePlayer.new("T:bo", "G:bo")}]
	var m := FriendsPanel.model(Friends.friends[0])
	t.eq(String(m["action"]), "gc_invite", "a Game Center friend can be invited without the service")
	t.eq(String(m["label"]), "Game Center friend", "and says what they are (not 'Status unavailable')")
	Friends.gc_sent["T:ada"] = {"state": "sent", "at": Time.get_ticks_msec()}
	t.eq(String(FriendsPanel.model(Friends.friends[0])["action"]), "gc_sent", "sent: Invited ✓")
	Friends._on_gc_answer(ada, Social.INVITE_ACCEPTED)
	t.eq(Friends.gc_state("T:ada"), "accepted", "the answer finds the friend by team player id")
	t.eq(String(FriendsPanel.model(Friends.friends[0])["action"]), "gc_joining", "accepted: Joining…")
	Friends._on_gc_answer(FakePlayer.new("", "G:bo"), Social.INVITE_DECLINED)
	t.eq(Friends.gc_state("T:bo"), "declined", "or by game player id")
	t.eq(String(FriendsPanel.model(Friends.friends[1])["action"]), "gc_declined", "declined: Can't come")
	# an unanswered invite lapses back to Invite
	Friends.gc_sent["T:ada"] = {"state": "sent", "at": Time.get_ticks_msec() - Friends.GC_INVITE_TTL_MS - 10}
	t.eq(Friends.gc_state("T:ada"), "", "no answer: the invite lapses")
	t.eq(String(FriendsPanel.model(Friends.friends[0])["action"]), "gc_invite", "and Invite is back")
	# without Game Center, nothing is offered
	Friends.gc_invite_test = false
	t.eq(String(FriendsPanel.model(Friends.friends[0])["action"]), "", "no Game Center: no Invite")
	Friends.friends = saved_friends
	Friends.presence = saved_presence
	Friends.service = saved_service
	Friends.gc_sent = saved_sent


func test_invite_request_is_invite_only() -> void:
	# the request carries no automatch group or attributes (those would make
	# Game Center wait for a matching stranger), only the recipients
	var src := FileAccess.get_file_as_string("res://src/autoload/social_service.gd")
	var i := src.find("func invite_players(")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i)
	t.check(body.contains("\"recipients\"") and body.contains("\"recipient_response\""), "recipients and their answers")
	t.check(not body.contains("player_group") and not body.contains("player_attributes"), "no automatch group or attributes")
	t.check(body.contains("add_players") and body.contains("find_match"), "into the party's match, or a new one")
