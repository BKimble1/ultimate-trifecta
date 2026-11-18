class_name SnowCover
extends RefCounted
## (2.2 build 21) Season 1's snow on the ground and on things.
##
##  * Snow caps: everything outdoors that faces up (bush and tree tops, roofs,
##    benches, walls, lamp heads) wears a broken layer of snow, drawn by the
##    world and prop shaders from the surface's facing (world_common,
##    prop.gdshader).  Never indoors: the start dorms' interiors are masked.
##  * Snow patches: a few soft drifts on open lawns (PATCHES, picked from the
##    map's open ground, the same on every device), with ragged edges.
##  * Footprints (SnowPrints): a runner or Night Watch on foot in a patch
##    leaves prints that stay for the whole round.
## One small texture per map holds both masks (R: the patches, G: indoors,
## as the height of that interior's ceiling, so roofs above stay snowy),
## shared with the shaders through global shader parameters (project
## settings, [shader_globals]); the prints read the same R, so a print is
## only ever where the snow is drawn.  View only: nothing in the simulation
## knows about snow.

const TEXEL := 1.0            # metres per texel (the shader adds the fine ragged edge)
## G holds the interior's ceiling height (world y) over this range
const CEIL_RANGE := 24.0
const PATCHES := 14
const R_RANGE := Vector2(4.5, 8.5)
## patches keep this far from the home dorms' doors (the way out stays clear)
const DOOR_CLEAR := 10.0

static var _cache: Dictionary = {}   # layout instance id -> data
static var _tasks: Dictionary = {}   # layout instance id -> [task id, result holder]


## {img: Image, tex: ImageTexture, origin: Vector2, size: Vector2,
##  patches: [Vector4(x, z, r, rot)], aspect: [float], indoor_top: float}
## Built at once (tests, tools).
static func for_layout(layout: CampusLayout, map_id: String) -> Dictionary:
	var key := layout.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var d := _build(layout, _inputs(map_id))
	_finish(d)
	_cache[key] = d
	return d


## A round's loading starts the build on a worker (it takes tens of
## milliseconds on the big campus: never inside a loading frame); poll()
## returns it once it's done ({} until then).  Once per map per session.
static func request(layout: CampusLayout, map_id: String) -> void:
	var key := layout.get_instance_id()
	if _cache.has(key) or _tasks.has(key):
		return
	var holder := {}
	var inputs := _inputs(map_id)   # the dorms' geometry, read here on the main thread
	var tid := WorkerThreadPool.add_task(func() -> void: holder["d"] = _build(layout, inputs), false, "snow cover")
	_tasks[key] = [tid, holder]


static func poll(layout: CampusLayout) -> Dictionary:
	var key := layout.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	if not _tasks.has(key):
		return {}
	var t: Array = _tasks[key]
	if not WorkerThreadPool.is_task_completed(int(t[0])):
		return {}
	WorkerThreadPool.wait_for_task_completion(int(t[0]))
	_tasks.erase(key)
	var d: Dictionary = (t[1] as Dictionary).get("d", {})
	if d.is_empty():
		return {}
	_finish(d)
	_cache[key] = d
	return d


## The texture is made on the main thread.
static func _finish(d: Dictionary) -> void:
	d["tex"] = ImageTexture.create_from_image(d["img"])


## Everything the build needs from the dorms: their doors and interiors.
static func _inputs(map_id: String) -> Dictionary:
	var doors: Array = []
	var indoor: Array = []   # [poly, ceiling y]
	var indoor_top := 0.0
	for id in CampusDorms.ids(map_id):
		var g := CampusDorms.geometry(id)
		if g.is_empty():
			continue
		for dr in g.get("doors", []):
			doors.append((dr as Dictionary).get("pos", Vector2.ZERO))
		var top := float(g.get("floor", 0.0)) + float(g.get("ceil", 3.0)) + 0.2
		indoor_top = maxf(indoor_top, top)
		for poly in g.get("inside", []):
			indoor.append([poly, top])
	return {"doors": doors, "indoor": indoor, "indoor_top": indoor_top}


static func _pick(layout: CampusLayout, doors: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261201 + layout.coin_spots.size() * 31 + int(layout.bounds.size.x)
	var cands: Array = []
	for c in layout.coin_spots:
		cands.append(c)
	for g in layout.gadget_spots:
		cands.append(g)
	# a seeded shuffle (the same on every device)
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var out: Array = []
	for c in cands:
		if out.size() >= PATCHES:
			break
		var r := rng.randf_range(R_RANGE.x, R_RANGE.y)
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, 6.0)
		var p := (c as Vector2) + off
		if not layout._open_ground(p, r * 0.75):
			continue
		var bad := false
		for dp in doors:
			if (dp as Vector2).distance_to(p) < r + DOOR_CLEAR:
				bad = true
				break
		for q in out:
			if not bad and Vector2(q.x, q.y).distance_to(p) < r + float(q.z) + 8.0:
				bad = true
		if not bad:
			out.append(Vector4(p.x, p.y, r, rng.randf() * PI))
	return out


