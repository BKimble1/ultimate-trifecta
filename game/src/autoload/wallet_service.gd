extends Node
## Wallet (V6, autoload "Wallet"): the player's Coins, owned items and Season
## progress as the trusted service last reported them, cached on the device
## for offline use, plus a durable outbox for every operation whose result
## isn't known yet.
##
## Trust model (docs/ECONOMY.md):
##  - The service (service/src/commerce.js) owns the ledger: append-only
##    grants and spends with idempotency keys, wallet revisions, atomic
##    non-negative debit + entitlement, Season XP and claims, round
##    settlement and App Store delivery.  This node never mints Coins: it
##    shows the last verified snapshot and asks the service to act.
##  - Offline, Play and the Locker keep working from the cached snapshot and
##    the pre-V6 unlocks kept on this device; spending, claiming and buying
##    are unavailable and say why.  An operation that was sent but not
##    answered (a timeout is not a "no") stays in the outbox with its
##    idempotency key and is retried, so it can never apply twice.
##  - With no service in the build (game/config/service.cfg empty) the
##    economy is off: nothing is spent, claimed or settled, and screens say
##    so.  The pre-V6 balance stays visible as "on this device" until the
##    one-time import to an account.
##
## Results interface for the results screen: round_summary(match_id).

signal changed
signal round_updated(match_id: String)

const SCHEMA := 1
const MAX_ROUNDS := 60
const RETRY_S := 20.0

## where the wallet cache lives (tests point it elsewhere)
var path := "user://wallet.json"
var state: Dictionary = {}
var syncing := false
var last_error := ""
var _pumping := false
var _inflight := {}            # op id -> true (sent, awaiting reply)
var _retry: Timer
## tests: replace the clock (unix seconds)
var clock_override: Callable


func _ready() -> void:
	_load()
	_retry = Timer.new()
	_retry.wait_time = RETRY_S
	_retry.timeout.connect(_on_retry)
	add_child(_retry)
	Cloud.changed.connect(_on_cloud_changed)
	_mirror()


func now() -> int:
	return int(clock_override.call()) if clock_override.is_valid() else int(Time.get_unix_time_from_system())


static func blank_state() -> Dictionary:
	return {
		"schema": SCHEMA,
		"account": {},
		"legacy_import": {"state": "", "profile_id": "", "coins": 0, "items": [], "at": 0},
		"outbox": [],
		"rounds": {},
		"round_order": [],
	}


# ------------------------------------------------------------------ storage
## Reload from `path` (tests).
func reload() -> void:
	_inflight.clear()
	_load()
	_mirror()


func _load() -> void:
	state = blank_state()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and int((parsed as Dictionary).get("schema", 0)) == SCHEMA:
		for k in state:
			if (parsed as Dictionary).has(k):
				state[k] = parsed[k]


## Written whole to a temporary file, then renamed over the old one, so a
## crash mid-write never leaves a half wallet.
func _save() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))


## Profile deletion (Settings): the local cache, outbox and round records go.
## Account data is the service's to delete; Apple restores direct skins.
func reset_local() -> void:
	state = blank_state()
	_inflight.clear()
	_save()
	_mirror()
	changed.emit()


# ------------------------------------------------------------------ status
## "off" (no service in this build), "signed_out", "syncing", "offline"
## (configured, not reachable or not signed in) or "ready".
func service_state() -> String:
	if not Cloud.configured():
		return "off"
	if syncing and not synced():
		return "syncing"
	if Cloud.signed_in() and synced():
		return "ready"
	if Cloud.state == "signed_out" or Cloud.state == "off":
		return "signed_out"
	return "offline"


## The snapshot belongs to the signed-in profile.
func synced() -> bool:
	var a: Dictionary = state.get("account", {})
	return not a.is_empty() and Cloud.profile_id() != "" and String(a.get("profile_id", "")) == Cloud.profile_id()


## Can the player spend, claim or buy right now?  {ok, message}
func can_transact() -> Dictionary:
	match service_state():
		"off":
			return {"ok": false, "message": "The Shop, Coins and Season Pass need the game service, which isn't set up in this build. Your items and Coins are safe."}
		"signed_out":
			return {"ok": false, "message": "Sign in with Game Center to use Coins and the Season Pass."}
		"syncing":
			return {"ok": false, "message": "Checking your wallet…"}
		"offline":
			return {"ok": false, "message": "You're offline. Your items still work; buying and claiming come back when you reconnect."}
	return {"ok": true, "message": ""}


