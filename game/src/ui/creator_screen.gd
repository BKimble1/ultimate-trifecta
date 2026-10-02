class_name CreatorScreen
extends Screen
## "Create Your Runner": the character creator (V3; replaces the V2 wardrobe).
##
##   left    the player's runner in the dorm (App.stage, "wardrobe" framing):
##           drag to turn, Idle / Run preview
##   right   category tabs (Outfit, Colours, Face, Hair, Hat, Shoes, Move) with
##           tiles for items and round swatches for colours; every option
##           shows its state: Wearing, Owned, a price, or locked (too few coins)
##   bottom  Cancel and Apply (Apply buys whatever is not owned yet and
##           equips the whole look in one step; nothing is charged for trying)
##
## The draft is only a preview until Apply.  Leaving with unapplied changes
## asks first.  Hair hidden under the chosen hat is flagged on the hair tiles.

const TABS := [
	["outfit", "Outfit", ["outfit", "pattern"]],
	["colours", "Colours", ["color", "trim"]],
	["face", "Face", ["skin", "face", "brows", "marks"]],
	["hair", "Hair", ["hair", "hair_color"]],
	["hat", "Hat", ["hat"]],
	["shoes", "Shoes", ["shoes"]],
	["move", "Move", ["emote"]],
]
const FIELD_TITLES := {
	"outfit": "Outfit", "pattern": "Pattern", "color": "Main colour", "trim": "Trim", "skin": "Skin tone",
	"face": "Eyes", "brows": "Brows", "marks": "Cheeks", "hair": "Hairstyle", "hair_color": "Hair colour",
	"hat": "Hat", "shoes": "Shoes", "emote": "Ready move (plays when you ready up)",
}
const SWATCH_FIELDS := ["color", "trim", "skin", "hair_color"]

## when true (first launch / profile setup), Apply continues with `on_done`
var first_run := false
var on_done: Callable

var draft: Dictionary = {}
var saved: Dictionary = {}
var tab := "outfit"
var tab_btns: Dictionary = {}
var body: VBoxContainer
var coins_lbl: Label
var price_lbl: Label
var apply_btn: Button
var preview_run := false
var run_btn: Button
var _yaw := 0.0
var _drag_from := -1.0
var _spin := 0.0


