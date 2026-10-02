extends Node
## Versioned local profile: settings, appearance, level, personal stats and
## the per-match stats ledger. Stored only on this device.
## V6 (version 4): Coins, purchases and Season progress live in the Wallet
## (the service's ledger, cached in user://wallet.json).  The pre-V6 balance
## and unlocks are kept here, frozen, in "legacy" (imported once to an
## account by the Wallet); "owned" stays the list of pre-V6 unlocks on this
## device; "coins" is only a mirror of the displayed balance for old readers.
## Identity kept: a random local id and an auto-generated fun name; with Game
## Center signed in, the Game Center id/name are used for rooms instead.

signal changed

const PATH := "user://profile.json"
## 3 (V3): "cosmetic" holds the schema-2 appearance (Cosmetics); owned keys
## use schema-2 item keys; free items need no owned entry.
## 4 (V6): "legacy" freezes the pre-V6 balance/unlocks/round counts for the
## one-time account import; "profile_style" (name card, badge); the 200-entry
## "rewarded" list is a stats ledger only (financial idempotency is the
## service's, keyed per round and player, never truncated).
const VERSION := 4
const ADJ := ["Sleepy", "Soggy", "Sneaky", "Snoozy", "Zippy", "Drowsy", "Splashy", "Fuzzy", "Comfy", "Wobbly", "Speedy", "Moonlit"]
const ANIMALS := ["Otter", "Duck", "Frog", "Llama", "Panda", "Gecko", "Walrus", "Badger", "Koala", "Puffin", "Newt", "Moose"]

var data: Dictionary = {}
var _dirty := false
var _save_t := 0.0


func _ready() -> void:
	load_profile()
	_apply_settings()


func default_profile() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var uid := "local-%08x%08x" % [rng.randi(), rng.randi()]
	return {
		"version": VERSION,
		"uid": uid,
		"name": generated_name(rng),
		"settings": {"sensitivity": 1.0, "invert_y": false, "reduced_motion": false, "sfx": 0.9, "music": 0.6,
			"quality": 1, "sprint_threshold": 0.88, "touch_sprint": true, "role_pref": "any",
			"stick_mode": "dynamic", "sprint_mode": "edge", "button_size": 1.0, "touch_layout": "standard", "haptics": true},
		"cosmetic": Cosmetics.DEFAULT.duplicate(),
		"owned": [],
		"coins": 0, "level": 1, "xp": 0,
		"legacy": {"coins": 0, "owned": [], "online_rounds": 0, "practice_rounds": 0, "from_version": VERSION},
		"profile_style": {"card": "", "badge": ""},
		"stats": {"online": _blank_stats(), "practice": _blank_stats()},
		"rewarded": [],
		"recent": [],
		"tutorial_done": false,
		"muted": [],
		"blocked": [],          # [{pid, uid, name}]: persists; also sent to the service when signed in
		"cloud_profile": {},
		"onboarded": false,     # first launch: Create Your Runner + name
	}


## A fun default name that always fits the name rules (3-16 characters):
## "Sleepy Otter 42", or without the number when the words are long.
static func generated_name(rng: RandomNumberGenerator) -> String:
	var base := "%s %s" % [ADJ[rng.randi() % ADJ.size()], ANIMALS[rng.randi() % ANIMALS.size()]]
	var with_num := "%s %d" % [base, rng.randi_range(10, 99)]
	return with_num if with_num.length() <= NameRules.MAX_LEN else base


## Names saved by older versions that don't fit today's rules (V1/V2 could
## generate 17-character names) are kept as close as possible: the number is
## dropped, else a new name is generated.  Never shown as "Player".
static func fit_name(n: String) -> String:
	var name := NameRules.normalize(n)
	if NameRules.shape_error(name) == "":
		return name
	var parts := name.split(" ")
	if parts.size() > 1 and parts[-1].is_valid_int():
		var short := " ".join(parts.slice(0, parts.size() - 1))
		if NameRules.shape_error(short) == "":
			return short
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n)
	return generated_name(rng)


