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
##
## Pass 8 challenges (docs/ECONOMY.md §10): the service's snapshot carries
## the player's daily and weekly challenges; challenge_cards() is the Season
## Pass view, round_summary()["challenges"] a round's part, and
## pinned_challenge_text() the one pinned goal for the pause/map area.
## Progress and the bonus Season XP are only ever the service's.

signal changed
signal round_updated(match_id: String)
## Pass 8: a challenge the service just reported complete (its card)
signal challenge_completed(card: Dictionary)

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
		# Pass 8: the one pinned challenge (a catalogue id; this device only)
		# and the completions already announced (instance ids, bounded)
		"challenge_pin": "",
		"challenge_seen": [],
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
	return not a.is_empty() and Cloud.profile_id() != "" and String(a.get("profile_id", "")) == Cloud.profile_id() and not _cached().is_empty()


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
	var a := _cached()
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
		var a := _cached()
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
## {xp, premium, claimed, service_tiers}.  xp is the service's recorded
## Season XP, never capped or rewritten here: the tier is always computed
## from it and this game's table (Pass 9: XP earned past the old tier 30 now
## counts toward tiers 31-100).  service_tiers (Pass 9): the last tier the
## game service can grant (service_tiers()).
func season_state(sid: String) -> Dictionary:
	var a := _season_account()
	var s: Dictionary = a.get("season", {}).get(sid, {})
	var claimed := {}
	for k in s.get("claimed", []):
		claimed[String(k)] = true
	return {"xp": int(s.get("xp", 0)), "premium": bool(s.get("premium", false)) or owns_id("season:%s:premium" % sid), "claimed": claimed,
		"service_tiers": service_tiers(sid)}


## The snapshot season state is read from: the live one when synced, the
## last one while offline.
func _season_account() -> Dictionary:
	var a: Dictionary = _account()
	if a.is_empty() and Cloud.profile_id() == "":
		a = _cached()   # offline view of the last snapshot
	return a


## FINAL_RELEASE_SWEEP: the last snapshot for offline views, only when it
## came from the deployment this install talks to now: an App Store install
## never shows a TestFlight (sandbox) balance or item, nor the other way
## round.  (The development single endpoint has no environment to compare.)
func _cached() -> Dictionary:
	var a: Dictionary = state.get("account", {})
	var want := Cloud.wallet_environment()
	if a.is_empty() or (want != "" and String(a.get("environment", "")) != want):
		return {}
	return a


## Pass 9: the last tier of this game's table that the game service can
## grant.  A current service says (its snapshot's season "tiers"); an older
## one (catalogue version 2, 30 tiers) is known by its catalogue version, so
## a reward it doesn't have is shown as earned, never as a Claim that would
## do nothing.  Without any snapshot: this game's own table.
func service_tiers(sid: String) -> int:
	var local := Economy.max_tier(sid)
	var a := _season_account()
	if a.is_empty():
		return local
	var s: Dictionary = a.get("season", {}).get(sid, {})
	if int(s.get("tiers", 0)) > 0:
		return mini(local, int(s["tiers"]))
	var v := int(a.get("catalogue_version", Catalogue.version()))
	return mini(local, Economy.tiers_in_version(sid, v)) if v < Catalogue.version() else local


func premium(sid: String) -> bool:
	return bool(season_state(sid)["premium"])


## Everything claimable now (Economy.claimable), minus cells past the
## service's table and cells whose claim is already queued (sent or waiting
## to be sent: it completes by itself, so it is never queued twice).
func claimable(sid: String) -> Array:
	var st := season_state(sid)
	return Economy.claimable(sid, int(st["xp"]), bool(st["premium"]), st["claimed"], int(st["service_tiers"])).filter(
		func(c: Dictionary) -> bool: return not claim_pending(sid, int(c["tier"]), String(c["track"])))


## Pass 9: a claim of this cell is in the outbox (offline, or its reply was
## lost): it is retried with the same key until the service answers.
func claim_pending(sid: String, tier: int, track: String) -> bool:
	var path := "/v1/season/%s/claim" % sid
	for op in state["outbox"]:
		if String(op.get("kind", "")) != "claim" or String(op.get("path", "")) != path or String(op.get("profile_id", "")) != Cloud.profile_id():
			continue
		for c in (op.get("body", {}) as Dictionary).get("claims", []):
			if c is Dictionary and int(c.get("tier", 0)) == tier and String(c.get("track", "")) == track:
				return true
	return false