static func _build(layout: CampusLayout, inputs: Dictionary) -> Dictionary:
	var patches := _pick(layout, inputs["doors"])
	var aspects: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + patches.size()
	for i in patches.size():
		aspects.append(rng.randf_range(0.6, 0.95))
	# bounds: every patch and every dorm interior
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in patches:
		lo = lo.min(Vector2(q.x - q.z, q.y - q.z))
		hi = hi.max(Vector2(q.x + q.z, q.y + q.z))
	var indoor: Array = inputs["indoor"]
	var indoor_top := float(inputs["indoor_top"])
	for e in indoor:
		for v in (e[0] as PackedVector2Array):
			lo = lo.min(v)
			hi = hi.max(v)
	if lo.x == INF:
		lo = Vector2.ZERO
		hi = Vector2.ONE
	lo -= Vector2(2, 2)
	hi += Vector2(2, 2)
	var w := int(ceil((hi.x - lo.x) / TEXEL))
	var h := int(ceil((hi.y - lo.y) / TEXEL))
	var data := PackedByteArray()
	data.resize(w * h * 2)
	data.fill(0)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.22
	# the patches: soft ellipses with ragged edges
	for i in patches.size():
		var q: Vector4 = patches[i]
		var asp := float(aspects[i])
		var rot := Vector2.from_angle(q.w)
		var x0 := maxi(0, int((q.x - q.z - 1.0 - lo.x) / TEXEL))
		var x1 := mini(w - 1, int((q.x + q.z + 1.0 - lo.x) / TEXEL))
		var y0 := maxi(0, int((q.y - q.z - 1.0 - lo.y) / TEXEL))
		var y1 := mini(h - 1, int((q.y + q.z + 1.0 - lo.y) / TEXEL))
		for ty in range(y0, y1 + 1):
			for tx in range(x0, x1 + 1):
				var p := lo + Vector2(tx + 0.5, ty + 0.5) * TEXEL
				var rel := p - Vector2(q.x, q.y)
				var u := Vector2(rel.dot(rot), rel.dot(rot.orthogonal()) / asp) / q.z
				var dd := u.length() + noise.get_noise_2d(p.x, p.y) * 0.22
				var a := clampf((1.0 - dd) / 0.35, 0.0, 1.0)
				if a <= 0.0:
					continue
				var ix := (ty * w + tx) * 2
				data[ix] = maxi(data[ix], int(a * 255.0))
	# indoors: the start dorms' interiors (no snow on the furniture)
	for e in indoor:
		var poly: PackedVector2Array = e[0]
		var gv := clampi(int(ceil(float(e[1]) / CEIL_RANGE * 255.0)), 1, 255)
		var pl := Vector2(INF, INF)
		var ph := Vector2(-INF, -INF)
		for v in poly:
			pl = pl.min(v)
			ph = ph.max(v)
		for ty in range(maxi(0, int((pl.y - 0.5 - lo.y) / TEXEL)), mini(h - 1, int((ph.y + 0.5 - lo.y) / TEXEL)) + 1):
			for tx in range(maxi(0, int((pl.x - 0.5 - lo.x) / TEXEL)), mini(w - 1, int((ph.x + 0.5 - lo.x) / TEXEL)) + 1):
				var p2 := lo + Vector2(tx + 0.5, ty + 0.5) * TEXEL
				if Geometry2D.is_point_in_polygon(p2, poly):
					data[(ty * w + tx) * 2 + 1] = maxi(data[(ty * w + tx) * 2 + 1], gv)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RG8, data)
	return {"img": img, "origin": lo, "size": Vector2(w, h) * TEXEL,
		"patches": patches, "aspect": aspects, "indoor_top": indoor_top}


## How much snow lies on the ground at `p` (0..1), as drawn.
static func amount_at(d: Dictionary, p: Vector2) -> float:
	if d.is_empty():
		return 0.0
	var img: Image = d["img"]
	var uv := (p - (d["origin"] as Vector2)) / TEXEL
	var x := int(uv.x)
	var y := int(uv.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return 0.0
	return img.get_pixel(x, y).r


## Snow on for a round on this map (or off: menus, the dorm stage).
static func apply(d: Dictionary) -> void:
	RenderingServer.global_shader_parameter_set("snow_field", d["tex"])
	RenderingServer.global_shader_parameter_set("snow_origin", d["origin"])
	RenderingServer.global_shader_parameter_set("snow_size", d["size"])
	RenderingServer.global_shader_parameter_set("snow_indoor_top", CEIL_RANGE)
	RenderingServer.global_shader_parameter_set("snow_on", 1.0)


static func off() -> void:
	RenderingServer.global_shader_parameter_set("snow_on", 0.0)
