extends RefCounted
## FINAL_RELEASE_SWEEP: one build, two service deployments (docs/final/commerce.md).
## The launch routing from the App Store receipt kind, the App Review
## fallback (production refuses a sandbox purchase -> the install moves to
## the sandbox deployment as the same player -> the still-unfinished
## transaction is delivered there and finished exactly once), the reverse,
## the persistence of the move, a move waiting for an open party, and a
## TestFlight install becoming an App Store install never showing the sandbox
## wallet.  Simulated store (src/dev/test_store_adapter.gd) and two
## test-double services (src/dev/fake_commerce_service.gd) standing in for the
## sandbox and production deployments.
var t
var rig
var prod
var sb
var _saved := {}

const PACK := "com.idlery.ultimatetrifecta.coins.1500"
const SKIN := "com.idlery.ultimatetrifecta.skin.moonlight_runner"
const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const R := preload("res://src/autoload/cloud_service.gd")


## Both deployments configured; the install's receipt kind is `kind`.
func _two(kind: int, gc: String = "T:_reviewer") -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(false, true)
	_saved = {"endpoints": Cloud.endpoints, "deployment": Cloud.deployment, "route_path": Cloud.route_path,
		"receipt": Cloud.receipt_override, "ios": Cloud.ios_override, "overrides": Cloud.transport_overrides}
	prod = FakeService.new()
	prod.environment = "Production"
	sb = FakeService.new()
	sb.environment = "Sandbox"
	prod.gc_player = gc
	sb.gc_player = gc
	Cloud.endpoints = {"production": {"url": "https://production.invalid", "key_pem": ""}, "sandbox": {"url": "https://sandbox.invalid", "key_pem": ""}}
	Cloud.route_path = "user://service_route_test.cfg"
	Cloud.reset_route_for_tests()
	Cloud.ios_override = 1
	_set_kind(kind)
	Cloud.transport_overrides = {"production": prod.handle, "sandbox": sb.handle}
	Cloud.identity_override = func() -> Dictionary:
		return {"ok": true, "player_id": gc, "bundle_id": "com.idlery.ultimatetrifecta", "timestamp": 0, "salt": "", "signature": "", "public_key_url": ""}
	Cloud.apply_route()
	Cloud.token = ""
	Cloud.profile = {}


func _set_kind(kind: int) -> void:
	Cloud.receipt_override = func() -> int: return kind


func _sign_in() -> void:
	await Cloud.sign_in()
	await Wallet.refresh()
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")


func _done() -> void:
	Cloud.reset_route_for_tests()
	Cloud.endpoints = _saved["endpoints"]
	Cloud.route_path = _saved["route_path"]
	Cloud.receipt_override = _saved["receipt"]
	Cloud.ios_override = _saved["ios"]
	Cloud.transport_overrides = _saved["overrides"]
	Cloud.identity_override = Callable()
	Cloud.apply_route()
	App.party_code = ""
	await rig.frames(4)   # let the doubles' last replies land
	await rig.end()


func _state(pid: String) -> String:
	return String(Purchases.states.get(pid, {}).get("state", ""))


