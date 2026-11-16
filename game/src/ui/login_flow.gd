class_name LoginFlow
extends RefCounted
## What greets a player arriving home (2.2 build 15), one thing at a time,
## once home has settled (the launch curtain gone):
##   1. the daily present, once a day (DailyGift)
##   2. the event poster (ChampionPromo), every few launches or after time
##      away
## Runs on a cold launch and again when the game comes back from the
## background after a long time away.  Never during automation, before
## onboarding, in a party with others, or over a sheet that is already open.

## time away that counts as "coming back" (also brings the poster back)
const AWAY_S := 6 * 3600
const SETTLE_S := 0.9

## seconds between the last use and this launch or resume
static var away_s := 0
## off in the automated tests (screens there are built and torn down fast)
static var enabled := true
static var _running := false
static var _resume_due := false


## App start: count the launch and measure the time away.
static func note_launch() -> void:
	var now := Rankings.now()
	var last := int(Save.get_setting("last_active_at", 0))
	away_s = (now - last) if last > 0 else 0
	Save.set_setting("launches", int(Save.get_setting("launches", 0)) + 1)
	Save.set_setting("last_active_at", now)


## Going to the background: remember when.
static func note_pause() -> void:
	Save.set_setting("last_active_at", Rankings.now())


## Back from the background: after a long absence the greeting runs again
## (on home, now or the next time home is shown).
static func note_resume() -> void:
	var last := int(Save.get_setting("last_active_at", 0))
	var gone := (Rankings.now() - last) if last > 0 else 0
	Save.set_setting("last_active_at", Rankings.now())
	if gone >= AWAY_S or not DailyGift.seen_today():
		away_s = gone
		_resume_due = true
		var s: Variant = App.screen
		if s is LobbyScreen and (s as LobbyScreen).is_inside_tree():
			run(s as LobbyScreen)


static func pending_resume() -> bool:
	return _resume_due


## Home calls this on arrival.  Waits for the launch curtain and a moment
## on screen, then shows what is due, one after another.
static func run(screen: Screen) -> void:
	if _running or not enabled or App.dev_automation or not bool(Save.data.get("onboarded", false)):
		return
	_running = true
	_resume_due = false
	var tree := screen.get_tree()
	await _settle(screen, tree)
	if _ok(screen) and DailyGift.due():
		var g := DailyGift.open(screen as Screen)
		while is_instance_valid(g) and g.is_inside_tree():
			await tree.process_frame
		if _ok(screen):
			await tree.create_timer(0.4).timeout
	if _ok(screen):
		ChampionPromo.maybe_show(screen as Screen)
	_running = false


static func _settle(screen: Variant, tree: SceneTree) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(screen) and (screen as Node).is_inside_tree() and BootCurtain.live > 0 and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame
	if is_instance_valid(screen) and (screen as Node).is_inside_tree():
		await tree.create_timer(SETTLE_S).timeout


static func _ok(screen: Variant) -> bool:
	return is_instance_valid(screen) and (screen as Node).is_inside_tree() and App.screen == screen and not (screen as Screen).has_modal()
