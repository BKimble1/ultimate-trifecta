class_name CreatorScreen
extends Screen
## The wardrobe (V5; "Create Your Runner" on first launch).
##
##   left    the player's runner in the dorm (App.stage, "wardrobe"
##           framing, head to shoes): drag to turn, Idle / Run preview
##   right   a category strip (Outfit, Colors, Face, Hair, Hat, Shoes,
##           Emotes) over portrait item cards: the item's picture on your
##           runner, its name below in full (two lines when needed, never
##           trimmed), and a state row: Equipped, Owned, or its price (with
##           a lock when you can't afford it yet).  The draft's choice has a
##           restrained teal edge and a check.  Colours are round swatches.
##   bottom  what Apply will do, Undo, and the primary action, which always
##           says why it is unavailable ("Wearing this", "Need 40 more coins")
##
## The draft is only a preview until Apply (nothing is charged for trying).
## Leaving with unapplied changes asks first.  Picking an item updates the
## live runner at once, with a short hop.  Cards are updated in place; the
## category's scroll position is kept per category.
##
## Pictures: rendered off-screen one at a time through the shared portrait
## atlas (no live 3D per card, no GPU readback), cached by look, requested
## only for the visible category; a category change cancels the previous
## category's queued requests, and a finished picture lands on every card
## still showing exactly that look.

const TABS := [
	["outfit", "Outfit", ["outfit", "pattern"]],
	["colours", "Colors", ["color", "trim"]],
	["face", "Face", ["skin", "face", "brows", "marks"]],
	["hair", "Hair", ["hair", "hair_color"]],
	["hat", "Hat", ["hat"]],
	["shoes", "Shoes", ["shoes"]],
	["move", "Emotes", ["emote"]],
]
const FIELD_TITLES := {
	"outfit": "Outfit", "pattern": "Pattern", "color": "Main color", "trim": "Trim", "skin": "Skin tone",
	"face": "Eyes", "brows": "Brows", "marks": "Cheeks", "hair": "Hairstyle", "hair_color": "Hair color",
	"hat": "Hat", "shoes": "Shoes", "emote": "Your move · plays when you ready up",
}
const SWATCH_FIELDS := ["color", "trim", "skin", "hair_color"]
## Picture framing for an item's card ("" = an icon card).
const THUMB_FRAMING := {"outfit": "body", "pattern": "body", "hair": "head", "hat": "head", "shoes": "feet",
	"face": "head", "brows": "head", "marks": "head"}
const CARD_W := 158.0
const CARD_GAP := 12.0

## when true (first launch / profile setup), Apply continues with `on_done`
var first_run := false
var on_done: Callable
## where Back goes (lobby sets this; default: home)
var back_action_override: Callable

var draft: Dictionary = {}
var saved: Dictionary = {}
var tab := "outfit"
var tab_btns: Dictionary = {}
var body: VBoxContainer
var scroll: ScrollContainer
var coins_lbl: Label
var price_lbl: Label
var apply_btn: Button
var undo_btn: Button
var preview_run := false
var run_btn: Button
var panel: PanelContainer
var cards: Array[ItemCard] = []
var swatches: Array[Swatch] = []
var _notes: Dictionary = {}       # field -> Label (hair hidden / pattern note)
var _picked: Dictionary = {}      # swatch field -> Label naming the chosen colour
var _scroll_of: Dictionary = {}   # tab -> scroll position
var _yaw := 0.0
var _drag_from := -1.0
var _spin := 0.0
var _yaw_set := false
var _stage_area: Control


