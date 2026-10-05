class_name TouchLayout
extends RefCounted
## Pure layout of the match touch controls (V4).  No nodes: unit-tested in
## tests/test_touch_layout.gd.
##
## Units.  The canvas is 720 units high (stretch canvas_items/expand).  Sizes
## are authored in iOS points and converted with `upp` (canvas units per
## point): on a device upp = screen scale / (screen pixels per canvas unit),
## so a 44 pt target is 44 pt on an iPhone SE, a Pro Max and an iPad alike.
## Positions are anchored to the safe area (notch / Dynamic Island / home
## indicator insets), never to raw screen pixels.
##
## Two clusters:
##   move    the stick (dynamic: a broad zone on that side; fixed: at the anchor)
##   action  the right-thumb buttons around one primary button.  Slots are
##           fixed per context, and contextual buttons (Drive, a gadget) have
##           a reserved slot, so nothing shuffles when they appear.
##
## Saved layout (Save setting "touch_layout_v2"): normalized anchors inside
## the safe rect (0..1), per context for the action cluster, plus size,
## opacity and mirroring.  Loaded on another device or aspect, the clusters
## are clamped back inside the safe area and kept clear of each other and of
## the HUD's reserved corners; an impossible layout falls back to the default.

const VERSION := 2
const CONTEXTS := ["runner", "patrol", "cart", "watch"]

## Points.
const STICK_R := 58.0
const KNOB_R := 21.0
const MIN_TARGET_R := 22.0          # 44 pt
const EDGE_GAP := 10.0              # between a cluster and the safe edge
const CLUSTER_GAP := 16.0           # between the clusters
const HIT_PAD := 12.0               # extra touch radius when there is room

## Action slots per context, relative to the primary's centre (points).
## The right thumb pivots near the bottom-right corner: "inner" sits along
## the arc to the left and a little lower, "upper" above and a little right.
const SLOTS := {
	"runner": {"jump": [0.0, 0.0, 42.0], "gadget": [-112.0, 26.0, 32.0]},   # (Pass 9: no Sprint button)
	"patrol": {"tag": [0.0, 0.0, 44.0], "jump": [-114.0, 26.0, 33.0], "cart": [8.0, -106.0, 30.0]},
	# Exit is small and well apart from Gas/Brake: no exit while steering
	"cart": {"gas": [0.0, 0.0, 44.0], "brake": [-112.0, 24.0, 34.0], "cart": [14.0, -132.0, 26.0]},
	"watch": {"next": [0.0, 0.0, 38.0], "cheer": [-104.0, 22.0, 32.0]},
}
## Default primary centre, from the safe area's bottom-right corner (points).
const DEFAULT_ACTION_INSET := Vector2(104.0, 96.0)
## Default fixed-stick centre, from the safe area's bottom-left corner.
const DEFAULT_MOVE_INSET := Vector2(112.0, 104.0)
## The top of the screen belongs to the HUD (objectives, timer, map):
## no control cluster is placed above this fraction of the view height.
const TOP_BAND := 0.30
const SIZE_MIN := 0.85
const SIZE_MAX := 1.25
const OPACITY_MIN := 0.45
const OPACITY_MAX := 1.0


static func default_layout() -> Dictionary:
	return {"v": VERSION, "move": [], "action": {}, "size": 1.0, "opacity": 0.85, "mirror": false}


## Saved data (any version, possibly hand-edited or from an older build)
## -> a valid layout.  V3 settings (button_size, touch_layout) migrate.
static func sanitize(raw: Variant, legacy_size: float = 1.0, legacy_mirror: bool = false) -> Dictionary:
	var out := default_layout()
	out["size"] = clampf(legacy_size, SIZE_MIN, SIZE_MAX)
	out["mirror"] = legacy_mirror
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	out["size"] = clampf(float(d.get("size", out["size"])), SIZE_MIN, SIZE_MAX)
	out["opacity"] = clampf(float(d.get("opacity", 0.85)), OPACITY_MIN, OPACITY_MAX)
	out["mirror"] = bool(d.get("mirror", out["mirror"]))
	out["move"] = _norm(d.get("move", []))
	var act: Dictionary = {}
	var src: Variant = d.get("action", {})
	if src is Dictionary:
		for ctx in CONTEXTS:
			var a := _norm((src as Dictionary).get(ctx, []))
			if not a.is_empty():
				act[ctx] = a
	out["action"] = act
	return out