# ------------------------------------------------------------------ snapshot
## Applies a wallet snapshot from the service (every wallet reply carries
## one).  Older revisions never replace newer ones.
func apply_snapshot(w: Variant) -> void:
	if not (w is Dictionary) or (w as Dictionary).is_empty():
		return
	var wd: Dictionary = w
	# FINAL_RELEASE_SWEEP: a reply from the deployment this install just left
	# (it was in flight during a move) is never applied as this one's
	var env := String(wd.get("environment", ""))
	if Cloud.wallet_environment() != "" and env != "" and env != Cloud.wallet_environment():
		return
	var pid := String(wd.get("profile_id", Cloud.profile_id()))
	var cur: Dictionary = state.get("account", {})
	if String(cur.get("profile_id", "")) == pid and String(cur.get("environment", "")) == env and int(wd.get("revision", 0)) < int(cur.get("revision", 0)):
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
			# Pass 9: the last tier the service's table has (absent from an
			# older service: then its catalogue version tells)
			if int(s.get("tiers", 0)) > 0:
				seasons[String(sid)]["tiers"] = int(s["tiers"])
	state["account"] = {
		"profile_id": pid, "environment": String(wd.get("environment", "")), "balance": maxi(0, int(wd.get("balance", 0))),
		"revision": int(wd.get("revision", 0)), "debt": int(wd.get("debt", 0)),
		# (null when the service can't bind purchases: then nothing is bought)
		"app_account_token": String(wd["app_account_token"]) if wd.get("app_account_token") is String else "", "entitlements": ent, "season": seasons,
		"synced_at": now(), "catalogue_version": int(wd.get("catalogue_version", Catalogue.version())),
	}
	var ch: Variant = wd.get("challenges")
	if ch is Dictionary:
		var cd: Dictionary = (ch as Dictionary).duplicate(true)
		cd["received_at"] = now()
		state["account"]["challenges"] = cd
		_announce_completions(cd)
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
##
## Pass 8: a rotating skin is bought through its scheduled offer (`offer`,
## or the item's active offer): only while Offers trusts the service's time
## and the offer is on sale, at the offer's price.  The service checks the
## offer again on its own clock when it accepts the purchase; if the offer
## changed first, nothing is charged ("offer_changed").  A queued purchase
## retried after the offer ended returns the accepted result (same key).
func spend(item_id: String, offer: Dictionary = {}) -> Dictionary:
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
	var body := {"item_id": item_id, "price": price, "catalogue_version": Catalogue.version()}
	var meta := {"item": item_id}
	if Catalogue.is_rotation(item_id):
		var o := offer if not offer.is_empty() else Offers.offer_for(item_id)
		if not Offers.trusted():
			return {"ok": false, "state": "failed", "message": "Connect to refresh Shop. Nothing was charged."}
		if o.is_empty() or String(o.get("item_id", "")) != item_id or not Offers.is_active(o):
			return {"ok": false, "state": "offer_changed", "message": "This skin isn't in the Shop right now. Nothing was charged."}
		price = int(o["price"])
		body["price"] = price
		body["offer_id"] = String(o["offer_id"])
		meta["offer_id"] = String(o["offer_id"])
	if balance() < price:
		return {"ok": false, "state": "failed", "message": "You need %s more Coins." % Catalogue.format_coins(price - balance())}
	var op := _enqueue("spend", HTTPClient.METHOD_POST, "/v1/wallet/spend", body, meta)
	op["body"]["idempotency_key"] = op["id"]
	_save()
	var r := await _send(op)
	if bool(r.get("ok", false)):
		return {"ok": true, "state": "delivered", "message": "", "offer": r.get("offer", {})}
	if int(r.get("http_status", 0)) == 0:
		return {"ok": false, "state": "pending", "message": "We couldn't reach the game service. Your purchase will finish by itself when you're back online, and you won't be charged twice."}
	if String(r.get("error", "")) == "offer_changed":
		Offers.refresh()
		return {"ok": false, "state": "offer_changed", "message": "%s Check the Shop's current offers." % Cloud.explain(r)}
	return {"ok": false, "state": "failed", "message": Cloud.explain(r)}