func build() -> void:
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	draft = saved.duplicate()
	if App.stage:
		App.stage.set_mode("wardrobe")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.45, 0.0)
	var view := get_viewport().get_visible_rect().size
	var v := content
	var top := UIKit.hbox(14)
	v.add_child(top)
	if not first_run:
		var back := UIKit.icon_button("back")
		back.tooltip_text = "Back"
		back.accessibility_name = "Back"
		back.pressed.connect(_go_back)
		top.add_child(back)
	var title := UIKit.styled("Create Your Runner" if first_run else "Wardrobe", "title")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	top.add_child(UIKit.spacer_h())
	var coin_chip := UIKit.scrim(999, 18, 0.7)
	coin_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins_lbl = UIKit.styled("", "num", UIKit.AMBER)
	coin_chip.add_child(coins_lbl)
	top.add_child(coin_chip)

	var mid := UIKit.hbox(16)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(mid)
	# left: the stage area (drag to turn) + preview controls
	var stage_area := StageDrag.new()
	_stage_area = stage_area
	stage_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_area.creator = self
	mid.add_child(stage_area)
	# preview controls stacked in the corner, clear of the runner
	var pv := UIKit.vbox(8)
	stage_area.add_child(pv)
	var turn_hint := UIKit.chip("Drag to turn", Color(UIKit.NAVY, 0.6), UIKit.IVORY_MUTED, 18)
	turn_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pv.add_child(turn_hint)
	var turn_lbl: Label = turn_hint.find_children("*", "Label", true, false)[0]
	var on_dev := func(k: String) -> void:
		if is_instance_valid(turn_lbl):
			turn_lbl.text = "Right stick to turn" if k == "gamepad" else "Drag to turn"
	Controls.device_changed.connect(on_dev)
	on_dev.call(Controls.device)
	run_btn = UIKit.quiet("Run", Vector2(130, 0))
	run_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	run_btn.tooltip_text = "Preview running"
	run_btn.pressed.connect(func() -> void:
		preview_run = not preview_run
		run_btn.text = "Idle" if preview_run else "Run")
	pv.add_child(run_btn)
	pv.move_child(run_btn, 0)
	stage_area.resized.connect(func() -> void: pv.position = Vector2(0, stage_area.size.y - pv.get_combined_minimum_size().y))

	# right: categories + cards.  The panel takes ~58% of a wide phone and a
	# little more of a 4:3 iPad, so the runner keeps its full height.
	panel = UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 16)
	var aspect := view.x / maxf(1.0, view.y)
	panel.custom_minimum_size = Vector2(clampf(view.x * (0.56 if aspect > 1.7 else 0.6), 560.0, 900.0), 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(panel)
	var pvb := UIKit.vbox(12)
	panel.add_child(pvb)
	pvb.add_child(_category_strip())
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	pvb.add_child(scroll)
	body = UIKit.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# bottom: what Apply does · Undo · Apply
	var bottom := UIKit.hbox(14)
	v.add_child(bottom)
	bottom.add_child(UIKit.spacer_h())
	price_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	price_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(price_lbl)
	undo_btn = UIKit.quiet("Undo" if not first_run else "Surprise me", Vector2(190, 84))
	undo_btn.pressed.connect(_on_cancel)
	bottom.add_child(undo_btn)
	apply_btn = UIKit.primary("Apply" if not first_run else "That's me!", Vector2(320, 90), 28)
	apply_btn.pressed.connect(_on_apply)
	bottom.add_child(apply_btn)
	focus_first(tab_btns[tab])
	back_action = _back if not first_run else func() -> void: pass
	_build_tab()
	Motion.settle_in(panel)
	_stage_area.resized.connect(_frame_stage)
	get_viewport().size_changed.connect(_frame_stage)
	_frame_stage.call_deferred()
	var lc := App.stage.local_character() if App.stage else null
	_yaw = lc.rotation.y if lc else 0.0


## Tell the stage where the free space left of the item panel is.
func _frame_stage() -> void:
	if App.stage and is_instance_valid(_stage_area) and _stage_area.is_inside_tree():
		var w := get_viewport().get_visible_rect().size.x
		var r := _stage_area.get_global_rect()
		# a little right of centre: the preview controls sit in the left corner
		App.stage.set_wardrobe_region((r.get_center().x + r.size.x * 0.12) / maxf(1.0, w), r.size.x / maxf(1.0, w))


func _category_strip() -> Control:
	var tab_scroll := ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tab_scroll.follow_focus = true
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(tabs)
	tabs.add_child(Glyphs.Hint.new("menu_prev", "", 30.0))
	for t in TABS:
		var b := UIKit.quiet(String(t[1]), Vector2(0, 0), UIKit.T_LABEL)
		b.custom_minimum_size.y = maxf(56.0, UIKit.touch_min())
		var f := UIKit.face_of(b)
		var sel := UIKit.box(Color(UIKit.TEAL, 0.16), 999, 0, Color.WHITE)
		sel.set_border_width_all(2)
		sel.border_color = UIKit.TEAL
		var n := UIKit.box(Color(0, 0, 0, 0), 999, 0, Color.WHITE)
		f.styles = {"normal": n, "hover": UIKit.box(Color(UIKit.IVORY, 0.06), 999), "pressed": UIKit.box(Color(UIKit.IVORY, 0.1), 999),
			"disabled": n, "selected": sel}
		f.fg = {"normal": UIKit.IVORY_MUTED, "hover": UIKit.IVORY, "selected": UIKit.IVORY}
		var key: String = t[0]
		b.pressed.connect(func() -> void: _select_tab(key))
		tabs.add_child(b)
		tab_btns[key] = b
	tabs.add_child(Glyphs.Hint.new("menu_next", "", 30.0))
	tab_scroll.custom_minimum_size.y = maxf(56.0, UIKit.touch_min()) + 4.0
	return tab_scroll


func _process(delta: float) -> void:
	var v := App.stage.local_character() if App.stage else null
	if v == null:
		return
	# controller: right stick turns the runner (same as dragging)
	if Controls.active_joy >= 0 and not has_modal():
		var rx := InputRouter.radial(Vector2(Input.get_joy_axis(Controls.active_joy, JOY_AXIS_RIGHT_X), 0.0), 0.2, 0.95).x
		if rx != 0.0:
			drag_turn(rx * 220.0 * delta)
	if _drag_from < 0.0 and not UIKit.reduced_motion() and not preview_run:
		# a slow sway so the sides of the outfit show, until the player drags
		_spin += delta * 0.45
	var base := atan2(-(App.stage.cam.global_position.x - v.global_position.x), -(App.stage.cam.global_position.z - v.global_position.z))
	if _yaw_set:
		v.set_facing(_yaw)
	else:
		v.set_facing(base - 0.25 + sin(_spin) * 0.5)
	var rs := v.rs.duplicate()
	rs["vel"] = (Basis(Vector3.UP, v.rotation.y) * Vector3(0, 0, -5.0)) if preview_run else Vector3.ZERO
	rs["state"] = TC.PState.ACTIVE
	rs["on_floor"] = true
	rs["pos"] = v.global_position
	v.apply_state(rs)


## Controller shoulders (or Q / E) switch categories.
func _unhandled_input(event: InputEvent) -> void:
	if not has_modal():
		for dir in [["menu_prev", -1], ["menu_next", 1]]:
			if event.is_action_pressed(String(dir[0])):
				_step_tab(int(dir[1]))
				get_viewport().set_input_as_handled()
				return
	super(event)


func _step_tab(d: int) -> void:
	var keys: Array = TABS.map(func(t: Array) -> String: return String(t[0]))
	_select_tab(String(keys[wrapi(keys.find(tab) + d, 0, keys.size())]))
	UIKit.soft_focus(tab_btns[tab] as Button)


func _select_tab(key: String) -> void:
	if key == tab and not cards.is_empty():
		return
	_scroll_of[tab] = scroll.scroll_vertical
	Portraits.shared().cancel("tile:")
	tab = key
	_build_tab()
	Motion.settle_in(body, UIKit.T_FAST)


func drag_turn(dx: float) -> void:
	var v := App.stage.local_character() if App.stage else null
	if v == null:
		return
	if not _yaw_set:
		_yaw = v.rotation.y
		_yaw_set = true
	_yaw = wrapf(_yaw + dx * 0.012, -PI, PI)


## Build the current category's cards (only on a category change).
func _build_tab() -> void:
	for k in tab_btns:
		UIKit.set_selected(tab_btns[k], k == tab)
	for c in body.get_children():
		c.queue_free()
	cards.clear()
	swatches.clear()
	_notes.clear()
	var fields: Array = []
	for t in TABS:
		if t[0] == tab:
			fields = t[2]
	var cols := _columns()
	_picked.clear()
	for f in fields:
		# section header: the field and, for colours, the chosen one's name
		var hdr := UIKit.hbox(10)
		var single: bool = fields.size() == 1 and String(f) != "emote"
		if not single:
			hdr.add_child(UIKit.styled(String(FIELD_TITLES[f]), "overline", UIKit.IVORY_MUTED))
		if f in SWATCH_FIELDS:
			var pk := UIKit.styled("", "caption", UIKit.IVORY)
			_picked[f] = pk
			hdr.add_child(pk)
		if hdr.get_child_count() > 0:
			body.add_child(hdr)
		else:
			hdr.free()
		if f in SWATCH_FIELDS:
			body.add_child(_swatches(f))
		else:
			body.add_child(_cards(f, cols))
		if f == "hair" or f == "pattern":
			var note := UIKit.styled("", "caption", UIKit.AMBER)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_notes[f] = note
			body.add_child(note)
	_refresh()
	var at := int(_scroll_of.get(tab, 0))
	(func() -> void:
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.scroll_vertical = at).call()


## Cards per row for the panel's width (3 on a phone, more on wide panels).
func _columns() -> int:
	var w := panel.custom_minimum_size.x - 40.0
	return clampi(int(floor((w + CARD_GAP) / (CARD_W + CARD_GAP))), 3, 6)


func _cards(f: String, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", int(CARD_GAP))
	g.add_theme_constant_override("v_separation", int(CARD_GAP))
	var w := (panel.custom_minimum_size.x - 40.0 - CARD_GAP * float(cols - 1)) / float(cols)
	for k in Cosmetics.keys_of(f):
		var card := ItemCard.new()
		card.setup(self, f, String(k), maxf(CARD_W, w), String(THUMB_FRAMING.get(f, "")))
		card.pressed.connect(_pick.bind(f, String(k)))
		g.add_child(card)
		cards.append(card)
	return g


func _swatches(f: String) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 12)
	h.add_theme_constant_override("v_separation", 12)
	for k in Cosmetics.keys_of(f):
		var sw := Swatch.new()
		sw.field = f
		sw.key = String(k)
		sw.pressed.connect(_pick.bind(f, String(k)))
		h.add_child(sw)
		swatches.append(sw)
	return h


## Everything that depends on the draft: card states and pictures, swatch
## rings, notes, and the footer.  Cards are updated in place.
func _refresh() -> void:
	for c in cards:
		c.refresh()
	for sw in swatches:
		_paint_swatch(sw)
	for f in _picked:
		var k := String(draft[f])
		(_picked[f] as Label).text = "·  %s  ·  %s" % [Cosmetics.entry(f, k)["name"], state_of(f, k)["text"]]
	if _notes.has("hair"):
		var hid: Array = Cosmetics.HAT_HIDES_HAIR.get(String(draft["hat"]), [])
		var hood := String(draft["outfit"]) in Cosmetics.HOOD_OUTFITS
		var parts: Array = Cosmetics.entry("hair", String(draft["hair"]))["parts"]
		var covered := hood or parts.any(func(p: String) -> bool: return p in hid)
		var why := "the hood" if hood else String(Cosmetics.entry("hat", String(draft["hat"]))["name"])
		(_notes["hair"] as Label).text = ("Your hairstyle is tucked under %s. Choose No Hat to show it." % why) if covered else ""
		(_notes["hair"] as Label).visible = covered
	if _notes.has("pattern"):
		var no_pattern := not String(draft["outfit"]) in Cosmetics.PATTERNED_OUTFITS
		(_notes["pattern"] as Label).text = "Patterns show on Pajamas and the Fluffy Robe." if no_pattern else ""
		(_notes["pattern"] as Label).visible = no_pattern
	_update_footer()


func _paint_swatch(sw: Swatch) -> void:
	var it: Dictionary = Cosmetics.entry(sw.field, sw.key)
	sw.col = it.get("rgb", Color(0, 0, 0, 0))
	sw.auto = false
	if sw.field == "trim" and sw.key == "auto":
		sw.col = Cosmetics.tints(Cosmetics.sanitize({"color": draft["color"]}))[1]
		sw.auto = true
	var was := sw.selected
	sw.selected = String(draft[sw.field]) == sw.key
	sw.equipped = String(saved[sw.field]) == sw.key
	var st := state_of(sw.field, sw.key)
	sw.locked = bool(st["locked"])
	sw.price = int(st["cost"]) if not bool(st["owned"]) else 0
	sw.tooltip_text = "%s — %s" % [it["name"], st["text"]]
	sw.accessibility_name = sw.tooltip_text
	if sw.selected and not was and is_inside_tree():
		sw.flash()
	sw.queue_redraw()


## An item's state for its card: {text, col, owned, equipped, locked, cost}.
func state_of(f: String, k: String) -> Dictionary:
	var owned := Save.owns(f, k)
	var cost := Cosmetics.cost(f, k)
	var equipped: bool = String(saved[f]) == k
	var afford := int(Save.data["coins"]) >= cost
	var out := {"owned": owned, "equipped": equipped, "cost": cost, "locked": not owned and not afford}
	if equipped:
		out["text"] = "Equipped"
		out["col"] = UIKit.TEAL
	elif owned:
		out["text"] = "Owned"
		out["col"] = UIKit.IVORY_MUTED
	else:
		out["text"] = "%d coins" % cost
		out["col"] = UIKit.AMBER if afford else UIKit.IVORY_MUTED
	return out


func _pick(f: String, k: String) -> void:
	if String(draft[f]) == k:
		return
	draft[f] = k
	draft = Cosmetics.sanitize(draft)
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, draft)
		if f in ["outfit", "hat", "shoes", "hair", "pattern"] and not UIKit.reduced_motion():
			v.play_arrive()   # a little hop to show the new look
		if f == "emote":
			var id := TC.EMOTES.find(k)
			if id >= 0 and App.stage:
				App.stage.emote(Save.player_uid(), id)
	Sfx.play("pop")
	_refresh()