static func _norm(v: Variant) -> Array:
	if v is Array and (v as Array).size() == 2:
		var x := float(v[0])
		var y := float(v[1])
		if is_finite(x) and is_finite(y):
			return [clampf(x, 0.0, 1.0), clampf(y, 0.0, 1.0)]
	return []


## Canvas units per point for a viewport (see the header).
static func units_per_point(canvas_to_px: float, screen_scale: float) -> float:
	if canvas_to_px <= 0.0:
		return 720.0 / 390.0
	return maxf(screen_scale, 1.0) / canvas_to_px


## Where everything goes for one context.  `safe` is the safe rect in canvas
## units; `reserved` are HUD rects the clusters must stay clear of.
## Returns {"buttons": {name: {"c", "r", "hit"}}, "stick_c", "stick_r",
##  "knob_r", "zone": Rect2, "action_anchor": Vector2, "clamped": bool,
##  "fallback": bool}.
static func resolve(layout: Dictionary, ctx: String, view: Vector2, safe: Rect2, upp: float, reserved: Array = [], allow_fallback: bool = true) -> Dictionary:
	var s: float = clampf(float(layout.get("size", 1.0)), SIZE_MIN, SIZE_MAX)
	var mirror := bool(layout.get("mirror", false))
	var k := upp * s
	var slots: Dictionary = SLOTS.get(ctx, SLOTS["runner"])
	var stick_r := STICK_R * k
	# --- anchors (normalized in the safe rect, or the default)
	var move_n: Array = layout.get("move", [])
	var move_c := Vector2.ZERO
	if move_n.size() == 2:
		move_c = safe.position + Vector2(float(move_n[0]), float(move_n[1])) * safe.size
	else:
		move_c = Vector2(safe.position.x + DEFAULT_MOVE_INSET.x * k, safe.end.y - DEFAULT_MOVE_INSET.y * k)
		if mirror:
			move_c.x = safe.position.x + safe.end.x - move_c.x
	var act_n: Array = (layout.get("action", {}) as Dictionary).get(ctx, [])
	var act_c := Vector2.ZERO
	var custom_action := act_n.size() == 2
	if custom_action:
		act_c = safe.position + Vector2(float(act_n[0]), float(act_n[1])) * safe.size
	else:
		act_c = Vector2(safe.end.x - DEFAULT_ACTION_INSET.x * k, safe.end.y - DEFAULT_ACTION_INSET.y * k)
		if mirror:
			act_c.x = safe.position.x + safe.end.x - act_c.x
	# --- clamp both clusters inside the safe area, below the HUD band
	var clamped := false
	var top := maxf(safe.position.y, view.y * TOP_BAND)
	if top < safe.end.y:
		safe = Rect2(Vector2(safe.position.x, top), Vector2(safe.size.x, safe.end.y - top))
	var edge := EDGE_GAP * upp
	var mc2 := _clamp_center(move_c, Rect2(-Vector2.ONE * stick_r, Vector2.ONE * stick_r * 2.0), safe, edge)
	clamped = clamped or not mc2.is_equal_approx(move_c)
	move_c = mc2
	var ext := _extent(slots, k, mirror)
	var ac2 := _clamp_center(act_c, ext, safe, edge)
	clamped = clamped or not ac2.is_equal_approx(act_c)
	act_c = ac2
	# --- keep the action cluster clear of the stick and the HUD corners
	var stick_box := Rect2(move_c - Vector2.ONE * stick_r, Vector2.ONE * stick_r * 2.0).grow(CLUSTER_GAP * upp)
	var blockers: Array = [stick_box]
	for r in reserved:
		blockers.append(r)
	if _hits(Rect2(act_c + ext.position, ext.size), blockers):
		var fixed := _push_clear(act_c, ext, safe, edge, blockers, mirror)
		if fixed.x == INF and allow_fallback:
			# nothing fits around this layout: the recommended one (once)
			var dl := default_layout()
			dl["size"] = s
			dl["mirror"] = mirror
			var res := resolve(dl, ctx, view, safe, upp, [], false)
			res["fallback"] = true
			return res
		if fixed.x != INF:
			act_c = fixed
		clamped = true
	# --- buttons with hit padding that never overlaps a neighbour
	var buttons := {}
	for name in slots:
		var sl: Array = slots[name]
		var off := Vector2(float(sl[0]), float(sl[1])) * k
		if mirror:
			off.x = -off.x
		buttons[name] = {"c": act_c + off, "r": maxf(float(sl[2]), MIN_TARGET_R) * k, "hit": 0.0}
	for name in buttons:
		var b: Dictionary = buttons[name]
		var pad := HIT_PAD * upp
		for other in buttons:
			if other == name:
				continue
			var o: Dictionary = buttons[other]
			var gap := (b["c"] as Vector2).distance_to(o["c"]) - float(b["r"]) - float(o["r"])
			pad = minf(pad, maxf(0.0, gap * 0.5))
		b["hit"] = float(b["r"]) + pad
	# --- the dynamic stick's zone: that side of the screen, below the top
	# HUD band, not under the action cluster
	var zone_w := view.x * 0.45
	var zone := Rect2(0.0, view.y * 0.18, zone_w, view.y * 0.82)
	if mirror:
		zone.position.x = view.x - zone_w
	return {"buttons": buttons, "stick_c": move_c, "stick_r": stick_r, "knob_r": KNOB_R * k, "zone": zone,
		"action_anchor": act_c, "move_anchor": move_c, "clamped": clamped, "fallback": false, "upp": upp}


