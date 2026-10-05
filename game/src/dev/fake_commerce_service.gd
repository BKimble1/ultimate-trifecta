extends RefCounted
## TEST DOUBLE (src/dev: never exported).  An in-process stand-in for the
## commerce part of the game service, for client tests and labelled
## development captures.  It follows the service's contract
## (service/src/commerce.js, tested on its own with node --test): wallet
## snapshots with revisions, idempotency keys, atomic spend + entitlement,
## Season claims, round registration/report/ack settlement, App Store
## delivery keyed by transaction ID, the one-time legacy import, and the
## Pass 8 challenges (progress and the bonus once, settled with the round,
## by the registered start's UTC day/week with the 24 h grace).  It accepts
## the simulated store's unsigned "test." transactions, which the real
## service rejects (it verifies Apple's certificate chain).
##
## Pass 8 (DEV FIXTURE, never in a release: src/dev isn't exported): the
## Shop's rotating offers as service/src/offers.js serves them
## (GET /v1/shop/offers) and the same acceptance check on a spend, from the
## catalogue's schedule or one a test sets (use_schedule), judged by this
## double's own clock (clock_ms: a test or a labelled capture fixes it).
##
## Use: install(); Cloud.transport_override and identity_override point here.

var profiles := {}          # pid -> {gc}
var wallets := {}           # pid -> {balance, revision, debt, token, entitlements{}, season{sid:{xp, premium, claimed[]}}}
var ledger_keys := {}       # idem key -> reply
var apple := {}             # transaction id -> {pid, product, revoked}
var rounds := {}            # match id -> {host, participants{pid:slot}, report, acks{}, settled{}}
var legacy_done := {}       # pid -> {coins, items}
var challenge_rows := {}    # pid -> {instance_id: {challenge_id, period, period_start/end (ms), goal, xp, progress, completed_at}}
var challenge_bonus := {}   # pid -> {instance_id: {xp, match_id, at}}
var network_down := false
var drop_reply := false     # apply the request, then lose the reply (a timeout after commit)
var calls: Array = []       # [method, path] for assertions
var gc_player := "T:_tester"
var environment := "Sandbox"
var _seq := 0
## the double's clock (unix ms); unset = the real time
var clock_ms: Callable
## offers: [{offer_id, item_id, slot, price, revision, starts_at, ends_at (ms)}]
var schedule: Array = []
var schedule_revision := 1
var offers_supported := true
var offer_sales := {}       # idem key -> {offer_id, item_id, price, accepted_at}
const LOOKAHEAD_MS := 72 * 3600 * 1000


func _init() -> void:
	var sec := Catalogue.offers_section()
	schedule_revision = int(sec.get("schedule_revision", 1))
	for o in sec.get("schedule", []):
		schedule.append({"offer_id": String(o["offer_id"]), "item_id": String(o["item_id"]), "slot": int(o["slot"]), "price": int(o["price"]),
			"revision": int(o.get("revision", 1)), "starts_at": float(Catalogue.parse_utc_ms(String(o["starts_at_utc"]))),
			"ends_at": float(Catalogue.parse_utc_ms(String(o["ends_at_utc"])))})


func now_ms() -> float:
	return float(clock_ms.call()) if clock_ms.is_valid() else Time.get_unix_time_from_system() * 1000.0


## A test schedule (times in ms).
func use_schedule(list: Array, revision: int = 7) -> void:
	schedule = list.duplicate(true)
	schedule_revision = revision


func install() -> void:
	Cloud.transport_override = handle
	Cloud.identity_override = func() -> Dictionary:
		return {"ok": true, "player_id": gc_player, "bundle_id": "com.idlery.ultimatetrifecta", "timestamp": 0, "salt": "",
			"signature": "", "public_key_url": ""}


static func uninstall() -> void:
	Cloud.transport_override = Callable()
	Cloud.identity_override = Callable()
	Cloud.token = ""
	Cloud.profile = {}
	Cloud.state = "signed_out" if Cloud.configured() else "off"