func build() -> void:
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	draft = saved.duplicate()
	if App.stage:
		App.stage.set_mode("wardrobe")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := content
	var top := UIKit.hbox(14)
	v.add_child(top)
	if not first_run:
		var back := UIKit.icon_button("back")
		back.tooltip_text = "Back"
		back.pressed.connect(_go_back)
		top.add_child(back)
	var title := UIKit.heading("Create Your Runner", 40)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	top.add_child(UIKit.spacer_h())
	coins_lbl = UIKit.label("", 22, UIKit.AMBER, true)
	coins_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(coins_lbl)

	var mid := UIKit.hbox(16)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(mid)
	# left: the stage area (drag to turn) + preview controls
	var stage_area := StageDrag.new()
	stage_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_area.creator = self
	mid.add_child(stage_area)
	var pv := UIKit.hbox(10)
	pv.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stage_area.add_child(pv)
	var turn_hint := UIKit.chip("Drag to turn", Color(UIKit.SLATE, 0.75), UIKit.IVORY_MUTED, 18)
	turn_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(turn_hint)
	var turn_lbl: Label = turn_hint.find_children("*", "Label", true, false)[0]
	var on_dev := func(k: String) -> void:
		if is_instance_valid(turn_lbl):
			turn_lbl.text = "Right stick to turn" if k == "gamepad" else "Drag to turn"
	Controls.device_changed.connect(on_dev)
	on_dev.call(Controls.device)
	run_btn = UIKit.quiet("Run", Vector2(140, 64), 22)
	run_btn.tooltip_text = "Preview running"
	run_btn.pressed.connect(func() -> void:
		preview_run = not preview_run
		run_btn.text = "Idle" if preview_run else "Run")
	pv.add_child(run_btn)
	stage_area.resized.connect(func() -> void: pv.position = Vector2(0, stage_area.size.y - pv.get_combined_minimum_size().y))

	# right: tabs + options
	var panel := UIKit.panel(Color(UIKit.SLATE, 0.94), UIKit.R_PANEL, 18)
	panel.custom_minimum_size = Vector2(640, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(panel)
	var pvb := UIKit.vbox(12)
	panel.add_child(pvb)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	pvb.add_child(tabs)
	tabs.add_child(Glyphs.Hint.new("menu_prev", "", 30.0))
	for t in TABS:
		var b := UIKit.quiet(String(t[1]), Vector2(0, 60), 19)
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			tab = key
			_rebuild())
		tabs.add_child(b)
		tab_btns[key] = b
	tabs.add_child(Glyphs.Hint.new("menu_next", "", 30.0))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	pvb.add_child(sc)
	body = UIKit.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)

	# bottom: price + Cancel / Apply
	var bottom := UIKit.hbox(14)
	v.add_child(bottom)
	bottom.add_child(UIKit.spacer_h())
	price_lbl = UIKit.label("", 20, UIKit.IVORY_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	price_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(price_lbl)
	var cancel := UIKit.quiet("Cancel" if not first_run else "Randomise", Vector2(200, 84), 24)
	cancel.pressed.connect(_on_cancel)
	bottom.add_child(cancel)
	apply_btn = UIKit.primary("Apply" if not first_run else "That's me!", Vector2(300, 92), 30)
	apply_btn.pressed.connect(_on_apply)
	bottom.add_child(apply_btn)
	focus_first(tab_btns[tab])
	back_action = _back if not first_run else func() -> void: pass
	_rebuild()
	UIKit.appear(panel, Vector2(40, 0), UIKit.T_SHEET)
	var lc := App.stage.local_character() if App.stage else null
	_yaw = lc.rotation.y if lc else 0.0


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


var _yaw_set := false


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
	tab = String(keys[wrapi(keys.find(tab) + d, 0, keys.size())])
	_rebuild()
	(tab_btns[tab] as Button).grab_focus()


func drag_turn(dx: float) -> void:
	var v := App.stage.local_character() if App.stage else null
	if v == null:
		return
	if not _yaw_set:
		_yaw = v.rotation.y
		_yaw_set = true
	_yaw = wrapf(_yaw + dx * 0.012, -PI, PI)


func _rebuild() -> void:
	for k in tab_btns:
		var b: Button = tab_btns[k]
		if k == tab:
			UIKit._apply(b, UIKit.TEAL, UIKit.NAVY)
		else:
			b.add_theme_stylebox_override("normal", UIKit.box(Color(UIKit.SLATE_HI, 0.5), UIKit.R_BUTTON, 2, Color(UIKit.IVORY, 0.18)))
			for c in ["font_color", "font_hover_color", "font_focus_color"]:
				b.add_theme_color_override(c, UIKit.IVORY)
	for c in body.get_children():
		c.queue_free()
	var fields: Array = []
	for t in TABS:
		if t[0] == tab:
			fields = t[2]
	for f in fields:
		body.add_child(UIKit.label(String(FIELD_TITLES[f]), 20, UIKit.IVORY_MUTED, true))
		if f in SWATCH_FIELDS:
			body.add_child(_swatches(f))
		else:
			body.add_child(_tiles(f))
		if f == "hair":
			var hid: Array = Cosmetics.HAT_HIDES_HAIR.get(String(draft["hat"]), [])
			var hood := String(draft["outfit"]) in Cosmetics.HOOD_OUTFITS
			var parts: Array = Cosmetics.entry("hair", String(draft["hair"]))["parts"]
			var covered := hood or parts.any(func(p: String) -> bool: return p in hid)
			if covered:
				var why := "the hood" if hood else String(Cosmetics.entry("hat", String(draft["hat"]))["name"])
				body.add_child(UIKit.label("Your hairstyle is tucked under %s. Pick No Hat to show it." % why, 18, UIKit.AMBER))
		if f == "pattern" and not String(draft["outfit"]) in Cosmetics.PATTERNED_OUTFITS:
			body.add_child(UIKit.label("Patterns show on Pajamas and the Robe.", 18, UIKit.IVORY_MUTED))
	_update_footer()


func _state_text(f: String, k: String) -> Array:
	# [text, colour, locked]
	var equipped: bool = String(draft[f]) == k
	var owned := Save.owns(f, k)
	var cost := Cosmetics.cost(f, k)
	if equipped and String(saved[f]) == k:
		return ["Wearing", UIKit.NAVY, false]
	if equipped:
		return ["Trying on" if owned else "Trying on · %d" % cost, UIKit.NAVY, false]
	if owned:
		return ["Owned", UIKit.IVORY_MUTED, false]
	var afford := int(Save.data["coins"]) >= cost
	return ["%d coins" % cost, UIKit.AMBER if afford else UIKit.IVORY_MUTED, not afford]


func _tiles(f: String) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for k in Cosmetics.keys_of(f):
		var it: Dictionary = Cosmetics.entry(f, k)
		var st: Array = _state_text(f, k)
		var b := UIKit.secondary("", Vector2(190, 96), 20)
		var vb := UIKit.vbox(2)
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 14
		vb.offset_right = -10
		vb.offset_bottom = -UIKit.LIP
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sel: bool = String(draft[f]) == k
		var nm := UIKit.label(String(it["name"]), 21, UIKit.NAVY if sel else UIKit.IVORY, true)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)
		var row := UIKit.hbox(6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bool(st[2]):
			row.add_child(Icons.IconRect.new("lock", UIKit.IVORY_MUTED, 20))
		var sl := UIKit.label(String(st[0]), 17, st[1] if not sel else UIKit.NAVY)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sl)
		vb.add_child(row)
		b.add_child(vb)
		if sel:
			UIKit._apply(b, UIKit.TEAL, UIKit.NAVY)
		b.tooltip_text = "%s — %s" % [it["name"], st[0]]
		var kk: String = k
		b.pressed.connect(func() -> void: _pick(f, kk))
		g.add_child(b)
	return g