func _update_footer() -> void:
	var coins := int(Save.data["coins"])
	coins_lbl.text = "%d ¢" % coins
	var price := Save.price_of(draft)
	var changed: bool = draft != saved
	var short := price - coins
	undo_btn.visible = changed or first_run
	if first_run:
		apply_btn.text = "That's me!"
		apply_btn.disabled = short > 0
		price_lbl.text = "You can change this any time in the Wardrobe."
	elif not changed:
		apply_btn.text = "Wearing this"
		apply_btn.disabled = true
		price_lbl.text = "Try anything on: nothing is charged until you apply."
	elif short > 0:
		apply_btn.text = "Need %d more coins" % short
		apply_btn.disabled = true
		price_lbl.text = "This look costs %d coins. Play rounds to earn more." % price
	elif price > 0:
		apply_btn.text = "Buy & apply · %d ¢" % price
		apply_btn.disabled = false
		price_lbl.text = "New items are yours to keep."
	else:
		apply_btn.text = "Apply"
		apply_btn.disabled = false
		price_lbl.text = "Everything here is yours."
	apply_btn.accessibility_name = apply_btn.text


func _on_apply() -> void:
	var r := Save.apply_appearance(draft)
	if not bool(r["ok"]):
		dialog("You need %d more coins for this look. Play a few rounds, or try a different item." % int(r["short"]))
		return
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	Diag.mark("appearance_applied")
	Save.save_now()
	if int(r["spent"]) > 0:
		Sfx.play("pickup")
	App.sync_stage_local()
	App.sync_cloud_appearance()
	if App.session and is_instance_valid(App.session) and App.session.phase == TC.Phase.LOBBY and App.session.mode != NetSession.Mode.OFFLINE:
		App.session.set_local_cosmetic(saved)
	_refresh()
	if first_run and on_done.is_valid():
		on_done.call()
		return
	UIKit.toast(self, "Looking good!" if int(r["spent"]) == 0 else "Bought and applied (%d coins)" % int(r["spent"]))


