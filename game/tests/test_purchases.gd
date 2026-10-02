extends RefCounted
## V6 App Store purchases (simulated store + test-double service): product
## matching, success/cancel/pending/error, duplicate callbacks, interruption
## before and after the durable grant, finishing only after delivery,
## restore, refunds, account mismatch, sandbox/production separation,
## offline recovery and honest states with no service.
var t
var rig

const PACK := "com.idlery.ultimatetrifecta.coins.1500"
const SKIN := "com.idlery.ultimatetrifecta.skin.moonlight_runner"


func _rig() -> Variant:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	return rig


func _ready_to_buy() -> void:
	await _rig().begin()
	await rig.sign_in()
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")


func test_products_match_the_catalogue() -> void:
	await _ready_to_buy()
	for pid in Catalogue.product_ids():
		t.check(Purchases.products.has(pid), "%s loaded from the store" % pid)
	var v := Purchases.view(PACK)
	t.check(bool(v["can_buy"]), "available")
	t.eq(String(v["price"]), "(test price)", "the price shown is the store's own string, never a stored one")
	# a product the store doesn't return is unavailable, not priced
	rig.store.catalog.erase(PACK)
	Purchases.load_products(true)
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")
	t.eq(String(Purchases.view(PACK)["state"]), "unavailable", "unconfigured product: honestly unavailable")
	t.check(not bool(Purchases.view(PACK)["can_buy"]), "and can't be bought")
	await rig.end()


func test_success_delivers_then_finishes() -> void:
	await _ready_to_buy()
	var r := Purchases.buy(PACK)
	t.check(bool(r["ok"]), "Apple's sheet opens (simulated)")
	t.eq(String(Purchases.view(PACK)["state"]), "purchasing", "purchasing")
	await rig.until(func() -> bool: return String(Purchases.states.get(PACK, {}).get("state", "")) == "delivered")
	t.eq(Wallet.balance(), 1500, "+1,500 Coins delivered")
	t.eq(rig.store.unfinished.size(), 0, "the transaction is finished")
	t.eq(rig.store.finish_calls, 1, "finished exactly once, after delivery")
	t.check(String(Purchases.states[PACK]["message"]).contains("1,500"), "says what was added")
	await rig.end()


func test_cancel_pending_and_errors_are_honest() -> void:
	await _ready_to_buy()
	rig.store.next_outcome = "cancel"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return String(Purchases.states.get(PACK, {}).get("state", "")) == "cancelled")
	t.check(String(Purchases.states[PACK]["message"]).contains("weren't charged"), "cancel: not charged")
	t.eq(Wallet.balance(), 0, "nothing added")
	rig.store.next_outcome = "pending"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return String(Purchases.states.get(PACK, {}).get("state", "")) == "pending_approval")
	t.eq(String(Purchases.view(PACK)["state"]), "pending_approval", "Ask to Buy: waiting for approval")
	t.check(not bool(Purchases.view(PACK)["can_buy"]), "no second purchase while it waits")
	rig.store.approve_pending()
	await rig.until(func() -> bool: return Wallet.balance() == 1500)
	t.eq(Wallet.balance(), 1500, "approved later: delivered once")
	rig.store.next_outcome = "error"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return String(Purchases.states.get(PACK, {}).get("state", "")) == "failed")
	var msg := String(Purchases.states[PACK]["message"])
	t.check(msg.contains("If you were charged"), "an error is not presented as 'not charged': %s" % msg)
	rig.store.next_outcome = "unverified"
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return String(Purchases.states.get(PACK, {}).get("state", "")) == "failed" and Purchases.unverified_count > 0)
	t.eq(Wallet.balance(), 1500, "an unverified transaction delivers nothing")
	await rig.end()


func test_duplicate_callbacks_deliver_once() -> void:
	await _ready_to_buy()
	var tx: Dictionary = rig.store.make_tx(PACK, Wallet.app_account_token())
	rig.store.unfinished.append(tx)
	# StoreKit can hand the same unfinished transaction over again
	rig.store.transaction.emit(tx)
	rig.store.transaction.emit(tx)
	rig.store.fetch_unfinished()
	await rig.until(func() -> bool: return rig.store.unfinished.is_empty())
	await rig.frames(5)
	t.eq(Wallet.balance(), 1500, "three callbacks, one delivery")
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 1500, "the ledger agrees")
	await rig.end()


func test_interrupted_before_durable_grant() -> void:
	await _ready_to_buy()
	rig.svc.network_down = true
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return Purchases.delivering(PACK))
	await rig.frames(5)
	t.eq(rig.store.unfinished.size(), 1, "not delivered: NOT finished (StoreKit keeps it)")
	t.eq(String(Purchases.view(PACK)["state"]), "delivering", "shown as paid and on its way")
	t.check(not bool(Purchases.view(PACK)["can_buy"]), "no accidental second charge offered")
	# the app is killed: next launch replays the unfinished transaction
	rig.svc.network_down = false
	Purchases.use_adapter(rig.store)
	await rig.until(func() -> bool: return rig.store.unfinished.is_empty())
	t.eq(Wallet.balance(), 1500, "delivered after relaunch")
	t.eq(rig.store.finish_calls, 1, "then finished")
	await rig.end()