func test_launch_routing_for_each_receipt_kind() -> void:
	var both := ["production", "sandbox"]
	var cases := [
		[R.Receipt.APP_STORE, true, "production", "receipt", "App Store install (receipt)"],
		[R.Receipt.SANDBOX, true, "sandbox", "receipt", "TestFlight / development (sandboxReceipt)"],
		[R.Receipt.NONE, true, "production", "default", "no receipt URL (never on current iOS): production, the safe default"],
		[R.Receipt.OTHER, true, "production", "default", "an unknown receipt name: production"],
		[R.Receipt.UNAVAILABLE, true, "production", "default", "an older native library without the call: production"],
		[R.Receipt.APP_STORE, false, "sandbox", "desktop", "desktop and tests: sandbox"],
	]
	for c in cases:
		var r: Dictionary = R.pick_route(both, bool(c[1]), int(c[0]), {})
		t.eq([r["deployment"], r["reason"]], [c[2], c[3]], String(c[4]))
	t.eq(R.pick_route(["single"], true, R.Receipt.APP_STORE, {})["deployment"], "single", "the development single endpoint")
	t.eq(R.pick_route(["production"], true, R.Receipt.SANDBOX, {})["deployment"], "production", "only one deployment configured: that one")
	t.eq(R.pick_route([], true, R.Receipt.APP_STORE, {})["deployment"], "", "none: the service is off")
	# a remembered move holds while the receipt kind is the one it was made with
	var moved := {"deployment": "sandbox", "receipt_kind": R.Receipt.APP_STORE}
	t.eq(R.pick_route(both, true, R.Receipt.APP_STORE, moved), {"deployment": "sandbox", "reason": "moved"}, "App Review install: stays moved")
	t.eq(R.pick_route(both, true, R.Receipt.UNAVAILABLE, moved)["deployment"], "production", "another kind of install: the move no longer applies")
	t.eq(R.pick_route(both, true, R.Receipt.SANDBOX, {"deployment": "production", "receipt_kind": R.Receipt.SANDBOX})["deployment"], "production",
		"the reverse move (a real purchase on a sandbox route) holds too")
	# the native call exists in the library this build ships (desktop: -1)
	t.check(ClassDB.class_exists("UTShare") and ClassDB.class_has_method("UTShare", "receipt_kind"), "UTShare.receipt_kind() is bound (tools/build_native.sh)")
	var saved: Callable = Cloud.receipt_override
	Cloud.receipt_override = Callable()
	if OS.get_name() != "iOS":
		t.eq(Cloud.read_receipt_kind(), R.Receipt.UNAVAILABLE, "desktop: unavailable, never a made-up kind")
	Cloud.receipt_override = saved
	# the configured pair from service.cfg, the single url only as a fallback
	var cf := ConfigFile.new()
	cf.set_value("service", "production_url", "https://p.example/")
	cf.set_value("service", "sandbox_url", "https://s.example")
	cf.set_value("service", "url", "https://dev.example")
	var keep: Dictionary = Cloud.endpoints
	Cloud.load_endpoints(cf)
	t.eq(Cloud.endpoints.keys(), ["production", "sandbox"], "the pair wins over the development url")
	t.eq(String(Cloud.endpoints["production"]["url"]), "https://p.example", "trailing slash trimmed")
	var cf2 := ConfigFile.new()
	cf2.set_value("service", "url", "https://dev.example")
	Cloud.load_endpoints(cf2)
	t.eq(Cloud.endpoints.keys(), ["single"], "only the old url: one development endpoint")
	Cloud.endpoints = keep


