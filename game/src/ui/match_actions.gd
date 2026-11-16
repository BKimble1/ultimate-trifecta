class_name MatchActions
extends Control
## (2.2 build 16) Round buttons: Emote under the minimap, top right (every
## round), and (2.2 build 17) Chat in the bottom-left corner (party rounds;
## MatchChat's drawer).  Emote opens a wheel of the five equipped emotes
## (EmoteSlots) in the middle of the screen; a tap plays one (as keys 1-5
## do) and the wheel closes; a tap outside it or a few seconds close it.
## Both buttons and the open wheel are reserved touch regions (never the
## stick or the camera).  Round buttons look like the HUD's other glass buttons with a
## coloured ring so they read at a glance.

const SIZE := 64.0
const ROW_S := 5.0

var hud: MatchHUD
var emote_btn: Button
var chat_btn: Button
var row: EmoteWheel
var _row_until := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	emote_btn = _round_button("smile", Color("ffc35a"), "Emote")
	emote_btn.pressed.connect(toggle_row)
	add_child(emote_btn)
	if hud.chat != null:
		chat_btn = _round_button("chat", UIKit.TEAL, "Chat")
		chat_btn.pressed.connect(hud.chat.open_drawer)
		add_child(chat_btn)
		hud.chat.adopt_button(chat_btn)
	row = EmoteWheel.new()
	row.actions = self
	row.visible = false
	add_child(row)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func _round_button(icon: String, ring: Color, label: String) -> Button:
	var b := UIKit.icon_button(icon, "", SIZE)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = label
	b.accessibility_name = label
	var f := UIKit.face_of(b)
	var n := UIKit.card_box(Color(UIKit.SLATE, 0.88), 999, 1.0, 16, 0.08)
	n.set_border_width_all(3)
	n.border_color = Color(ring, 0.9)
	f.styles["normal"] = n
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(UIKit.SLATE_HI, 0.95)
	f.styles["hover"] = h
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(ring.darkened(0.5), 0.95)
	f.styles["pressed"] = p
	f.queue_redraw()
	return b


func _layout() -> void:
	if not is_instance_valid(hud.minimap):
		return
	var mr := hud.minimap.get_global_rect()
	var vs := get_viewport().get_visible_rect().size
	var sm := UIKit.safe_margins(get_viewport())
	# Emote: under the minimap, its right edge a little past the map's
	emote_btn.size = Vector2(SIZE, SIZE)
	emote_btn.position = Vector2(mr.end.x - SIZE + 18.0, mr.end.y + 12.0)
	# Chat: the bottom-left corner, clear of the stick
	if chat_btn:
		chat_btn.size = Vector2(SIZE, SIZE)
		chat_btn.position = Vector2(sm.position.x + 18.0, vs.y - sm.size.y - SIZE - 18.0)
	row.size = Vector2(EmoteWheel.R * 2.0 + 40.0, EmoteWheel.R * 2.0 + 40.0)
	row.position = vs * 0.5 - row.size * 0.5


## Touch regions the stick and camera must leave alone.
func reserved() -> Array[Rect2]:
	var out: Array[Rect2] = [emote_btn.get_global_rect()]
	if chat_btn:
		out.append(chat_btn.get_global_rect())
	if row.visible:
		out.append(row.get_global_rect())
	return out


func toggle_row() -> void:
	if row.visible:
		_close_row()
		return
	row.open(EmoteSlots.ids())
	row.visible = true
	_row_until = Time.get_ticks_msec() / 1000.0 + ROW_S
	_layout.call_deferred()


func _close_row() -> void:
	row.visible = false


func pick(slot: int) -> void:
	Controls.request_emote(slot)
	_close_row()


## (2.2 build 17) The emote wheel: five slices round a centre Close, each
## with its emote's picture and name; the slice under the finger lights up.
class EmoteWheel:
	extends Control
	const R := 170.0
	const R_IN := 62.0
	var actions: MatchActions
	var ids: Array = []
	var hover := -1
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func open(p_ids: Array) -> void:
		ids = p_ids
		hover = -1
		_t = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()

	func _slice_at(p: Vector2) -> int:
		var c := size * 0.5
		var d := p - c
		if d.length() < R_IN or d.length() > R + 20.0 or ids.is_empty():
			return -1
		var a := fposmod(atan2(d.y, d.x) + PI * 0.5 + PI / float(ids.size()), TAU)
		return int(a / (TAU / float(ids.size()))) % ids.size()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			hover = _slice_at((ev as InputEventMouseMotion).position)
		var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
		var pos := (ev as InputEventMouseButton).position if ev is InputEventMouseButton else Vector2.ZERO
		if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			press = true
			pos = (ev as InputEventScreenTouch).position
		if press:
			var i := _slice_at(pos)
			accept_event()
			if i >= 0:
				actions.pick(i)
			else:
				actions._close_row()

	func _draw() -> void:
		var c := size * 0.5
		var n := maxi(1, ids.size())
		var grow := 1.0 if UIKit.reduced_motion() else minf(1.0, _t / 0.15)
		var r := R * (0.7 + 0.3 * grow)
		# backdrop disc and ring
		draw_circle(c, r + 14.0, Color(UIKit.NAVY, 0.55 * grow))
		draw_circle(c, r, Color(UIKit.SLATE, 0.92 * grow))
		for i in n:
			var a0 := -PI * 0.5 - PI / float(n) + TAU * float(i) / float(n)
			var a1 := a0 + TAU / float(n)
			if i == hover:
				var pts := PackedVector2Array()
				for k in 17:
					pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / 16.0)) * r)
				for k in 17:
					pts.append(c + Vector2.from_angle(lerpf(a1, a0, float(k) / 16.0)) * R_IN)
				draw_colored_polygon(pts, Color(UIKit.AMBER, 0.35))
			# dividers
			draw_line(c + Vector2.from_angle(a0) * R_IN, c + Vector2.from_angle(a0) * r, Color(UIKit.IVORY, 0.12), 2.0, true)
			if i < ids.size():
				var mid := c + Vector2.from_angle((a0 + a1) * 0.5) * ((r + R_IN) * 0.5)
				Icons.draw_shape(self, Icons.emote_icon(int(ids[i])), mid + Vector2(0, -10), 24.0, UIKit.IVORY)
				var nm := String(Cosmetics.entry("emote", String(TC.EMOTES[int(ids[i])])).get("name", ""))
				var f := UIKit.font_w(700)
				var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				draw_string(f, mid + Vector2(-w * 0.5, 30), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UIKit.IVORY, 0.85))
				draw_string(UIKit.font_num(800), mid + Vector2(-4, -40), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UIKit.AMBER, 0.9))
		draw_arc(c, r, 0, TAU, 64, Color(UIKit.AMBER, 0.7), 3.0, true)
		# the centre: close
		draw_circle(c, R_IN - 6.0, Color(UIKit.NAVY, 0.95))
		draw_arc(c, R_IN - 6.0, 0, TAU, 40, Color(UIKit.IVORY, 0.2), 2.0, true)
		Icons.draw_shape(self, "close", c, 16.0, UIKit.IVORY_MUTED)


func _process(_delta: float) -> void:
	if row.visible and Time.get_ticks_msec() / 1000.0 > _row_until:
		_close_row()
