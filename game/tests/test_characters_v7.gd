extends RefCounted
## V7 character pass: the swim cap's goggles fit the shared head (lenses and
## frames sit on the cap, never in the head or floating off it; the pair is
## mirror-symmetric; the strap lies on the cap all the way round and meets
## both cups; the lenses face out; no brow pokes through the cap under any
## face or brow shape), and the asset is versioned for the portrait cache.
## Measured on the real runner.glb geometry (rest pose: the cap and goggles
## are rigid on the head bone, so the rest pose is how they sit in every
## animation; tools/character/clip_check.py checks the arms against them
## through every clip).
var t

const GLB := "res://assets/characters/runner.glb"
## material classes as the shader reads them (1 - UV2.y), and the goggles'
## roughness values (tools/character/parts.py GOG_FRAME / GOG_STRAP)
const LENS_CLASS := 0.6875
const FRAME_ROUGH := 0.45
const STRAP_ROUGH := 0.62


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))


## Mesh arrays of one part of the asset (surface 0: every part is one surface).
func _arrays(part: String) -> Array:
	var scene: Node = (load(GLB) as PackedScene).instantiate()
	var out: Array = []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) == part:
			out = (n as MeshInstance3D).mesh.surface_get_arrays(0)
			t.check((n as MeshInstance3D).mesh.get_surface_count() == 1, "%s is one surface (one draw call)" % part)
	scene.free()
	return out


## The head surface every head-fitted part follows (rig.py, from the
## manifest), in Godot axes.
class Head:
	var c: Vector3
	var r: Vector3
	var pw: float

	func _init(h: Dictionary) -> void:
		var a: Array = h["center"]
		c = Vector3(a[0], a[1], a[2])
		var rr: Array = h["radii"]
		r = Vector3(rr[0], rr[1], rr[2])   # (x, forward, up) as in rig.HEAD_R
		pw = float(h["power"])

	static func scale_at(zn: float) -> Vector2:
		var cheek := exp(-pow((zn + 0.30) / 0.42, 2.0))
		var top := clampf((zn - 0.25) / 0.75, 0.0, 1.0)
		top = top * top * (3.0 - 2.0 * top)
		return Vector2(1.0 + 0.075 * cheek - 0.045 * top, 1.0 + 0.035 * cheek - 0.02 * top)

	func f(p: Vector3, grow: float) -> float:
		var d := p - c
		var zn := d.y / (r.z + grow)
		var s := scale_at(clampf(zn, -1.0, 1.0))
		return pow(absf(d.x / ((r.x + grow) * s.x)), pw) + pow(absf(-d.z / ((r.y + grow) * s.y)), pw) + pow(absf(zn), pw)

	## How far p is off the skin (the grow whose shell passes through p).
	func offset(p: Vector3) -> float:
		var lo := -0.2
		var hi := 0.3
		for i in 36:
			var m := (lo + hi) * 0.5
			if f(p, m) > 1.0:
				lo = m
			else:
				hi = m
		return (lo + hi) * 0.5


func _classify(arr: Array) -> Dictionary:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var out := {"cap": PackedInt32Array(), "lens": PackedInt32Array(), "frame": PackedInt32Array(), "strap": PackedInt32Array()}
	for i in vs.size():
		var cls := 1.0 - uv2[i].y
		var k := ""
		if absf(cls - LENS_CLASS) < 0.01:
			k = "lens"
		elif cs[i].a > 0.9:
			k = "cap"
		elif absf(uv2[i].x - FRAME_ROUGH) < 0.01:
			k = "frame"
		elif absf(uv2[i].x - STRAP_ROUGH) < 0.01:
			k = "strap"
		if k != "":
			out[k].append(i)
	return out


