extends Node
## Versioned local profile: settings, wardrobe, coins, level, personal stats,
## reward ledger (each match id pays out once). Stored only on this device.
## Identity kept: a random local id and an auto-generated fun name; with Game
## Center signed in, the Game Center id/name are used for rooms instead.

signal changed

const PATH := "user://profile.json"
## 3 (V3): "cosmetic" holds the schema-2 appearance (Cosmetics); owned keys
## use schema-2 item keys; free items need no owned entry.
const VERSION := 3
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
		"name": "%s %s %d" % [ADJ[rng.randi() % ADJ.size()], ANIMALS[rng.randi() % ANIMALS.size()], rng.randi_range(10, 99)],
		"settings": {"sensitivity": 1.0, "invert_y": false, "reduced_motion": false, "sfx": 0.9, "music": 0.6,
			"quality": 1, "sprint_threshold": 0.88, "touch_sprint": true, "role_pref": "any",
			"stick_mode": "dynamic", "sprint_mode": "edge", "button_size": 1.0, "touch_layout": "standard", "haptics": true},
		"cosmetic": Cosmetics.DEFAULT.duplicate(),
		"owned": [],
		"coins": 0, "level": 1, "xp": 0,
		"stats": {"online": _blank_stats(), "practice": _blank_stats()},
		"rewarded": [],
		"recent": [],
		"tutorial_done": false,
		"muted": [],
		"blocked": [],          # [{pid, uid, name}]: persists; also sent to the service when signed in
		"cloud_profile": {},
		"onboarded": false,     # first launch: Create Your Runner + name
	}


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
	# V1/V2 wardrobe -> schema 2 appearance (same look) and item keys
	out["cosmetic"] = Cosmetics.sanitize(out["cosmetic"] if out["cosmetic"] is Dictionary else {})
	out["owned"] = Cosmetics.migrate_owned(out["owned"] if out["owned"] is Array else [])
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


func owns(field: String, key: String) -> bool:
	if Cosmetics.entry(field, key).is_empty():
		return false
	return Cosmetics.cost(field, key) == 0 or (data["owned"] as Array).has(Cosmetics.own_key(field, key))


func buy(field: String, key: String) -> bool:
	if owns(field, key):
		return true
	if Cosmetics.entry(field, key).is_empty():
		return false
	var cost := Cosmetics.cost(field, key)
	if int(data["coins"]) < cost:
		return false
	data["coins"] = int(data["coins"]) - cost
	(data["owned"] as Array).append(Cosmetics.own_key(field, key))
	mark()
	return true


## Coins needed to apply an appearance (items not yet owned).
func price_of(appearance: Dictionary) -> int:
	var a := Cosmetics.sanitize(appearance)
	var total := 0
	for f in Cosmetics.ORDER:
		if not owns(f, a[f]):
			total += Cosmetics.cost(f, a[f])
	return total


## Creator "Apply": buys whatever is not owned yet and equips the whole look
## in one step.  Idempotent: applying the same look again costs nothing.
## Returns {"ok", "spent", "short"}; nothing changes when coins are short.
func apply_appearance(appearance: Dictionary) -> Dictionary:
	var a := Cosmetics.sanitize(appearance)
	var price := price_of(a)
	if int(data["coins"]) < price:
		return {"ok": false, "spent": 0, "short": price - int(data["coins"])}
	for f in Cosmetics.ORDER:
		if not owns(f, a[f]):
			(data["owned"] as Array).append(Cosmetics.own_key(f, a[f]))
	data["coins"] = int(data["coins"]) - price
	data["cosmetic"] = a
	mark()
	return {"ok": true, "spent": price, "short": 0}


func equip(field: String, key: Variant) -> void:
	if owns(field, String(key)):
		data["cosmetic"][field] = String(key)
	data["cosmetic"] = Cosmetics.sanitize(data["cosmetic"])
	mark()


## Applies rewards + stats once per match id. Returns {} if already applied
## or if the round was cancelled (host loss etc.).
func apply_results(results: Dictionary, slot: int, practice: bool) -> Dictionary:
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
		if int(r["slot"]) == slot:
			me = r
	if me.is_empty():
		return {}
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
	data["coins"] = int(data["coins"]) + int(rew["coins"])
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
	return rew