func app_account_token() -> String:
	return String(state.get("account", {}).get("app_account_token", "")) if synced() else ""


# ------------------------------------------------------------------ balance
func _account() -> Dictionary:
	return state.get("account", {}) if synced() else {}


## Coins to show.  The account balance when known; before any account, the
## pre-V6 balance still on this device.
func balance() -> int:
	if synced():
		return int(state["account"].get("balance", 0))
	if legacy_pending():
		return legacy_coins()
	var a: Dictionary = state.get("account", {})
	if not a.is_empty() and Cloud.profile_id() == "" and String(a.get("profile_id", "")) != "":
		return int(a.get("balance", 0))   # offline: the last verified balance
	return 0


## The balance shown is the device's pre-V6 balance, not an account's.
func balance_is_device() -> bool:
	return not synced() and legacy_pending()


func balance_label() -> String:
	return Catalogue.format_coins(balance())


func debt() -> int:
	return int(_account().get("debt", 0))


# ------------------------------------------------------------------ legacy
func legacy() -> Dictionary:
	return Save.data.get("legacy", {})


func legacy_coins() -> int:
	return int(legacy().get("coins", 0))


## The pre-V6 balance hasn't moved to an account yet.
func legacy_pending() -> bool:
	var li: Dictionary = state.get("legacy_import", {})
	return String(li.get("state", "")) == "" and (legacy_coins() > 0 or not (legacy().get("owned", []) as Array).is_empty())


# ------------------------------------------------------------------ ownership
## Ownership of a runner option (free base options, pre-V6 unlocks on this
## device, account entitlements, and Apple-verified direct skins).
func owns(field: String, key: String) -> bool:
	if Cosmetics.entry(field, key).is_empty():
		return false
	if Catalogue.is_free(field, key):
		return true
	return owns_id(Catalogue.id_for(field, key))


func owns_id(id: String) -> bool:
	if Catalogue.is_runner_item(id):
		var s := Catalogue.split(id)
		if Catalogue.is_free(String(s[0]), String(s[1])):
			return true
	return ownership_source(id) != ""


## Why the player owns it: "free", "device" (pre-V6 unlock), "account"
## source names (coin_purchase, apple, season, legacy_beta, admin), "apple"
## (verified StoreKit entitlement on this device) or "" (not owned).
func ownership_source(id: String) -> String:
	if Catalogue.is_runner_item(id):
		var s := Catalogue.split(id)
		if Catalogue.is_free(String(s[0]), String(s[1])):
			return "free"
	if (Save.data.get("owned", []) as Array).has(id):
		return "device"
	var ent: Dictionary = _account().get("entitlements", {})
	if ent.has(id) and not bool(ent[id].get("revoked", false)):
		return String(ent[id].get("source", "account"))
	if not synced():
		# offline: the last verified snapshot still counts for this profile
		var a: Dictionary = state.get("account", {})
		var e2: Dictionary = a.get("entitlements", {})
		if Cloud.profile_id() == "" and e2.has(id) and not bool(e2[id].get("revoked", false)):
			return String(e2[id].get("source", "account"))
	var pur := get_node_or_null("/root/Purchases")
	if pur != null and pur.apple_entitled(id):
		return "apple"
	return ""


## Everything owned in a Cosmetics field (Locker).
func owned_keys(field: String) -> Array:
	return Cosmetics.keys_of(field).filter(func(k: String) -> bool: return owns(field, k))


# ------------------------------------------------------------------ season
func season_state(sid: String) -> Dictionary:
	var a: Dictionary = _account()
	if a.is_empty() and Cloud.profile_id() == "":
		a = state.get("account", {})   # offline view of the last snapshot
	var s: Dictionary = a.get("season", {}).get(sid, {})
	var claimed := {}
	for k in s.get("claimed", []):
		claimed[String(k)] = true
	return {"xp": int(s.get("xp", 0)), "premium": bool(s.get("premium", false)) or owns_id("season:%s:premium" % sid), "claimed": claimed}


func premium(sid: String) -> bool:
	return bool(season_state(sid)["premium"])


func claimable(sid: String) -> Array:
	var st := season_state(sid)
	return Economy.claimable(sid, int(st["xp"]), bool(st["premium"]), st["claimed"])


