extends RefCounted
## (2.2 build 21) Snow on the ground and footprints in it (SnowCover,
## SnowPrints): a few patches on open lawn on every map, the same on every
## device, clear of the dorm doors; never indoors; prints only where the
## snow is, a stride apart, left and right in turn, none in the air or
## across a teleport, and they stay.
var t


func _maps() -> Array:
	var out: Array = []
	for mid in CampusMaps.ids():
		if CampusMaps.playable(mid):
			out.append(CampusMaps.sanitize(mid))
	if out.is_empty():
		out = [CampusMaps.sanitize("")]
	return out


func test_patches_lie_on_open_ground_on_every_map() -> void:
	for mid in _maps():
		var L := CampusMaps.layout(mid)
		var d := SnowCover._build(L, SnowCover._inputs(mid))
		var ps: Array = d["patches"]
		t.check(ps.size() >= 8 and ps.size() <= SnowCover.PATCHES, "%s: a few patches (%d)" % [mid, ps.size()])
		for q in ps:
			var c := Vector2(q.x, q.y)
			t.check(L._open_ground(c, float(q.z) * 0.7), "%s: patch at %s on open ground" % [mid, str(c)])
			t.check(SnowCover.amount_at(d, c) > 0.9, "%s: deep snow in the middle of %s" % [mid, str(c)])
			for dp in SnowCover._inputs(mid)["doors"]:
				t.check((dp as Vector2).distance_to(c) >= float(q.z) + SnowCover.DOOR_CLEAR - 0.01, "%s: clear of the door at %s" % [mid, str(dp)])
		# the same on every device
		var d2 := SnowCover._build(L, SnowCover._inputs(mid))
		t.eq(d2["patches"], d["patches"], "%s: the same patches every time" % mid)
		t.check((d2["img"] as Image).get_data() == (d["img"] as Image).get_data(), "%s: the same snow field" % mid)
		# a modest texture (one texel a metre)
		var sz: Vector2i = (d["img"] as Image).get_size()
		t.check(sz.x * sz.y <= 1100 * 1100, "%s: snow field %s texels" % [mid, str(sz)])


func test_dorm_interiors_are_masked_for_caps() -> void:
	for mid in _maps():
		var L := CampusMaps.layout(mid)
		var d := SnowCover._build(L, SnowCover._inputs(mid))
		var img: Image = d["img"]
		for id in CampusDorms.ids(mid):
			var g := CampusDorms.geometry(id)
			var room: PackedVector2Array = g["room"]
			var c := Vector2.ZERO
			for v in room:
				c += v
			c /= float(room.size())
			var uv := (c - (d["origin"] as Vector2)) / SnowCover.TEXEL
			var gch := img.get_pixel(int(uv.x), int(uv.y)).g
			var top := float(g.get("floor", 0.0)) + float(g["ceil"])
			t.check(gch * SnowCover.CEIL_RANGE >= top, "%s %s: no snow under the ceiling indoors (%.1f >= %.1f)" % [mid, id, gch * SnowCover.CEIL_RANGE, top])
			t.check(SnowCover.amount_at(d, c) < 0.01, "%s %s: no drift indoors" % [mid, id])


func test_footprints_follow_the_runner_through_the_snow() -> void:
	var mid: String = _maps()[0]
	var L := CampusMaps.layout(mid)
	var d := SnowCover._build(L, SnowCover._inputs(mid))
	var q: Vector4 = d["patches"][0]
	var pr := SnowPrints.new()
	pr.setup(d)
	t.add_child(pr)
	# run straight through the middle of the patch, 5 cm a frame
	var a := Vector2(q.x - q.z - 3.0, q.y)
	var b := Vector2(q.x + q.z + 3.0, q.y)
	var n := int(a.distance_to(b) / 0.05)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		pr.track(0, Vector3(p.x, 0.0, p.y), true)
	var deep := 0
	for i in range(-int(q.z), int(q.z) + 1):
		if SnowCover.amount_at(d, Vector2(q.x + i, q.y)) > 0.55:
			deep += 1
	t.check(pr.placed >= int(deep / SnowPrints.STRIDE * 0.6), "a print every stride in the snow (%d over ~%d m)" % [pr.placed, deep])
	t.check(pr.placed <= int((q.z * 2.0 + 2.0) / SnowPrints.STRIDE) + 2, "and none outside it (%d)" % pr.placed)
	# left and right in turn
	var mm := pr.multimesh
	if pr.placed >= 2:
		var o0 := pr.spots[0].z - q.y
		var o1 := pr.spots[1].z - q.y
		t.check(signf(o0) != signf(o1) and absf(absf(o0) - SnowPrints.SIDE) < 0.01, "left, right (%.2f, %.2f)" % [o0, o1])
	# in the air: nothing; a teleport across: nothing
	var before := pr.placed
	for i in 60:
		var p2 := a.lerp(b, 0.5) + Vector2(0, 0.05 * i)
		pr.track(1, Vector3(p2.x, 1.0, p2.y), false)
	t.eq(pr.placed, before, "no prints while in the air")
	pr.track(2, Vector3(a.x, 0, a.y), true)
	pr.track(2, Vector3(q.x, 0, q.y), true)
	t.eq(pr.placed, before, "no print across a jump in position")
	t.eq(mm.visible_instance_count, pr.placed, "every print stays")
	pr.queue_free()