# ------------------------------------------------------------------ claims
## The most cells one claim request carries (the version 2 service read at
## most 60; Pass 9: a whole 100-tier Claim all goes in several requests, so
## an older service still answers every one).
const CLAIM_BATCH := 60

## Claim Season rewards ([{tier, track}], or every claimable one).  Claims
## are idempotent on the service: claiming again never grants twice.  Each
## request is an outbox operation with its own idempotency key (a lost reply
## is retried and answers "already claimed").  Pass 9: every cell names the
## reward this game shows ("coins:50", an item id); a service on another
## catalogue grants nothing for a cell whose reward differs and says so.
## Returns {ok, state: delivered | pending | failed, claimed, skipped,
## message}: message is set when something earned couldn't be claimed.
func claim(sid: String, which: Array = []) -> Dictionary:
	var can := can_transact()
	if not bool(can["ok"]):
		return {"ok": false, "state": "failed", "message": String(can["message"])}
	var list := which if not which.is_empty() else claimable(sid)
	if list.is_empty():
		return {"ok": false, "state": "failed", "message": "Nothing to claim yet."}
	var cells: Array = list.map(func(c: Dictionary) -> Dictionary:
		return {"tier": int(c["tier"]), "track": String(c["track"]),
			"reward": Economy.reward_key(Economy.reward_at(sid, int(c["tier"]), String(c["track"])))})
	var ops: Array = []
	for i in range(0, cells.size(), CLAIM_BATCH):
		var op := _enqueue("claim", HTTPClient.METHOD_POST, "/v1/season/%s/claim" % sid, {"claims": cells.slice(i, i + CLAIM_BATCH)})
		op["body"]["idempotency_key"] = op["id"]
		ops.append(op)
	_save()
	var got: Array = []
	var skipped: Array = []
	for op in ops:
		if _inflight.has(op["id"]) or not (state["outbox"] as Array).has(op):
			continue   # the retry pump took it meanwhile (same key: applied once)
		var r := await _send(op)
		if bool(r.get("ok", false)):
			var granted: Array = r.get("claimed", [])
			got.append_array(granted)
			if r.has("skipped"):
				skipped.append_array(r["skipped"])
			else:
				# an older service answers only what it granted: a requested
				# cell it neither granted nor has as claimed is one its table
				# doesn't have
				var now_claimed: Dictionary = season_state(sid)["claimed"]
				for c in op["body"]["claims"]:
					var key := Economy.claim_key(int(c["tier"]), String(c["track"]))
					if not now_claimed.has(key) and not granted.any(func(g: Variant) -> bool: return g is Dictionary and Economy.claim_key(int(g.get("tier", 0)), String(g.get("track", ""))) == key):
						skipped.append({"tier": int(c["tier"]), "track": String(c["track"]), "reason": "no_reward"})
			continue
		if int(r.get("http_status", 0)) == 0:
			return {"ok": false, "state": "pending", "claimed": got, "skipped": skipped,
				"message": "We couldn't reach the game service. Your claim will finish when you're back online."}
		return {"ok": false, "state": "failed", "claimed": got, "skipped": skipped, "message": Cloud.explain(r)}
	return {"ok": true, "state": "delivered", "claimed": got, "skipped": skipped, "message": claim_note(skipped)}


func claim_all(sid: String) -> Dictionary:
	return await claim(sid, [])