func _pid_for(gc: String) -> String:
	for pid in profiles:
		if profiles[pid]["gc"] == gc:
			return pid
	_seq += 1
	var pid := "p_test%03d" % _seq
	profiles[pid] = {"gc": gc}
	return pid


func wallet(pid: String) -> Dictionary:
	if not wallets.has(pid):
		_seq += 1
		wallets[pid] = {"balance": 0, "revision": 0, "debt": 0, "token": "00000000-0000-4000-8000-%012d" % _seq,
			"entitlements": {}, "season": {"s1": {"xp": 0, "premium": false, "claimed": []}}}
	return wallets[pid]


func snapshot(pid: String) -> Dictionary:
	var w := wallet(pid)
	var ents: Array = []
	for id in w["entitlements"]:
		ents.append({"item": id, "source": w["entitlements"][id]["source"], "revoked": bool(w["entitlements"][id].get("revoked", false))})
	var rs: Array = []
	for mid in rounds:
		var st: Dictionary = rounds[mid].get("settled", {}).get(pid, {})
		if not st.is_empty():
			rs.append({"match_id": mid, "state": st["state"], "coins": st["coins"], "xp": st["xp"], "reason": st.get("reason", ""),
				"challenge_xp": int(st.get("challenge_xp", 0)), "challenges": st.get("challenges")})
	return {"profile_id": pid, "environment": environment.to_lower(), "balance": w["balance"], "revision": w["revision"], "debt": w["debt"],
		"app_account_token": w["token"], "entitlements": ents, "season": w["season"].duplicate(true), "catalogue_version": Catalogue.version(),
		"rounds": rs, "challenges": _challenges_view(pid)}


func _bump(pid: String) -> void:
	wallet(pid)["revision"] = int(wallet(pid)["revision"]) + 1


func grant(pid: String, coins: int) -> void:
	var w := wallet(pid)
	w["balance"] = int(w["balance"]) + coins
	_bump(pid)


func _ok(pid: String, extra: Dictionary = {}) -> Dictionary:
	var b := {"ok": true, "wallet": snapshot(pid)}
	b.merge(extra, true)
	return {"status": 200, "body": b}


func _err(status: int, code: String, message: String) -> Dictionary:
	return {"status": status, "body": {"ok": false, "error": code, "message": message}}


func _who(headers: PackedStringArray) -> String:
	for h in headers:
		if h.begins_with("Authorization: Bearer "):
			return h.substr(22)
	return ""


func handle(method: int, path: String, body: Variant, headers: PackedStringArray) -> Dictionary:
	await Engine.get_main_loop().process_frame
	calls.append([method, path])
	if network_down:
		return {"status": 0, "body": {"ok": false, "error": "network", "message": "Couldn't reach the game service. Check your connection."}}
	var r := _route(method, path, body if body is Dictionary else {}, _who(headers))
	if drop_reply and path != "/v1/auth/gamecenter":
		return {"status": 0, "body": {"ok": false, "error": "network", "message": "Couldn't reach the game service. Check your connection."}}
	return r