# ------------------------------------------------------------------ snapshot
## Applies a wallet snapshot from the service (every wallet reply carries
## one).  Older revisions never replace newer ones.
func apply_snapshot(w: Variant) -> void:
	if not (w is Dictionary) or (w as Dictionary).is_empty():
		return
	var wd: Dictionary = w
	var pid := String(wd.get("profile_id", Cloud.profile_id()))
	var cur: Dictionary = state.get("account", {})
	if String(cur.get("profile_id", "")) == pid and int(wd.get("revision", 0)) < int(cur.get("revision", 0)):
		return   # an older reply arriving late
	var ent := {}
	for e in wd.get("entitlements", []):
		if e is Dictionary:
			ent[String(e.get("item", ""))] = {"source": String(e.get("source", "")), "revoked": bool(e.get("revoked", false))}
	var seasons := {}
	var sw: Variant = wd.get("season", {})
	if sw is Dictionary:
		for sid in sw:
			var s: Dictionary = sw[sid]
			seasons[String(sid)] = {"xp": int(s.get("xp", 0)), "premium": bool(s.get("premium", false)),
				"claimed": (s.get("claimed", []) as Array).map(func(x: Variant) -> String: return String(x))}
	state["account"] = {
		"profile_id": pid, "environment": String(wd.get("environment", "")), "balance": maxi(0, int(wd.get("balance", 0))),
		"revision": int(wd.get("revision", 0)), "debt": int(wd.get("debt", 0)),
		"app_account_token": String(wd.get("app_account_token", "")), "entitlements": ent, "season": seasons,
		"synced_at": now(), "catalogue_version": int(wd.get("catalogue_version", Catalogue.version())),
	}
	for r in wd.get("rounds", []):
		if r is Dictionary:
			_apply_round_status(r)
	_save()
	_mirror()
	changed.emit()


## Save.data["coins"] mirrors the balance for older readers (never read
## back here: the wallet's authority is the service snapshot).
func _mirror() -> void:
	if Save.data.has("coins"):
		Save.data["coins"] = balance()


# ------------------------------------------------------------------ service
## A sign-in schedules a wallet refresh shortly after (not inside flows that
## sign in only to re-confirm, e.g. profile deletion, which finish first).
const AUTO_REFRESH_S := 1.5
var _auto_at := -1.0


func _on_cloud_changed() -> void:
	if Cloud.signed_in() and not syncing and _auto_at < 0.0:
		var a: Dictionary = state.get("account", {})
		if a.is_empty() or String(a.get("profile_id", "")) != Cloud.profile_id() or now() - int(a.get("synced_at", 0)) > 60:
			_auto_at = AUTO_REFRESH_S
	changed.emit()


func _process(delta: float) -> void:
	if _auto_at < 0.0:
		return
	_auto_at -= delta
	if _auto_at <= 0.0:
		_auto_at = -1.0
		if Cloud.signed_in() and not syncing:
			refresh()


## GET /v1/wallet: the authoritative snapshot (account recovery and device
## sync: everything the account owns comes back from here, never as fresh
## credit).  Then the one-time legacy import and the outbox.
func refresh() -> Dictionary:
	if not Cloud.configured():
		return {"ok": false, "error": "service_off"}
	if syncing:
		while syncing:
			await get_tree().process_frame
		return {"ok": synced()}
	syncing = true
	changed.emit()
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_GET, "/v1/wallet")
	syncing = false
	if bool(r.get("ok", false)):
		last_error = ""
		apply_snapshot(r.get("wallet", {}))
		_maybe_legacy_import()
		_pump()
	else:
		last_error = Cloud.explain(r)
		changed.emit()
	return r


func _on_retry() -> void:
	if Cloud.signed_in() and not (state["outbox"] as Array).is_empty() and not _next_op().is_empty():
		_pump()
	elif (state["outbox"] as Array).is_empty():
		_retry.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and Cloud.signed_in():
		refresh()


# ------------------------------------------------------------------ outbox
static func new_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _enqueue(kind: String, method: int, path: String, body: Dictionary, meta: Dictionary = {}) -> Dictionary:
	var op := {"id": new_key(), "kind": kind, "method": method, "path": path, "body": body, "profile_id": Cloud.profile_id(),
		"created_at": now(), "attempts": 0, "next_at": 0}
	op.merge(meta)
	(state["outbox"] as Array).append(op)
	_save()
	if _retry and _retry.is_stopped():
		_retry.start()
	return op


