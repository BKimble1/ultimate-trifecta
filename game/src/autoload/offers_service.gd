extends Node
## Offers (Pass 8, autoload "Offers"): the Shop's scheduled rotating offers
## as the game service last reported them, and the service's clock.
##
## The service is the authority for time and availability
## (service/src/offers.js): GET /v1/shop/offers returns its own time with
## the offers on sale now and those starting in the next 72 h.  This node:
##  - keeps the service time as an offset from the monotonic clock (ticks),
##    so changing the device clock or time zone can't add purchase time.  The
##    device clock is only ever used to make an offer end *sooner* (the
##    estimate is the later of the two: iOS's monotonic clock pauses while
##    the device sleeps, the wall clock doesn't), never later;
##  - rolls countdowns forward inside the window the service described and
##    asks again at each change, on resume and before the window ends;
##  - trusts its time only when it synced with the service in this run
##    within TRUST_S (and the two clocks agree); otherwise the Shop says
##    "Connect to refresh Shop" and nothing can be bought from a stale offer
##    (the service also checks every purchase against its own clock);
##  - caches the last answer (user://shop_offers.json) so the last offers can
##    still be previewed offline (never bought, never counted down).
## With no service in the build (Cloud not configured) there is no rotation:
## status "off", and the Shop shows the existing unavailable state.

signal changed

const CACHE_SCHEMA := 1
## a sync older than this (monotonic or wall time) is not trusted
const TRUST_S := 6 * 3600
## the monotonic and wall clocks drifting apart by more than this since the
## sync (device sleep, a clock change) asks the service again
const SKEW_S := 90.0
## refresh this long before the described window ends
const EARLY_S := 3600
## while something shows the Shop: ask again at least this often
const POLL_S := 15 * 60
## cached offers older than this (wall time) aren't shown at all
const CACHE_SHOW_S := 3 * 86400

var path := "user://shop_offers.json"
## off | idle | loading | live | stale | unsupported
var status := "idle"
var last_error := ""
var offers: Array = []            # [{offer_id, item_id, slot, price, revision, starts_at, ends_at}] (ms)
var schedule_revision := 0
var known_until_ms := 0
var server_ms_at_sync := 0.0
var _ticks_at_sync := -1          # Time.get_ticks_msec() at the sync (this run only)
var _wall_at_sync := 0.0          # device unix ms at the sync
var _have_sync := false
var _loading := false
var _last_key := ""
var _last_ask := -1.0             # ticks (s) of the last request
var _timer: Timer
## tests: replace the monotonic clock (ms) and the device clock (unix ms)
var ticks_override: Callable
var wall_override: Callable


func _ready() -> void:
	_load()
	status = "off" if not Cloud.configured() else ("stale" if not offers.is_empty() else "idle")
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	Cloud.changed.connect(_on_cloud)


# ------------------------------------------------------------------ clocks
func ticks_ms() -> int:
	return int(ticks_override.call()) if ticks_override.is_valid() else Time.get_ticks_msec()


func wall_ms() -> float:
	return float(wall_override.call()) if wall_override.is_valid() else Time.get_unix_time_from_system() * 1000.0


## The service's time now (ms), or -1 when there is no sync in this run.
func server_now_ms() -> float:
	if not _have_sync:
		return -1.0
	var mono := server_ms_at_sync + float(ticks_ms() - _ticks_at_sync)
	var wall := server_ms_at_sync + (wall_ms() - _wall_at_sync)
	return maxf(mono, wall)


## Seconds since the sync (the larger of the monotonic and wall readings).
func age_s() -> float:
	if not _have_sync:
		return INF
	return maxf(float(ticks_ms() - _ticks_at_sync), wall_ms() - _wall_at_sync) / 1000.0


## The clocks disagree since the sync (sleep, or the device clock changed).
func skewed() -> bool:
	if not _have_sync:
		return false
	return absf((wall_ms() - _wall_at_sync) - float(ticks_ms() - _ticks_at_sync)) / 1000.0 > SKEW_S


## The offers and the time can be trusted for countdowns and buying.
func trusted() -> bool:
	if not _have_sync or status == "off":
		return false
	return age_s() <= TRUST_S and server_now_ms() < float(known_until_ms)


# ------------------------------------------------------------------ views
func configured() -> bool:
	return Cloud.configured()


## live | loading | stale | off | unsupported (what the Shop shows).
func shop_status() -> String:
	if not Cloud.configured():
		return "off"
	if trusted():
		return "live"
	if status == "unsupported":
		return "unsupported"
	if _loading and not _have_sync and offers.is_empty():
		return "loading"
	return "stale"