func test_app_review_fallback_moves_to_sandbox_and_finishes_once() -> void:
	await _two(R.Receipt.APP_STORE)
	t.eq(Cloud.deployment, "production", "an App Store install starts on production")
	await _sign_in()
	var token := Wallet.app_account_token()
	t.check(token != "", "the production wallet's token")
	t.eq(String(Wallet.state["account"]["environment"]), "production", "the production snapshot")
	# App Review: Apple's sandbox signs the purchase
	rig.store.environment = "Sandbox"
	t.check(bool(Purchases.buy(PACK)["ok"]), "Apple's sheet opens from the tap")
	await rig.until(func() -> bool: return Cloud.deployment == "sandbox", 200)
	t.eq(Cloud.deployment, "sandbox", "production refused it as a sandbox purchase: the install moved")
	t.eq(rig.store.finish_calls, 0, "nothing finished while it moves")
	t.eq(rig.store.unfinished.size(), 1, "the transaction stays with StoreKit")
	await rig.until(func() -> bool: return _state(PACK) == "delivered", 600)
	t.eq(_state(PACK), "delivered", "delivered by the sandbox deployment")
	t.eq(int(sb.wallet(Cloud.profile_id())["balance"]), 1500, "credited once, in the sandbox ledger")
	t.eq(sb.apple.size(), 1, "one transaction in the sandbox ledger")
	t.eq(prod.apple.size(), 0, "production recorded nothing")
	for pid in prod.wallets:
		t.eq(int(prod.wallets[pid]["balance"]), 0, "and credited nothing")
	t.eq(rig.store.finish_calls, 1, "finished exactly once, after the sandbox had it")
	t.eq(rig.store.unfinished.size(), 0, "nothing left unfinished")
	t.eq(Wallet.app_account_token(), token, "the same player: the same appAccountToken in both deployments")
	t.eq(Wallet.balance(), 1500, "the Shop shows the delivered Coins")
	t.eq(String(Wallet.state["account"]["environment"]), "sandbox", "the sandbox snapshot")
	# StoreKit hands it over again (a relaunch raced the finish): no second credit
	var tx: Dictionary = rig.store.finished[0]
	rig.store.transaction.emit(tx)
	await rig.frames(8)
	t.eq(int(sb.wallet(Cloud.profile_id())["balance"]), 1500, "a replay is not a second credit")
	# the move is remembered for this install
	var cf := ConfigFile.new()
	t.eq(cf.load(Cloud.route_path), OK, "the move is saved")
	t.eq([String(cf.get_value("route", "deployment")), int(cf.get_value("route", "receipt_kind")), String(cf.get_value("route", "reason"))],
		["sandbox", R.Receipt.APP_STORE, "sandbox_purchase"], "with the receipt kind it was made with")
	# a later purchase goes straight to the sandbox
	Purchases.states.clear()
	Purchases.buy(SKIN)
	await rig.until(func() -> bool: return Wallet.owns_id("outfit:moonlight_runner"), 300)
	t.check(Wallet.owns_id("outfit:moonlight_runner"), "the skin is delivered on the sandbox route")
	t.eq(prod.apple.size(), 0, "production still has nothing")
	await _done()


func test_move_persists_across_relaunch_and_happens_once_per_launch() -> void:
	await _two(R.Receipt.APP_STORE)
	await _sign_in()
	rig.store.environment = "Sandbox"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return _state(PACK) == "delivered", 600)
	t.eq(Cloud.deployment, "sandbox", "on the sandbox deployment")
	# relaunch: the remembered move applies
	Cloud._moved_this_run = false
	Cloud.apply_route()
	t.eq([Cloud.deployment, Cloud.route_reason], ["sandbox", "moved"], "relaunch: still the sandbox deployment")
	# a different kind of install (the receipt kind changed): the move is dropped
	_set_kind(R.Receipt.UNAVAILABLE)
	Cloud.apply_route()
	t.eq(Cloud.deployment, "production", "the move belonged to the other install kind")
	_set_kind(R.Receipt.APP_STORE)
	Cloud.apply_route()
	t.eq(Cloud.deployment, "sandbox", "on the sandbox deployment")
	# only one automatic move per launch: a production purchase now (it can't
	# happen in one install, but must not ping-pong) is kept, not moved
	Cloud._moved_this_run = true
	await Cloud.sign_in()
	await Wallet.refresh()
	rig.store.environment = "Production"
	Purchases.states.clear()
	var fin: int = rig.store.finish_calls
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return _state(PACK) == "failed", 300)
	t.eq(_state(PACK), "failed", "no second move in one launch")
	t.check(String(Purchases.states[PACK]["message"]).contains("kept safe"), String(Purchases.states[PACK]["message"]))
	t.eq(Cloud.deployment, "sandbox", "on the sandbox deployment")
	t.eq(rig.store.finish_calls, fin, "and never finished undelivered")
	t.eq(rig.store.unfinished.size(), 1, "StoreKit offers it again at the next launch")
	await _done()


func test_reverse_fallback_a_real_purchase_on_a_sandbox_route_moves_to_production() -> void:
	await _two(R.Receipt.SANDBOX, "T:_buyer")
	t.eq(Cloud.deployment, "sandbox", "on the sandbox deployment")
	await _sign_in()
	rig.store.environment = "Production"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return _state(PACK) == "delivered", 600)
	t.eq(Cloud.deployment, "production", "the sandbox refused a Production purchase: moved to production")
	t.eq(int(prod.wallet(Cloud.profile_id())["balance"]), 1500, "credited once by production")
	t.eq(sb.apple.size(), 0, "the sandbox recorded nothing")
	t.eq(rig.store.finish_calls, 1, "finished exactly once")
	await _done()