func _route(method: int, path: String, b: Dictionary, pid: String) -> Dictionary:
	if path == "/v1/config":
		return {"status": 200, "body": {"ok": true, "environment": environment.to_lower()}}
	if path == "/v1/shop/offers":
		return _offers() if offers_supported else _err(404, "no_route", "Not found.")
	if path == "/v1/auth/gamecenter":
		var p := _pid_for(String(b.get("player_id", "")))
		return {"status": 200, "body": {"ok": true, "token": p, "expires_at": (Time.get_unix_time_from_system() + 3600) * 1000,
			"profile": {"profile_id": p, "display_name": "Tester", "discriminator": "0001", "needs_name": false, "status": "active"}}}
	if pid == "" or not profiles.has(pid):
		return _err(401, "signed_out", "Please sign in.")
	if method == HTTPClient.METHOD_GET and path == "/v1/wallet":
		return _ok(pid)
	if method == HTTPClient.METHOD_POST and path == "/v1/wallet/spend":
		return _spend(pid, b)
	if method == HTTPClient.METHOD_POST and path == "/v1/wallet/apple":
		return _apple(pid, b)
	if method == HTTPClient.METHOD_POST and path == "/v1/wallet/legacy-import":
		return _legacy(pid, b)
	if method == HTTPClient.METHOD_POST and path.begins_with("/v1/season/") and path.ends_with("/claim"):
		return _claim(pid, path.get_slice("/", 3), b)
	if method == HTTPClient.METHOD_POST and path == "/v1/rounds":
		return _round_register(pid, b)
	if method == HTTPClient.METHOD_POST and path.begins_with("/v1/rounds/") and path.ends_with("/report"):
		return _round_report(pid, path.get_slice("/", 3).uri_decode(), b)
	if method == HTTPClient.METHOD_POST and path.begins_with("/v1/rounds/") and path.ends_with("/ack"):
		return _round_ack(pid, path.get_slice("/", 3).uri_decode(), b)
	return _err(404, "no_route", "Not found.")


func _spend(pid: String, b: Dictionary) -> Dictionary:
	var key := "spend:%s:%s" % [pid, String(b.get("idempotency_key", ""))]
	if ledger_keys.has(key):
		var extra := {"replay": true}
		if offer_sales.has(key):
			extra["offer"] = offer_sales[key]
			extra["accepted_at"] = offer_sales[key]["accepted_at"]
		return _ok(pid, extra)
	var id := String(b.get("item_id", ""))
	var price := Catalogue.price(id)
	if not Catalogue.kind(id) in ["coin_item", "season_premium"]:
		return _err(400, "not_for_sale", "That item isn't sold for Coins.")
	var w := wallet(pid)
	if (w["entitlements"] as Dictionary).has(id):
		return _err(409, "already_owned", "You already own this.")
	var offer := {}
	if Catalogue.is_rotation(id):
		var t := now_ms()
		var oid := String(b.get("offer_id", ""))
		if oid == "":
			offer = _active_for(id, t)
			if offer.is_empty():
				return _changed("not_in_rotation", "This skin isn't in the Shop right now. Nothing was charged.")
		else:
			for o in schedule:
				if String(o["offer_id"]) == oid:
					offer = o
			if offer.is_empty():
				return _changed("unknown_offer", "This offer isn't in the Shop any more. Nothing was charged.")
			if String(offer["item_id"]) != id:
				return _changed("item_mismatch", "This offer is for a different item. Nothing was charged.")
			if t < float(offer["starts_at"]):
				return _changed("not_started", "This offer hasn't started yet. Nothing was charged.")
			if t >= float(offer["ends_at"]):
				return _changed("expired", "This offer has left the Shop. Nothing was charged.")
		price = int(offer["price"])
		if int(b.get("price", -1)) != price:
			return _changed("price", "The price changed. Nothing was charged.")
	elif int(b.get("price", -1)) != price:
		return _err(409, "price_changed", "The price changed. Check it and try again.")
	if int(w["balance"]) < price:
		return _err(409, "insufficient_funds", "You don't have enough Coins.")
	w["balance"] = int(w["balance"]) - price
	w["entitlements"][id] = {"source": "coin_purchase"}
	if Catalogue.kind(id) == "season_premium":
		w["season"][String(Catalogue.item(id).get("season", "s1"))]["premium"] = true
	_bump(pid)
	ledger_keys[key] = true
	if not offer.is_empty():
		offer_sales[key] = {"offer_id": offer["offer_id"], "item_id": id, "price": price, "starts_at": offer["starts_at"],
			"ends_at": offer["ends_at"], "accepted_at": now_ms()}
		return _ok(pid, {"bought": id, "offer": offer_sales[key], "accepted_at": now_ms()})
	return _ok(pid, {"bought": id})


