class_name MatchActions
extends Control
## (2.2 build 16) Round buttons under the minimap, top right: Emote (every
## round) and, in party rounds, Chat (MatchChat's drawer).  Emote opens a
## short row of the five equipped emotes (EmoteSlots) to its left; a tap
## plays one (as keys 1-5 do) and the row closes; it closes by itself after
## a few seconds.  Both are reserved touch regions (never the stick or the
## camera).  Round buttons look like the HUD's other glass buttons with a
## coloured ring so they read at a glance.

const SIZE := 64.0
const ROW_S := 4.0

var hud: MatchHUD
var emote_btn: Button
var chat_btn: Button
var row: HBoxContainer
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
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
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
	var y := mr.end.y + 10.0
	var x := mr.end.x - SIZE
	emote_btn.size = Vector2(SIZE, SIZE)
	emote_btn.position = Vector2(x, y)
	if chat_btn:
		chat_btn.size = Vector2(SIZE, SIZE)
		chat_btn.position = Vector2(x - SIZE - 10.0, y)
	row.position = Vector2((chat_btn.position.x if chat_btn else x) - 10.0 - row.get_combined_minimum_size().x, y)


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
	for c in row.get_children():
		c.queue_free()
	var ids := EmoteSlots.ids()
	for i in ids.size():
		var slot := i
		var b := UIKit.icon_button(Icons.emote_icon(int(ids[i])), "", SIZE)
		b.focus_mode = Control.FOCUS_NONE
		b.accessibility_name = String(Cosmetics.entry("emote", String(TC.EMOTES[int(ids[i])])).get("name", "Emote"))
		b.pressed.connect(func() -> void:
			Controls.request_emote(slot)
			_close_row())
		row.add_child(b)
	row.visible = true
	_row_until = Time.get_ticks_msec() / 1000.0 + ROW_S
	_layout.call_deferred()


func _close_row() -> void:
	row.visible = false


func _process(_delta: float) -> void:
	if row.visible and Time.get_ticks_msec() / 1000.0 > _row_until:
		_close_row()