## Bounding box of a context's slots around the primary (canvas units,
## including hit padding).
static func _extent(slots: Dictionary, k: float, mirror: bool) -> Rect2:
	var box := Rect2()
	var first := true
	for name in slots:
		var sl: Array = slots[name]
		var off := Vector2(float(sl[0]), float(sl[1])) * k
		if mirror:
			off.x = -off.x
		var r := (maxf(float(sl[2]), MIN_TARGET_R) + HIT_PAD) * k
		var b := Rect2(off - Vector2.ONE * r, Vector2.ONE * r * 2.0)
		box = b if first else box.merge(b)
		first = false
	return box


static func _clamp_center(c: Vector2, ext: Rect2, safe: Rect2, edge: float) -> Vector2:
	var lo := safe.position + Vector2.ONE * edge - ext.position
	var hi := safe.end - Vector2.ONE * edge - ext.end
	if lo.x > hi.x:
		lo.x = (lo.x + hi.x) * 0.5
		hi.x = lo.x
	if lo.y > hi.y:
		lo.y = (lo.y + hi.y) * 0.5
		hi.y = lo.y
	return Vector2(clampf(c.x, lo.x, hi.x), clampf(c.y, lo.y, hi.y))


static func _hits(box: Rect2, blockers: Array) -> bool:
	for r in blockers:
		if box.intersects(r as Rect2):
			return true
	return false


## Slide the action cluster toward its own edge, then down, until it is
## clear; INF when no position inside the safe area works.
static func _push_clear(c: Vector2, ext: Rect2, safe: Rect2, edge: float, blockers: Array, mirror: bool) -> Vector2:
	var step := 8.0
	var dir := -1.0 if mirror else 1.0
	for dy_i in 40:
		for dx_i in 80:
			var p := _clamp_center(c + Vector2(dir * dx_i * step, dy_i * step), ext, safe, edge)
			if not _hits(Rect2(p + ext.position, ext.size), blockers):
				return p
	return Vector2(INF, INF)


## Normalized anchor for a dragged cluster centre (editor).
static func normalize(p: Vector2, safe: Rect2) -> Array:
	var n := (p - safe.position) / safe.size
	return [clampf(n.x, 0.0, 1.0), clampf(n.y, 0.0, 1.0)]


## Context of the action cluster for a player state.
static func context_for(role: int, in_cart: bool, watching: bool) -> String:
	if watching:
		return "watch"
	if in_cart:
		return "cart"
	return "patrol" if role == TC.Role.PATROL else "runner"