func _changed(reason: String, message: String) -> Dictionary:
	var r := _err(409, "offer_changed", message)
	r["body"]["reason"] = reason
	return r


func _active_for(id: String, t: float) -> Dictionary:
	var best := {}
	for o in schedule:
		if String(o["item_id"]) == id and float(o["starts_at"]) <= t and t < float(o["ends_at"]):
			if best.is_empty() or float(o["ends_at"]) > float(best["ends_at"]):
				best = o
	return best


func _offers() -> Dictionary:
	var t := now_ms()
	var cur: Array = []
	var up: Array = []
	var nxt := -1.0
	for o in schedule:
		if float(o["starts_at"]) <= t and t < float(o["ends_at"]):
			cur.append(o.duplicate())
			nxt = float(o["ends_at"]) if nxt < 0.0 else minf(nxt, float(o["ends_at"]))
		elif float(o["starts_at"]) > t and float(o["starts_at"]) <= t + LOOKAHEAD_MS:
			up.append(o.duplicate())
			nxt = float(o["starts_at"]) if nxt < 0.0 else minf(nxt, float(o["starts_at"]))
	cur.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	return {"status": 200, "body": {"ok": true, "server_time": t, "schedule_revision": schedule_revision, "slots": 4,
		"current": cur, "upcoming": up, "next_change_at": nxt if nxt >= 0.0 else null, "known_until": t + LOOKAHEAD_MS}}


func _apple(pid: String, b: Dictionary) -> Dictionary:
	var jws := String(b.get("jws", ""))
	if not jws.begins_with("test."):
		return _err(400, "bad_transaction", "This purchase couldn't be verified.")
	var payload: Variant = JSON.parse_string(Marshalls.base64_to_utf8(jws.substr(5)))
	if not (payload is Dictionary):
		return _err(400, "bad_transaction", "This purchase couldn't be verified.")
	var tx: Dictionary = payload
	if String(tx.get("environment", "")) != environment:
		return _err(400, "wrong_environment", "This purchase is from a different App Store environment.")
	var tid := String(tx.get("transactionId", ""))
	var prod := Catalogue.product(String(tx.get("productId", "")))
	if prod.is_empty():
		return _err(400, "unknown_product", "Unknown product.")
	var token := String(tx.get("appAccountToken", ""))
	if token != "" and token != String(wallet(pid)["token"]):
		return _err(409, "account_mismatch", "This purchase belongs to another player profile.")
	var revoked := float(tx.get("revocationDate", 0)) > 0.0
	if apple.has(tid):
		var rec: Dictionary = apple[tid]
		if rec["pid"] != pid:
			return _err(409, "account_mismatch", "This purchase belongs to another player profile.")
		if revoked and not bool(rec["revoked"]):
			_revoke(pid, prod, rec)
			return _ok(pid, {"revoked": true})
		return _ok(pid, {"replay": true, "delivered": {}})
	apple[tid] = {"pid": pid, "product": prod, "revoked": revoked}
	if revoked:
		return _ok(pid, {"revoked": true})
	var w := wallet(pid)
	var delivered := {}
	if String(prod["kind"]) == "coin_pack":
		w["balance"] = int(w["balance"]) + int(prod["coins"])
		delivered = {"coins": int(prod["coins"])}
	else:
		w["entitlements"][String(prod["item"])] = {"source": "apple"}
		delivered = {"item": String(prod["item"])}
	_bump(pid)
	return _ok(pid, {"delivered": delivered})


func _revoke(pid: String, prod: Dictionary, rec: Dictionary) -> void:
	rec["revoked"] = true
	var w := wallet(pid)
	if String(prod["kind"]) == "coin_pack":
		var take := mini(int(w["balance"]), int(prod["coins"]))
		w["balance"] = int(w["balance"]) - take
		w["debt"] = int(w["debt"]) + int(prod["coins"]) - take
	else:
		var e: Dictionary = w["entitlements"].get(String(prod["item"]), {})
		if not e.is_empty():
			e["revoked"] = true
	_bump(pid)