func _blank_stats() -> Dictionary:
	return {"matches": 0, "runner_rounds": 0, "patrol_rounds": 0, "wins": 0, "splashes": 0, "finishes": 0,
		"unique_captures": 0, "times_caught": 0, "fastest_trifecta_awards": 0, "with_bots": 0}


func load_profile() -> void:
	data = default_profile()
	if not FileAccess.file_exists(PATH):
		_dirty = true
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		data = migrate(parsed)


## Upgrades older profile versions and fills any missing keys.
func migrate(d: Dictionary) -> Dictionary:
	var out := default_profile()
	var v := int(d.get("version", 1))
	for k in out:
		if d.has(k):
			out[k] = d[k]
	if v < 2:
		# v1 kept a single stats table; split into online/practice
		if d.has("stats") and not (d["stats"] as Dictionary).has("online"):
			out["stats"] = {"online": _merge_stats(_blank_stats(), d["stats"]), "practice": _blank_stats()}
	for k2 in default_profile()["settings"]:
		if not (out["settings"] as Dictionary).has(k2):
			out["settings"][k2] = default_profile()["settings"][k2]
	for mode in ["online", "practice"]:
		if not (out["stats"] as Dictionary).has(mode):
			out["stats"][mode] = _blank_stats()
		out["stats"][mode] = _merge_stats(_blank_stats(), out["stats"][mode])
	out["name"] = fit_name(String(out["name"]))
	# V1/V2 wardrobe -> schema 2 appearance (same look) and item keys
	out["cosmetic"] = Cosmetics.sanitize(out["cosmetic"] if out["cosmetic"] is Dictionary else {})
	out["owned"] = Cosmetics.migrate_owned(out["owned"] if out["owned"] is Array else [])
	if v < 4:
		# V6: freeze the pre-V6 balance, unlocks and round counts for the
		# Wallet's one-time, bounded account import (source "legacy_beta").
		# A v4 profile is never re-frozen, so migrating twice changes nothing.
		var st: Dictionary = out["stats"]
		out["legacy"] = {"coins": maxi(0, int(d.get("coins", 0))), "owned": (out["owned"] as Array).duplicate(),
			"online_rounds": int(st["online"].get("matches", 0)), "practice_rounds": int(st["practice"].get("matches", 0)), "from_version": v}
	if not (out["legacy"] is Dictionary):
		out["legacy"] = default_profile()["legacy"]
	var lg: Dictionary = out["legacy"]
	out["legacy"] = {"coins": maxi(0, int(lg.get("coins", 0))), "owned": Cosmetics.migrate_owned(lg.get("owned", []) if lg.get("owned", []) is Array else []),
		"online_rounds": maxi(0, int(lg.get("online_rounds", 0))), "practice_rounds": maxi(0, int(lg.get("practice_rounds", 0))),
		"from_version": int(lg.get("from_version", VERSION))}
	if not (out["profile_style"] is Dictionary):
		out["profile_style"] = {"card": "", "badge": ""}
	out["version"] = VERSION
	return out


func _merge_stats(base: Dictionary, extra: Dictionary) -> Dictionary:
	for k in extra:
		if base.has(k):
			base[k] = int(extra[k])
	return base


func save_now() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
	_dirty = false


func _process(delta: float) -> void:
	if _dirty:
		_save_t += delta
		if _save_t > 0.5:
			_save_t = 0.0
			save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _dirty:
			save_now()


## Rejoin key for the party we were last in (lets this device back into its
## own slot after a dropped connection or an app restart; never shared).
func remember_rejoin(code: String, key: String) -> void:
	data["rejoin"] = {"code": code, "key": key}
	mark()


func rejoin_key_for(code: String) -> String:
	var r: Dictionary = data.get("rejoin", {})
	return String(r.get("key", "")) if String(r.get("code", "")) == code and code != "" else ""