func _on_cancel() -> void:
	if first_run:
		var r := Cosmetics.bot_cosmetic(randi())
		# only free items for a random start
		for f in Cosmetics.ORDER:
			if Cosmetics.cost(f, String(r[f])) > 0:
				r[f] = Cosmetics.DEFAULT[f]
		draft = Cosmetics.sanitize(r)
		var v := App.stage.local_character() if App.stage else null
		if v:
			v.set_appearance(TC.Role.RUNNER, draft)
		_refresh()
		return
	draft = saved.duplicate()
	App.sync_stage_local()
	var v2 := App.stage.local_character() if App.stage else null
	if v2:
		v2.set_appearance(TC.Role.RUNNER, saved)
	_refresh()


func _back() -> void:
	if draft != saved and not first_run:
		dialog("Leave without applying your new look?", [["Keep editing", Callable()], ["Leave", _leave]])
		return
	_leave()


func _leave() -> void:
	Portraits.shared().cancel("tile:")
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, saved)
		var rs := v.rs.duplicate()
		rs["vel"] = Vector3.ZERO
		v.apply_state(rs)
	if back_action_override.is_valid():
		back_action_override.call()
	else:
		App.goto_title()


func _exit_tree() -> void:
	Portraits.shared().cancel("tile:")


## Left area: drag horizontally to turn the runner.
class StageDrag:
	extends Control
	var creator: CreatorScreen
	var _last := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch or e is InputEventMouseButton:
			var pressed: bool = e.pressed
			_last = e.position.x if pressed else -1.0
			creator._drag_from = _last
		elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _last >= 0.0:
			creator.drag_turn(e.position.x - _last)
			_last = e.position.x