func _legacy(pid: String, b: Dictionary) -> Dictionary:
	if legacy_done.has(pid):
		return _ok(pid, {"already_imported": true, "imported_coins": 0, "imported_items": []})
	var coins := Economy.legacy_import_amount(int(b.get("coins", 0)), int(b.get("online_rounds", 0)), int(b.get("practice_rounds", 0)))
	var items: Array = []
	for id in b.get("items", []):
		if bool(Catalogue.item(String(id)).get("legacy", false)):
			items.append(String(id))
			wallet(pid)["entitlements"][String(id)] = {"source": "legacy_beta"}
	wallet(pid)["balance"] = int(wallet(pid)["balance"]) + coins
	_bump(pid)
	legacy_done[pid] = {"coins": coins, "items": items}
	return _ok(pid, {"imported_coins": coins, "imported_items": items})


func _claim(pid: String, sid: String, b: Dictionary) -> Dictionary:
	var w := wallet(pid)
	var s: Dictionary = w["season"][sid]
	var claimed := {}
	for k in s["claimed"]:
		claimed[k] = true
	var done: Array = []
	for c in b.get("claims", []):
		var tier := int(c["tier"])
		var track := String(c["track"])
		if Economy.cell_state(sid, tier, track, int(s["xp"]), bool(s["premium"]), claimed) != "claimable":
			continue
		var r := Economy.reward_at(sid, tier, track)
		if r.has("coins"):
			w["balance"] = int(w["balance"]) + int(r["coins"])
		elif not (w["entitlements"] as Dictionary).has(String(r["item"])):
			w["entitlements"][String(r["item"])] = {"source": "season"}
		claimed[Economy.claim_key(tier, track)] = true
		(s["claimed"] as Array).append(Economy.claim_key(tier, track))
		done.append({"tier": tier, "track": track})
	if not done.is_empty():
		_bump(pid)
	return _ok(pid, {"claimed": done})


func _round_register(pid: String, b: Dictionary) -> Dictionary:
	var mid := String(b.get("match_id", ""))
	if rounds.has(mid):
		return {"status": 200, "body": {"ok": true, "replay": true}}
	var parts := {}
	for p in b.get("participants", []):
		parts[String(p["profile_id"])] = int(p["slot"])
	rounds[mid] = {"host": pid, "participants": parts, "report": {}, "acks": {}, "settled": {}, "started_at": _now_ms()}
	return {"status": 200, "body": {"ok": true}}


func _round_report(pid: String, mid: String, b: Dictionary) -> Dictionary:
	if not rounds.has(mid) or rounds[mid]["host"] != pid:
		return _err(404, "no_round", "Unknown round.")
	rounds[mid]["report"] = b
	for p in rounds[mid]["acks"].keys():
		_try_settle(mid, p)
	return {"status": 200, "body": {"ok": true}}


func _round_ack(pid: String, mid: String, b: Dictionary) -> Dictionary:
	if not rounds.has(mid) or not rounds[mid]["participants"].has(pid):
		return _err(404, "no_round", "This round isn't registered.")
	rounds[mid]["acks"][pid] = String(b.get("digest", ""))
	_try_settle(mid, pid)
	var st: Dictionary = rounds[mid]["settled"].get(pid, {"state": "pending", "coins": 0, "xp": 0})
	var out := _ok(pid)
	out["body"]["settlement"] = st.duplicate()
	return out