func pending_ops() -> int:
	return (state["outbox"] as Array).size()


func pending_for(item_id: String) -> bool:
	for op in state["outbox"]:
		if String(op.get("item", "")) == item_id:
			return true
	return false


## Sends queued operations in order, one at a time.  Operations of another
## profile wait until that profile signs in (account change).  A network
## failure leaves the operation queued (a timeout is not a "no"); a definite
## refusal drops it with its message.
func _pump() -> void:
	if _pumping or not Cloud.signed_in():
		return
	_pumping = true
	var guard := 0
	while guard < 64:
		guard += 1
		var op := _next_op()
		if op.is_empty():
			break
		var r := await _send(op)
		if int(r.get("http_status", 0)) == 0 and not bool(r.get("ok", false)):
			break   # no answer: try again later
	_pumping = false


func _next_op() -> Dictionary:
	var t := now()
	for op in state["outbox"]:
		if String(op.get("profile_id", "")) == Cloud.profile_id() and not _inflight.has(op["id"]) and int(op.get("next_at", 0)) <= t:
			return op
	return {}


func _drop_op(id: String) -> void:
	var box: Array = state["outbox"]
	for i in range(box.size() - 1, -1, -1):
		if String(box[i].get("id", "")) == id:
			box.remove_at(i)


## Sends one operation and records its outcome.  Returns the reply.
func _send(op: Dictionary) -> Dictionary:
	var id := String(op["id"])
	_inflight[id] = true
	op["attempts"] = int(op.get("attempts", 0)) + 1
	var r: Dictionary = await Cloud.api(int(op["method"]), String(op["path"]), op["body"])
	_inflight.erase(id)
	var status := int(r.get("http_status", 0))
	if bool(r.get("ok", false)):
		apply_snapshot(r.get("wallet", {}))
	if _retry_later(op, r):
		_save()
		return r
	_after_op(op, r)
	if bool(r.get("ok", false)) or status >= 400:
		_drop_op(id)
	_save()
	return r


## A confirmation can reach the service before the host's registration of
## the round does (or while it is being retried): that "unknown round" is
## retried for a while instead of being taken as final.
const ACK_RETRY_S := 30 * 60


func _retry_later(op: Dictionary, r: Dictionary) -> bool:
	if String(op["kind"]) != "round_ack" or String(r.get("error", "")) != "no_round":
		return false
	if now() - int(op.get("created_at", 0)) > ACK_RETRY_S:
		return false
	op["next_at"] = now() + 60
	return true


func _after_op(op: Dictionary, r: Dictionary) -> void:
	match String(op["kind"]):
		"round_ack", "round_report":
			var mid := String(op.get("match_id", ""))
			if r.has("settlement") and r["settlement"] is Dictionary:
				var st: Dictionary = r["settlement"]
				st["match_id"] = mid
				_apply_round_status(st)
			elif int(r.get("http_status", 0)) >= 400 and String(op["kind"]) == "round_ack":
				_set_round(mid, {"state": "rejected", "reason": String(r.get("error", "")), "message": Cloud.explain(r)})
		"legacy_import":
			if bool(r.get("ok", false)):
				state["legacy_import"] = {"state": "done", "profile_id": Cloud.profile_id(), "coins": int(r.get("imported_coins", 0)),
					"items": r.get("imported_items", []), "already": bool(r.get("already_imported", false)), "at": now()}
			elif int(r.get("http_status", 0)) >= 400:
				state["legacy_import"] = {"state": "refused", "profile_id": Cloud.profile_id(), "reason": String(r.get("error", "")), "at": now()}
			changed.emit()