func _swatches(f: String) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 12)
	h.add_theme_constant_override("v_separation", 12)
	for k in Cosmetics.keys_of(f):
		var it: Dictionary = Cosmetics.entry(f, k)
		var st: Array = _state_text(f, k)
		var sw := Swatch.new()
		sw.col = it.get("rgb", Color(0, 0, 0, 0))
		if f == "trim" and k == "auto":
			sw.col = Cosmetics.tints(draft)[1] if String(draft["trim"]) == "auto" else Cosmetics.tints(Cosmetics.sanitize({"color": draft["color"]}))[1]
			sw.auto = true
		sw.selected = String(draft[f]) == k
		sw.locked = bool(st[2])
		sw.price = Cosmetics.cost(f, k) if not Save.owns(f, k) else 0
		sw.tooltip_text = "%s — %s" % [it["name"], st[0]]
		var kk: String = k
		sw.pressed.connect(func() -> void: _pick(f, kk))
		h.add_child(sw)
	return h


func _pick(f: String, k: String) -> void:
	draft[f] = k
	draft = Cosmetics.sanitize(draft)
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, draft)
	Sfx.play("pop")
	var keep := get_viewport().gui_get_focus_owner()
	var idx := keep.get_index() if keep and body.is_ancestor_of(keep) else -1
	var parent_i := keep.get_parent().get_index() if idx >= 0 else -1
	_rebuild()
	# keep controller focus on the same option after the rebuild
	if parent_i >= 0:
		(func() -> void:
			if parent_i < body.get_child_count():
				var grp := body.get_child(parent_i)
				if idx < grp.get_child_count() and grp.get_child(idx) is Control:
					(grp.get_child(idx) as Control).grab_focus()).call_deferred()


func _update_footer() -> void:
	coins_lbl.text = "%d coins" % int(Save.data["coins"])
	var price := Save.price_of(draft)
	var changed: bool = draft != saved
	var short := price - int(Save.data["coins"])
	if not changed and not first_run:
		price_lbl.text = "This is your current look"
	elif price == 0:
		price_lbl.text = "Everything here is yours"
	elif short > 0:
		price_lbl.text = "Costs %d coins — %d more to go. Play a few rounds!" % [price, short]
	else:
		price_lbl.text = "Apply for %d coins" % price
	apply_btn.disabled = short > 0 or (not changed and not first_run)


func _on_apply() -> void:
	var r := Save.apply_appearance(draft)
	if not bool(r["ok"]):
		dialog("You need %d more coins for this look. Play a few rounds, or try a different item." % int(r["short"]))
		return
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	Save.save_now()
	if int(r["spent"]) > 0:
		Sfx.play("pickup")
	App.sync_stage_local()
	App.sync_cloud_appearance()
	if App.session and is_instance_valid(App.session) and App.session.phase == TC.Phase.LOBBY and App.session.mode != NetSession.Mode.OFFLINE:
		App.session.set_local_cosmetic(saved)
	_rebuild()
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
		_rebuild()
		return
	draft = saved.duplicate()
	App.sync_stage_local()
	var v2 := App.stage.local_character() if App.stage else null
	if v2:
		v2.set_appearance(TC.Role.RUNNER, saved)
	_rebuild()


func _back() -> void:
	if draft != saved and not first_run:
		dialog("Leave without applying your new look?", [["Keep editing", Callable()], ["Leave", _leave]])
		return
	_leave()


func _leave() -> void:
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


## where Back goes (lobby sets this; default: home)
var back_action_override: Callable


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


## Round colour swatch with selected ring, lock and price badge.
class Swatch:
	extends Button
	var col := Color.WHITE
	var selected := false
	var locked := false
	var auto := false
	var price := 0

	func _init() -> void:
		var s := maxf(UIKit.touch_min(), 72.0)
		custom_minimum_size = Vector2(s, s)
		flat = true
		focus_mode = Control.FOCUS_ALL
		UIKit.press_feedback(self)
		add_theme_stylebox_override("focus", UIKit.box(Color(0, 0, 0, 0), 999, 3, UIKit.TEAL, 0))
		pressed.connect(func() -> void: Sfx.play("click"))

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.38
		if selected:
			draw_circle(c, r + 7.0, UIKit.IVORY)
			draw_circle(c, r + 3.5, UIKit.NAVY)
		draw_circle(c + Vector2(0, 3), r, col.darkened(0.35))
		draw_circle(c, r, col)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.22, Color(1, 1, 1, 0.25))
		if auto:
			var f := UIKit.font_w(700)
			draw_string(f, c + Vector2(-r, r * 0.25), "A", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 0.9),
				UIKit.NAVY if col.get_luminance() > 0.5 else UIKit.IVORY)
		if locked:
			draw_circle(c, r, Color(UIKit.NAVY, 0.45))
			Icons.draw_shape(self, "lock", c, r * 0.5, UIKit.IVORY)
		elif price > 0:
			draw_circle(c + Vector2(r * 0.75, r * 0.75), r * 0.32, UIKit.AMBER)
			var f2 := UIKit.font_w(700)
			draw_string(f2, c + Vector2(r * 0.75 - r, r * 0.75 + r * 0.12), "¢", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 0.42), UIKit.NAVY)
