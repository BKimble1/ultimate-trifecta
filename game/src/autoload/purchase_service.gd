extends Node
## Purchases (V6, autoload "Purchases"): Apple in-app purchases for the Shop.
##
## Products (config/catalogue.json "products"): six consumable Coin packs
## and two permanent (non-consumable) skins.  Season 1 Premium is bought with
## Coins (Wallet.spend), never here.  Prices are StoreKit's localized ones;
## a product StoreKit doesn't return is shown as unavailable, never with a
## made-up price.
##
## Transaction contract (docs/COMMERCE_SETUP.md):
##  1. buy() runs only from an explicit tap and opens Apple's own sheet.
##  2. StoreKit verifies the transaction on the device (only verified ones
##     reach `transaction`); the service verifies its signed JWS again
##     (Apple's certificate chain, bundle, product, environment, account).
##  3. The service delivers it exactly once (keyed by transaction ID).
##  4. The reply's wallet snapshot updates the Shop and Locker.
##  5. Only then is the transaction finished.  Without an answer it stays
##     unfinished and StoreKit hands it back (launch, resume, retry), so an
##     interrupted purchase is delivered later, once.
##  6. Refunds/revocations arrive as transactions with a revocation date
##     (and as App Store Server Notifications on the service).
## Cancel, Ask to Buy (pending), unavailable products, account changes and
## offline states each get an honest state; a timeout is never shown as
## "not charged", and a pack waiting for delivery can't be bought again by
## accident.

signal products_changed
signal state_changed(product_id: String)
signal restore_finished(summary: Dictionary)

const PRODUCTS_TTL_S := 600
const RESTORE_QUIET_S := 3.0

var adapter: StoreAdapter
var products: Dictionary = {}          # product_id -> {display_name, display_price, description}
var products_state := "idle"           # idle | loading | loaded | failed | unsupported
var states: Dictionary = {}            # product_id -> {state, message}
var _delivering: Dictionary = {}       # transaction_id -> true
var _held: Dictionary = {}             # transaction_id -> tx (waiting for the service)
var _entitled: Dictionary = {}         # item_id -> true: verified non-consumable on this Apple Account
var _loaded_at := 0
var _restoring := false
var _restore_seen: Array = []
var _restore_timer: Timer
var unverified_count := 0


func _ready() -> void:
	_restore_timer = Timer.new()
	_restore_timer.one_shot = true
	_restore_timer.timeout.connect(_restore_settled)
	add_child(_restore_timer)
	var a: StoreAdapter = null
	if OS.get_cmdline_user_args().has("--store-test") and ResourceLoader.exists("res://src/dev/test_store_adapter.gd"):
		# development captures only: src/dev is not exported, so a release
		# build can't pick this (no purchase bypass ships)
		a = (load("res://src/dev/test_store_adapter.gd") as GDScript).new()
	use_adapter(a if a != null else StoreKitAdapter.new())
	Cloud.changed.connect(_retry_held)
	Wallet.changed.connect(_retry_held)


## Swap the store (tests use the simulated store).
func use_adapter(a: StoreAdapter) -> void:
	if adapter != null:
		for sig in ["products_loaded", "purchase_result", "transaction", "unverified", "restore_done"]:
			for c in adapter.get_signal_connection_list(sig):
				adapter.disconnect(sig, c["callable"])
	adapter = a
	products.clear()
	states.clear()
	_delivering.clear()
	_held.clear()
	_entitled.clear()
	products_state = "idle" if adapter.available() else "unsupported"
	adapter.products_loaded.connect(_on_products)
	adapter.purchase_result.connect(_on_purchase_result)
	adapter.transaction.connect(_on_transaction)
	adapter.unverified.connect(_on_unverified)
	adapter.restore_done.connect(_on_restore_done)
	if adapter.available():
		adapter.start()
		adapter.fetch_entitlements()
		load_products()
	products_changed.emit()


func supported() -> bool:
	return adapter != null and adapter.available()


func load_products(force: bool = false) -> void:
	if not supported() or products_state == "loading":
		return
	if not force and products_state == "loaded" and Time.get_unix_time_from_system() - _loaded_at < PRODUCTS_TTL_S:
		return
	products_state = "loading"
	products_changed.emit()
	adapter.request_products(Catalogue.product_ids())


func _on_products(list: Array, ok: bool) -> void:
	products.clear()
	for p in list:
		if Catalogue.product(String(p["product_id"])).is_empty():
			continue   # not ours: ignored
		products[String(p["product_id"])] = p
	products_state = "loaded" if ok else "failed"
	_loaded_at = int(Time.get_unix_time_from_system())
	products_changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and supported():
		adapter.fetch_unfinished()
		_retry_held()


# ------------------------------------------------------------------ views
func _set_state(pid: String, st: String, message: String = "") -> void:
	states[pid] = {"state": st, "message": message}
	state_changed.emit(pid)


## A verified Apple entitlement for this item on this Apple Account
## (direct skins; restored through StoreKit's current entitlements).
func apple_entitled(item_id: String) -> bool:
	return _entitled.has(item_id)


