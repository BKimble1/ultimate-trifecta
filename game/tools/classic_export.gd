extends SceneTree
## Writes the classic map's gameplay data (game/data/maps/classic/*.json, the
## layer schema of docs/campus/DATA_SCHEMA.md) from ClassicLayout, the 2.0
## description of Moonbrook College restored in src/map/classic.  The shared
## gameplay pipeline (CampusLayout, CampusBuilder collision, NavGrid,
## CampusDorms, the rules) reads the export; the classic look keeps reading
## ClassicLayout itself.  Deterministic: test_classic_map regenerates the
## layers in memory and fails if the committed files differ.
## Usage: godot --headless --path game -s res://tools/classic_export.gd

const OUT := "res://data/maps/classic/"


func _initialize() -> void:
	var layers := export_layers(ClassicLayout.new())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for name in layers:
		var f := FileAccess.open(OUT + String(name) + ".json", FileAccess.WRITE)
		f.store_string(to_json(layers[name]))
		f.close()
		print("%s: %d items" % [name, (layers[name]["items"] as Array).size()])
	quit()


## The JSON text of one layer (stable key order, 3 decimals): what the
## committed files hold.
static func to_json(layer: Dictionary) -> String:
	return JSON.stringify(layer, " ", true) + "\n"


static func _r(v: float) -> float:
	return snappedf(v, 0.001)


static func _p(v: Vector2) -> Array:
	return [_r(v.x), _r(v.y)]