func _range_of(head: Head, vs: PackedVector3Array, idx: PackedInt32Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in idx:
		var g := head.offset(vs[i])
		lo = minf(lo, g)
		hi = maxf(hi, g)
	return Vector2(lo, hi)


func test_goggles_fit_the_head() -> void:
	var m := _manifest()
	t.check(m.has("head"), "the manifest describes the head surface")
	var head := Head.new(m["head"])
	var cap_grow := float(m["head"]["cap_grow"])
	var arr := _arrays("hat_swimcap")
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var k := _classify(arr)
	for part in ["cap", "lens", "frame", "strap"]:
		t.check((k[part] as PackedInt32Array).size() > 50, "the swim cap has %s geometry (%d vertices)" % [part, (k[part] as PackedInt32Array).size()])
	# the asset and this test agree on the head: the cap shell lies at its grow
	var cap_off: Array = []
	for i in k["cap"]:
		cap_off.append(head.offset(vs[i]))
	cap_off.sort()
	t.near(float(cap_off[cap_off.size() / 2]), cap_grow, 0.0015, "the cap shell follows the shared head surface (median offset)")
	# lenses: above the cap, not floating off it, facing out
	var lens := _range_of(head, vs, k["lens"])
	t.check(lens.x > cap_grow + 0.004 and lens.y < 0.035,
		"lenses sit 4 mm-3.5 cm off the skin, on their frames (got %.1f-%.1f mm)" % [lens.x * 1000.0, lens.y * 1000.0])
	# frames: their base touches the cap (no floating frame), never inside the head
	for sx in [-1.0, 1.0]:
		var side := PackedInt32Array()
		for i in k["frame"]:
			if signf(vs[i].x) == sx:
				side.append(i)
		var fr := _range_of(head, vs, side)
		t.check(fr.x > cap_grow - 0.004, "%s frame never sinks into the head (min %.1f mm off the skin)" % ["left" if sx < 0 else "right", fr.x * 1000.0])
		t.check(fr.x < cap_grow + 0.001, "%s frame's base rests on the cap (min %.1f mm, cap %.1f)" % ["left" if sx < 0 else "right", fr.x * 1000.0, cap_grow * 1000.0])
		t.check(fr.y < 0.04, "%s frame stands < 4 cm off the skin (%.1f mm)" % ["left" if sx < 0 else "right", fr.y * 1000.0])
	# paired lenses: two cups mirrored across the face's centre, on the forehead
	var cen := [Vector3.ZERO, Vector3.ZERO]
	var cnt := [0, 0]
	var xs := [Vector2(INF, -INF), Vector2(INF, -INF)]
	for i in k["lens"]:
		var s := 0 if vs[i].x < 0.0 else 1
		cen[s] += vs[i]
		cnt[s] += 1
		xs[s] = Vector2(minf(xs[s].x, vs[i].x), maxf(xs[s].y, vs[i].x))
	t.check(cnt[0] > 0 and cnt[1] > 0, "two lenses")
	if cnt[0] > 0 and cnt[1] > 0:
		var a: Vector3 = cen[0] / cnt[0]
		var b: Vector3 = cen[1] / cnt[1]
		t.check(absf(a.x + b.x) < 0.001 and absf(a.y - b.y) < 0.001 and absf(a.z - b.z) < 0.001, "the lenses mirror each other (%s / %s)" % [a, b])
		t.check(a.y > head.c.y + 0.1 and a.z < head.c.z - 0.2, "the lenses are on the forehead (centre %s)" % a)
		for s in 2:
			var w: float = xs[s].y - xs[s].x
			t.check(w > 0.05 and w < 0.11, "lens %d is 5-11 cm wide (%.1f cm)" % [s, w * 100.0])
		t.check(xs[1].x > 0.0 and xs[0].y < 0.0, "the lenses do not overlap the centre line")
	# the whole goggle (not the cap) is mirror-symmetric to 1 mm
	var gog := PackedVector3Array()
	for part in ["lens", "frame", "strap"]:
		for i in k[part]:
			gog.append(vs[i])
	var worst := 0.0
	for p in gog:
		var q := Vector3(-p.x, p.y, p.z)
		var best := INF
		for o in gog:
			best = minf(best, o.distance_squared_to(q))
			if best < 1e-8:
				break
		worst = maxf(worst, sqrt(best))
	t.check(worst < 0.001, "the goggles are mirror-symmetric (worst %.2f mm)" % (worst * 1000.0))


func test_goggle_lenses_face_out() -> void:
	var head := Head.new(_manifest()["head"])
	var arr := _arrays("hat_swimcap")
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var lens := {}
	for i in _classify(arr)["lens"]:
		lens[i] = true
	var good := 0
	var bad := 0
	for f in ix.size() / 3:
		var a := ix[f * 3]
		if not lens.has(a):
			continue
		var p0 := vs[a]
		var p1 := vs[ix[f * 3 + 1]]
		var p2 := vs[ix[f * 3 + 2]]
		# Godot's front faces wind clockwise: the outward normal is (p2-p0) x (p1-p0)
		var n := (p2 - p0).cross(p1 - p0)
		if n.length() < 1e-10:
			continue
		var out := (p0 - head.c).normalized()
		if n.normalized().dot(out) > 0.3:
			good += 1
		else:
			bad += 1
	t.check(good > 100, "lens faces counted (%d)" % good)
	t.eq(bad, 0, "every lens face looks away from the head")


## The strap follows the head: it lies on the cap all the way round (the V6
## strap was a tilted planar ring 1.5-6 cm off the cap), and with the frames
## and the bridge it closes the loop round the head, meeting both cups.
func test_goggle_strap_is_continuous_and_on_the_cap() -> void:
	var m := _manifest()
	var head := Head.new(m["head"])
	var cap_grow := float(m["head"]["cap_grow"])
	var arr := _arrays("hat_swimcap")
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var k := _classify(arr)
	var st := _range_of(head, vs, k["strap"])
	t.check(st.x > cap_grow - 0.003 and st.y < cap_grow + 0.012,
		"the strap and bridge lie on the cap (%.1f-%.1f mm off the skin, cap %.1f)" % [st.x * 1000.0, st.y * 1000.0, cap_grow * 1000.0])
	# angular coverage round the head's vertical axis (1 degree bins, filled
	# across each face: the strap's rings are a few degrees apart)
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var cls := {}
	for part in ["strap", "frame"]:
		for i in k[part]:
			cls[i] = true
	var bins := {}
	for f in ix.size() / 3:
		if not cls.has(ix[f * 3]):
			continue
		var angs: Array = []
		for c in 3:
			var d := vs[ix[f * 3 + c]] - head.c
			angs.append(rad_to_deg(atan2(d.x, -d.z)))
		if float(angs.max()) - float(angs.min()) > 180.0:
			angs = angs.map(func(a: float) -> float: return a + 360.0 if a < 0.0 else a)
		for a in range(int(floor(float(angs.min()))), int(ceil(float(angs.max()))) + 1):
			bins[posmod(a + 180, 360)] = true
	var gap := 0
	var run := 0
	for a in 720:
		if bins.has(a % 360):
			run = 0
		else:
			run += 1
			gap = maxi(gap, run)
	t.check(gap <= 2, "strap, clips, frames and bridge close the loop round the head (largest gap %d deg)" % gap)
	# both clips: strap vertices right next to each frame's outer side
	for sx in [-1.0, 1.0]:
		var near_d := INF
		for i in k["strap"]:
			if signf(vs[i].x) != sx or vs[i].z > head.c.z:
				continue
			for j in k["frame"]:
				if signf(vs[j].x) == sx:
					near_d = minf(near_d, vs[i].distance_to(vs[j]))
		t.check(near_d < 0.004, "the strap meets the %s cup (%.1f mm)" % ["left" if sx < 0 else "right", near_d * 1000.0])
	# the strap is over the cap everywhere, never across skin: above the
	# cap's lowest point at that angle (10 degree bins; the cap's rings are
	# 7.5 degrees apart)
	var edge := {}
	for i in k["cap"]:
		var d := vs[i] - head.c
		var b := posmod(int(floor(rad_to_deg(atan2(d.x, -d.z)) / 10.0)), 36)
		edge[b] = minf(float(edge.get(b, INF)), vs[i].y)
	var worst := INF
	for i in k["strap"]:
		var d := vs[i] - head.c
		var b := posmod(int(floor(rad_to_deg(atan2(d.x, -d.z)) / 10.0)), 36)
		worst = minf(worst, vs[i].y - float(edge.get(b, INF)))
	t.check(worst > 0.01, "every part of the strap is above the cap's edge (closest %.1f mm)" % (worst * 1000.0))


## No brow pokes through the cap or touches the goggles under any face or
## brow shape (V6: the cap edge ran through the brows).
func test_brows_clear_the_swim_cap_in_every_face() -> void:
	var arr := _arrays("hat_swimcap")
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var k := _classify(arr)
	var head := Head.new(_manifest()["head"])
	# the cap's lowest edge over the brows (front, |x| < 0.16)
	var edge := INF
	for i in k["cap"]:
		var p := vs[i]
		if p.z < head.c.z - 0.15 and absf(p.x) < 0.16:
			edge = minf(edge, p.y)
	var scene: Node = (load(GLB) as PackedScene).instantiate()
	var base: MeshInstance3D = null
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) == "base":
			base = n
	var mesh := base.mesh as ArrayMesh
	var barr := mesh.surface_get_arrays(0)
	var bv: PackedVector3Array = barr[Mesh.ARRAY_VERTEX]
	var bc: PackedColorArray = barr[Mesh.ARRAY_COLOR]
	# brows: the hair-tinted vertices of the face (tint selector 0.2)
	var brow := PackedInt32Array()
	for i in bv.size():
		if absf(bc[i].a - 0.2) < 0.02 and bv[i].y > 1.2 and bv[i].z < head.c.z - 0.15:
			brow.append(i)
	t.check(brow.size() > 50, "brow vertices found (%d)" % brow.size())
	var shapes: Array = [""]
	for s in ["brow_up", "brow_angry", "face_bright", "face_sleepy", "brow_flat"]:
		shapes.append(s)
	var bsa: Array = mesh.surface_get_blend_shape_arrays(0)
	for s in shapes:
		var top := -INF
		var idx := -1
		for b in mesh.get_blend_shape_count():
			if String(mesh.get_blend_shape_name(b)) == s:
				idx = b
		for i in brow:
			var p := bv[i]
			if idx >= 0:
				# shape targets may be stored as offsets or as positions
				var sv: PackedVector3Array = bsa[idx][Mesh.ARRAY_VERTEX]
				p = p + sv[i] if sv[i].length() < 0.3 else sv[i]
			top = maxf(top, p.y)
		t.check(top < edge - 0.002, "brows (%s) stay under the cap's edge: top %.3f m, edge %.3f m" % [s if s != "" else "neutral", top, edge])
	scene.free()
