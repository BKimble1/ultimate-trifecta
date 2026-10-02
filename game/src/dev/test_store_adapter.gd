extends StoreAdapter
## TEST ADAPTER (src/dev: never exported, so a release build can't select
## it).  A simulated App Store for client tests and labelled captures: it
## behaves like StoreKit 2 as the purchase service sees it (verified
## transactions until finished, unfinished replay at start/resume, Ask to
## Buy, cancel, errors, entitlements for non-consumables, refunds), but its
## transactions are unsigned "test." JWS strings that only the test double
## service accepts.  Prices are placeholders the tests choose, never shown
## as real prices outside labelled captures.

var catalog := {}            # product_id -> {display_name, display_price}
var next_outcome := "success"   # success | cancel | pending | error | unverified | invalid
var unfinished: Array = []   # tx dicts (not finished)
var finished: Array = []
var entitlements: Array = [] # non-consumable tx dicts
var environment := "Sandbox"
var purchases_started := 0
var finish_calls := 0
var _seq := 7000
var _pending: Array = []     # [product_id, token] waiting for approval


func _init() -> void:
	for pid in Catalogue.product_ids():
		var p := Catalogue.product(pid)
		catalog[pid] = {"display_name": Catalogue.display_name(String(p["item"])), "display_price": "(test price)"}


func available() -> bool:
	return true


func adapter_name() -> String:
	return "test"


func start() -> void:
	fetch_unfinished()


func request_products(ids: PackedStringArray) -> void:
	var out: Array = []
	for pid in ids:
		if catalog.has(pid):
			out.append({"product_id": pid, "display_name": catalog[pid]["display_name"], "display_price": catalog[pid]["display_price"],
				"description": ""})
	products_loaded.emit.call_deferred(out, true)


func make_tx(pid: String, token: String, revoked: bool = false) -> Dictionary:
	_seq += 1
	var payload := {"transactionId": str(_seq), "originalTransactionId": str(_seq), "productId": pid, "appAccountToken": token,
		"environment": environment, "bundleId": "com.idlery.ultimatetrifecta", "revocationDate": 1 if revoked else 0}
	return {"transaction_id": str(_seq), "original_id": str(_seq), "product_id": pid,
		"jws": "test." + Marshalls.utf8_to_base64(JSON.stringify(payload)), "purchase_date": Time.get_unix_time_from_system(),
		"revocation_date": 1.0 if revoked else 0.0, "ownership_type": "purchased", "handle": null, "token": token}


func purchase(pid: String, token: String) -> void:
	purchases_started += 1
	if not catalog.has(pid):
		purchase_result.emit.call_deferred({}, Status.INVALID_PRODUCT, "Invalid Product")
		return
	match next_outcome:
		"cancel":
			purchase_result.emit.call_deferred({"product_id": pid}, Status.USER_CANCELLED, "User cancelled")
		"pending":
			_pending.append([pid, token])
			purchase_result.emit.call_deferred({"product_id": pid}, Status.PENDING, "Purchase pending")
		"error":
			purchase_result.emit.call_deferred({"product_id": pid}, Status.CANCELLED, "The network connection was lost.")
		"unverified":
			purchase_result.emit.call_deferred({"product_id": pid}, Status.UNVERIFIED, "Unverified transaction")
		"invalid":
			purchase_result.emit.call_deferred({"product_id": pid}, Status.INVALID_PRODUCT, "Invalid Product")
		_:
			var tx := make_tx(pid, token)
			unfinished.append(tx)
			purchase_result.emit.call_deferred(tx, Status.OK, "")


## Ask to Buy: a parent approves later; the transaction arrives as an update.
func approve_pending() -> void:
	for p in _pending:
		var tx := make_tx(String(p[0]), String(p[1]))
		unfinished.append(tx)
		transaction.emit.call_deferred(tx)
	_pending.clear()


## Apple refunds a purchase: the revoked transaction arrives as an update.
func refund(tx: Dictionary) -> void:
	var r := tx.duplicate()
	var payload: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(String(tx["jws"]).substr(5)))
	payload["revocationDate"] = 1
	r["jws"] = "test." + Marshalls.utf8_to_base64(JSON.stringify(payload))
	r["revocation_date"] = 1.0
	entitlements = entitlements.filter(func(e: Dictionary) -> bool: return String(e["transaction_id"]) != String(tx["transaction_id"]))
	unfinished.append(r)
	transaction.emit.call_deferred(r)


func restore() -> void:
	restore_done.emit.call_deferred(true, "")


func fetch_entitlements() -> void:
	for tx in entitlements:
		transaction.emit.call_deferred(tx)


func fetch_unfinished() -> void:
	for tx in unfinished:
		transaction.emit.call_deferred(tx)


func finish(tx: Dictionary) -> void:
	finish_calls += 1
	var tid := String(tx.get("transaction_id", ""))
	for i in range(unfinished.size() - 1, -1, -1):
		if String(unfinished[i]["transaction_id"]) == tid:
			var done: Dictionary = unfinished[i]
			unfinished.remove_at(i)
			finished.append(done)
			if String(Catalogue.product(String(done["product_id"])).get("kind", "")) == "apple_skin" and float(done["revocation_date"]) == 0.0:
				entitlements.append(done)


func is_finished(tid: String) -> bool:
	return finished.any(func(t: Dictionary) -> bool: return String(t["transaction_id"]) == tid)