func _try_settle(mid: String, pid: String) -> void:
	var rd: Dictionary = rounds[mid]
	if rd["report"].is_empty() or rd["settled"].has(pid):
		return
	var rep: Dictionary = rd["report"]
	var row: Dictionary = {}
	for r in rep.get("players", []):
		if String(r["profile_id"]) == pid:
			row = r
	if row.is_empty():
		return
	var results := {"outcome": int(rep["outcome"]), "round_time": float(rep["round_time_s"]), "coin_spawns": int(rep["coin_spawns"]),
		"fastest_slot": int(row["slot"]) if bool(row.get("first_home", false)) else -1, "players": rep["players"]}
	var digest := Economy.row_digest(mid, results, row)
	if digest != String(rd["acks"][pid]):
		rd["settled"][pid] = {"state": "mismatch", "coins": 0, "xp": 0}
		return
	var c := Economy.round_coins(row, results)
	var x := Economy.round_season_xp(row, results)
	var w := wallet(pid)
	w["balance"] = int(w["balance"]) + int(c["coins"])
	w["season"]["s1"]["xp"] = int(w["season"]["s1"]["xp"]) + int(x["xp"])
	var ch := _settle_challenges(pid, mid, rd, row, results, int(rep.get("report_version", 1)) >= ChallengeRules.REPORT_VERSION)
	_bump(pid)
	rd["settled"][pid] = {"state": "settled", "coins": int(c["coins"]), "xp": int(x["xp"]), "challenge_xp": int(ch["xp"]), "challenges": ch}


# ------------------------------------------------------------------ challenges
## Challenges use the same clock as offers (clock_ms, else the real time).
func _now_ms() -> int:
	return int(now_ms())


## The round's challenge progress and bonus, as service/src/challenges.js.
func _settle_challenges(pid: String, mid: String, rd: Dictionary, row: Dictionary, results: Dictionary, v2: bool) -> Dictionary:
	var started := int(int(rd.get("started_at", _now_ms())) / 1000.0)
	var t := int(_now_ms() / 1000.0)
	var inc := ChallengeRules.increments(row, results) if v2 else {"state": "no_evidence", "active_rounds": 0, "credits": 0, "round_wins": 0}
	var items: Array = []
	var closed: Array = []
	var xp := 0
	if String(inc["state"]) == "applied":
		for kind in ["daily", "weekly"]:
			var per := ChallengeRules.period_of(kind, started)
			if t > int(per["end"]) + ChallengeRules.grace_s():
				closed.append(kind)
				continue
			for d in ChallengeRules.defs():
				if String(d["period"]) != kind or int(inc.get(String(d["metric"]), 0)) <= 0:
					continue
				var n := int(inc[String(d["metric"])])
				var r := _instance(pid, kind, per, d)
				r["progress"] = mini(int(r["goal"]), int(r["progress"]) + n)
				var done := _bonus(pid, r, mid)
				xp += int(r["xp"]) if done else 0
				items.append({"challenge_id": String(d["id"]), "instance_id": String(r["instance_id"]), "period": kind, "inc": n,
					"progress": int(r["progress"]), "goal": int(r["goal"]), "completed": int(r["progress"]) >= int(r["goal"]),
					"completed_now": done, "xp": int(r["xp"]) if done else 0})
	if xp > 0:
		wallet(pid)["season"]["s1"]["xp"] = int(wallet(pid)["season"]["s1"]["xp"]) + xp
	var st := "closed" if String(inc["state"]) == "applied" and items.is_empty() and not closed.is_empty() else String(inc["state"])
	return {"state": st, "xp": xp, "items": items, "closed": closed, "credits": int(inc["credits"]), "active_s": int(row.get("active_s", 0)),
		"need": ceili(ChallengeRules.active_need(float(results.get("round_time", 0.0))))}


func _instance(pid: String, kind: String, per: Dictionary, d: Dictionary) -> Dictionary:
	if not challenge_rows.has(pid):
		challenge_rows[pid] = {}
	var rows: Dictionary = challenge_rows[pid]
	var iid := ChallengeRules.instance_id(kind, String(per["key"]), String(d["id"]))
	if not rows.has(iid):
		rows[iid] = {"instance_id": iid, "challenge_id": String(d["id"]), "period": kind, "period_start": int(per["start"]) * 1000,
			"period_end": int(per["end"]) * 1000, "metric": String(d["metric"]), "goal": int(d["goal"]), "xp": int(d["xp"]), "progress": 0,
			"completed_at": null}
	return rows[iid]