## A portrait-oriented item card: the item's picture on your runner (or an
## icon for moves), the full name below, and a state row.
class ItemCard:
	extends Button
	var creator: CreatorScreen
	var field := ""
	var key := ""
	var framing := ""
	var pic: TextureRect
	var holder: Control
	var name_l: Label
	var state_l: Label
	var lock_i: Icons.IconRect
	var check: Control
	var pic_key := ""
	var has_pic := false

	func setup(c: CreatorScreen, f: String, k: String, w: float, fr: String) -> void:
		creator = c
		field = f
		key = k
		framing = fr
		var it: Dictionary = Cosmetics.entry(f, k)
		var img := w - 24.0
		UIKit.make_card(self, Vector2(w, img + 116.0), Color(UIKit.SLATE_HI, 0.96))
		var v := UIKit.vbox(4)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_right = -10
		v.offset_top = 10
		v.offset_bottom = -8
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.face_of(self).add_child(v)
		holder = PicHolder.new()
		holder.custom_minimum_size = Vector2(img, img)
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(holder)
		if fr != "":
			pic = TextureRect.new()
			pic.set_anchors_preset(Control.PRESET_FULL_RECT)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(pic)
		else:
			var id := TC.EMOTES.find(k)
			var ic := Icons.IconRect.new(Icons.emote_icon(id) if id >= 0 else "smile", UIKit.AMBER, img * 0.6)
			ic.set_anchors_preset(Control.PRESET_CENTER)
			ic.position = Vector2(img * 0.2, img * 0.2)
			holder.add_child(ic)
			(holder as PicHolder).placeholder = false
		name_l = UIKit.styled(String(it["name"]), "label", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.max_lines_visible = 2
		name_l.add_theme_constant_override("line_spacing", -2)
		name_l.add_theme_font_size_override("font_size", 20)
		# two lines are always reserved, so every card's state row lines up
		name_l.custom_minimum_size = Vector2(w - 20.0, 54.0)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name_l)
		var row := UIKit.hbox(4)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_i = Icons.IconRect.new("lock", UIKit.IVORY_MUTED, 18)
		lock_i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lock_i)
		state_l = UIKit.styled("", "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		state_l.add_theme_font_size_override("font_size", 18)
		state_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(state_l)
		v.add_child(row)
		check = CheckBadge.new()
		check.position = Vector2(w - 38.0, 8.0)
		check.visible = false
		UIKit.face_of(self).add_child(check)

	func refresh() -> void:
		var st: Dictionary = creator.state_of(field, key)
		var it: Dictionary = Cosmetics.entry(field, key)
		state_l.text = String(st["text"])
		state_l.add_theme_color_override("font_color", st["col"])
		lock_i.visible = bool(st["locked"])
		var sel: bool = String(creator.draft[field]) == key
		UIKit.set_selected(self, sel)
		check.visible = sel
		accessibility_name = "%s, %s%s" % [it["name"], st["text"], ", selected" if sel else ""]
		if framing != "":
			_request()

	## The item on the draft's look, in this card's framing.
	func _request() -> void:
		var app: Dictionary = creator.draft.duplicate()
		app[field] = key
		if field == "hair":
			app["hat"] = "none"   # show the hairstyle itself
		var k := Portraits.key_for(app, TC.Role.RUNNER, framing)
		if k == pic_key and has_pic:
			return
		pic_key = k
		var ps := Portraits.shared()
		has_pic = ps.has_picture(k)
		var tex := ps.portrait(app, TC.Role.RUNNER, "tile:%s:%s" % [field, key], framing)
		pic.texture = tex if has_pic else null
		(holder as PicHolder).placeholder = not has_pic
		holder.queue_redraw()
		if not has_pic and not ps.portrait_ready.is_connected(_on_pic):
			ps.portrait_ready.connect(_on_pic)

	func _on_pic(k: String, tex: Texture2D) -> void:
		if k != pic_key or not is_instance_valid(pic):
			return
		has_pic = true
		pic.texture = tex
		(holder as PicHolder).placeholder = false
		holder.queue_redraw()
		if not UIKit.reduced_motion():
			pic.modulate.a = 0.0
			Motion.animate(pic, "modulate:a", 1.0, 0.16)


## The picture's well: a soft rounded backdrop, and until the picture is
## ready a faint runner silhouette (no spinning or pulsing).
class PicHolder:
	extends Control
	var placeholder := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.38), UIKit.R_SMALL), r)
		if placeholder:
			var c := size * 0.5
			var s := minf(size.x, size.y)
			var col := Color(UIKit.IVORY, 0.1)
			draw_circle(c + Vector2(0, -s * 0.16), s * 0.13, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, s * 0.32), c + Vector2(-s * 0.16, s * 0.02),
				c + Vector2(0, -s * 0.03), c + Vector2(s * 0.16, s * 0.02), c + Vector2(s * 0.2, s * 0.32)]), col)