## Pass 9: one honest sentence for cells the service answered but didn't
## grant because its catalogue differs from this game's ("" otherwise:
## already claimed, not reached or Premium needed are shown by the pass).
static func claim_note(skipped: Array) -> String:
	var changed := skipped.any(func(s: Variant) -> bool: return s is Dictionary and String(s.get("reason", "")) == "reward_changed")
	var missing := skipped.any(func(s: Variant) -> bool: return s is Dictionary and String(s.get("reason", "")) == "no_reward")
	if changed:
		return "The game service has a different reward at this tier, so nothing was claimed. Update the game to see it."
	if missing:
		return "The game service doesn't have this tier's reward yet, so nothing was claimed. It stays earned: claim it once the service is updated."
	return ""


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
		"coins_settled": 0, "season_xp_settled": 0, "practice": practice, "reason": String(elig["reason"]),
		# Pass 8: what this round should add to challenges (the service decides)
		"challenge_inc": ChallengeRules.increments(me, results), "challenge_credits": ChallengeRules.credits(me),
		"challenge_before": _progress_by_id()}
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
			"present": bool(r.get("present", true)), "away_s": float(r.get("away_s", 0.0)), "active_s": maxi(0, int(r.get("active_s", 0)))})
	# report v2 (Pass 8): rows carry active_s, bound into each player's digest
	_enqueue("round_report", HTTPClient.METHOD_POST, "/v1/rounds/%s/report" % mid.uri_encode(), {
		"report_version": ChallengeRules.REPORT_VERSION,
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
		"season_xp_settled": int(st.get("xp", 0)), "reason": String(st.get("reason", "")), "challenge_xp_settled": int(st.get("challenge_xp", 0))}
	if st.get("challenges") is Dictionary:
		patch["challenges"] = st["challenges"]
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
##                     (after includes challenge bonus XP)
##   lines / season_lines  the breakdown; message  one honest sentence
##   challenges        Pass 8: the round's part in challenges
##                     (_round_challenges); challenge_xp  bonus XP added
func round_summary(match_id: String) -> Dictionary:
	var rec: Dictionary = (state["rounds"] as Dictionary).get(match_id, {})
	if rec.is_empty():
		return {"state": "unknown", "message": "", "coins_collected": 0, "coins": 0, "coins_projected": 0, "season_xp": 0,
			"season_xp_projected": 0, "lines": [], "season_lines": [], "challenge_xp": 0,
			"challenges": {"state": "none", "result": "", "xp": 0, "lines": [], "message": ""}}
	var sid := String(rec.get("season", Catalogue.current_season_id()))
	var st := String(rec.get("state", "unknown"))
	var settled := st == "settled"
	var before := int(rec.get("xp_before", 0))
	var ch := _round_challenges(rec)
	var gain := int(rec.get("season_xp_settled", 0)) if settled else (int(rec.get("season_xp_projected", 0)) if st == "pending" else 0)
	gain += int(ch.get("xp", 0)) if st in ["settled", "pending"] else 0
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
		"challenge_xp": int(ch.get("xp", 0)) if settled else 0, "challenges": ch,
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


# ------------------------------------------------------------------ challenges
## Pass 8 (docs/ECONOMY.md §10).  The last challenge snapshot of this profile
## ({} if none): the live one when synced, the cached one while offline.
func _challenge_snapshot() -> Dictionary:
	var a: Dictionary = _account()
	if a.is_empty() and Cloud.profile_id() == "":
		a = _cached()
	var c: Variant = a.get("challenges")
	return c if c is Dictionary else {}


## The service's clock (unix s) by the offset seen at the last snapshot; the
## device's own clock when there is none.  Only for choosing which period's
## progress to show: the service assigns rounds to periods itself.
func server_now() -> int:
	var c := _challenge_snapshot()
	if c.is_empty() or float(c.get("server_time", 0)) <= 0.0:
		return now()
	return now() + int(float(c["server_time"]) / 1000.0) - int(c.get("received_at", now()))


## The Season Pass cards, daily then weekly: {id, name, task, period, metric,
## goal, xp, progress, completed, bonus_xp (delivered), resets_at (unix s),
## known (progress is the service's for the current period), pinned}.
func challenge_cards() -> Array:
	var snap := _challenge_snapshot()
	var t := server_now()
	var items: Array = snap.get("items", []) if snap.get("items") is Array else []
	var pin := pinned_challenge_id()
	var out: Array = []
	for d in ChallengeRules.defs():
		var kind := String(d["period"])
		var per := ChallengeRules.period_of(kind, t)
		var card := {"id": String(d["id"]), "name": String(d["name"]), "task": String(d["task"]), "period": kind, "metric": String(d["metric"]),
			"goal": int(d["goal"]), "xp": int(d["xp"]), "progress": 0, "completed": false, "bonus_xp": 0, "resets_at": int(per["end"]),
			"known": false, "pinned": String(d["id"]) == pin}
		for it in items:
			if it is Dictionary and String(it.get("challenge_id", "")) == card["id"] and int(float(it.get("period_start", 0)) / 1000.0) == int(per["start"]):
				card["goal"] = maxi(1, int(it.get("goal", card["goal"])))
				card["xp"] = int(it.get("xp", card["xp"]))
				card["progress"] = clampi(int(it.get("progress", 0)), 0, int(card["goal"]))
				card["completed"] = bool(it.get("completed", false))
				card["bonus_xp"] = int(it.get("bonus_xp", 0))
				card["known"] = true
		out.append(card)
	return out


## The Challenges section's one status line: {live, text}.  `live`: the
## cards show the service's progress for the current periods.
func challenge_status() -> Dictionary:
	var snap := _challenge_snapshot()
	var current := challenge_cards().any(func(c: Dictionary) -> bool: return bool(c["known"]))
	match service_state():
		"off":
			return {"live": false, "text": "Preview: no game service in this build. No progress or Season XP is added."}
		"signed_out":
			return {"live": false, "text": "Sign in with Game Center to track challenges."}
		"offline":
			if current:
				return {"live": true, "text": "Offline · progress as of %s" % ChallengeRules.local_clock(int(snap.get("received_at", now())))}
			return {"live": false, "text": "You're offline. Challenge progress shows when you reconnect."}
		"syncing":
			if not current:
				return {"live": false, "text": "Checking your challenges…"}
	if snap.is_empty():
		return {"live": false, "text": "Challenges aren't available from the game service yet."}
	if not current:
		return {"live": false, "text": "Checking your challenges…"}
	return {"live": true, "text": ""}


## The pinned challenge's id ("" when none).  One at a time, this device.
func pinned_challenge_id() -> String:
	var id := String(state.get("challenge_pin", ""))
	return id if not ChallengeRules.def(id).is_empty() else ""


## Pin a challenge ("" unpins; pinning another replaces the pin).
func pin_challenge(id: String) -> void:
	state["challenge_pin"] = id if not ChallengeRules.def(id).is_empty() else ""
	_save()
	changed.emit()


## One line for the pause / expanded map area: the pinned goal, "" when none
## is pinned.  `live_row` (optional, during a round): the player's row so far
## (role, stamps, unique_captures) adds a provisional "+2 this round" to a
## credits goal; the service counts it only after the round is verified.
func pinned_challenge_text(live_row: Dictionary = {}) -> String:
	var id := pinned_challenge_id()
	if id == "":
		return ""
	var card: Dictionary = {}
	for c in challenge_cards():
		if String(c["id"]) == id:
			card = c
	if card.is_empty():
		return ""
	var nm := String(card["name"])
	if not bool(card["known"]):
		return "%s · %s" % [nm, String(card["task"])]
	if bool(card["completed"]):
		return "%s complete · %s" % [nm, ChallengeRules.xp_text(int(card["xp"]))]
	var text := "%s %d/%d · %s" % [nm, int(card["progress"]), int(card["goal"]), ChallengeRules.xp_text(int(card["xp"]))]
	if not live_row.is_empty() and String(card["metric"]) == "credits":
		var add := mini(ChallengeRules.credits(live_row), int(card["goal"]) - int(card["progress"]))
		if add > 0:
			text += " · +%d this round (provisional)" % add
	return text


## {id: {progress, goal, known, completed}} now (a round's projection base).
func _progress_by_id() -> Dictionary:
	var out := {}
	for c in challenge_cards():
		out[String(c["id"])] = {"progress": int(c["progress"]), "goal": int(c["goal"]), "known": bool(c["known"]), "completed": bool(c["completed"])}
	return out


## A round's part in challenges (round_summary()["challenges"]):
##   state    settled | pending | practice | none
##   result   applied | inactive | no_evidence | closed (what the service did)
##   xp       bonus Season XP: added when settled, expected when pending
##   lines    [{id, name, period, progress (-1 unknown), goal, inc,
##            completed_now, xp}]
##   message  one honest sentence ("" when the lines say it all)
func _round_challenges(rec: Dictionary) -> Dictionary:
	var st := String(rec.get("state", ""))
	var none := {"state": "none", "result": "", "xp": 0, "lines": [], "message": ""}
	if st == "practice":
		var n := int(rec.get("challenge_credits", 0))
		return {"state": "practice", "result": "", "xp": 0, "lines": [],
			"message": "Training only: %d contribution credit%s. Practice doesn't count toward challenges." % [n, "" if n == 1 else "s"]}
	if st == "settled":
		var ch: Variant = rec.get("challenges")
		if not (ch is Dictionary):
			return none
		var cd: Dictionary = ch
		var lines: Array = []
		for it in cd.get("items", []):
			if not (it is Dictionary):
				continue
			if bool(it.get("completed", false)) and not bool(it.get("completed_now", false)):
				continue   # done before this round: nothing new to say
			var cid := String(it.get("challenge_id", ""))
			lines.append({"id": cid, "name": String(ChallengeRules.def(cid).get("name", cid)), "period": String(it.get("period", "")),
				"progress": int(it.get("progress", 0)), "goal": int(it.get("goal", 0)), "inc": int(it.get("inc", 0)),
				"completed_now": bool(it.get("completed_now", false)), "xp": int(it.get("xp", 0))})
		var res := String(cd.get("state", ""))
		var msg := ""
		match res:
			"inactive":
				msg = "No challenge progress: challenges count rounds with at least %d s of active play." % int(cd.get("need", 60))
			"no_evidence":
				msg = "No challenge progress from this round."
			"closed":
				msg = "This round was confirmed too late for its challenges."
		if res == "applied" and not (cd.get("closed", []) as Array).is_empty():
			msg = "Confirmed too late for that day's challenges; the week's counted."
		return {"state": "settled", "result": res, "xp": int(cd.get("xp", 0)), "lines": lines, "message": msg}
	if st == "pending":
		var inc: Dictionary = rec.get("challenge_inc", {})
		if String(inc.get("state", "")) != "applied":
			return {"state": "pending", "result": "inactive", "xp": 0, "lines": [],
				"message": "Not enough active play in this round to count for challenges."}
		var before: Dictionary = rec.get("challenge_before", {})
		var lines: Array = []
		var xp := 0
		for d in ChallengeRules.defs():
			var add := int(inc.get(String(d["metric"]), 0))
			if add <= 0:
				continue
			var b: Dictionary = before.get(String(d["id"]), {})
			var known := bool(b.get("known", false))
			if known and bool(b.get("completed", false)):
				continue
			var goal := int(b.get("goal", d["goal"]))
			var after := mini(goal, int(b.get("progress", 0)) + add)
			var done := known and after >= goal
			if done:
				xp += int(d["xp"])
			lines.append({"id": String(d["id"]), "name": String(d["name"]), "period": String(d["period"]), "progress": after if known else -1,
				"goal": goal, "inc": add, "completed_now": done, "xp": int(d["xp"]) if done else 0})
		return {"state": "pending", "result": "applied", "xp": xp, "lines": lines, "message": ""}
	return none


## Fresh completions in a snapshot become one milestone each (a new device
## doesn't replay old ones: only those completed in the last 15 minutes).
func _announce_completions(cd: Dictionary) -> void:
	var seen: Array = state.get("challenge_seen", [])
	var srv := int(float(cd.get("server_time", 0)) / 1000.0)
	var all: Array = []
	for k in ["items", "recent"]:
		if cd.get(k) is Array:
			all.append_array(cd[k])
	for it in all:
		if not (it is Dictionary) or int(it.get("bonus_xp", 0)) <= 0:
			continue
		var iid := String(it.get("instance_id", ""))
		if iid == "" or seen.has(iid):
			continue
		seen.append(iid)
		var at := int(float(it.get("completed_at", 0)) / 1000.0)
		if at > 0 and srv - at <= 15 * 60:
			var cid := String(it.get("challenge_id", ""))
			challenge_completed.emit.call_deferred({"id": cid, "name": String(ChallengeRules.def(cid).get("name", cid)),
				"xp": int(it.get("bonus_xp", 0)), "period": String(it.get("period", ""))})
	while seen.size() > 64:
		seen.pop_front()
	state["challenge_seen"] = seen
