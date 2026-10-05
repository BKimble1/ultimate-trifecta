class_name PaceFields
extends RefCounted
## Pass 8: route-distance fields for the live runner pace (RunnerPace).
##
## One field per water and one per home dorm: the cost of walking from any
## 1 m cell of the runners' navigation grid (NavGrid.foot: the same solid
## cells, low-wall and fence costs and corner rule the bots' A* uses) to the
## nearest of that place's sources.  A field is a multi-source Dijkstra
## (a bucket queue: integer step costs 10 straight / 14 diagonal, times the
## destination cell's weight, like AStarGrid2D) over the whole grid, so a
## runner's remaining route is then a handful of array reads:
##
##   water field   sources: the water's validated entry points (its bots'
##                 jump points) and shore exits - where a runner really
##                 gets in, never a point across a wall or fence
##   home field    sources: the approach point outside each of tonight's
##                 doors; each cell also keeps which door is nearest by
##                 route (the suggested door, never one through the dorm)
##
## Built off the main thread: request() is called from the round's staged
## preparation (MatchSim.setup inside the "sim" job), copies what it needs
## from the layout, and starts one worker-pool task; nothing waits for it.
## Until a field is ready the pace says so (stamp-based shared places).
## Fields depend on the layout only (not the round), so they are kept for
## later rounds: at most 6 waters + 3 dorms = 9 fields (~3.4 MB).
## Bot path searches are unaffected: the grid is read under the same lock
## a bot search takes (once per layout, ~tens of ms, in loading).

const UNREACH := 0x3FFFFFFF
## cost units per metre (10 = straight step of 1 m on an ordinary cell)
const UNIT := 10.0
const BUCKETS := 128            # > the largest step cost (14 x weight 6 = 84)
## how far a position may be from an open cell (capsules stand in the
## inflation band around walls; the dorm floor next to furniture)
const LOOKUP_R := 4

static var _mutex := Mutex.new()
static var _layout: CampusLayout = null
static var _w := 0
static var _h := 0
static var _origin := Vector2.ZERO
static var _solid := PackedByteArray()      # 1 = solid (written once by the worker)
static var _wt := PackedByteArray()         # weight per cell (1, 4, 6)
static var _fields: Dictionary = {}         # key -> {"d": PackedInt32Array, "lab": PackedByteArray, "ms": float}
static var _task := -1
static var _task_keys: Array = []
static var _waiting: Array = []             # specs asked for while a task ran
## measurements (docs/pass8/match.md): grid copy and each field, worker ms
static var stats := {"extract_ms": 0.0, "fields": {}, "tasks": 0}


static func water_key(water_index: int) -> String:
	return "w%d" % water_index


static func home_key(dorm_id: String) -> String:
	return "h:" + dorm_id


## Main thread: make sure the fields for these waters and this dorm exist or
## are being built.  Cheap (no grid work here).
static func request(lay: CampusLayout, water_indices: Array, dorm_id: String) -> void:
	poll()
	_mutex.lock()
	if _layout != lay:
		if _task >= 0:
			_mutex.unlock()
			return          # another layout is still being read; asked again later
		_layout = lay
		_fields.clear()
		_solid = PackedByteArray()
		_wt = PackedByteArray()
	var specs: Array = []
	for wi in water_indices:
		var k := water_key(int(wi))
		if not _fields.has(k) and not _task_keys.has(k) and not _queued(k):
			var w: Dictionary = lay.waters[int(wi)]
			var src := PackedVector2Array()
			for jp in w.get("jump_points", []):
				src.append(jp)
			for e in w.get("exits", []):
				src.append(Vector2((e as Vector3).x, (e as Vector3).z))
			specs.append({"key": k, "src": src, "lab": PackedByteArray()})
	var hk := home_key(dorm_id)
	if dorm_id != "" and not _fields.has(hk) and not _task_keys.has(hk) and not _queued(hk):
		var src2 := PackedVector2Array()
		var lab := PackedByteArray()
		var doors: Array = CampusDorms.geometry(dorm_id).get("doors", [])
		for i in doors.size():
			src2.append((doors[i] as Dictionary)["approach"])
			lab.append(i)
		specs.append({"key": hk, "src": src2, "lab": lab})
	var running := _task >= 0
	if running:
		for s in specs:
			_waiting.append(s)
	_mutex.unlock()
	if specs.is_empty() or running:
		return
	_start(lay, specs)


