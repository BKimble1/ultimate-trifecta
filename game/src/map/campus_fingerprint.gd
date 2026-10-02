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