func test_a_move_waits_for_the_open_party() -> void:
	await _two(R.Receipt.APP_STORE)
	await _sign_in()
	App.party_code = "ABC234"   # a room on the production deployment
	rig.store.environment = "Sandbox"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return Cloud.pending_move() == "sandbox", 200)
	t.eq(Cloud.pending_move(), "sandbox", "the move waits while the party is open")
	t.eq(Cloud.deployment, "production", "the party's deployment is kept")
	t.eq(String(Purchases.view(PACK)["state"]), "delivering", "shown as paid and on its way")
	t.check(not bool(Purchases.view(PACK)["can_buy"]), "no accidental second purchase")
	var apple_calls := func() -> int: return prod.calls.filter(func(c: Array) -> bool: return String(c[1]) == "/v1/wallet/apple").size()
	var before: int = apple_calls.call()
	Cloud.changed.emit()   # (signals that normally retry a held purchase)
	Wallet.changed.emit()
	await rig.frames(30)
	t.eq(apple_calls.call(), before, "no retries against production meanwhile")
	App.party_code = ""   # back home
	await rig.until(func() -> bool: return _state(PACK) == "delivered", 900)
	t.eq(Cloud.deployment, "sandbox", "moved once the party ended")
	t.eq(int(sb.wallet(Cloud.profile_id())["balance"]), 1500, "delivered once")
	t.eq(rig.store.finish_calls, 1, "finished exactly once")
	await _done()


func test_testflight_to_app_store_never_shows_the_sandbox_wallet() -> void:
	await _two(R.Receipt.SANDBOX, "T:_tester")
	await _sign_in()
	rig.store.environment = "Sandbox"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return _state(PACK) == "delivered", 600)
	Purchases.states.clear()
	Purchases.buy(SKIN)
	await rig.until(func() -> bool: return _state(SKIN) == "delivered", 300)
	t.check(Wallet.owns_id("outfit:moonlight_runner"), "TestFlight: the sandbox skin")
	t.eq(Wallet.balance(), 1500, "TestFlight: the sandbox balance")
	t.eq(String(Wallet.state["account"]["environment"]), "sandbox", "the sandbox snapshot")
	# the App Store build is installed over it (same device data), first launch
	# offline.  The App Store's StoreKit has no sandbox transaction or
	# entitlement of the TestFlight build.
	rig.store.entitlements.clear()
	rig.store.unfinished.clear()
	Purchases.use_adapter(rig.store)
	prod.network_down = true
	_set_kind(R.Receipt.APP_STORE)
	Cloud.apply_route()
	Cloud.token = ""
	Cloud.profile = {}
	t.eq(Cloud.deployment, "production", "the App Store install routes to production")
	await Cloud.sign_in()
	t.check(not Cloud.signed_in(), "offline")
	t.eq(Wallet.balance(), 0, "offline, the cached sandbox balance is not shown as this install's")
	t.check(not Wallet.owns_id("outfit:moonlight_runner"), "nor the sandbox skin")
	t.eq(Wallet.season_state("s1")["xp"], 0, "nor the sandbox Season XP")
	# online: production's own (empty) wallet
	prod.network_down = false
	await Cloud.sign_in()
	await Wallet.refresh()
	await rig.until(func() -> bool: return Wallet.synced(), 300)
	t.eq(String(Wallet.state["account"]["environment"]), "production", "the production snapshot")
	t.eq(Wallet.balance(), 0, "production starts empty: no sandbox balance imported")
	t.check(not Wallet.owns_id("outfit:moonlight_runner"), "no sandbox skin in production")
	# a sandbox reply that was still in flight is never applied here
	var stale: Dictionary = sb.snapshot(sb.profiles.keys()[0])
	Wallet.apply_snapshot(stale)
	t.eq(String(Wallet.state["account"]["environment"]), "production", "a late sandbox snapshot is dropped")
	t.eq(Wallet.balance(), 0, "and shows nothing of the sandbox")
	await _done()