func delivering(pid: String) -> bool:
	for tid in _delivering:
		if String(_delivering[tid]) == pid:
			return true
	for tid in _held:
		if String(_held[tid].get("product_id", "")) == pid:
			return true
	return false


## What the Shop shows for a product: {state, price, title, message,
## can_buy, button}.  state: unsupported | service | loading | unavailable |
## available | owned | purchasing | pending_approval | delivering |
## delivered | cancelled | failed
func view(pid: String) -> Dictionary:
	var item := Catalogue.item_for_product(pid)
	var p: Dictionary = products.get(pid, {})
	var out := {"state": "available", "price": String(p.get("display_price", "")), "title": String(p.get("display_name", "")),
		"message": "", "can_buy": false, "button": ""}
	var st: Dictionary = states.get(pid, {})
	var cur := String(st.get("state", ""))
	if Catalogue.kind(item) == "apple_skin" and Wallet.owns_id(item):
		out.merge({"state": "owned", "button": "Owned", "message": ""}, true)
		return out
	if delivering(pid) or cur == "delivering":
		out.merge({"state": "delivering", "button": "Adding…", "message": "Your purchase went through. Adding it to your account…"}, true)
		return out
	if cur in ["purchasing", "pending_approval"]:
		out.merge({"state": cur, "button": "Waiting…" if cur == "pending_approval" else "Opening…",
			"message": String(st.get("message", ""))}, true)
		return out
	if not supported():
		out.merge({"state": "unsupported", "button": "Unavailable", "message": "App Store purchases work in the iPhone and iPad app."}, true)
		return out
	var can := Wallet.can_transact()
	if not bool(can["ok"]):
		out.merge({"state": "service", "button": "Unavailable", "message": String(can["message"])}, true)
		return out
	if products_state == "loading" or products_state == "idle":
		out.merge({"state": "loading", "button": "Loading…", "message": "Getting prices from the App Store…"}, true)
		return out
	if p.is_empty():
		out.merge({"state": "unavailable", "button": "Not available", "message": "This item isn't available from the App Store right now."}, true)
		return out
	out["can_buy"] = true
	out["button"] = String(p.get("display_price", ""))
	if cur in ["cancelled", "failed", "delivered"]:
		out["state"] = cur
		out["message"] = String(st.get("message", ""))
	return out


## Pass 8: the Coin pack with the lowest price per Coin, computed only from
## StoreKit's own numeric prices, and only when every compared pack is priced
## in the same currency (the same currency text around the digits of its
## localized price) and it is cheaper per Coin than every other pack by more
## than rounding.  "" otherwise: no "best value" claim without real numbers.
func best_value_pack() -> String:
	var rows: Array = []
	var cur := ""
	for it in Catalogue.items_of_kind("coin_pack"):
		var pid := String(it.get("product", ""))
		var p: Dictionary = products.get(pid, {})
		var price := float(p.get("price", 0.0))
		var coins := int(it.get("coins", 0))
		if p.is_empty() or price <= 0.0 or coins <= 0:
			continue
		var c := currency_mark(String(p.get("display_price", "")))
		if c == "":
			return ""
		if cur == "":
			cur = c
		elif c != cur:
			return ""
		rows.append([price / coins, pid])
	if rows.size() < 2:
		return ""
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if float(rows[0][0]) >= float(rows[1][0]) * 0.999:
		return ""
	return String(rows[0][1])


## The currency part of a localized price ("$0.99" -> "$", "0,99 €" -> "€",
## "US$1.99" -> "US$"): everything but digits, separators and spaces.
static func currency_mark(display_price: String) -> String:
	var out := ""
	for ch in display_price:
		if not (ch in "0123456789.,'    "):
			out += ch
	return out


# ------------------------------------------------------------------ buying
## From an explicit tap only.  Opens Apple's purchase sheet, or returns why
## it can't ({ok:false, message}).
func buy(pid: String) -> Dictionary:
	var v := view(pid)
	if not bool(v["can_buy"]):
		return {"ok": false, "message": String(v["message"]) if String(v["message"]) != "" else "This item can't be bought right now."}
	_set_state(pid, "purchasing", "Confirm with Apple to continue.")
	adapter.purchase(pid, Wallet.app_account_token())
	return {"ok": true}


func _on_purchase_result(tx: Dictionary, status: int, message: String) -> void:
	var pid := String(tx.get("product_id", ""))
	if pid == "":
		# no transaction: the result is about the purchase that is open now
		for k in states:
			if String(states[k].get("state", "")) == "purchasing":
				pid = String(k)
	match status:
		StoreAdapter.Status.OK:
			_on_transaction(tx)
		StoreAdapter.Status.USER_CANCELLED:
			_set_state(pid, "cancelled", "Purchase cancelled. You weren't charged.")
		StoreAdapter.Status.PENDING:
			_set_state(pid, "pending_approval", "Waiting for approval (Ask to Buy). It's added as soon as it's approved.")
		StoreAdapter.Status.INVALID_PRODUCT:
			_set_state(pid, "failed", "This item isn't available from the App Store right now.")
		StoreAdapter.Status.UNVERIFIED:
			unverified_count += 1
			_set_state(pid, "failed", "Apple couldn't verify this purchase, so nothing was added. If you were charged, contact Apple support for a refund.")
		_:
			# an error is not proof the purchase didn't happen: look again
			_set_state(pid, "failed", "The purchase didn't finish. If you were charged, it is added automatically as soon as the App Store confirms it.")
			if supported():
				adapter.fetch_unfinished()


