class_name CampusMaps
extends RefCounted
## The playable maps: a stable id per map (never a display title, never an
## index), what a player sees of it (title, a short line, a tag, the preview
## image) and where its pieces live (layer data, bounds, navigation cell, the
## builder that draws it, the route table).  Every system that used to assume
## one campus asks for the map by id: the host's settings, the round
## configuration (START) and reconnect snapshots carry it, and a guest
## without the same map data refuses the round instead of loading another.
##
## Both maps play by the same simulation: CampusData -> CampusLayout ->
## CampusBuilder collision -> NavGrid -> CampusDorms -> RulesLogic, keyed by
## the map's own layout.  Only the look differs: the reference campus is
## drawn by CampusBuilder, Moonbrook College by ClassicBuilder (its 2.0 art).
##
## Caches: one layout per map, built on first use (data only: a few MB; the
## 3D world is built per round and cached by MatchController for one map at
## a time).  Previews are static images captured offline from the finished
## maps (tools/capture_map_previews.sh); nothing renders a live campus to
## show a choice.

const CLASSIC := "classic"
const CAMPUS := "reference_campus"
## a new player, or a tester coming from the campus rebuild, starts here
const DEFAULT_ID := CAMPUS

const DEFS := {
	CLASSIC: {
		"title": "Moonbrook College", "tag": "Classic",
		"blurb": "The original campus: a compact quad, six waters close together and three halls to run home to.",
		"data": "res://data/maps/classic/", "bounds": Rect2(-160.0, -150.0, 320.0, 300.0), "nav_cell": 1.0, "mini_span": 110.0,
		"look": "classic", "routes": "res://config/route_table_classic.json", "route_band": 0.16,
		"dorms": ["puddlesworth", "lanternfield", "moonpenny"],
		"preview": "res://assets/maps/preview_classic.png",
	},
	CAMPUS: {
		"title": "Lakeside Campus", "tag": "New",
		"blurb": "A big lakeside campus with woods, ponds, hills and long runs between the waters.",
		"data": "res://data/campus/", "bounds": Rect2(-720.0, -560.0, 1190.0, 1000.0), "nav_cell": 2.0, "mini_span": 130.0,
		"look": "campus", "routes": "res://config/route_table.json",
		"dorms": ["west_hall", "north_hall"],
		"preview": "res://assets/maps/preview_reference_campus.png",
	},
}
## (`dorms`: every start_dorm id in the map's data, so a dorm id finds its
## map without loading the others; test_maps checks it against the data.
## Dorm ids are unique across maps: a classic hall id can never resolve to a
## hall of the other map.)
## the order the chooser shows them in
const ORDER := [CLASSIC, CAMPUS]

static var _data: Dictionary = {}      # id -> CampusData
static var _layouts: Dictionary = {}   # id -> CampusLayout


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id in ORDER:
		out.append(String(id))
	return out


static func has(id: String) -> bool:
	return DEFS.has(id)


## A known map id, or the default (old settings, a missing value).
static func sanitize(id: Variant) -> String:
	var s := String(id) if id is String or id is StringName else ""
	return s if DEFS.has(s) else DEFAULT_ID


static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func title(id: String) -> String:
	return String(def(id).get("title", ""))


## The map a start dorm id belongs to ("" if none).
static func map_of_dorm(dorm_id: String) -> String:
	for id in ORDER:
		if (DEFS[id]["dorms"] as Array).has(dorm_id):
			return String(id)
	return ""


static func bounds(id: String) -> Rect2:
	return def(id).get("bounds", Rect2())


## The map's layer data (loaded once).
static func data(id: String) -> CampusData:
	if not _data.has(id):
		var d := def(id)
		if d.is_empty():
			return null
		var cd := CampusData.new(String(d["data"]))
		cd.map_id = id
		_data[id] = cd
	return _data[id]


## The map's gameplay layout (built once; data only).
static func layout(id: String) -> CampusLayout:
	if not _layouts.has(id):
		var cd := data(id)
		if cd == null:
			return null
		_layouts[id] = CampusLayout.new(cd)
	return _layouts[id]


## What the round configuration names, so two builds with different map data
## never share a round: the id, the data's hash and the dorm geometry version.
static func revision(id: String) -> Dictionary:
	var cd := data(id)
	if cd == null:
		return {}
	return {"id": id, "data": cd.campus_hash, "dorms": CampusDorms.VERSION}


## Whether a round configuration's map is the one this build has.
static func compatible(rev: Variant) -> bool:
	if not (rev is Dictionary):
		return false
	var id := String((rev as Dictionary).get("id", ""))
	if not has(id):
		return false
	var mine := revision(id)
	return String((rev as Dictionary).get("data", "")) == String(mine["data"]) and int((rev as Dictionary).get("dorms", -1)) == int(mine["dorms"])


## Drops the cached layouts/data (tests that swap data; memory pressure).
## The layout of `keep` stays.
static func drop(keep: String = "") -> void:
	for id in _layouts.keys():
		if id != keep:
			_layouts.erase(id)
	for id in _data.keys():
		if id != keep:
			_data.erase(id)
