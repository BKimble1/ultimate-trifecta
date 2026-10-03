class_name CampusFingerprint
extends RefCounted
## Gameplay fingerprints of the campus (V5): the authoritative collision
## shapes, both navigation grids and the gameplay data in CampusLayout, each
## reduced to a SHA-256.  The V5 art pass may change how the campus looks but
## none of these; test_campus_art compares them with the values recorded on
## the V4 code (dcebf4e), so any change to a collider, a nav cell, a water
## exit or a spawn fails the test.


static func _sha(s: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _f(x: float) -> String:
	return "%.4f" % x


static func _v3(v: Vector3) -> String:
	return "%s,%s,%s" % [_f(v.x), _f(v.y), _f(v.z)]


static func _xf(t: Transform3D) -> String:
	return "%s|%s|%s|%s" % [_v3(t.basis.x), _v3(t.basis.y), _v3(t.basis.z), _v3(t.origin)]


## One line per collision shape: body, layer/mask, type, dimensions, transform.
static func collision_lines(layout: CampusLayout) -> PackedStringArray:
	var root := Node3D.new()
	CampusBuilder.new(layout).build_collision(root)
	var out := PackedStringArray()
	for body in root.get_children():
		var co := body as CollisionObject3D
		if co == null:
			continue
		for cs in co.get_children():
			var c := cs as CollisionShape3D
			if c == null:
				continue
			var sh := c.shape
			var dims := ""
			if sh is BoxShape3D:
				dims = _v3((sh as BoxShape3D).size)
			elif sh is CylinderShape3D:
				dims = "%s,%s" % [_f((sh as CylinderShape3D).radius), _f((sh as CylinderShape3D).height)]
			elif sh is HeightMapShape3D:
				var hm := sh as HeightMapShape3D
				var hctx := HashingContext.new()
				hctx.start(HashingContext.HASH_SHA256)
				hctx.update(hm.map_data.to_byte_array())
				dims = "%dx%d:%s" % [hm.map_width, hm.map_depth, hctx.finish().hex_encode()]
			else:
				dims = str(sh)
			out.append("%s|%d|%d|%s|%s|%s|%s" % [co.name, co.collision_layer, co.collision_mask, sh.get_class(), dims, _xf(c.transform), str(c.disabled)])
	root.free()
	return out


static func collision_hash(layout: CampusLayout) -> String:
	return _sha("\n".join(collision_lines(layout)))


## Every cell of the foot and cart grids: solid flags and weight scales.
static func nav_hash(layout: CampusLayout) -> String:
	var g := NavGrid.new(layout)
	var buf := PackedByteArray()
	buf.resize(g.dims.x * g.dims.y * 2)
	var wf := PackedFloat32Array()
	wf.resize(g.dims.x * g.dims.y * 2)
	var i := 0
	for y in g.dims.y:
		for x in g.dims.x:
			var c := Vector2i(x, y)
			buf[i * 2] = 1 if g.foot.is_point_solid(c) else 0
			buf[i * 2 + 1] = 1 if g.cart.is_point_solid(c) else 0
			wf[i * 2] = g.foot.get_point_weight_scale(c)
			wf[i * 2 + 1] = g.cart.get_point_weight_scale(c)
			i += 1
	var lw := g.low_wall_cells.keys()
	lw.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	ctx.update(wf.to_byte_array())
	ctx.update(str(lw).to_utf8_buffer())
	return ctx.finish().hex_encode()


## The gameplay data: waters (shapes, exits, pads, jump points), doors,
## spawns, gadget spots, and every list that becomes a collider or nav cell.
static func layout_hash(layout: CampusLayout) -> String:
	var parts := PackedStringArray()
	for w in layout.waters:
		var d: Dictionary = w.duplicate()
		d.erase("color")   # presentation only
		parts.append(var_to_str(d))
	for lst in [layout.buildings.map(func(b: Dictionary) -> Array: return [b["id"], b["pos"], b["size"], b["h"], b.get("base_y", 0.0), b.get("rot", 0.0)]),
			layout.roads, layout.paths.map(func(p: Dictionary) -> Array: return [p["pts"], p["w"]]), layout.plazas.map(func(p: Dictionary) -> Array: return [p["shape"], p["center"], p.get("radius", 0.0), p.get("size", Vector2.ZERO)]),
			layout.walls, layout.hedges, layout.fences, layout.cart_blockers, layout.trees.map(func(t: Dictionary) -> Array: return [t["pos"], t["r"]]),
			layout.rocks, layout.platforms.map(func(p: Dictionary) -> Array: return [p["center"], p["size"], p.get("dock", false)]), layout.ramps.map(func(r: Dictionary) -> Array: return [r["from"], r["to"], r["w"]]),
			layout.lamps, layout.benches, layout.dorm_doors, layout.dorm_pads, layout.runner_spawns, layout.patrol_spawns, layout.cart_spawns, layout.gadget_spots]:
		parts.append(var_to_str(lst))
	return _sha("\n".join(parts))


# ---------------------------------------------------------------------------
# V6: what changed, and where
# ---------------------------------------------------------------------------
## The collision lines of the shapes lying entirely outside every V6 dorm
## district (CampusDorms.DISTRICTS grown by `margin`), sorted: equal for
## the V5 and V6 layouts means nothing outside the districts changed.  The
## ground height field spans the campus; it is included (and unchanged).
static func collision_lines_outside(layout: CampusLayout, margin: float = 0.5) -> PackedStringArray:
	var root := Node3D.new()
	CampusBuilder.new(layout).build_collision(root)
	var out := PackedStringArray()
	for body in root.get_children():
		var co := body as CollisionObject3D
		if co == null:
			continue
		for cs in co.get_children():
			var c := cs as CollisionShape3D
			if c == null:
				continue
			if not (c.shape is HeightMapShape3D) and _in_district(_shape_rect(c), margin):
				continue
			var sh := c.shape
			var dims := ""
			if sh is BoxShape3D:
				dims = _v3((sh as BoxShape3D).size)
			elif sh is CylinderShape3D:
				dims = "%s,%s" % [_f((sh as CylinderShape3D).radius), _f((sh as CylinderShape3D).height)]
			elif sh is HeightMapShape3D:
				var hm := sh as HeightMapShape3D
				var hctx := HashingContext.new()
				hctx.start(HashingContext.HASH_SHA256)
				hctx.update(hm.map_data.to_byte_array())
				dims = "%dx%d:%s" % [hm.map_width, hm.map_depth, hctx.finish().hex_encode()]
			out.append("%s|%d|%d|%s|%s|%s" % [co.name, co.collision_layer, co.collision_mask, sh.get_class(), dims, _xf(c.transform)])
	root.free()
	out.sort()
	return out


static func _shape_rect(c: CollisionShape3D) -> Rect2:
	var ext := Vector3.ONE * 0.5
	if c.shape is BoxShape3D:
		ext = (c.shape as BoxShape3D).size * 0.5
	elif c.shape is CylinderShape3D:
		var r := (c.shape as CylinderShape3D).radius
		ext = Vector3(r, 1.0, r)
	var r2 := Rect2(Vector2(c.transform.origin.x, c.transform.origin.z), Vector2.ZERO)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p: Vector3 = c.transform * Vector3(ext.x * sx, 0.0, ext.z * sz)
			r2 = r2.expand(Vector2(p.x, p.z))
	return r2


static func _in_district(r: Rect2, margin: float) -> bool:
	for k in CampusDorms.DISTRICTS:
		if (CampusDorms.DISTRICTS[k] as Rect2).grow(margin).intersects(r, true):
			return true
	return false


## Both navigation grids, every cell whose centre lies outside the dorm
## districts grown by `margin` (nav inflation reaches ~1.5 m beyond a
## collider).  Returns [hash, cells compared].
static func nav_hash_outside(layout: CampusLayout, margin: float = 3.0) -> Array:
	var g := NavGrid.new(layout)
	var buf := PackedByteArray()
	var wf := PackedFloat32Array()
	var n := 0
	for y in g.dims.y:
		for x in g.dims.x:
			var c := Vector2i(x, y)
			var w := g.to_world(c)
			if _in_district(Rect2(w, Vector2.ZERO), margin):
				continue
			buf.append(1 if g.foot.is_point_solid(c) else 0)
			buf.append(1 if g.cart.is_point_solid(c) else 0)
			wf.append(g.foot.get_point_weight_scale(c))
			wf.append(g.cart.get_point_weight_scale(c))
			n += 1
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	ctx.update(wf.to_byte_array())
	return [ctx.finish().hex_encode(), n]


## The gameplay layout lists, item by item, keeping only items outside the
## dorm districts (segments and areas by their bounding rect).  Sorted
## per list.  {list name: PackedStringArray}
static func layout_outside(layout: CampusLayout) -> Dictionary:
	var out := {}
	var add := func(name: String, items: Array, rect_of: Callable) -> void:
		var lines := PackedStringArray()
		for it in items:
			if _in_district(rect_of.call(it), 0.0):
				continue
			lines.append(var_to_str(it))
		lines.sort()
		out[name] = lines
	var pt := func(p: Vector2) -> Rect2: return Rect2(p, Vector2.ZERO)
	var seg := func(s: Dictionary) -> Rect2: return Rect2(s["a"], Vector2.ZERO).expand(s["b"])
	var poly := func(r: Dictionary) -> Rect2:
		var pts: PackedVector2Array = r["pts"]
		var rr := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			rr = rr.expand(q)
		return rr
	var wat: Array = []
	for w in layout.waters:
		var d: Dictionary = w.duplicate()
		d.erase("color")
		wat.append(d)
	add.call("waters", wat, func(w: Dictionary) -> Rect2: return Rect2(w["center"], Vector2.ZERO))
	add.call("buildings", layout.buildings.map(func(b: Dictionary) -> Array: return [b["id"], b["pos"], b["size"], b["h"], b.get("base_y", 0.0), b.get("rot", 0.0)]),
		func(b: Array) -> Rect2: return Rect2((b[1] as Vector2) - (b[2] as Vector2) * 0.5, b[2]))
	add.call("roads", layout.roads, poly)
	add.call("paths", layout.paths.map(func(p: Dictionary) -> Dictionary: return {"pts": p["pts"], "w": p["w"]}), poly)
	add.call("plazas", layout.plazas.map(func(p: Dictionary) -> Array: return [p["shape"], p["center"], p.get("radius", 0.0), p.get("size", Vector2.ZERO)]),
		func(p: Array) -> Rect2: return Rect2((p[1] as Vector2) - (p[3] as Vector2) * 0.5, p[3]).grow(float(p[2])))
	for nm in ["walls", "hedges", "fences", "cart_blockers"]:
		add.call(nm, layout.get(nm), seg)
	add.call("trees", layout.trees.map(func(t: Dictionary) -> Array: return [t["pos"], t["r"]]), func(t: Array) -> Rect2: return Rect2(t[0], Vector2.ZERO))
	add.call("rocks", layout.rocks, func(r: Dictionary) -> Rect2: return Rect2(Vector2((r["pos"] as Vector3).x, (r["pos"] as Vector3).z), Vector2.ZERO))
	add.call("platforms", layout.platforms.map(func(p: Dictionary) -> Array: return [p["center"], p["size"], p.get("dock", false)]),
		func(p: Array) -> Rect2: return Rect2(Vector2((p[0] as Vector3).x, (p[0] as Vector3).z), Vector2.ZERO))
	add.call("ramps", layout.ramps.map(func(r: Dictionary) -> Array: return [r["from"], r["to"], r["w"]]),
		func(r: Array) -> Rect2: return Rect2(Vector2((r[0] as Vector3).x, (r[0] as Vector3).z), Vector2.ZERO))
	add.call("lamps", layout.lamps, pt)
	add.call("benches", layout.benches, func(b: Dictionary) -> Rect2: return Rect2(b["pos"], Vector2.ZERO))
	add.call("props", layout.props, func(p: Dictionary) -> Rect2: return Rect2(p["pos"], Vector2.ZERO))
	add.call("gadget_spots", layout.gadget_spots, pt)
	add.call("cart_spawns", layout.cart_spawns, func(c: Dictionary) -> Rect2: return Rect2(c["pos"], Vector2.ZERO))
	add.call("patrol_spawns", layout.patrol_spawns, pt)
	add.call("solids", layout.solids, func(s: Dictionary) -> Rect2: return Rect2(s["pos"], Vector2.ZERO))
	return out