func _on_unverified(_tx: Dictionary, _code: int) -> void:
	# never delivered, never logged (no payloads); counted for diagnostics
	unverified_count += 1


## Every verified transaction: a new purchase, an Ask to Buy approval, an
## unfinished one replayed at launch/resume, a restored entitlement, or a
## refund/revocation.  Duplicate callbacks are ignored while one delivery is
## running; the service ignores replays of a delivered transaction.
func _on_transaction(tx: Dictionary) -> void:
	var tid := String(tx.get("transaction_id", ""))
	var pid := String(tx.get("product_id", ""))
	var prod := Catalogue.product(pid)
	if tid == "" or prod.is_empty():
		return
	var item := String(prod.get("item", ""))
	if String(prod.get("kind", "")) == "apple_skin":
		if float(tx.get("revocation_date", 0.0)) > 0.0:
			_entitled.erase(item)
		else:
			_entitled[item] = true
		Wallet.changed.emit()
	if _restoring:
		_restore_seen.append(item)
		_restore_timer.start(RESTORE_QUIET_S)
	if _delivering.has(tid):
		return
	_deliver(tx)


func _deliver(tx: Dictionary) -> void:
	var tid := String(tx["transaction_id"])
	var pid := String(tx["product_id"])
	if not Cloud.configured() or not Cloud.signed_in():
		_held[tid] = tx
		_set_state(pid, "delivering", "Your purchase went through. It's added when you're signed in to the game service.")
		return
	_delivering[tid] = pid
	_held.erase(tid)
	_set_state(pid, "delivering")
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/wallet/apple", {"jws": String(tx.get("jws", "")),
		"transaction_id": tid, "product_id": pid})
	_delivering.erase(tid)
	if bool(r.get("ok", false)):
		Wallet.apply_snapshot(r.get("wallet", {}))
		adapter.finish(tx)    # only after the service has it durably
		var d: Dictionary = r.get("delivered", {})
		var msg := ""
		if bool(r.get("revoked", false)):
			msg = "A refunded purchase was removed."
		elif int(d.get("coins", 0)) > 0:
			msg = "+%s Coins added." % Catalogue.format_coins(int(d["coins"]))
		elif String(d.get("item", "")) != "":
			msg = "%s is in your Locker." % Catalogue.display_name(String(d["item"]))
		_set_state(pid, "delivered", msg)
		return
	var status := int(r.get("http_status", 0))
	if status == 0 or status >= 500 or String(r.get("error", "")) in ["network", "service_off", "game_center", "rate_limited"]:
		_held[tid] = tx    # retried later; never finished undelivered
		_set_state(pid, "delivering", "Your purchase went through. We'll add it as soon as the game service answers.")
		return
	match String(r.get("error", "")):
		"account_mismatch":
			_set_state(pid, "failed", "This purchase belongs to another player profile on this device. Sign in with that Game Center account to receive it.")
		"owned_by_other_profile":
			_set_state(pid, "failed", "This skin is already linked to another player profile.")
		_:
			# kept unfinished (no paid item is ever dropped); support can reconcile
			_set_state(pid, "failed", "We couldn't add this purchase (%s). It's kept safe; contact support with Settings › Profile." % Cloud.explain(r))


func _retry_held() -> void:
	if _held.is_empty() or not Cloud.signed_in() or not Wallet.synced():
		return
	for tid in _held.keys():
		if not _delivering.has(tid):
			_deliver(_held[tid])


# ------------------------------------------------------------------ restore
## Restore Purchases: Apple restores the permanent skins (AppStore.sync +
## current entitlements); the account ledger restores Coins, Coin-bought
## items and Season access (never as fresh credit).
func restore() -> void:
	if _restoring:
		return
	_restoring = true
	_restore_seen.clear()
	if supported():
		adapter.restore()
	else:
		_on_restore_done(false, "")
	if Cloud.signed_in():
		Wallet.refresh()


func restoring() -> bool:
	return _restoring


func _on_restore_done(ok: bool, message: String) -> void:
	if ok and supported():
		adapter.fetch_entitlements()
		_restore_timer.start(RESTORE_QUIET_S)
		return
	_restoring = false
	restore_finished.emit({"ok": ok, "items": [], "message": message if message != "" else "Apple couldn't restore purchases right now."})


func _restore_settled() -> void:
	if not _restoring:
		return
	_restoring = false
	var names: Array = []
	for it in _restore_seen:
		var n := Catalogue.display_name(String(it))
		if not names.has(n):
			names.append(n)
	restore_finished.emit({"ok": true, "items": _restore_seen.duplicate(),
		"message": ("Restored: %s." % ", ".join(names)) if not names.is_empty() else "No App Store skins to restore on this Apple Account. Coins and Coin-bought items come back from your game account."})