## Local block list (works offline; the service keeps the authoritative copy
## when signed in, which also stops blocked players joining your parties).
func is_blocked(pid: String, uid: String) -> bool:
	for b in data.get("blocked", []):
		if (pid != "" and String(b.get("pid", "")) == pid) or (uid != "" and String(b.get("uid", "")) == uid):
			return true
	return false


func add_block(pid: String, uid: String, name: String) -> void:
	if is_blocked(pid, uid):
		return
	(data["blocked"] as Array).append({"pid": pid, "uid": uid, "name": NameRules.safe_display(name)})
	mark()


func remove_block(pid: String, uid: String) -> void:
	data["blocked"] = (data["blocked"] as Array).filter(func(b: Dictionary) -> bool:
		return not ((pid != "" and String(b.get("pid", "")) == pid) or (uid != "" and String(b.get("uid", "")) == uid)))
	mark()


func mark() -> void:
	_dirty = true
	changed.emit()


func get_setting(k: String, def: Variant = null) -> Variant:
	return (data["settings"] as Dictionary).get(k, def)


func set_setting(k: String, v: Variant) -> void:
	data["settings"][k] = v
	_apply_settings()
	mark()


func _apply_settings() -> void:
	var s: Dictionary = data["settings"]
	Controls.sensitivity = float(s["sensitivity"])
	Controls.invert_y = bool(s["invert_y"])
	Controls.sprint_threshold = float(s["sprint_threshold"])
	Controls.touch_sprint_enabled = bool(s["touch_sprint"])
	Sfx.set_volumes(float(s["sfx"]), float(s["music"]))
	QualityPreset.apply(int(s.get("quality", 1)))


## The game display name: the service-approved online name when there is
## one, else the name chosen on this device (never the Game Center alias,
## which the game doesn't moderate).
func player_name() -> String:
	var cp: Dictionary = data.get("cloud_profile", {})
	var n: Variant = cp.get("display_name")
	if n != null and String(n) != "":
		return String(n)
	return NameRules.safe_display(String(data["name"]))


func player_uid() -> String:
	if Social.authenticated and Social.team_player_id != "":
		return Social.team_player_id
	if Social.authenticated and Social.local_player_id != "":
		return Social.local_player_id
	return String(data["uid"])


## Ownership is the Wallet's (free options, pre-V6 unlocks on this device,
## account entitlements, Apple-verified skins).
func owns(field: String, key: String) -> bool:
	return Wallet.owns(field, key)


## Locker "Save": equips a look made only of owned items.  Never spends:
## buying happens in the Shop.  Returns {"ok", "missing": [item ids]}.
func apply_appearance(appearance: Dictionary) -> Dictionary:
	var a := Cosmetics.sanitize(appearance)
	var missing: Array = []
	for f in Cosmetics.ORDER:
		if not owns(f, a[f]):
			missing.append(Catalogue.id_for(f, String(a[f])))
	if not missing.is_empty():
		return {"ok": false, "missing": missing}
	data["cosmetic"] = a
	mark()
	return {"ok": true, "missing": []}


func equip(field: String, key: Variant) -> void:
	if owns(field, String(key)):
		data["cosmetic"][field] = String(key)
	data["cosmetic"] = Cosmetics.sanitize(data["cosmetic"])
	mark()


## Name card / badge (UI-only profile cosmetics; "" = none).
func profile_style() -> Dictionary:
	var ps: Dictionary = data.get("profile_style", {})
	var out := {"card": String(ps.get("card", "")), "badge": String(ps.get("badge", ""))}
	for k in out:
		if out[k] != "" and not Wallet.owns_id(String(out[k])):
			out[k] = ""   # no longer owned (e.g. a different profile): shown as none
	return out


func set_profile_style(kind: String, id: String) -> void:
	if id != "" and not Wallet.owns_id(id):
		return
	var ps: Dictionary = data.get("profile_style", {"card": "", "badge": ""})
	ps[kind] = id
	data["profile_style"] = ps
	mark()