func test_interrupted_after_durable_grant_before_finish() -> void:
	await _ready_to_buy()
	rig.svc.drop_reply = true   # the service delivered; the app never heard
	Purchases.buy(PACK)
	await rig.until(func() -> bool: return Purchases.delivering(PACK) and not Purchases._delivering.size())
	await rig.frames(5)
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 1500, "the ledger has it")
	t.eq(rig.store.unfinished.size(), 1, "but without an answer it isn't finished")
	rig.svc.drop_reply = false
	Purchases.use_adapter(rig.store)   # relaunch: replayed
	await rig.until(func() -> bool: return rig.store.unfinished.is_empty())
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 1500, "the replay isn't a second credit")
	t.eq(Wallet.balance(), 1500, "the app shows the one delivery")
	await rig.end()


func test_skin_restore_and_refund() -> void:
	await _ready_to_buy()
	Purchases.buy(SKIN)
	await rig.until(func() -> bool: return Wallet.owns_id("outfit:moonlight_runner"))
	t.check(Wallet.owns_id("outfit:moonlight_runner"), "skin delivered")
	t.eq(String(Purchases.view(SKIN)["state"]), "owned", "an owned skin is never offered again")
	# a fresh install on another device: StoreKit's entitlements restore it
	var saved_entitlements: Array = rig.store.entitlements.duplicate()
	Wallet.state = Wallet.blank_state()
	Purchases.use_adapter(rig.store)
	rig.store.entitlements = saved_entitlements
	Purchases.restore()
	var done := {"v": {}}
	Purchases.restore_finished.connect(func(s: Dictionary) -> void: done["v"] = s, CONNECT_ONE_SHOT)
	await rig.until(func() -> bool: return not (done["v"] as Dictionary).is_empty(), 400)
	t.check(Purchases.apple_entitled("outfit:moonlight_runner"), "restored from Apple's entitlements")
	t.check(String(done["v"].get("message", "")).contains("Restored"), "says what was restored")
	t.eq(Wallet.balance(), 0, "restore never credits Coins")
	# Apple refunds it: the revocation removes the skin, nothing else
	rig.svc.grant(Cloud.profile_id(), 300)
	await Wallet.refresh()
	await Wallet.spend("outfit:robe")
	rig.store.refund(saved_entitlements[0])
	await rig.until(func() -> bool: return not Purchases.apple_entitled("outfit:moonlight_runner") and rig.store.unfinished.is_empty())
	await Wallet.refresh()
	t.check(not Wallet.owns_id("outfit:moonlight_runner"), "refunded skin revoked")
	t.check(Wallet.owns("outfit", "robe"), "unrelated items untouched")
	await rig.end()


func test_account_mismatch_and_environment() -> void:
	await _ready_to_buy()
	# a Coin purchase made for another game profile on this device
	var tx: Dictionary = rig.store.make_tx(PACK, "11111111-1111-4111-8111-111111111111")
	rig.store.unfinished.append(tx)
	rig.store.transaction.emit(tx)
	await rig.until(func() -> bool: return String(Purchases.states.get(PACK, {}).get("state", "")) == "failed")
	t.check(String(Purchases.states[PACK]["message"]).contains("another player profile"), "explains the account mismatch")
	t.eq(Wallet.balance(), 0, "not credited to the wrong account")
	t.eq(rig.store.unfinished.size(), 1, "kept unfinished for its owner")
	# a sandbox transaction against a production ledger
	rig.store.unfinished.clear()
	rig.svc.environment = "Production"
	var tx2: Dictionary = rig.store.make_tx(PACK, Wallet.app_account_token())
	rig.store.unfinished.append(tx2)
	Purchases.states.clear()
	rig.store.transaction.emit(tx2)
	await rig.until(func() -> bool: return String(Purchases.states.get(PACK, {}).get("state", "")) == "failed")
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 0, "sandbox credit never reaches a production balance")
	t.eq(rig.store.unfinished.size(), 1, "and nothing is finished undelivered")
	await rig.end()


func test_no_service_means_no_purchase_sheet() -> void:
	await _rig().begin(false, true)
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")
	var v := Purchases.view(PACK)
	t.eq(String(v["state"]), "service", "service off: unavailable, with the reason")
	t.check(String(v["message"]).contains("game service"), String(v["message"]))
	var r := Purchases.buy(PACK)
	t.check(not bool(r["ok"]), "buy refuses")
	t.eq(rig.store.purchases_started, 0, "Apple's sheet never opened")
	await rig.end()


func test_storekit_adapter_is_inert_off_ios() -> void:
	var a := StoreKitAdapter.new()
	t.check(not a.available(), "StoreKit is used only on iOS (desktop/tests: no store)")
	t.eq(a.adapter_name(), "none", "no adapter name")
	t.check(not ResourceLoader.exists("res://src/dev/test_store_adapter.gd") or OS.has_feature("editor") or not OS.has_feature("template"),
		"the simulated store lives in src/dev (excluded from exports)")
	var ep := FileAccess.get_file_as_string("res://export_presets.cfg")
	t.check(ep.contains("src/dev/*"), "export presets exclude src/dev (no purchase bypass ships)")
