extends RefCounted
## Final sweep: Game Center matchmaking failures reach the player.  Before,
## nothing listened to Social.room_failed, so a code join whose Game Center
## match never formed just waited.  A joining guest still waiting for its
## match is told why and taken back home; a host keeps their party (and its
## bots) and is told that others can't join; a failure with no waiting
## session is shown where the player is.
var t


func _cleanup() -> void:
	if App.session != null:
		App._close_session(false)
	App.goto_title()


func test_a_waiting_guest_is_told_and_taken_home() -> void:
	var was: Variant = Save.data.get("onboarded", false)
	Save.data["onboarded"] = true
	App._begin_session(NetSession.Mode.CLIENT, GameKitTransport.new(false), "ACDEFG")
	t.check(App.session != null and App.screen is LobbyScreen, "joining: the party room waits for the match")
	Social.room_failed.emit("The request timed out.")
	t.check(App.session == null, "the waiting join is closed")
	t.check(App.screen is TitleScreen, "and the player is back home")
	_cleanup()
	Save.data["onboarded"] = was


func test_a_host_keeps_the_party() -> void:
	App._begin_session(NetSession.Mode.HOST, GameKitTransport.new(true), "ACDEFH")
	var s := App.session
	Social.room_failed.emit("The request timed out.")
	t.check(App.session == s and App.screen is LobbyScreen, "the host's party stays open (bots can still play)")
	_cleanup()