## Selected item: a small teal check in the card's corner.
class CheckBadge:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(28, 28)

	func _draw() -> void:
		draw_circle(size * 0.5, 14.0, UIKit.TEAL)
		Icons.draw_shape(self, "check", size * 0.5, 8.5, UIKit.NAVY)


## Round colour swatch: selected ring, equipped dot, lock or price badge.
class Swatch:
	extends Button
	var field := ""
	var key := ""
	var col := Color.WHITE
	var selected := false
	var equipped := false
	var locked := false
	var auto := false
	var price := 0
	var glow := 0.0:
		set(v):
			glow = v
			queue_redraw()
	var visual: Control

	func _init() -> void:
		var s := maxf(UIKit.touch_min(), 72.0)
		custom_minimum_size = Vector2(s, s)
		flat = true
		focus_mode = Control.FOCUS_ALL
		add_theme_stylebox_override("focus", UIKit.focus_ring(999))
		pressed.connect(func() -> void: Sfx.play("click"))
		visual = Control.new()
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.set_anchors_preset(Control.PRESET_FULL_RECT)
		visual.draw.connect(_draw_visual)
		add_child(visual)
		set_meta(&"press_visual", visual)
		visual.resized.connect(func() -> void: visual.pivot_offset = visual.size * 0.5)
		UIKit.press_feedback(self)

	func flash() -> void:
		if UIKit.reduced_motion():
			return
		glow = 1.0
		Motion.animate(self, "glow", 0.0, 0.32)

	func _draw() -> void:
		if visual:
			visual.queue_redraw()

	func _draw_visual() -> void:
		var ci := visual
		var c := ci.size * 0.5
		var r := minf(ci.size.x, ci.size.y) * 0.36
		if selected:
			ci.draw_arc(c, r + 7.0, 0, TAU, 40, UIKit.TEAL, 3.0, true)
		if glow > 0.01:
			ci.draw_arc(c, r + 11.0, 0, TAU, 40, Color(UIKit.TEAL, 0.5 * glow), 3.0, true)
		ci.draw_circle(c + Vector2(0, 2), r, col.darkened(0.4))
		ci.draw_circle(c, r, col)
		ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.2, Color(1, 1, 1, 0.22))
		if auto:
			var f := UIKit.font_w(700)
			ci.draw_string(f, c + Vector2(-r, r * 0.3), "A", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 0.85),
				UIKit.NAVY if col.get_luminance() > 0.5 else UIKit.IVORY)
		if selected:
			ci.draw_circle(c + Vector2(r * 0.72, -r * 0.72), r * 0.34, UIKit.TEAL)
			Icons.draw_shape(ci, "check", c + Vector2(r * 0.72, -r * 0.72), r * 0.2, UIKit.NAVY)
		elif equipped:
			ci.draw_circle(c + Vector2(r * 0.72, -r * 0.72), r * 0.16, UIKit.TEAL)
		if locked:
			ci.draw_circle(c, r, Color(UIKit.NAVY, 0.45))
			Icons.draw_shape(ci, "lock", c, r * 0.45, UIKit.IVORY)
		elif price > 0:
			ci.draw_circle(c + Vector2(r * 0.75, r * 0.75), r * 0.32, UIKit.AMBER)
			var f2 := UIKit.font_w(800)
			ci.draw_string(f2, c + Vector2(r * 0.75 - r, r * 0.75 + r * 0.13), "¢", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 0.42), UIKit.NAVY)