# ------------------------------------------------------------------ spend
## Buy a Coin-priced item (or Season Premium) in the Shop.  The service
## debits and grants atomically; the price shown is checked against the
## catalogue there.  Returns {ok, state: "delivered" | "pending" | "failed",
## message}.  "pending" = sent, no answer yet: it completes by itself (same
## idempotency key) and can never charge twice.
func spend(item_id: String) -> Dictionary:
	var can := can_transact()
	if not bool(can["ok"]):
		return {"ok": false, "state": "failed", "message": String(can["message"])}
	if not Catalogue.kind(item_id) in ["coin_item", "season_premium"]:
		return {"ok": false, "state": "failed", "message": "That item isn't sold for Coins."}
	if owns_id(item_id):
		return {"ok": false, "state": "failed", "message": "You already own this."}
	if pending_for(item_id):
		return {"ok": false, "state": "pending", "message": "Still finishing your last purchase of this item."}
	var price := Catalogue.price(item_id)
	if balance() < price:
		return {"ok": false, "state": "failed", "message": "You need %s more Coins." % Catalogue.format_coins(price - balance())}
	var op := _enqueue("spend", HTTPClient.METHOD_POST, "/v1/wallet/spend",
		{"item_id": item_id, "price": price, "catalogue_version": Catalogue.version()}, {"item": item_id})
	op["body"]["idempotency_key"] = op["id"]
	_save()
	var r := await _send(op)
	if bool(r.get("ok", false)):
		return {"ok": true, "state": "delivered", "message": ""}
	if int(r.get("http_status", 0)) == 0:
		return {"ok": false, "state": "pending", "message": "We couldn't reach the game service. Your purchase will finish by itself when you're back online, and you won't be charged twice."}
	return {"ok": false, "state": "failed", "message": Cloud.explain(r)}


# ------------------------------------------------------------------ claims
## Claim Season rewards ([{tier, track}], or every claimable one).  Claims
## are idempotent on the service: claiming again never grants twice.
func claim(sid: String, which: Array = []) -> Dictionary:
	var can := can_transact()
	if not bool(can["ok"]):
		return {"ok": false, "state": "failed", "message": String(can["message"])}
	var list := which if not which.is_empty() else claimable(sid)
	if list.is_empty():
		return {"ok": false, "state": "failed", "message": "Nothing to claim yet."}
	var body := {"claims": list.map(func(c: Dictionary) -> Dictionary: return {"tier": int(c["tier"]), "track": String(c["track"])})}
	var op := _enqueue("claim", HTTPClient.METHOD_POST, "/v1/season/%s/claim" % sid, body)
	op["body"]["idempotency_key"] = op["id"]
	_save()
	var r := await _send(op)
	if bool(r.get("ok", false)):
		return {"ok": true, "state": "delivered", "claimed": r.get("claimed", []), "message": ""}
	if int(r.get("http_status", 0)) == 0:
		return {"ok": false, "state": "pending", "message": "We couldn't reach the game service. Your claim will finish when you're back online."}
	return {"ok": false, "state": "failed", "message": Cloud.explain(r)}


func claim_all(sid: String) -> Dictionary:
	return await claim(sid, [])


# ------------------------------------------------------------------ legacy import
## Once per account: the pre-V6 balance and unlocks on this device move to
## the signed-in account (bounded by Economy.legacy_import_amount on the
## service; recorded with source "legacy_beta").  Idempotent: the service
## keys it by account, so a second device or a retry imports nothing more.
func _maybe_legacy_import() -> void:
	if not legacy_pending() or not synced():
		return
	for op in state["outbox"]:
		if String(op["kind"]) == "legacy_import":
			return
	var lg := legacy()
	_enqueue("legacy_import", HTTPClient.METHOD_POST, "/v1/wallet/legacy-import", {
		"coins": legacy_coins(), "items": lg.get("owned", []), "online_rounds": int(lg.get("online_rounds", 0)),
		"practice_rounds": int(lg.get("practice_rounds", 0)), "from_version": int(lg.get("from_version", 0)),
	})


# ------------------------------------------------------------------ rounds
## Host, at round start: register the round with the service (room, match
## ID, the admitted players' profiles) so its result can be settled.  Only
## service-backed online parties register; practice never does.
func round_started(info: Dictionary) -> void:
	var s := App.session
	if s == null or not is_instance_valid(s) or not s.is_host() or s.mode == NetSession.Mode.OFFLINE:
		return
	if bool(info.get("practice", false)) or App.party_code == "" or not Cloud.signed_in():
		return
	var parts: Array = []
	for e in info.get("roster", []):
		if bool(e.get("is_bot", false)):
			continue
		var pid := _pid_for_slot(int(e.get("slot", -1)))
		if pid != "":
			parts.append({"profile_id": pid, "slot": int(e["slot"])})
	if parts.size() < 1:
		return
	_enqueue("round_register", HTTPClient.METHOD_POST, "/v1/rounds", {"code": App.party_code, "match_id": String(info.get("match_id", "")),
		"participants": parts, "round": int(info.get("round", 1))}, {"match_id": String(info.get("match_id", ""))})
	_pump()