## Applies rewards + stats once per match id. Returns {} if already applied
## or if the round was cancelled (host loss etc.).
## Applies one round's rewards and stats once (keyed by match id).  The
## local row is found by player identity when given (slots can change
## between rounds); a round the player mostly missed (a bot covered a
## disconnect) is recorded as seen but pays nothing.
func apply_results(results: Dictionary, slot: int, practice: bool, uid: String = "") -> Dictionary:
	var mid := String(results.get("match_id", ""))
	if mid == "" or (data["rewarded"] as Array).has(mid):
		return {}
	if int(results.get("outcome", 0)) == TC.Outcome.CANCELLED:
		return {}
	var me: Dictionary = {}
	var bots := 0
	for r in results.get("players", []):
		if bool(r.get("is_bot", false)):
			bots += 1
		if uid != "" and String(r.get("uid", "")) == uid:
			me = r
	if me.is_empty():
		for r in results.get("players", []):
			if int(r["slot"]) == slot and (uid == "" or String(r.get("uid", "")) == "" or String(r.get("uid", "")) == uid):
				me = r
	if me.is_empty():
		return {}
	slot = int(me["slot"])
	var away := float(me.get("away_s", 0.0))
	var rt := float(results.get("round_time", 0.0))
	# away for more than the allowed share of a known round length (an unknown
	# length never takes a reward away)
	if not bool(me.get("present", true)) or (rt > 0.0 and away > (1.0 - PartySeries.PRESENT_SHARE) * rt):
		(data["rewarded"] as Array).append(mid)
		mark()
		return {"coins": 0, "xp": 0, "season_xp": 0, "lines": [], "away": true, "wallet": Wallet.settle_round(results, me, practice)}
	var rew := RulesLogic.compute_rewards(results, slot, Rules.cfg, practice)
	var st: Dictionary = data["stats"]["practice" if practice else "online"]
	st["matches"] = int(st["matches"]) + 1
	if bots > 0:
		st["with_bots"] = int(st["with_bots"]) + 1
	var role := int(me["role"])
	var outcome := int(results["outcome"])
	if role == TC.Role.RUNNER:
		st["runner_rounds"] = int(st["runner_rounds"]) + 1
		st["splashes"] = int(st["splashes"]) + int(me.get("stamps", 0))
		if bool(me.get("finished", false)):
			st["finishes"] = int(st["finishes"]) + 1
		st["times_caught"] = int(st["times_caught"]) + int(me.get("times_captured", 0))
		if outcome == TC.Outcome.RUNNERS_WIN:
			st["wins"] = int(st["wins"]) + 1
		if int(results.get("fastest_slot", -1)) == slot:
			st["fastest_trifecta_awards"] = int(st["fastest_trifecta_awards"]) + 1
	else:
		st["patrol_rounds"] = int(st["patrol_rounds"]) + 1
		st["unique_captures"] = int(st["unique_captures"]) + int(me.get("unique_captures", 0))
		if outcome == TC.Outcome.PATROL_WIN:
			st["wins"] = int(st["wins"]) + 1
	var before_level := int(data["level"])
	# V6: Coins and Season XP are settled by the service through the Wallet
	# (eligible online rounds only); lifetime XP stays local
	var lx := RulesLogic.add_xp(int(data["level"]), int(data["xp"]), int(rew["xp"]), Rules.cfg)
	data["level"] = lx[0]
	data["xp"] = lx[1]
	var ledger: Array = data["rewarded"]
	ledger.append(mid)
	while ledger.size() > 200:
		ledger.pop_front()
	var recent: Array = data["recent"]
	recent.push_front({"when": Time.get_datetime_string_from_system(false, true), "kind": "practice" if practice else "online",
		"role": role, "outcome": outcome, "bots": bots, "match_id": mid})
	while recent.size() > 20:
		recent.pop_back()
	mark()
	save_now()
	rew["level_up"] = int(data["level"]) > before_level
	rew["level"] = data["level"]
	rew["wallet"] = Wallet.settle_round(results, me, practice)
	return rew