static func _p3(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func _pts(a: PackedVector2Array) -> Array:
	var out: Array = []
	for q in a:
		out.append(_p(q))
	return out


static func _rect_poly(c: Vector2, size: Vector2, rot: float = 0.0) -> Array:
	var h := size * 0.5
	var out: Array = []
	for q in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		out.append(_p(c + (q as Vector2).rotated(rot)))
	return out


static func _ellipse_poly(c: Vector2, rx: float, rz: float, n: int = 64) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(_p(c + Vector2(cos(a) * rx, sin(a) * rz)))
	return out


static func _col(c: Color) -> Array:
	return [_r(c.r), _r(c.g), _r(c.b)]


static func _layer(items: Array) -> Dictionary:
	return {"map": "classic", "items": items}


## Every layer of the classic map from its 2.0 description.
static func export_layers(L: ClassicLayout) -> Dictionary:
	return {
		"buildings": _layer(_buildings(L)),
		"water": _layer(_waters(L)),
		"roads": _layer(_roads(L)),
		"paths": _layer(_paths(L)),
		"areas": _layer(_areas(L)),
		"barriers": _layer(_barriers(L)),
		"trees": _layer(_trees(L)),
		"props": _layer(_props(L)),
		"gameplay": _layer(_gameplay(L)),
	}


static func _buildings(L: ClassicLayout) -> Array:
	var out: Array = []
	for bd in L.buildings:
		var id := String(bd["id"])
		var pos: Vector2 = bd["pos"]
		var size: Vector2 = bd["size"]
		var rot := float(bd.get("rot", 0.0))
		var it := {"id": id, "kind": "classic", "label": String(bd["name"]), "footprint": _rect_poly(pos, size, rot),
			"h": _r(float(bd["h"])), "status": "existing"}
		var base := float(bd.get("base_y", 0.0))
		if base > 0.0:
			# the bell tower stands on its arch: solid from base_y up only
			it["parts"] = [{"footprint": _rect_poly(pos, size, rot), "h": _r(float(bd["h"])), "base": _r(base)}]
		if id == "shed":
			# open front (south): the back wall and both side walls 0.6 m thick
			# and a 0.6 m roof slab, as 2.0's collider had it
			var hz := size.y * 0.5
			var hx := size.x * 0.5
			var open := [_p(pos + Vector2(-hx + 0.6, -hz + 0.6)), _p(pos + Vector2(hx - 0.6, -hz + 0.6)),
				_p(pos + Vector2(hx - 0.6, hz)), _p(pos + Vector2(-hx + 0.6, hz))]
			it["passages"] = [{"polygon": open, "floor": 0.0, "clear": _r(float(bd["h"]) - 0.6), "exact": true}]
		out.append(it)
	return out


## The classic waters keep their hand-placed shore exits, jump points and
## respawn pads, and their 2.0 pits (straight-sided: bank 0.6 m).
static func _waters(L: ClassicLayout) -> Array:
	var kinds := {"fountain": "fountain", "pond": "pond", "pool": "pool", "quarry": "pond", "garden": "pool", "inlet": "pond"}
	var out: Array = []
	for w in L.waters:
		var id := String(w["id"])
		var c: Vector2 = w["center"]
		var it := {"id": id, "kind": String(kinds.get(id, "pond")), "label": String(w["name"]),
			"surface": _r(float(w["surface_y"])), "floor": _r(float(w["floor_y"])), "rim_h": _r(float(w.get("rim_h", 0.0))),
			"rim_t": _r(float(w.get("rim_t", 0.5))), "bank": 0.6}
		match String(w["shape"]):
			"circle":
				it["circle"] = [_p(c), _r(float(w["radius"]))]
				it["pedestal"] = [1.3, 2.6]     # the fountain's central column (r, h), centred at ground level
			"ellipse":
				it["polygon"] = _ellipse_poly(c, float(w["rx"]), float(w["rz"]))
			"rect":
				it["polygon"] = _rect_poly(c, w["size"])
		var ex: Array = []
		for e in w["exits"]:
			ex.append(_p(Vector2((e as Vector3).x, (e as Vector3).z)))
		it["exits"] = ex
		var pads: Array = []
		for p in w["pads"]:
			pads.append(_p(p))
		it["pads"] = pads
		var jp: Array = []
		for p in w["jump_points"]:
			jp.append(_p(p))
		it["jump_points"] = jp
		out.append(it)
	return out


static func _roads(L: ClassicLayout) -> Array:
	var out: Array = []
	for i in L.roads.size():
		var r: Dictionary = L.roads[i]
		out.append({"id": "road_%02d" % i, "pts": _pts(r["pts"]), "w": _r(float(r["w"])), "kind": "campus", "curb": false})
	return out


static func _paths(L: ClassicLayout) -> Array:
	var out: Array = []
	for i in L.paths.size():
		var p: Dictionary = L.paths[i]
		var c: Color = p["color"]
		var surface := "stone"
		if c.is_equal_approx(Color(0.62, 0.56, 0.46)):
			surface = "gravel"
		elif c.is_equal_approx(Color(0.55, 0.40, 0.28)):
			surface = "boardwalk"
		out.append({"id": "path_%02d" % i, "pts": _pts(p["pts"]), "w": _r(float(p["w"])), "surface": surface})
	return out


static func _areas(L: ClassicLayout) -> Array:
	var out: Array = []
	for i in L.plazas.size():
		var pl: Dictionary = L.plazas[i]
		var poly: Array = _ellipse_poly(pl["center"], float(pl["radius"]), float(pl["radius"]), 48) if pl["shape"] == "circle" else _rect_poly(pl["center"], pl["size"])
		out.append({"id": "plaza_%02d" % i, "kind": "plaza", "polygon": poly})
	return out


static func _barriers(L: ClassicLayout) -> Array:
	var out: Array = []
	var n := 0
	for s in L.walls:
		out.append({"id": "wall_%03d" % n, "kind": "wall_low", "pts": [_p(s["a"]), _p(s["b"])], "h": _r(float(s["h"])), "t": _r(float(s["t"]))})
		n += 1
	for s in L.hedges:
		out.append({"id": "hedge_%03d" % n, "kind": "hedge", "pts": [_p(s["a"]), _p(s["b"])], "h": _r(float(s["h"])), "t": _r(float(s["t"]))})
		n += 1
	for s in L.fences:
		out.append({"id": "fence_%03d" % n, "kind": "fence_" + String(s["kind"]), "pts": [_p(s["a"]), _p(s["b"])], "h": _r(float(s["h"]))})
		n += 1
	for s in L.cart_blockers:
		if bool(s.get("hidden", false)):
			continue      # a dorm doorway's cart line: CampusDorms derives it
		out.append({"id": "bollards_%03d" % n, "kind": "bollards", "pts": [_p(s["a"]), _p(s["b"])]})
		n += 1
	return out


static func _trees(L: ClassicLayout) -> Array:
	var out: Array = []
	for i in L.trees.size():
		var t: Dictionary = L.trees[i]
		out.append({"id": "tree_%03d" % i, "pos": _p(t["pos"]), "r": _r(float(t["r"])), "h": _r(float(t["h"])),
			"kind": String(t["kind"]), "obs": "classic"})
	return out


## Lamps, benches and decor; plus the classic map's own solid pieces: the
## quarry boulders, the ledge and its ramp, the inlet dock and the dorm
## yards' name signs.
static func _props(L: ClassicLayout) -> Array:
	var out: Array = []
	var n := 0
	for lp in L.lamps:
		out.append({"id": "lamp_%03d" % n, "kind": "lamp", "p": _p(lp)})
		n += 1
	for bn in L.benches:
		out.append({"id": "bench_%03d" % n, "kind": "bench", "p": _p(bn["pos"]), "rot": _r(rad_to_deg(float(bn["rot"])))})
		n += 1
	for pr in L.props:
		# decor only: 2.0 gave none of these a collider
		out.append({"id": "prop_%03d" % n, "kind": String(pr["kind"]), "p": _p(pr["pos"]), "rot": _r(rad_to_deg(float(pr["rot"]))), "collide": false})
		n += 1
	for rk in L.rocks:
		var rp: Vector3 = rk["pos"]
		out.append({"id": "boulder_%03d" % n, "kind": "boulder", "p": _p(Vector2(rp.x, rp.z)), "size": _p3(rk["size"]), "rot": _r(rad_to_deg(float(rk["rot"])))})
		n += 1
	for pf in L.platforms:
		out.append({"id": "platform_%03d" % n, "kind": "platform", "center": _p3(pf["center"]), "size": _p3(pf["size"]),
			"rot": 0.0, "dock": bool(pf.get("dock", false))})
		n += 1
	for rp2 in L.ramps:
		out.append({"id": "ramp_%03d" % n, "kind": "ramp", "from": _p3(rp2["from"]), "to": _p3(rp2["to"]), "w": _r(float(rp2["w"]))})
		n += 1
	for so in L.solids:
		out.append({"id": "solid_%03d" % n, "kind": String(so["kind"]), "p": _p(so["pos"]), "size": _p3(so["size"]), "rot": _r(rad_to_deg(float(so["rot"]))), "solid": true})
		n += 1
	return out


static func _gameplay(L: ClassicLayout) -> Array:
	var out: Array = []
	# the play boundary: 2.0's invisible walls stood 1 m outside BOUNDS
	var bb := ClassicLayout.BOUNDS.grow(1.0)
	out.append({"id": "boundary", "kind": "boundary", "polygon": [_p(bb.position), _p(Vector2(bb.end.x, bb.position.y)), _p(bb.end), _p(Vector2(bb.position.x, bb.end.y))]})
	var ps: Array = []
	for p in L.patrol_spawns:
		ps.append(_p(p))
	out.append({"id": "patrol_spawns", "kind": "patrol_spawns", "pts": ps})
	var cs: Array = []
	for c in L.cart_spawns:
		cs.append([_p(c["pos"]), _r(rad_to_deg(float(c["yaw"])))])
	out.append({"id": "cart_spawns", "kind": "cart_spawns", "spots": cs})
	var gs: Array = []
	for p in L.gadget_spots:
		gs.append(_p(p))
	out.append({"id": "gadget_spots", "kind": "gadget_spots", "pts": gs})
	var co: Array = []
	for p in L.coin_spots:
		co.append(_p(p))
	out.append({"id": "coin_spots", "kind": "coin_spots", "pts": co})
	for i in L.landmarks.size():
		var lm: Dictionary = L.landmarks[i]
		out.append({"id": "label_%02d" % i, "kind": "landmark_label", "label": String(lm["name"]), "p": _p(lm["pos"])})
	var pool: Array = []
	for w in L.waters:
		pool.append({"id": String(w["id"]), "items": [String(w["id"])], "name": String(w["name"]), "short": String(w["short"]),
			"color": _col(w["color"]), "icon": String(w["icon"])})
	out.append({"id": "objective_pool", "kind": "objective_pool", "waters": pool})
	for d in ClassicDorms.DORMS:
		out.append(_start_dorm(d))
	return out


## One classic dorm as a start_dorm definition: the same common room, doors,
## lintels, furniture and pads ClassicDorms builds (CampusDorms derives the
## walls as the footprint minus the room and doorways, the upper block as
## the slab over them, and the doorway cart lines).
static func _start_dorm(d: Dictionary) -> Dictionary:
	var id := String(d["id"])
	var g := ClassicDorms.geometry(id)
	var room: Rect2 = g["room"]
	var doors: Array = []
	for dr in g["doors"]:
		doors.append({"id": String(dr["id"]), "name": String(dr["name"]), "p": _p(dr["pos"]), "normal": _p(dr["normal"]),
			"w": ClassicDorms.DOOR_W, "wall_t": ClassicDorms.WALL_T})
	var furniture: Array = []
	for bx in g["boxes"]:
		var kind := String(bx[2])
		if kind != "sofa" and kind != "hearth":
			continue
		var c: Vector3 = bx[0]
		var s: Vector3 = bx[1]
		furniture.append({"kind": kind, "p": _p(Vector2(c.x, c.z)), "size": _p3(s), "yaw": 0.0})
	var pads: Array = []
	for pd in g["pads"]:
		var pp: Vector2 = pd["pos"]
		pads.append([_r(pp.x), _r(pp.y), int(pd["door"])])
	var rp := [_p(room.position), _p(Vector2(room.end.x, room.position.y)), _p(room.end), _p(Vector2(room.position.x, room.end.y))]
	return {"id": "start_" + id, "kind": "start_dorm", "dorm": id, "building": "dorm_" + id, "name": String(d["name"]),
		"short": String(d["short"]), "default": id == "puddlesworth", "race_start": true, "ceil": ClassicDorms.CEIL,
		"h": _r(float(d["h"])), "room": rp, "doors": doors, "furniture": furniture, "pads": pads}