func _pid_for_slot(slot: int) -> String:
	var s := App.session
	if s == null or not is_instance_valid(s) or slot < 0 or slot >= s.roster.size() or s.roster[slot] == null:
		return ""
	return String(s.roster[slot].get("pid", ""))


func _pid_for_uid(uid: String) -> String:
	var s := App.session
	if s == null or not is_instance_valid(s):
		return ""
	for e in s.roster:
		if e != null and String(e.get("uid", "")) == uid:
			return String(e.get("pid", ""))
	return ""


## Called once per round result (Save.apply_results).  Projects the round's
## Coins and Season XP, records what will happen to them, and (online, with
## the service) queues the confirmation; the host also reports the result.
## Returns the round summary.
func settle_round(results: Dictionary, me: Dictionary, practice: bool) -> Dictionary:
	var mid := String(results.get("match_id", ""))
	if mid == "":
		return {}
	if (state["rounds"] as Dictionary).has(mid):
		return round_summary(mid)
	var elig := Economy.eligibility(results, me, practice)
	var picked := Economy.coins_picked(me, results)
	var c := Economy.round_coins(me, results)
	var sx := Economy.round_season_xp(me, results)
	var sid := Catalogue.current_season_id()
	var before := int(season_state(sid)["xp"])
	var rec := {"match_id": mid, "at": now(), "coins_collected": picked, "coins_projected": int(c["coins"]), "lines": c["lines"],
		"season_xp_projected": int(sx["xp"]), "season_lines": sx["lines"], "xp_before": before, "season": sid,
		"coins_settled": 0, "season_xp_settled": 0, "practice": practice, "reason": String(elig["reason"])}
	if int(results.get("outcome", 0)) == TC.Outcome.CANCELLED:
		rec["state"] = "cancelled"
	elif practice:
		rec["state"] = "practice"
	elif not bool(elig["eligible"]):
		rec["state"] = "not_eligible"
	elif not Cloud.configured():
		rec["state"] = "no_service"
	elif App.party_code == "":
		rec["state"] = "unverified_room"
	else:
		rec["state"] = "pending"
	_set_round(mid, rec)
	if String(rec["state"]) == "pending":
		var s := App.session
		var hosting := s != null and is_instance_valid(s) and s.is_host()
		if hosting:
			_report_round(results)
		_enqueue("round_ack", HTTPClient.METHOD_POST, "/v1/rounds/%s/ack" % mid.uri_encode(),
			{"digest": Economy.row_digest(mid, results, me)}, {"match_id": mid})
		_pump()
	return round_summary(mid)


func _report_round(results: Dictionary) -> void:
	var mid := String(results.get("match_id", ""))
	var rows: Array = []
	for r in results.get("players", []):
		if not (r is Dictionary) or bool(r.get("is_bot", false)):
			continue
		var pid := _pid_for_uid(String(r.get("uid", "")))
		if pid == "":
			continue
		rows.append({"profile_id": pid, "slot": int(r.get("slot", -1)), "role": int(r.get("role", 0)), "stamps": int(r.get("stamps", 0)),
			"finished": bool(r.get("finished", false)), "first_home": Economy.first_home(r, results),
			"unique_captures": int(r.get("unique_captures", 0)), "coins_picked": maxi(0, int(r.get("coins_picked", 0))),
			"present": bool(r.get("present", true)), "away_s": float(r.get("away_s", 0.0))})
	_enqueue("round_report", HTTPClient.METHOD_POST, "/v1/rounds/%s/report" % mid.uri_encode(), {
		"outcome": int(results.get("outcome", 0)), "round_time_s": float(results.get("round_time", 0.0)),
		"coin_spawns": int(results.get("coin_spawns", Catalogue.economy().get("eligibility", {}).get("max_coin_spawns", 10))),
		"players": rows}, {"match_id": mid})