## The offers on sale now by the service's clock ([] when not trusted),
## one per slot, in slot order.
func active() -> Array:
	if not trusted():
		return []
	var t := server_now_ms()
	var out: Array = offers.filter(func(o: Dictionary) -> bool: return float(o["starts_at"]) <= t and t < float(o["ends_at"]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["slot"]) < int(b["slot"]) if int(a["slot"]) != int(b["slot"]) else float(a["starts_at"]) < float(b["starts_at"]))
	return out


## The last offers known to be on sale (for an offline preview when the time
## isn't trusted: shown, never bought, never counted down).
func last_seen() -> Array:
	if trusted():
		return active()
	if offers.is_empty() or wall_ms() - _wall_at_sync > CACHE_SHOW_S * 1000.0:
		return []
	var t := server_ms_at_sync
	var out: Array = offers.filter(func(o: Dictionary) -> bool: return float(o["starts_at"]) <= t and t < float(o["ends_at"]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	return out


## The active offer for an item ({} when none or not trusted).  Overlapping
## offers for one item: the one that stays longest (as the service picks).
func offer_for(item_id: String) -> Dictionary:
	var best: Dictionary = {}
	for o in active():
		if String(o["item_id"]) == item_id and (best.is_empty() or float(o["ends_at"]) > float(best["ends_at"])):
			best = o
	return best


func is_active(offer: Dictionary) -> bool:
	if offer.is_empty() or not trusted():
		return false
	var t := server_now_ms()
	return float(offer["starts_at"]) <= t and t < float(offer["ends_at"])


## Can this item be bought in the Shop right now?  Always-available items
## yes; a rotating item only while it has an active offer.
func listed(item_id: String) -> bool:
	if not Catalogue.is_rotation(item_id):
		return true
	return not offer_for(item_id).is_empty()


## Whole seconds until an offer leaves (0 when gone).
func seconds_left(offer: Dictionary) -> int:
	if offer.is_empty() or not _have_sync:
		return 0
	return maxi(0, int(ceil((float(offer["ends_at"]) - server_now_ms()) / 1000.0)))


## The next moment any offer starts or ends (ms), or -1.
func next_change_ms() -> float:
	if not trusted():
		return -1.0
	var t := server_now_ms()
	var best := -1.0
	for o in offers:
		for k in ["starts_at", "ends_at"]:
			var v := float(o[k])
			if v > t and (best < 0.0 or v < best):
				best = v
	return best


## Seconds until the Shop next changes (-1 when unknown).
func refresh_in_s() -> int:
	var n := next_change_ms()
	return -1 if n < 0.0 else maxi(0, int(ceil((n - server_now_ms()) / 1000.0)))


## "1d 04h" from a day up, "02:14:09" below a day.
static func countdown(sec: int) -> String:
	sec = maxi(0, sec)
	if sec >= 86400:
		return "%dd %02dh" % [sec / 86400, (sec % 86400) / 3600]
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


const _DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


## A moment in the device's local time: "Wednesday, Oct 7, 2:00 AM", using
## the device's current UTC offset (presentation only; never a purchase
## time).  `bias_min` overrides the offset (tests).
static func local_text(unix_ms: float, bias_min: int = 999999) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) if bias_min == 999999 else bias_min
	var d := Time.get_datetime_dict_from_unix_time(int(floor(unix_ms / 1000.0)) + bias * 60)
	var h := int(d["hour"])
	var h12 := 12 if h % 12 == 0 else h % 12
	return "%s, %s %d, %d:%02d %s" % [_DAYS[int(d["weekday"])], _MONTHS[int(d["month"]) - 1], int(d["day"]), h12, int(d["minute"]),
		"AM" if h < 12 else "PM"]


# ------------------------------------------------------------------ service
func _on_cloud() -> void:
	var was := status
	if not Cloud.configured():
		status = "off"
	elif status == "off":
		status = "stale" if not offers.is_empty() else "idle"
	if was != status:
		changed.emit()


## Ask the service unless a recent answer is good enough (`force`: always).
## Untrusted: at most every 20 s (the Shop calls this every second).
func refresh_if_needed(force: bool = false) -> void:
	if not Cloud.configured() or _loading:
		return
	var since := INF if _last_ask < 0.0 else float(ticks_ms()) / 1000.0 - _last_ask
	if force:
		refresh()
	elif not trusted() or skewed():
		if since > 20.0 and status != "unsupported":
			refresh()
	elif since > POLL_S or server_now_ms() > float(known_until_ms) - EARLY_S * 1000.0:
		refresh()


## GET /v1/shop/offers.  The round trip is split evenly: the service's
## time is taken as half-way through it.
func refresh() -> Dictionary:
	if not Cloud.configured():
		status = "off"
		changed.emit()
		return {"ok": false, "error": "service_off"}
	if _loading:
		while _loading:
			await get_tree().process_frame
		return {"ok": trusted()}
	_loading = true
	_last_ask = float(ticks_ms()) / 1000.0
	if not _have_sync:
		changed.emit()   # "loading"
	var t0 := ticks_ms()
	var r: Dictionary = await Cloud.public_get("/v1/shop/offers")
	var t1 := ticks_ms()
	_loading = false
	if bool(r.get("ok", false)) and r.has("server_time"):
		_apply(r, float(t1 - t0) * 0.5, t1)
		last_error = ""
	else:
		var st := int(r.get("http_status", 0))
		if st == 404:
			status = "unsupported"   # an older deployment without rotation
		elif status != "off":
			status = "stale"
		last_error = Cloud.explain(r)
	_last_key = _key()
	changed.emit()
	return r


func _apply(r: Dictionary, half_rtt_ms: float, ticks_now: int) -> void:
	var list: Array = []
	for src in [r.get("current", []), r.get("upcoming", [])]:
		for o in src:
			if o is Dictionary and String(o.get("offer_id", "")) != "":
				list.append(_norm(o))
	offers = list
	schedule_revision = int(r.get("schedule_revision", 0))
	known_until_ms = int(r.get("known_until", 0))
	server_ms_at_sync = float(r["server_time"]) + half_rtt_ms
	_ticks_at_sync = ticks_now
	_wall_at_sync = wall_ms()
	_have_sync = true
	status = "live"
	_save()


func _norm(o: Dictionary) -> Dictionary:
	var s := float(o.get("starts_at", Catalogue.parse_utc_ms(String(o.get("starts_at_utc", "")))))
	var e := float(o.get("ends_at", Catalogue.parse_utc_ms(String(o.get("ends_at_utc", "")))))
	return {"offer_id": String(o["offer_id"]), "item_id": String(o.get("item_id", "")), "slot": int(o.get("slot", 0)),
		"price": int(o.get("price", 0)), "revision": int(o.get("revision", 0)), "starts_at": s, "ends_at": e}


## Once a second: notice an offer starting or ending (the Shop then refreshes
## in place) and ask the service again when needed.
func _tick() -> void:
	var k := _key()
	if k != _last_key:
		_last_key = k
		changed.emit()
		if Cloud.configured() and _have_sync:
			refresh()
		return
	if _have_sync and Cloud.configured() and not _loading and (skewed() or server_now_ms() > float(known_until_ms) - EARLY_S * 1000.0):
		if _last_ask < 0.0 or float(ticks_ms()) / 1000.0 - _last_ask > 30.0:
			refresh()


## What the Shop shows, as one comparable string.
func _key() -> String:
	var parts: Array = [shop_status()]
	for o in active():
		parts.append(String(o["offer_id"]))
	return "|".join(PackedStringArray(parts.map(func(x: Variant) -> String: return String(x))))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# the monotonic clock may have paused while the device slept
		if Cloud.configured() and _have_sync:
			refresh()


# ------------------------------------------------------------------ cache
func _save() -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"schema": CACHE_SCHEMA, "offers": offers, "schedule_revision": schedule_revision,
		"known_until": known_until_ms, "server_ms": server_ms_at_sync, "wall_ms": _wall_at_sync}))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))