## The bonus once per player and instance; true when this call delivered it.
func _bonus(pid: String, r: Dictionary, mid: String) -> bool:
	if not challenge_bonus.has(pid):
		challenge_bonus[pid] = {}
	var bon: Dictionary = challenge_bonus[pid]
	if int(r["progress"]) < int(r["goal"]) or bon.has(String(r["instance_id"])):
		return false
	bon[String(r["instance_id"])] = {"xp": int(r["xp"]), "match_id": mid, "at": _now_ms()}
	r["completed_at"] = _now_ms()
	return true


## Development fixture: put a current-period challenge at `progress` (a
## complete one gets its bonus, as a settlement would have added it).
func set_challenge(pid: String, cid: String, progress: int, add_xp: bool = true) -> void:
	var d := ChallengeRules.def(cid)
	var kind := String(d["period"])
	var r := _instance(pid, kind, ChallengeRules.period_of(kind, int(_now_ms() / 1000.0)), d)
	r["progress"] = clampi(progress, 0, int(r["goal"]))
	if _bonus(pid, r, "fixture") and add_xp:
		wallet(pid)["season"]["s1"]["xp"] = int(wallet(pid)["season"]["s1"]["xp"]) + int(r["xp"])
	_bump(pid)


## The snapshot's challenges, as service/src/challenges.js snapshot().
func _challenges_view(pid: String) -> Dictionary:
	var t := int(_now_ms() / 1000.0)
	var rows: Dictionary = challenge_rows.get(pid, {})
	var bon: Dictionary = challenge_bonus.get(pid, {})
	var items: Array = []
	var seen := {}
	for d in ChallengeRules.defs():
		var kind := String(d["period"])
		var per := ChallengeRules.period_of(kind, t)
		var iid := ChallengeRules.instance_id(kind, String(per["key"]), String(d["id"]))
		seen[iid] = true
		var r: Dictionary = rows.get(iid, {"instance_id": iid, "challenge_id": String(d["id"]), "period": kind, "period_start": int(per["start"]) * 1000,
			"period_end": int(per["end"]) * 1000, "metric": String(d["metric"]), "goal": int(d["goal"]), "xp": int(d["xp"]), "progress": 0,
			"completed_at": null})
		items.append(_view(r, bon, true))
	var recent: Array = []
	for iid in rows:
		var r: Dictionary = rows[iid]
		if not seen.has(iid) and int(r["progress"]) > 0 and int(r["period_end"]) > (t - ChallengeRules.grace_s()) * 1000:
			recent.append(_view(r, bon, false))
	var dp := ChallengeRules.period_of("daily", t)
	var wp := ChallengeRules.period_of("weekly", t)
	return {"version": int(ChallengeRules.cfg().get("version", 1)), "server_time": _now_ms(), "grace_s": ChallengeRules.grace_s(),
		"daily": {"start": int(dp["start"]) * 1000, "end": int(dp["end"]) * 1000}, "weekly": {"start": int(wp["start"]) * 1000, "end": int(wp["end"]) * 1000},
		"items": items, "recent": recent}


func _view(r: Dictionary, bon: Dictionary, current: bool) -> Dictionary:
	var d := ChallengeRules.def(String(r["challenge_id"]))
	var v := r.duplicate()
	v["name"] = String(d.get("name", r["challenge_id"]))
	v["task"] = String(d.get("task", ""))
	v["completed"] = int(r["progress"]) >= int(r["goal"])
	v["bonus_xp"] = int(bon[r["instance_id"]]["xp"]) if bon.has(r["instance_id"]) else 0
	v["current"] = current
	return v