func _set_round(mid: String, patch: Dictionary) -> void:
	var rounds: Dictionary = state["rounds"]
	var rec: Dictionary = rounds.get(mid, {"match_id": mid})
	rec.merge(patch, true)
	rounds[mid] = rec
	var order: Array = state["round_order"]
	if not order.has(mid):
		order.append(mid)
	# bounded display history; rounds still waiting on the service are kept
	while order.size() > MAX_ROUNDS:
		var victim := ""
		for m in order:
			if String(rounds.get(m, {}).get("state", "")) != "pending":
				victim = String(m)
				break
		if victim == "":
			break
		order.erase(victim)
		rounds.erase(victim)
	_save()
	round_updated.emit(mid)


## A settlement reported by the service ({match_id, state, coins, xp, reason}).
func _apply_round_status(st: Dictionary) -> void:
	var mid := String(st.get("match_id", ""))
	if mid == "":
		return
	var patch := {"state": String(st.get("state", "pending")), "coins_settled": int(st.get("coins", 0)),
		"season_xp_settled": int(st.get("xp", 0)), "reason": String(st.get("reason", ""))}
	if not (state["rounds"] as Dictionary).has(mid):
		patch["at"] = now()
	_set_round(mid, patch)


## The results screen's view of one round:
##   state     cancelled | practice | not_eligible | no_service |
##             unverified_room | pending | settled | capped | rejected |
##             mismatch | unknown
##   coins_collected   pickups this round (shown in every state)
##   coins             settled Coins (0 until settled), coins_projected
##   season_xp         settled XP, season_xp_projected
##   xp_before/xp_after, tier_before/tier_after, frac_before/frac_after
##   lines / season_lines  the breakdown; message  one honest sentence
func round_summary(match_id: String) -> Dictionary:
	var rec: Dictionary = (state["rounds"] as Dictionary).get(match_id, {})
	if rec.is_empty():
		return {"state": "unknown", "message": "", "coins_collected": 0, "coins": 0, "coins_projected": 0, "season_xp": 0,
			"season_xp_projected": 0, "lines": [], "season_lines": []}
	var sid := String(rec.get("season", Catalogue.current_season_id()))
	var st := String(rec.get("state", "unknown"))
	var settled := st == "settled"
	var before := int(rec.get("xp_before", 0))
	var gain := int(rec.get("season_xp_settled", 0)) if settled else (int(rec.get("season_xp_projected", 0)) if st == "pending" else 0)
	var after := before + gain
	var pb := Economy.tier_progress(sid, before)
	var pa := Economy.tier_progress(sid, after)
	return {
		"match_id": match_id, "state": st, "reason": String(rec.get("reason", "")), "message": _round_message(rec), "season": sid,
		"coins_collected": int(rec.get("coins_collected", 0)), "coins": int(rec.get("coins_settled", 0)),
		"coins_projected": int(rec.get("coins_projected", 0)), "season_xp": int(rec.get("season_xp_settled", 0)),
		"season_xp_projected": int(rec.get("season_xp_projected", 0)), "xp_before": before, "xp_after": after,
		"tier_before": int(pb["tier"]), "tier_after": int(pa["tier"]), "frac_before": float(pb["frac"]), "frac_after": float(pa["frac"]),
		"lines": rec.get("lines", []), "season_lines": rec.get("season_lines", []), "final": st != "pending",
	}


func _round_message(rec: Dictionary) -> String:
	var picked := int(rec.get("coins_collected", 0))
	var got := "" if picked <= 0 else (" You collected %d coin%s." % [picked, "" if picked == 1 else "s"])
	match String(rec.get("state", "")):
		"cancelled":
			return "This round was cancelled, so it pays nothing."
		"practice":
			return "Practice rounds don't add Coins or Season XP.%s" % got
		"not_eligible":
			match String(rec.get("reason", "")):
				"away":
					return "You were away for most of this round, so it pays nothing."
				"few_humans":
					return "Coins and Season XP need at least two players in the round (bots don't count)."
			return "This round doesn't pay Coins or Season XP."
		"no_service":
			return "Coins and Season XP are saved by the game service, which isn't set up in this build, so this round's rewards weren't added.%s" % got
		"unverified_room":
			return "This party wasn't created through the game service, so its rewards can't be verified or added."
		"pending":
			return "Adding your rewards… they're checked by the game service and saved once."
		"settled":
			return "Added to your account."
		"capped":
			return "You've reached today's limit of rewarded rounds. Play on for fun; rewards return tomorrow (UTC)."
		"mismatch":
			return "Your game and the host's report didn't match, so this round wasn't paid."
		"rejected":
			return "The game service couldn't verify this round, so it wasn't paid."
	return ""