## Last run's answer: for offline previews only (no sync in this run, so it
## is never trusted for countdowns or buying).
func _load() -> void:
	offers = []
	_have_sync = false
	_ticks_at_sync = -1
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or int((d as Dictionary).get("schema", 0)) != CACHE_SCHEMA:
		return
	for o in d.get("offers", []):
		if o is Dictionary:
			offers.append(_norm(o))
	schedule_revision = int(d.get("schedule_revision", 0))
	known_until_ms = int(d.get("known_until", 0))
	server_ms_at_sync = float(d.get("server_ms", 0.0))
	_wall_at_sync = float(d.get("wall_ms", 0.0))


## Tests: forget everything (and the cache file at `path`).
func reset(new_path: String = "") -> void:
	if new_path != "":
		path = new_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	offers = []
	_have_sync = false
	_ticks_at_sync = -1
	_loading = false
	_last_ask = -1.0
	known_until_ms = 0
	server_ms_at_sync = 0.0
	_wall_at_sync = 0.0
	status = "off" if not Cloud.configured() else "idle"
	_last_key = _key()


## Tests: reload from `path` as a fresh app run would (no sync this run).
func reload_as_new_run() -> void:
	_loading = false
	_last_ask = -1.0
	_load()
	status = "off" if not Cloud.configured() else ("stale" if not offers.is_empty() else "idle")
	_last_key = _key()