## (mutex held) a field already asked for while a task runs.
static func _queued(key: String) -> bool:
	for s in _waiting:
		if String(s["key"]) == key:
			return true
	return false


static func _start(lay: CampusLayout, specs: Array) -> void:
	var nav := NavGrid.shared(lay)          # built by the round's "nav" job
	_mutex.lock()
	_task_keys.clear()
	for s in specs:
		_task_keys.append(s["key"])
	stats["tasks"] = int(stats["tasks"]) + 1
	# high priority on purpose: Godot runs low-priority tasks on a small share
	# of the pool (one thread on a 4-6 core phone), the share the bots' path
	# searches use; a field build queued there could make a scheduled path
	# delivery wait.  This one task takes another thread instead.
	_task = WorkerThreadPool.add_task(_job.bind(nav, specs), true, "pace fields")
	_mutex.unlock()


## Main thread: release a finished task and start what was asked meanwhile.
static func poll() -> void:
	_mutex.lock()
	var t := _task
	var done := t >= 0 and WorkerThreadPool.is_task_completed(t)
	_mutex.unlock()
	if not done:
		return
	WorkerThreadPool.wait_for_task_completion(t)     # already complete: no wait
	_mutex.lock()
	_task = -1
	_task_keys.clear()
	var again: Array = []
	for s in _waiting:
		if not _fields.has(s["key"]):
			again.append(s)
	_waiting.clear()
	var lay := _layout
	_mutex.unlock()
	if not again.is_empty() and lay != null:
		_start(lay, again)


## A round left while fields are still being built: the App's reaper
## releases the task when it finishes (no wait on the main thread).
static func hand_off() -> void:
	_mutex.lock()
	var t := _task
	if t >= 0 and not WorkerThreadPool.is_task_completed(t):
		_task = -1
		_task_keys.clear()
		_waiting.clear()
		_mutex.unlock()
		var ids: Array[int] = [t]
		var tree := Engine.get_main_loop() as SceneTree
		var app: Node = tree.root.get_node_or_null("App") if tree != null else null
		if app != null and app.has_method("adopt_worker_tasks"):
			app.call("adopt_worker_tasks", ids)
		else:
			WorkerThreadPool.wait_for_task_completion(t)
		return
	_mutex.unlock()
	poll()


## Tests and tools: wait for the fields being built.
static func settle() -> void:
	while true:
		_mutex.lock()
		var t := _task
		_mutex.unlock()
		if t < 0:
			return
		WorkerThreadPool.wait_for_task_completion(t)
		_mutex.lock()
		if _task == t:
			_task = -1
			_task_keys.clear()
		var again: Array = _waiting.duplicate()
		_waiting.clear()
		var lay := _layout
		_mutex.unlock()
		var left: Array = again.filter(func(s: Dictionary) -> bool: return not has(String(s["key"])))
		if not left.is_empty() and lay != null:
			_start(lay, left)


static func has(key: String) -> bool:
	_mutex.lock()
	var ok := _fields.has(key)
	_mutex.unlock()
	return ok


## {"d": PackedInt32Array, "lab": PackedByteArray} or {} while not built.
static func field(key: String) -> Dictionary:
	_mutex.lock()
	var f: Dictionary = _fields.get(key, {})
	_mutex.unlock()
	return f


## Tests: forget every field (the next request builds them again).
static func clear() -> void:
	settle()
	_mutex.lock()
	_fields.clear()
	_layout = null
	_solid = PackedByteArray()
	_wt = PackedByteArray()
	_mutex.unlock()


# ---------------------------------------------------------------------------
# Lookups (main thread, after a field is ready)
# ---------------------------------------------------------------------------
## The open grid cell nearest a world point (within LOOKUP_R cells), or -1.
static func cell_of(p: Vector2) -> int:
	if _solid.is_empty():
		return -1
	var cx := clampi(int(floor(p.x - _origin.x)), 0, _w - 1)
	var cy := clampi(int(floor(p.y - _origin.y)), 0, _h - 1)
	var c := cy * _w + cx
	if _solid[c] == 0:
		return c
	var best := -1
	var bd := INF
	for r in range(1, LOOKUP_R + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= _w or y >= _h:
					continue
				var q := y * _w + x
				if _solid[q] != 0:
					continue
				var d := Vector2(_origin.x + float(x) + 0.5, _origin.y + float(y) + 0.5).distance_squared_to(p)
				if d < bd:
					bd = d
					best = q
		if best >= 0:
			return best
	return -1


## Field value at a cell in metres-equivalent, or INF.
static func metres(f: Dictionary, cell: int) -> float:
	if cell < 0 or f.is_empty():
		return INF
	var d: int = (f["d"] as PackedInt32Array)[cell]
	return INF if d >= UNREACH else float(d) / UNIT


## The source label (door index for a home field) nearest by route, or -1.
static func label_at(f: Dictionary, cell: int) -> int:
	if cell < 0 or f.is_empty():
		return -1
	var lab: PackedByteArray = f["lab"]
	if lab.is_empty():
		return -1
	var v := lab[cell]
	return -1 if v == 255 else int(v)


# ---------------------------------------------------------------------------
# Worker
# ---------------------------------------------------------------------------
static func _job(nav: NavGrid, specs: Array) -> void:
	_mutex.lock()
	var need_grid := _solid.is_empty()
	_mutex.unlock()
	if need_grid:
		var t0 := Time.get_ticks_usec()
		var lock: Mutex = nav._grid_lock[false]
		lock.lock()                 # the same lock a bot's foot search holds
		var w := nav.dims.x
		var h := nav.dims.y
		var solid := PackedByteArray()
		solid.resize(w * h)
		var wt := PackedByteArray()
		wt.resize(w * h)
		var g := nav.foot
		for y in h:
			for x in w:
				var c := Vector2i(x, y)
				var i := y * w + x
				var s := g.is_point_solid(c) or x < 1 or y < 1 or x >= w - 1 or y >= h - 1
				solid[i] = 1 if s else 0
				wt[i] = clampi(int(round(g.get_point_weight_scale(c))), 1, 6)
		lock.unlock()
		_mutex.lock()
		_w = w
		_h = h
		_origin = nav.origin
		_solid = solid
		_wt = wt
		stats["extract_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
		_mutex.unlock()
	for s in specs:
		var t1 := Time.get_ticks_usec()
		var src_cells := PackedInt32Array()
		var src_lab := PackedByteArray()
		var pts: PackedVector2Array = s["src"]
		var labs: PackedByteArray = s["lab"]
		for i in pts.size():
			var c := cell_of(pts[i])
			if c >= 0:
				src_cells.append(c)
				src_lab.append(labs[i] if i < labs.size() else 0)
		var out := flood(_solid, _wt, _w, _h, src_cells, src_lab if not labs.is_empty() else PackedByteArray())
		var ms := float(Time.get_ticks_usec() - t1) / 1000.0
		out["ms"] = ms
		_mutex.lock()
		_fields[String(s["key"])] = out
		(stats["fields"] as Dictionary)[String(s["key"])] = ms
		_mutex.unlock()


## Multi-source Dijkstra on an 8-connected grid (a bucket queue; step cost
## 10 / 14 x the weight of the cell entered; a diagonal step only when both
## side cells are open: AStarGrid2D's DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES).
## The grid's border cells must be solid (no bounds checks inside).
## Returns {"d": costs (UNREACH where unreachable), "lab": nearest source's
## label per cell (only when labels are given)}.
static func flood(solid: PackedByteArray, wt: PackedByteArray, w: int, h: int, sources: PackedInt32Array, labels: PackedByteArray = PackedByteArray()) -> Dictionary:
	var n := w * h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(UNREACH)
	var with_lab := not labels.is_empty()
	var lab := PackedByteArray()
	if with_lab:
		lab.resize(n)
		lab.fill(255)
	var head := PackedInt32Array()
	head.resize(BUCKETS)
	head.fill(-1)
	var e_cell := PackedInt32Array()
	var e_next := PackedInt32Array()
	var pending := 0
	for i in sources.size():
		var s := sources[i]
		if dist[s] == 0:
			continue
		dist[s] = 0
		if with_lab:
			lab[s] = labels[i]
		e_cell.append(s)
		e_next.append(head[0])
		head[0] = e_cell.size() - 1
		pending += 1
	var cur := 0
	var mask := BUCKETS - 1
	var q := 0
	var nd := 0
	while pending > 0:
		var b := cur & mask
		var idx := head[b]
		if idx < 0:
			cur += 1
			continue
		head[b] = e_next[idx]
		pending -= 1
		var c := e_cell[idx]
		if dist[c] != cur:
			continue                       # superseded by a shorter route
		var lc := lab[c] if with_lab else 0
		var open_e := solid[c + 1] == 0
		var open_w := solid[c - 1] == 0
		var open_s := solid[c + w] == 0
		var open_n := solid[c - w] == 0
		# (unrolled: four sides, then four diagonals whose two sides are open)
		if open_e:
			q = c + 1
			nd = cur + 10 * wt[q]
			if nd < dist[q]:
				dist[q] = nd
				if with_lab:
					lab[q] = lc
				e_cell.append(q)
				e_next.append(head[nd & mask])
				head[nd & mask] = e_cell.size() - 1
				pending += 1
		if open_w:
			q = c - 1
			nd = cur + 10 * wt[q]
			if nd < dist[q]:
				dist[q] = nd
				if with_lab:
					lab[q] = lc
				e_cell.append(q)
				e_next.append(head[nd & mask])
				head[nd & mask] = e_cell.size() - 1
				pending += 1
		if open_s:
			q = c + w
			nd = cur + 10 * wt[q]
			if nd < dist[q]:
				dist[q] = nd
				if with_lab:
					lab[q] = lc
				e_cell.append(q)
				e_next.append(head[nd & mask])
				head[nd & mask] = e_cell.size() - 1
				pending += 1
		if open_n:
			q = c - w
			nd = cur + 10 * wt[q]
			if nd < dist[q]:
				dist[q] = nd
				if with_lab:
					lab[q] = lc
				e_cell.append(q)
				e_next.append(head[nd & mask])
				head[nd & mask] = e_cell.size() - 1
				pending += 1
		if open_e and open_s:
			q = c + 1 + w
			if solid[q] == 0:
				nd = cur + 14 * wt[q]
				if nd < dist[q]:
					dist[q] = nd
					if with_lab:
						lab[q] = lc
					e_cell.append(q)
					e_next.append(head[nd & mask])
					head[nd & mask] = e_cell.size() - 1
					pending += 1
		if open_e and open_n:
			q = c + 1 - w
			if solid[q] == 0:
				nd = cur + 14 * wt[q]
				if nd < dist[q]:
					dist[q] = nd
					if with_lab:
						lab[q] = lc
					e_cell.append(q)
					e_next.append(head[nd & mask])
					head[nd & mask] = e_cell.size() - 1
					pending += 1
		if open_w and open_s:
			q = c - 1 + w
			if solid[q] == 0:
				nd = cur + 14 * wt[q]
				if nd < dist[q]:
					dist[q] = nd
					if with_lab:
						lab[q] = lc
					e_cell.append(q)
					e_next.append(head[nd & mask])
					head[nd & mask] = e_cell.size() - 1
					pending += 1
		if open_w and open_n:
			q = c - 1 - w
			if solid[q] == 0:
				nd = cur + 14 * wt[q]
				if nd < dist[q]:
					dist[q] = nd
					if with_lab:
						lab[q] = lc
					e_cell.append(q)
					e_next.append(head[nd & mask])
					head[nd & mask] = e_cell.size() - 1
					pending += 1
	return {"d": dist, "lab": lab}
