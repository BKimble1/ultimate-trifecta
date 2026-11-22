class_name CreatorScreen
extends Screen
## The Locker (V6; "Create Your Runner" on first launch).  It shows only what
## the player owns (free base options, pre-V6 unlocks, everything bought or
## earned on the account) and it never spends.  Buying is in the Shop; each
## category ends with a short link to what isn't owned yet.
##
##   top     Back, the navigation bar (Play · Locker · Shop · Season Pass) and
##           the Coins chip (one 44 pt row)
##   left    the player's runner in the dorm (App.stage, "wardrobe" framing):
##           fitted between the top row and the bottom edge, hat to shoes;
##           drag to turn, Idle / Run preview
##   right   one panel: the category strip (Outfit, Colors, Face, Hair, Hat,
##           Shoes, Emotes, Profile), the item grid, and a footer row with
##           the selected item, its state, and Undo / Save look (shown only
##           when the look has changed)
##
## V7 (owner screenshots IMG_3016/3018): cards are compact and laid out for
## the panel's final width (UIKit.AutoGrid), per content type: full-body
## outfits, close-up hats/faces/hair, feet-framed shoes, short emote cards
## whose glyph is centred in its well by anchors (V6 offset it by a positive
## position from a centre anchor, so it sat past the well's corner).  A small
## "Equipped" line replaces V6's giant disabled "Wearing this" button; the
## footer prose and the "N more in the Shop" card are gone (a compact link
## ends the list).  Outfit pictures show the outfit with no hat and plain
## shoes (CommerceArt.preview_look), not the player's own nightcap and
## slippers; the live runner always wears the real draft.  Picking an emote
## plays it on the runner (again on a second tap).
##
## The draft is only a preview until Save.  Leaving with unsaved changes asks
## first (also when switching tabs).  Cards are updated in place; each
## category keeps its scroll position.  Pictures: rendered off-screen one at
## a time through the shared portrait atlas (no live 3D per card), cached by
## look, requested only for the visible category; a category change cancels
## the previous category's queued requests.

const TABS := [
	["outfit", "Outfit", ["outfit", "pattern"]],
	["colours", "Colors", ["color", "trim"]],
	# (2.2 build 16) hair joins the face tab (room for Music)
	["face", "Face", ["skin", "face", "brows", "marks", "hair", "hair_color"]],
	["hat", "Hat", ["hat"]],
	["shoes", "Shoes", ["shoes"]],
	["move", "Emotes", ["emote"]],
	["profile", "Profile", ["card", "badge"]],
	# (2.2 build 16) lobby music: discs to put on
	["albums", "Music", []],
]
## (2.2 build 16) open the Locker on this category once (Settings › Audio)
static var open_category := ""
const FIELD_TITLES := {
	"outfit": "Outfit", "pattern": "Pattern", "color": "Main color", "trim": "Trim", "skin": "Skin tone",
	"face": "Eyes", "brows": "Brows", "marks": "Cheeks", "hair": "Hairstyle", "hair_color": "Hair color",
	"hat": "Hat", "shoes": "Shoes", "emote": "Emotes you own",
	"card": "Name card · shown with your name", "badge": "Badge",
}
const PROFILE_FIELDS := ["card", "badge"]
const SWATCH_FIELDS := ["color", "trim", "skin", "hair_color"]
## Picture framing for an item's card ("" = an emote glyph card).
const THUMB_FRAMING := {"outfit": "body", "pattern": "body", "hair": "head", "hat": "hat", "shoes": "feet",
	"face": "head", "brows": "head", "marks": "head"}
## The narrowest card the layout makes (AutoGrid never goes below it).
const CARD_W := 144.0
const CARD_GAP := float(UIKit.GAP_CARD)
## Card padding, gap between its rows, the state row and the name size.
const PAD := 8.0
const ROW_GAP := 6.0
const STATE_H := 22.0
const NAME_FS := 20
## The picture well's height per content type, as a share of its width.
const WELL := {"body": 1.04, "hat": 0.9, "head": 0.84, "feet": 0.66, "emote": 0.44, "card": 0.4, "badge": 0.72}
## Smallest card per content type (name cards are wide plates).
const CARD_MIN := {"card": 240.0, "emote": 116.0}   # (build 20) emotes: six to a row, short cards
## The item panel's share of the width beside the runner (stage 1 : panel 1.6).
const PANEL_RATIO := 1.6
## (2.2 build 18) the Locker's panel a little wider than the Shop's: its
## eight categories keep their 44 pt targets without the last one cut off
const LOCKER_RATIO := 2.0

## when true (first launch / profile setup), Apply continues with `on_done`
var first_run := false
var on_done: Callable
## (build 23) first launch under the season film: the setup controls wait
## for reveal_after_film() (the runner is already framed behind the film)
var await_reveal := false
var setup_step := "look"           # "look" | "name"
var setup_panel: PanelContainer
var name_form: NameSheet
var continue_btn: Button
var surprise_btn: Button
var _step_l: Label
var _title_l: Label
var _look_box: Control
var _name_box: Control
var _setup_footer: Control
var _pattern_btns: Dictionary = {}
var _pattern_row: Control
var _turn_chip: Control
var _finishing := false
var _blocker: Control


## Until the controls are revealed, keys and buttons do nothing here.
func _input(event: InputEvent) -> void:
	if first_run and is_instance_valid(_blocker) and (event is InputEventKey or event is InputEventJoypadButton):
		get_viewport().set_input_as_handled()
## where Back goes (lobby sets this; default: home)
var back_action_override: Callable

var draft: Dictionary = {}
var saved: Dictionary = {}
## name card + badge (UI-only profile cosmetics): draft and saved
var draft_style: Dictionary = {}
var saved_style: Dictionary = {}
var discover: Array[Button] = []
var tab := "outfit"
var tab_btns: Dictionary = {}
var body: VBoxContainer
var scroll: ScrollContainer
var coins_lbl: Label
var sel_name: Label
var sel_state: Label
var apply_btn: Button
var undo_btn: Button
var footer: HBoxContainer
var preview_run := false
var run_btn: Button
var panel: PanelContainer
var cards: Array = []            # ItemCard / ProfileCard
var grids: Array = []            # AutoGrid per field shown
var swatches: Array[Swatch] = []
var _notes: Dictionary = {}       # field -> Label (hair hidden / pattern note)
var _picked: Dictionary = {}      # swatch field -> Label naming the chosen colour
var _scroll_of: Dictionary = {}   # tab -> scroll position
var _last_field := ""
var _yaw := 0.0
var _drag_from := -1.0
var _spin := 0.0
var _yaw_set := false
var _stage_area: Control


func build() -> void:
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	draft = saved.duplicate()
	saved_style = Save.profile_style()
	draft_style = saved_style.duplicate()
	if App.stage:
		App.stage.set_mode("wardrobe")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.45, 0.0)
	content.add_theme_constant_override("separation", UIKit.SP_M)
	if first_run:
		_build_setup()
		return
	if not first_run:
		nav_bar("locker")
	else:
		var top := UIKit.hbox(14)
		top.custom_minimum_size.y = UIKit.row_h()
		var title := UIKit.styled("Create Your Runner", "title")
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(title)
		top.add_child(UIKit.spacer_h())
		content.add_child(top)
	coins_lbl = null

	var mid := UIKit.hbox(UIKit.SP_L)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	# left: the stage area (drag to turn) + preview controls
	var stage_area := StageDrag.new()
	_stage_area = stage_area
	stage_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_area.size_flags_stretch_ratio = 1.0
	stage_area.creator = self
	mid.add_child(stage_area)
	# preview controls stacked in the corner, clear of the runner
	var pv := UIKit.vbox(UIKit.SP_S)
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
	# V6: the lambda only touches a local, so it is bound to the script, not
	# this screen, and was never disconnected: every Locker visit left one
	# more connection and closure behind (test_screen_cycles)
	tree_exiting.connect(func() -> void:
		if Controls.device_changed.is_connected(on_dev):
			Controls.device_changed.disconnect(on_dev), CONNECT_ONE_SHOT)
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

	# right: one panel with categories, the grid and the footer.  Its width
	# is a share of the row (stretch ratio), from the allocated rect.
	panel = UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, UIKit.PAD_PANEL)
	panel.name = "ItemPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = LOCKER_RATIO
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(panel)
	var pvb := UIKit.vbox(UIKit.SP_S)
	panel.add_child(pvb)
	pvb.add_child(_category_strip())
	scroll = UIKit.scroll_area()
	scroll.name = "Items"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# the bar's room is always kept, so the grid's width never flips when a
	# list becomes long enough to scroll
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.follow_focus = true
	pvb.add_child(scroll)
	body = UIKit.vbox(UIKit.SP_S)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	pvb.add_child(_footer())
	if open_category != "" and tab_btns.has(open_category):
		tab = open_category
	open_category = ""
	focus_first(tab_btns[tab])
	back_action = _back if not first_run else func() -> void: pass
	_build_tab()
	UIKit.fade_in(panel)
	_stage_area.resized.connect(_frame_stage)
	get_viewport().size_changed.connect(_frame_stage)
	_frame_stage.call_deferred()
	var lc := App.stage.local_character() if App.stage else null
	_yaw = lc.rotation.y if lc else 0.0


## The panel's footer: the selected item and its state on the left; Undo and
## Save look on the right, only while the look differs from the saved one
## (first launch: Surprise me / That's me!).  One 44 pt row, always there, so
## nothing moves when the buttons appear.
func _footer() -> Control:
	footer = UIKit.hbox(UIKit.SP_M)
	footer.name = "Footer"
	footer.custom_minimum_size.y = UIKit.row_h()
	var info := UIKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_name = UIKit.styled("", "label")
	sel_name.clip_text = true
	sel_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(sel_name)
	sel_state = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	sel_state.clip_text = true
	sel_state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(sel_state)
	footer.add_child(info)
	undo_btn = UIKit.quiet("Undo" if not first_run else "Surprise me", Vector2(0, UIKit.row_h()))
	undo_btn.name = "Undo"
	undo_btn.custom_minimum_size.x = maxf(UIKit.row_h() * 1.6, 0.0)
	undo_btn.pressed.connect(_on_cancel)
	footer.add_child(undo_btn)
	apply_btn = UIKit.primary("Save look" if not first_run else "That's me!", Vector2(0, UIKit.row_h()), 24)
	apply_btn.name = "SaveLook"
	apply_btn.custom_minimum_size.x = maxf(UIKit.row_h() * 2.2, 0.0)
	apply_btn.pressed.connect(_on_apply)
	footer.add_child(apply_btn)
	return footer


## Tell the stage where the free space left of the item panel is: across, a
## little right of centre (the preview controls sit in the left corner); and
## down, the band between the top row and the bottom edge, so the runner's
## hat never runs under the tabs and the shoes stay above the edge.
func _frame_stage() -> void:
	if App.stage and is_instance_valid(_stage_area) and _stage_area.is_inside_tree():
		var vs := get_viewport().get_visible_rect().size
		var r := _stage_area.get_global_rect()
		if r.size.x < 2.0 or r.size.y < 2.0:
			return
		App.stage.set_wardrobe_region((r.get_center().x + r.size.x * 0.12) / maxf(1.0, vs.x), r.size.x / maxf(1.0, vs.x),
			r.position.y / maxf(1.0, vs.y), r.end.y / maxf(1.0, vs.y))


func _category_strip() -> Control:
	var tab_scroll := UIKit.scroll_area(true)
	tab_scroll.name = "Categories"
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tab_scroll.follow_focus = true
	var tabs := HBoxContainer.new()
	# pills sit edge to edge (each keeps its whole 44 pt target): eight fit
	# an iPhone SE panel without scrolling
	tabs.add_theme_constant_override("separation", 0)
	tab_scroll.add_child(tabs)
	tabs.add_child(Glyphs.Hint.new("menu_prev", "", 30.0))
	for t in TABS:
		var b := UIKit.quiet(String(t[1]), Vector2(0, 0), UIKit.T_LABEL)
		b.name = "Cat_" + String(t[0])
		b.custom_minimum_size.y = UIKit.row_h()
		var f := UIKit.face_of(b)
		var sel := UIKit.box(Color(UIKit.TEAL, 0.16), 999, 0, Color.WHITE)
		sel.set_border_width_all(2)
		sel.border_color = UIKit.TEAL
		var n := UIKit.box(Color(0, 0, 0, 0), 999, 0, Color.WHITE)
		f.styles = {"normal": n, "hover": UIKit.box(Color(UIKit.IVORY, 0.06), 999), "pressed": UIKit.box(Color(UIKit.IVORY, 0.1), 999),
			"disabled": n, "selected": sel}
		f.fg = {"normal": UIKit.IVORY_MUTED, "hover": UIKit.IVORY, "selected": UIKit.IVORY}
		var key: String = t[0]
		b.set_meta(&"sfx", "tab")
		b.pressed.connect(func() -> void: _select_tab(key))
		tabs.add_child(b)
		tab_btns[key] = b
	tabs.add_child(Glyphs.Hint.new("menu_next", "", 30.0))
	tab_scroll.custom_minimum_size.y = UIKit.row_h()
	tab_scroll.resized.connect(_fit_tabs.bind(tab_scroll, tabs))
	return tab_scroll


## The category strip fits its panel: on a narrow one (iPhone SE) the
## padding tightens and the labels step down a size before any category
## would sit cut off at the edge.  Scrolling stays as the last resort.
const TAB_FITS := [[UIKit.T_LABEL, 18], [UIKit.T_LABEL, 12], [UIKit.T_CAPTION, 10], [UIKit.T_CAPTION, 6], [UIKit.T_CAPTION - 2, 4], [UIKit.T_CAPTION - 3, 2]]


func _fit_tabs(strip: ScrollContainer, row: HBoxContainer) -> void:
	var avail := strip.size.x
	if avail <= 0.0:
		return
	var pick: Array = TAB_FITS[TAB_FITS.size() - 1]
	for opt in TAB_FITS:
		if tabs_width(row, int(opt[0]), int(opt[1])) <= avail:
			pick = opt
			break
	for b in tab_btns.values():
		var btn := b as Button
		btn.add_theme_font_size_override("font_size", int(pick[0]))
		var st := btn.get_theme_stylebox("normal")   # one StyleBoxEmpty shared by every state
		st.content_margin_left = float(pick[1])
		st.content_margin_right = float(pick[1])
		btn.update_minimum_size()
		UIKit.face_of(btn).queue_redraw()   # its text padding follows the button's


## Width the strip's row needs with these label sizes and side padding.
func tabs_width(row: HBoxContainer, font_size: int, pad: int) -> float:
	var need := 0.0
	var shown := 0
	for c in row.get_children():
		var ctl := c as Control
		if not ctl.visible:
			continue
		shown += 1
		if tab_btns.values().has(ctl):
			var btn := ctl as Button
			var w := btn.get_theme_font("font").get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			need += maxf(ceilf(w) + 2.0 * pad, UIKit.touch_min())
		else:
			need += ctl.get_combined_minimum_size().x
	return need + float(row.get_theme_constant("separation")) * maxi(shown - 1, 0)


func _process(delta: float) -> void:
	if first_run:
		_keyboard_fit()
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
	if first_run and setup_step == "look" and not has_modal():
		for dir in [["menu_prev", -1], ["menu_next", 1]]:
			if event.is_action_pressed(String(dir[0])):
				_step_group(int(dir[1]))
				get_viewport().set_input_as_handled()
				return
	if not has_modal() and not first_run:
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
	# a restore still pending: the tab never moved from where it was going
	_scroll_of[tab] = _restore_at if _restore_at >= 0 else scroll.scroll_vertical
	Portraits.cancel_shared("tile:")
	tab = key
	_build_tab()
	UIKit.fade_in(body, UIKit.T_FAST)


func drag_turn(dx: float) -> void:
	var v := App.stage.local_character() if App.stage else null
	if v == null:
		return
	if not _yaw_set:
		_yaw = v.rotation.y
		_yaw_set = true
	_yaw = wrapf(_yaw + dx * 0.012, -PI, PI)


func _tab_fields(key: String) -> Array:
	for t in TABS:
		if t[0] == key:
			return t[2]
	return []


## The width the grids get: the list's final width less its scrollbar's
## reserved room (before the first layout, the share of the content rect the
## panel will get).  Grids still re-fit to their own final width.
func grid_width() -> float:
	var w := scroll.size.x if is_instance_valid(scroll) else 0.0
	if w < 2.0:
		var cw := content_size().x
		if cw < 2.0:
			cw = get_viewport().get_visible_rect().size.x * 0.8 if is_inside_tree() else 1000.0
		w = (cw - UIKit.SP_L) * LOCKER_RATIO / (1.0 + LOCKER_RATIO) - UIKit.PAD_PANEL * 2.0
	var bar := scroll.get_v_scroll_bar().get_combined_minimum_size().x if is_instance_valid(scroll) else 8.0
	return maxf(CARD_W, w - bar - 2.0)


## Build the current category's cards (only on a category change).
func _build_tab() -> void:
	for k in tab_btns:
		UIKit.set_selected(tab_btns[k], k == tab)
	for c in body.get_children():
		c.queue_free()
	cards.clear()
	grids.clear()
	swatches.clear()
	discover.clear()
	_notes.clear()
	var fields: Array = _tab_fields(tab)
	var gw := grid_width()
	_picked.clear()
	_discs.clear()
	if tab == "albums":
		_build_albums(gw)
		_update_footer()
		return
	if tab == "move":
		body.add_child(_emote_slot_row(gw))
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
		elif f in PROFILE_FIELDS:
			body.add_child(_profile_cards(f, gw))
		else:
			body.add_child(_cards(f, gw))
		if String(f) == "outfit" and tab == "outfit" and not first_run:
			# (2.2 build 18) Random look and three kept looks, under the outfits
			body.add_child(_looks_row())
		if f == "hair" or f == "pattern":
			var note := UIKit.styled("", "caption", UIKit.AMBER)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size.x = gw * 0.9
			_notes[f] = note
			body.add_child(note)
	# Pass 9: a complete skin (Record Breaker, Dr. Doom) says what it replaces
	# while worn, on its own tab and on the tabs whose choices it covers
	if tab != "profile" and tab != "move":
		var sn := UIKit.styled("", "caption", UIKit.AMBER)
		sn.name = "SkinNote"
		sn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sn.custom_minimum_size.x = gw * 0.9
		_notes["skin"] = sn
		body.add_child(sn)
		body.move_child(sn, 0)
	if not first_run:
		var link := _discover_link(fields)
		if link:
			body.add_child(link)
	_refresh()
	# V6: the category's own position, applied once its cards have laid out.
	# Only the newest request is kept (rapid tab switching restores the tab
	# that is showing, never an earlier one), through this screen's one-shot
	# frame hook (dropped if the screen goes), and never under a finger.
	_restore_at = int(_scroll_of.get(tab, 0))
	if is_inside_tree() and not get_tree().process_frame.is_connected(_restore_scroll):
		get_tree().process_frame.connect(_restore_scroll, CONNECT_ONE_SHOT)


var _restore_at := -1
var _discs: Array = []
var _emote_slot := 0
var _slot_btns: Array = []


## (2.2 build 16) The five equipped emotes: pick a slot, then an emote.
## (build 20) Redrawn so nothing can overlap: each slot's number sits in its
## corner (slot 1 also says READY), the slot being filled has a gold edge, and
## the two lines of help sit above and below the row, never on the tiles.
func _emote_slot_row(gw: float) -> Control:
	var v := UIKit.vbox(8)
	v.name = "EmoteSlots"
	var hdr := UIKit.styled("Pick a slot, then tap an emote below.", "caption", UIKit.IVORY_MUTED)
	hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr.custom_minimum_size.x = gw * 0.95
	v.add_child(hdr)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_slot_btns.clear()
	var w := floorf((gw - 8.0 * 4.0) / 5.0)
	var h := clampf(roundf(w * 0.72), 88.0, 112.0)
	for i in EmoteSlots.N:
		var b := UIKit.card_button(Vector2(w, h), UIKit.SLATE)
		b.name = "Slot_%d" % (i + 1)
		var idx := i
		b.pressed.connect(func() -> void:
			_emote_slot = idx
			_last_field = "emote"
			_paint_emote_slots()
			_refresh()
			_update_footer()
			var id := EmoteSlots.id_at(idx)
			if id >= 0 and App.stage:
				App.stage.emote(Save.player_uid(), id))
		row.add_child(b)
		_slot_btns.append(b)
	var foot := UIKit.styled("Slot 1 is also your ready move.", "caption", UIKit.IVORY_DIM)
	foot.add_theme_font_size_override("font_size", 17)
	v.add_child(foot)
	_paint_emote_slots()
	return v


func _paint_emote_slots() -> void:
	var ks := EmoteSlots.keys()
	for i in _slot_btns.size():
		var b: Button = _slot_btns[i]
		if not is_instance_valid(b):
			continue
		var f := UIKit.face_of(b)
		for c in f.get_children():
			c.queue_free()
		var w := b.custom_minimum_size.x
		var hh := b.custom_minimum_size.y
		var k := String(ks[i]) if i < ks.size() else ""
		var choosing := i == _emote_slot
		# the slot's number in its corner; slot 1 also says READY, top right
		var num := UIKit.styled(str(i + 1), "overline", UIKit.AMBER if choosing else UIKit.IVORY_MUTED)
		num.add_theme_font_size_override("font_size", 16)
		num.position = Vector2(10, 6)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.add_child(num)
		if i == 0:
			var rd := UIKit.styled("Ready", "overline", UIKit.AMBER if choosing else UIKit.IVORY_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
			rd.add_theme_font_size_override("font_size", 12)
			rd.position = Vector2(30, 8)
			rd.size = Vector2(w - 40, 18)
			rd.clip_text = true
			rd.mouse_filter = Control.MOUSE_FILTER_IGNORE
			f.add_child(rd)
		# the emote: its icon and name, centred under the corner labels
		var col := UIKit.vbox(2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.position = Vector2(4, 24)
		col.size = Vector2(w - 8, hh - 30)
		if k != "":
			var ic := Icons.IconRect.new(Icons.emote_icon(TC.EMOTES.find(k)), UIKit.IVORY, minf(w * 0.36, hh * 0.38))
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(ic)
			var nm := UIKit.styled(String(Cosmetics.entry("emote", k)["name"]), "caption", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
			nm.add_theme_font_size_override("font_size", 16)
			nm.clip_text = true
			nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			nm.custom_minimum_size.x = w - 12
			col.add_child(nm)
		else:
			col.add_child(UIKit.styled("Empty", "caption", UIKit.IVORY_DIM, HORIZONTAL_ALIGNMENT_CENTER))
		f.add_child(col)
		# the slot being filled: a gold edge (the others plain)
		var sb := UIKit.card_box(Color(UIKit.AMBER.darkened(0.62), 0.92) if choosing else Color(UIKit.SLATE, 0.92), 16, 1.0, 12, 0.08)
		if choosing:
			sb.set_border_width_all(3)
			sb.border_color = UIKit.AMBER
		f.styles["normal"] = sb
		f.styles["selected"] = sb
		f.queue_redraw()
		UIKit.set_selected(b, choosing)
		b.accessibility_name = "Emote slot %d%s, %s%s" % [i + 1, " (ready move)" if i == 0 else "", String(Cosmetics.entry("emote", k).get("name", "empty")) if k != "" else "empty", ", selected" if i == _emote_slot else ""]



## (2.2 build 16) Albums: every lobby album as a disc in its sleeve; a tap
## puts it on (saved at once, it plays now).  Free for everyone.
func _build_albums(gw: float) -> void:
	var intro := UIKit.styled("Tap a disc to play it.", "caption", UIKit.IVORY_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = gw * 0.95
	body.add_child(intro)
	var g := UIKit.AutoGrid.new(260.0, 1, 3, CARD_GAP)
	g.name = "Grid_albums"
	var cols := UIKit.columns_for(gw, g.min_cell, CARD_GAP, 1, 3)
	var w := UIKit.cell_width(gw, cols, CARD_GAP)
	for a in Albums.LIST:
		var d := AlbumDisc.new()
		d.setup(String(a["id"]), w)
		var id := String(a["id"])
		d.pressed.connect(func() -> void:
			Albums.choose(id)
			Sfx.play("click")
			for x in _discs:
				(x as AlbumDisc).refresh())
		g.add_child(d)
		_discs.append(d)
	g.columns = cols
	grids.append(g)
	body.add_child(g)


func _restore_scroll() -> void:
	var at := _restore_at
	_restore_at = -1
	if at < 0 or not is_instance_valid(scroll) or TouchScroll.is_dragging(scroll):
		return
	scroll.scroll_vertical = at


## Cards per row: from each grid's final width (AutoGrid), never from a
## requested minimum size.  The current category's first grid's count.
func _columns() -> int:
	for g in grids:
		return (g as GridContainer).columns
	return UIKit.columns_for(grid_width(), CARD_W, CARD_GAP, 2, 6)


## The keys of a field shown in the Locker: everything owned, plus the
## saved choice (always wearable, even if ownership changed meanwhile).
func shown_keys(f: String) -> Array:
	return Cosmetics.keys_of(f).filter(func(k: String) -> bool: return Wallet.owns(f, k) or String(saved.get(f, "")) == k)


## Unowned items of a field, by where they come from: {shop: n, season: n}.
func not_owned(f: String) -> Dictionary:
	var out := {"shop": 0, "season": 0}
	var keys: Array = Cosmetics.keys_of(f) if not f in PROFILE_FIELDS else \
		Catalogue.all_items().filter(func(it: Dictionary) -> bool: return String(it["id"]).begins_with(f + ":")).map(func(it: Dictionary) -> String: return String(Catalogue.split(String(it["id"]))[1]))
	for k in keys:
		var id := Catalogue.id_for(f, String(k))
		if Wallet.owns_id(id) or (not f in PROFILE_FIELDS and Wallet.owns(f, String(k))):
			continue
		match Catalogue.source_of(id):
			"shop", "apple":
				# Pass 8: a rotating skin counts only while its offer is on
				# sale (owned ones are in the Locker whatever the rotation)
				if Catalogue.has_art(id) and Offers.listed(id):
					out["shop"] += 1
			"season":
				if Catalogue.has_art(id):
					out["season"] += 1
	return out


## A grid of item cards for one field, laid out for its final width.
func _cards(f: String, gw: float) -> GridContainer:
	var kind := "emote" if not THUMB_FRAMING.has(f) else String(THUMB_FRAMING[f])
	var g := UIKit.AutoGrid.new(float(CARD_MIN.get(kind, CARD_W)), 2, 6, CARD_GAP)
	g.name = "Grid_" + f
	var cols := UIKit.columns_for(gw, g.min_cell, CARD_GAP, 2, 6)
	var w := UIKit.cell_width(gw, cols, CARD_GAP)
	for k in shown_keys(f):
		var card := ItemCard.new()
		card.setup(self, f, String(k), w, String(THUMB_FRAMING.get(f, "")))
		card.pressed.connect(_pick.bind(f, String(k)))
		g.add_child(card)
		cards.append(card)
	g.columns = cols
	grids.append(g)
	return g


## The end of a category's list: what isn't owned yet and where it comes
## from, as one compact link ("4 more in the Shop ›" → the Shop; "2 more in
## the Season Pass ›" → the pass).  Never a card competing with owned items.
func _discover_link(fields: Array) -> Button:
	var shop := 0
	var season := 0
	for f in fields:
		var n := not_owned(String(f))
		shop += int(n["shop"])
		season += int(n["season"])
	if shop == 0 and season == 0:
		return null
	var to_shop := shop > 0
	var txt := ("%d more in the Shop" % shop) if to_shop else ("%d more in the Season Pass" % season)
	var b := UIKit.link(txt + "  ›", UIKit.T_LABEL)
	b.name = "Discover_" + tab
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.accessibility_name = "%s. %s" % [txt, "View in Shop" if to_shop else "Open Season Pass"]
	b.tooltip_text = "View in Shop" if to_shop else "Open Season Pass"
	var first := String(fields[0]) if not fields.is_empty() else ""
	b.pressed.connect(func() -> void:
		if to_shop:
			ShopScreen.focus_section = "outfits" if first == "outfit" else "accessories"
			NavShell.go("shop")
		else:
			NavShell.go("pass"))
	discover.append(b)
	return b


func _swatches(f: String) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.name = "Swatches_" + f
	h.add_theme_constant_override("h_separation", 12)
	h.add_theme_constant_override("v_separation", 12)
	for k in shown_keys(f):
		var sw := Swatch.new()
		sw.field = f
		sw.key = String(k)
		sw.pressed.connect(_pick.bind(f, String(k)))
		h.add_child(sw)
		swatches.append(sw)
	return h


## Name cards and badges: "None" plus every owned one, previewed as they
## appear when equipped (the player's name, the chosen badge).
func _profile_cards(f: String, gw: float) -> GridContainer:
	var kind := "card" if f == "card" else "badge"
	var g := UIKit.AutoGrid.new(float(CARD_MIN.get(kind, CARD_W)), 2, 6, CARD_GAP)
	g.name = "Grid_" + f
	var cols := UIKit.columns_for(gw, g.min_cell, CARD_GAP, 2, 6)
	var w := UIKit.cell_width(gw, cols, CARD_GAP)
	var ids: Array = [""]
	for it in Catalogue.all_items():
		var id := String(it["id"])
		if id.begins_with(f + ":") and Wallet.owns_id(id):
			ids.append(id)
	for id in ids:
		var pc := ProfileCard.new()
		pc.setup(self, f, String(id), w)
		pc.pressed.connect(_pick_style.bind(f, String(id)))
		g.add_child(pc)
		cards.append(pc)
	g.columns = cols
	grids.append(g)
	return g


func _pick_style(f: String, id: String) -> void:
	_last_field = f
	if String(draft_style.get(f, "")) == id:
		_update_footer()
		return
	draft_style[f] = id
	Sfx.play("pop")
	_refresh()


## Everything that depends on the draft: card states and pictures, swatch
## rings, notes, and the footer.  Cards are updated in place.
func _refresh() -> void:
	if first_run:
		_setup_refresh()
		return
	for c in cards:
		c.refresh()
	for sw in swatches:
		_paint_swatch(sw)
	for f in _picked:
		var k := String(draft[f])
		var st := state_of(f, k)
		(_picked[f] as Label).text = "·  %s%s" % [Cosmetics.entry(f, k)["name"], "  ·  Equipped" if bool(st["equipped"]) else ""]
	if _notes.has("skin"):
		var t := skin_note(tab, String(draft["outfit"]))
		(_notes["skin"] as Label).text = t
		(_notes["skin"] as Label).visible = t != ""
	if _notes.has("hair"):
		var hid: Array = Cosmetics.HAT_HIDES_HAIR.get(String(draft["hat"]), [])
		var hood := String(draft["outfit"]) in Cosmetics.HOOD_OUTFITS
		var parts: Array = Cosmetics.entry("hair", String(draft["hair"]))["parts"]
		var covered := hood or parts.any(func(p: String) -> bool: return p in hid)
		var why := "the hood" if hood else String(Cosmetics.entry("hat", String(draft["hat"]))["name"])
		(_notes["hair"] as Label).text = ("Tucked under %s. Choose No Hat to show it." % why) if covered else ""
		(_notes["hair"] as Label).visible = covered and not Cosmetics.is_complete_skin(String(draft["outfit"]))
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


## Pass 9: what a complete skin in the draft replaces, for this tab ("" when
## nothing on it is replaced).  The outfit tab says the whole rule; the tabs
## whose choices the skin covers say that those choices are kept for the
## player's other outfits (they are saved, not deleted).
static func skin_note(tab_key: String, outfit: String) -> String:
	if not Cosmetics.is_complete_skin(outfit):
		return ""
	var nm := String(Cosmetics.entry("outfit", outfit).get("name", ""))
	var own: Dictionary = Cosmetics.COMPLETE_SKINS[outfit].get("own", {})
	var kept := "Your pick here is saved for your other outfits."
	match tab_key:
		"outfit":
			return Cosmetics.override_note(outfit)
		"colours":
			return "%s keeps his own colours. %s" % [nm, kept]
		"face":
			return "%s has his own face and skin tone. %s" % [nm, kept]
		"hair":
			return "%s has his own %s. %s" % [nm, own.get("hair", "hair"), kept]
		"hat":
			return "%s is worn without a hat. %s" % [nm, kept]
		"shoes":
			return "%s wears his own %s. %s" % [nm, own.get("shoes", "footwear"), kept]
	return ""


## An item's state for its card: {text, col, owned, equipped, locked, cost}.
## The Locker shows only owned items, so there is never a price here.
func state_of(f: String, k: String) -> Dictionary:
	var equipped: bool
	var owned: bool
	if f in PROFILE_FIELDS:
		equipped = String(saved_style.get(f, "")) == k
		owned = k == "" or Wallet.owns_id(k)
	else:
		equipped = String(saved[f]) == k
		owned = Wallet.owns(f, k)
	var slot := EmoteSlots.keys().find(k) if f == "emote" else -1
	if f == "emote":
		equipped = slot >= 0
	var out := {"owned": owned, "equipped": equipped, "cost": 0, "locked": false}
	if equipped:
		out["text"] = ("Slot %d" % (slot + 1)) if f == "emote" else "Equipped"
		out["col"] = UIKit.TEAL
	else:
		out["text"] = "Owned" if owned else "Not owned"
		out["col"] = UIKit.IVORY_MUTED
	return out


func _pick(f: String, k: String) -> void:
	_last_field = f
	if f == "emote":
		# a pick (and a second tap) plays the move on the big runner
		var id := TC.EMOTES.find(k)
		if id >= 0 and App.stage:
			App.stage.emote(Save.player_uid(), id)
		# (2.2 build 16) it goes into the chosen loadout slot (saved at once);
		# slot 1 is also the ready-up move
		EmoteSlots.put(_emote_slot, k)
		var first := String(EmoteSlots.keys()[0])
		draft["emote"] = first
		saved["emote"] = first
		_paint_emote_slots()
		Sfx.play("pop")
		_refresh()
		_update_footer()
		if App.session and is_instance_valid(App.session) and App.session.phase == TC.Phase.LOBBY and App.session.mode != NetSession.Mode.OFFLINE:
			App.session.set_local_cosmetic(Cosmetics.sanitize(Save.data["cosmetic"]))
		return
	if String(draft[f]) == k:
		_update_footer()
		return
	draft[f] = k
	draft = Cosmetics.sanitize(draft)
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, draft)
		if f in ["outfit", "hat", "shoes", "hair", "pattern"] and not UIKit.reduced_motion():
			v.play_arrive()   # a little hop to show the new look
	Sfx.play("equip" if f in ["outfit", "hat", "shoes"] else "pop")
	_refresh()


func changed() -> bool:
	return draft != saved or draft_style != saved_style


## The field the footer describes: the last one picked in this category, or
## the category's first.
func _footer_field() -> String:
	var fields := _tab_fields(tab)
	if _last_field in fields:
		return _last_field
	return String(fields[0]) if not fields.is_empty() else ""


func _update_footer() -> void:
	var ch := changed()
	# (build 20) Emotes save the moment they're picked and the gold slot shows
	# what's equipped, so the footer only takes room there when another tab
	# has unsaved changes (its Save look must stay in reach).
	if is_instance_valid(footer):
		footer.visible = not (tab == "move" and not ch and not first_run)
	undo_btn.visible = ch or first_run
	apply_btn.visible = ch or first_run
	apply_btn.disabled = false
	apply_btn.text = "That's me!" if first_run else "Save look"
	apply_btn.accessibility_name = apply_btn.text
	var f := _footer_field()
	var nm := ""
	var same := true
	if f in PROFILE_FIELDS:
		var id := String(draft_style.get(f, ""))
		nm = ("No %s" % ("name card" if f == "card" else "badge")) if id == "" else Catalogue.display_name(id)
		same = id == String(saved_style.get(f, ""))
	elif f == "emote" and tab == "move":
		var ks := EmoteSlots.keys()
		nm = "Slot %d · %s" % [_emote_slot + 1, String(Cosmetics.entry("emote", String(ks[_emote_slot])).get("name", "")) if _emote_slot < ks.size() else "empty"]
	elif f != "":
		nm = String(Cosmetics.entry(f, String(draft[f])).get("name", ""))
		if f in SWATCH_FIELDS:
			nm = "%s: %s" % [FIELD_TITLES[f], nm]
		same = String(draft[f]) == String(saved[f])
	sel_name.text = nm
	if first_run:
		sel_state.text = "Change it any time later"
		sel_state.add_theme_color_override("font_color", UIKit.IVORY_MUTED)
	elif same:
		sel_state.text = "Equipped"
		sel_state.add_theme_color_override("font_color", UIKit.TEAL)
	else:
		sel_state.text = "Not saved yet"
		sel_state.add_theme_color_override("font_color", UIKit.AMBER)


## Save: equips the draft.  Never spends (Save.apply_appearance refuses
## anything not owned; buying is in the Shop).
func _on_apply() -> void:
	var r := Save.apply_appearance(draft)
	if not bool(r["ok"]):
		var names: Array = (r["missing"] as Array).map(func(id: String) -> String: return Catalogue.display_name(id))
		dialog("%s isn't in your Locker any more, so this look can't be saved. Pick something else." % ", ".join(names))
		return
	for k in draft_style:
		Save.set_profile_style(String(k), String(draft_style[k]))
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	saved_style = Save.profile_style()
	draft_style = saved_style.duplicate()
	Diag.mark("appearance_applied")
	Save.save_now()
	App.sync_stage_local()
	App.sync_cloud_appearance()
	if App.session and is_instance_valid(App.session) and App.session.phase == TC.Phase.LOBBY and App.session.mode != NetSession.Mode.OFFLINE:
		App.session.set_local_cosmetic(saved)
	_refresh()
	if first_run and on_done.is_valid():
		on_done.call()
		return
	UIKit.toast(self, "Looking good!")


# ---------------------------------------------------------------- first run
## (build 23) Create Your Runner, two steps around one big runner:
##   look  "What does my runner look like?": the owned starter outfits,
##         pattern, main colour, skin tone and hairstyle, each applied to the
##         runner at once (drag to turn); Surprise me (secondary) and
##         Continue (primary).  The default look is ready to go as it is.
##   name  "What should we call you?": the same runner, the generated name
##         already filled in (NameSheet embedded: the same rules, suggestions
##         and on-device saving); Back returns to the look with both drafts
##         kept; Enter the dorm saves the look and finishes setup (the only
##         way onboarding is marked done).
## The full Locker (every category, looks, albums, shop links) is for later.
const SETUP_GROUPS := [
	["outfit", "Outfit", ["outfit"]],
	["colors", "Color", ["color"]],
	["skin", "Skin", ["skin"]],
	["hair", "Hair", ["hair", "hair_color"]],
]
const SETUP_TITLES := {"outfit": "Outfit", "color": "Main color", "trim": "Trim", "skin": "Skin tone",
	"hair": "Hairstyle", "hair_color": "Hair color"}
var setup_group := "outfit"
var _seg_btns: Dictionary = {}
var _seg_boxes: Dictionary = {}
var _seg_row: Control


func _setup_section(f: String) -> Control:
	var sec := UIKit.vbox(UIKit.SP_S)
	sec.name = "Section_" + f
	var hdr := UIKit.hbox(10)
	hdr.add_child(UIKit.styled(String(SETUP_TITLES[f]), "overline", UIKit.IVORY_MUTED))
	var pk := UIKit.styled("", "caption", UIKit.IVORY)
	_picked[f] = pk
	hdr.add_child(pk)
	sec.add_child(hdr)
	if f in SWATCH_FIELDS:
		var sw := _swatches(f)
		sw.add_theme_constant_override("h_separation", 8)
		sw.add_theme_constant_override("v_separation", 8)
		for b in sw.get_children():
			(b as Control).custom_minimum_size = Vector2.ONE * maxf(UIKit.touch_min(), 56.0)
		sec.add_child(sw)
	elif f == "outfit":
		# two outfits: the pattern sits beside them, not under them
		var row := UIKit.hbox(UIKit.SP_L)
		row.add_child(_setup_cards(f))
		row.add_child(_pattern_chips())
		sec.add_child(row)
	else:
		sec.add_child(_setup_cards(f))
	return sec


func _select_group(g: String) -> void:
	setup_group = g
	for k in _seg_btns:
		UIKit.set_selected(_seg_btns[k], k == g)
	for k in _seg_boxes:
		(_seg_boxes[k] as Control).visible = k == g
	if is_instance_valid(scroll):
		scroll.scroll_vertical = 0
	if is_inside_tree() and is_instance_valid(body):
		UIKit.fade_in(_seg_boxes[g], UIKit.T_FAST)


func _step_group(d: int) -> void:
	var keys: Array = SETUP_GROUPS.map(func(t: Array) -> String: return String(t[0]))
	_select_group(String(keys[wrapi(keys.find(setup_group) + d, 0, keys.size())]))
	UIKit.soft_focus(_seg_btns[setup_group] as Button)


func _build_setup() -> void:
	var mid := UIKit.hbox(UIKit.SP_L)
	mid.name = "Setup"
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	var stage_area := StageDrag.new()
	stage_area.name = "RunnerArea"
	_stage_area = stage_area
	stage_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_area.size_flags_stretch_ratio = 0.7
	stage_area.creator = self
	mid.add_child(stage_area)
	_turn_chip = UIKit.chip("Drag to turn", Color(UIKit.NAVY, 0.6), UIKit.IVORY_MUTED, 18)
	_turn_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_area.add_child(_turn_chip)
	stage_area.resized.connect(func() -> void:
		_turn_chip.position = Vector2(0, stage_area.size.y - _turn_chip.get_combined_minimum_size().y))

	setup_panel = UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, UIKit.PAD_PANEL + 8)
	setup_panel.name = "SetupPanel"
	setup_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_panel.size_flags_stretch_ratio = 1.0
	setup_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(setup_panel)
	panel = setup_panel
	var pvb := UIKit.vbox(UIKit.SP_M)
	setup_panel.add_child(pvb)
	var head := UIKit.vbox(2)
	_step_l = UIKit.styled("Step 1 of 2", "overline", UIKit.AMBER)
	head.add_child(_step_l)
	_title_l = UIKit.styled("What does my runner look like?", "headline")
	_title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title_l)
	pvb.add_child(head)

	# step 1: the look
	scroll = UIKit.scroll_area()
	scroll.name = "Look"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_look_box = scroll
	pvb.add_child(scroll)
	body = UIKit.vbox(UIKit.SP_M)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	# one of three small groups at a time, so everything fits a phone
	var seg := UIKit.hbox(UIKit.SP_S)
	seg.name = "Groups"
	_seg_btns.clear()
	_seg_boxes.clear()
	for g in SETUP_GROUPS:
		var gb := UIKit.secondary(String(g[1]), Vector2(0, UIKit.row_h()), UIKit.T_CAPTION + 1)
		gb.name = "Group_" + String(g[0])
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gb.pressed.connect(_select_group.bind(String(g[0])))
		seg.add_child(gb)
		_seg_btns[String(g[0])] = gb
		var box := UIKit.vbox(UIKit.SP_M)
		box.name = "Group_" + String(g[0]) + "_Items"
		for f in g[2]:
			box.add_child(_setup_section(String(f)))
		body.add_child(box)
		_seg_boxes[String(g[0])] = box
	pvb.add_child(seg)
	pvb.move_child(seg, pvb.get_child_count() - 2)   # above the list
	_seg_row = seg
	_select_group("outfit")

	# step 2: the name (the same runner stays in view)
	name_form = NameSheet.new()
	name_form.embed("", "Enter the dorm", "Back")
	name_form.title_l.visible = false
	name_form.name = "NameStep"
	name_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_form.visible = false
	name_form.done.connect(func(n: String) -> void:
		if n != "":
			_finish_setup())
	name_form.back_requested.connect(show_look_step)
	_name_box = name_form
	pvb.add_child(name_form)

	# the look step's actions
	var foot := UIKit.hbox(UIKit.SP_M)
	foot.name = "SetupFooter"
	_setup_footer = foot
	surprise_btn = UIKit.quiet("Surprise me", Vector2(maxf(170.0, UIKit.row_h() * 2.0), UIKit.row_h()))
	surprise_btn.name = "SurpriseMe"
	surprise_btn.pressed.connect(func() -> void:
		_on_cancel()
		var v := App.stage.local_character() if App.stage else null
		if v and not UIKit.reduced_motion():
			v.play_arrive()
		Sfx.play("equip")
		Haptics.tick())
	foot.add_child(surprise_btn)
	continue_btn = UIKit.primary("Continue", Vector2(maxf(220.0, UIKit.row_h() * 2.6), UIKit.row_h()), 26)
	continue_btn.name = "Continue"
	continue_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_btn.pressed.connect(show_name_step)
	foot.add_child(continue_btn)
	pvb.add_child(foot)

	back_action = func() -> void:
		if setup_step == "name":
			show_look_step()
	focus_first(continue_btn)
	_setup_refresh()
	_stage_area.resized.connect(_frame_stage)
	get_viewport().size_changed.connect(_frame_stage)
	_frame_stage.call_deferred()
	var lc := App.stage.local_character() if App.stage else null
	_yaw = lc.rotation.y if lc else 0.0
	if await_reveal:
		# behind the film: the runner is framed and lit, the controls wait
		setup_panel.modulate.a = 0.0
		_turn_chip.modulate.a = 0.0
		_blocker = Control.new()
		_blocker.name = "RevealBlocker"
		_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
		_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_blocker)
	else:
		UIKit.fade_in(setup_panel)


## The film has faded onto the runner: the controls come in a beat later.
func reveal_after_film(fade_s: float) -> void:
	if not await_reveal:
		return
	await_reveal = false
	var tree := get_tree()
	await tree.create_timer(fade_s + (0.12 if UIKit.reduced_motion() else 0.35)).timeout
	if not is_inside_tree():
		return
	if is_instance_valid(_blocker):
		_blocker.queue_free()
	if UIKit.reduced_motion():
		Motion.animate(setup_panel, "modulate:a", 1.0, 0.18)
		Motion.animate(_turn_chip, "modulate:a", 1.0, 0.18)
	else:
		Motion.settle_in(setup_panel, 0.32)
		Motion.animate(_turn_chip, "modulate:a", 1.0, 0.4, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.25)
	if Controls.device != "touch":
		UIKit.soft_focus(continue_btn)


## The starter cards for a field: everything owned, in one row.
func _setup_cards(f: String) -> Control:
	var keys := shown_keys(f)
	var g := GridContainer.new()
	g.name = "Grid_" + f
	g.add_theme_constant_override("h_separation", int(CARD_GAP))
	g.add_theme_constant_override("v_separation", int(CARD_GAP))
	var cols := 4 if f == "hair" else keys.size()
	g.columns = cols
	var w := 104.0 if f == "hair" else 128.0
	for k in keys:
		var card := ItemCard.new()
		card.setup(self, f, String(k), w, String(THUMB_FRAMING.get(f, "")))
		card.pressed.connect(_pick.bind(f, String(k)))
		g.add_child(card)
		cards.append(card)
	grids.append(g)
	# re-fit the cards to the panel's real width once it is laid out
	g.resized.connect(func() -> void: _fit_setup_grid(g, keys.size()))
	return g


func _fit_setup_grid(g: GridContainer, n: int) -> void:
	var avail := scroll.size.x - 4.0 if is_instance_valid(scroll) and scroll.size.x > 2.0 else 0.0
	if avail < 2.0 or g.get_child_count() == 0:
		return
	var cols := g.columns
	if g.name == "Grid_outfit":
		avail -= maxf(140.0, UIKit.touch_min() * 1.7) + UIKit.SP_L
	var w := clampf(UIKit.cell_width(avail, cols, CARD_GAP), 84.0, 132.0 if g.name == "Grid_outfit" else 120.0)
	for c in g.get_children():
		var ic := c as ItemCard
		if ic and absf(ic.custom_minimum_size.x - w) > 1.0:
			ic.fit_cell(w, ic.name_lines(w))


## Pattern for patterned outfits: two small chips under the outfits.
func _pattern_chips() -> Control:
	var row := UIKit.vbox(UIKit.SP_S)
	row.name = "Patterns"
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pattern_row = row
	row.add_child(UIKit.styled("Pattern", "overline", UIKit.IVORY_MUTED))
	_pattern_btns.clear()
	for k in shown_keys("pattern"):
		var b := UIKit.secondary(String(Cosmetics.entry("pattern", String(k))["name"]), Vector2(maxf(140.0, UIKit.touch_min() * 1.7), UIKit.touch_min()), UIKit.T_CAPTION)
		b.name = "Pattern_" + String(k)
		b.pressed.connect(_pick.bind("pattern", String(k)))
		row.add_child(b)
		_pattern_btns[String(k)] = b
	return row


func _setup_refresh() -> void:
	for c in cards:
		c.refresh()
	for sw in swatches:
		_paint_swatch(sw)
	for f in _picked:
		(_picked[f] as Label).text = "·  %s" % Cosmetics.entry(f, String(draft[f]))["name"]
	for k in _pattern_btns:
		UIKit.set_selected(_pattern_btns[k], String(draft["pattern"]) == String(k))
	if is_instance_valid(_pattern_row):
		_pattern_row.visible = String(draft["outfit"]) in Cosmetics.PATTERNED_OUTFITS


func show_name_step() -> void:
	if setup_step == "name" or _finishing:
		return
	setup_step = "name"
	_step_l.text = "Step 2 of 2"
	_title_l.text = "What should we call you?"
	_look_box.visible = false
	_seg_row.visible = false
	setup_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_setup_footer.visible = false
	name_form.visible = true
	name_form._on_text(name_form.field.text)
	UIKit.fade_in(name_form, UIKit.T_FAST)
	Sfx.play("click")
	if Controls.device != "touch":
		UIKit.soft_focus(name_form.save_btn)


func show_look_step() -> void:
	if setup_step == "look" or _finishing:
		return
	setup_step = "look"
	name_form.field.release_focus()
	DisplayServer.virtual_keyboard_hide()
	_step_l.text = "Step 1 of 2"
	_title_l.text = "What does my runner look like?"
	name_form.visible = false
	_look_box.visible = true
	_seg_row.visible = true
	setup_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_footer.visible = true
	UIKit.fade_in(_look_box, UIKit.T_FAST)
	if Controls.device != "touch":
		UIKit.soft_focus(continue_btn)


## Enter the dorm: the look is saved and setup is finished (the name was
## saved on this device by the name step).  The only way out of setup.
func _finish_setup() -> void:
	if _finishing:
		return
	_finishing = true
	DisplayServer.virtual_keyboard_hide()
	var r := Save.apply_appearance(draft)
	if not bool(r["ok"]):
		Save.apply_appearance(Cosmetics.DEFAULT.duplicate())
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	Diag.mark("setup_finished")
	Save.save_now()
	App.sync_stage_local()
	if on_done.is_valid():
		on_done.call()


## While the name field has the keyboard up, the screen's bottom margin
## follows the keyboard, so the field and Enter the dorm stay above it
## (small landscape phones give the keyboard about half the height) and the
## runner reframes into the space left.
func _keyboard_fit() -> void:
	if not first_run or not is_instance_valid(name_form) or not is_inside_tree():
		return
	# (build 30) only where there is an on-screen keyboard (desktop logged a
	# warning every frame)
	var kh := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	if kh <= 0.0 and OS.get_cmdline_user_args().has("--sim-keyboard") and name_form.visible and name_form.field.has_focus():
		kh = float(DisplayServer.window_get_size().y) * 0.52   # dev captures: an iPhone's landscape keyboard
	var vs := get_viewport().get_visible_rect().size
	var units := roundf(kh * vs.y / maxf(1.0, float(DisplayServer.window_get_size().y)))
	var want := int(UIKit.safe_margins(get_viewport()).size.y) + UIKit.EDGE_Y
	if units > 0.0:
		want = int(units) + UIKit.SP_S
	if margin.get_theme_constant("margin_bottom") != want:
		margin.add_theme_constant_override("margin_bottom", want)
		name_form.sub_l.visible = units <= 0.0 or vs.y - units > 440.0


# ------------------------------------------------------------------ looks
## (2.2 build 18) the dice and three saved looks: tap an empty slot to keep
## the look on show there, tap a kept one to try it on (then Save look),
## hold it to replace it with the look on show.
const LOOK_SLOTS := 3
const LOOK_FIELDS := ["outfit", "pattern", "color", "trim", "hat", "shoes", "hair_color"]
var look_btns: Array = []


func _looks_row() -> Control:
	var row := UIKit.hbox(8)
	row.name = "Looks"
	var lt := UIKit.styled("Looks", "overline", UIKit.IVORY_MUTED)
	lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lt)
	row.add_child(UIKit.spacer_h())
	var dice := UIKit.icon_button("dice")
	dice.name = "RandomLook"
	dice.tooltip_text = "Random look"
	dice.accessibility_name = "Random look from your items"
	dice.pressed.connect(random_look)
	row.add_child(dice)
	look_btns.clear()
	for i in LOOK_SLOTS:
		var b := UIKit.quiet(str(i + 1), Vector2(UIKit.touch_min(), UIKit.touch_min()))
		b.name = "Look%d" % (i + 1)
		var idx := i
		b.button_down.connect(func() -> void: b.set_meta(&"down_ms", Time.get_ticks_msec()))
		b.pressed.connect(func() -> void:
			var held := Time.get_ticks_msec() - int(b.get_meta(&"down_ms", Time.get_ticks_msec())) >= 600
			look_slot(idx, held))
		row.add_child(b)
		look_btns.append(b)
	_paint_looks()
	return row


static func saved_looks() -> Array:
	var l: Array = (Save.get_setting("saved_looks", []) as Array).duplicate()
	while l.size() < LOOK_SLOTS:
		l.append({})
	return l


func _paint_looks() -> void:
	var l := CreatorScreen.saved_looks()
	for i in look_btns.size():
		var b: Button = look_btns[i]
		var filled := not (l[i] as Dictionary).is_empty()
		UIKit.face_of(b).fg = {"normal": UIKit.AMBER if filled else UIKit.IVORY_MUTED}
		UIKit.face_of(b).queue_redraw()
		b.accessibility_name = ("Look %d: try it on (hold to replace)" if filled else "Look %d: empty, tap to keep this look") % (i + 1)


## A random look from the items you own (your face and hair stay).
func random_look() -> void:
	var d := draft.duplicate()
	for f in LOOK_FIELDS:
		var owned: Array = Cosmetics.keys_of(f).filter(func(k: Variant) -> bool: return Wallet.owns(f, String(k)))
		if not owned.is_empty():
			d[f] = String(owned[randi() % owned.size()])
	_show_draft(Cosmetics.sanitize(d))
	Sfx.play("equip")
	Haptics.tick()


func look_slot(i: int, replace: bool) -> void:
	var l := CreatorScreen.saved_looks()
	var have: Dictionary = l[i]
	if have.is_empty() or replace:
		var keep := {}
		for f in LOOK_FIELDS:
			keep[f] = String(draft.get(f, Cosmetics.DEFAULT.get(f, "")))
		l[i] = keep
		Save.set_setting("saved_looks", l)
		UIKit.toast(self, "Look %d kept" % (i + 1), 1.4)
		Sfx.play("pop")
	else:
		var d := draft.duplicate()
		for f in have:
			if Wallet.owns(String(f), String(have[f])):
				d[String(f)] = String(have[f])
		_show_draft(Cosmetics.sanitize(d))
		UIKit.toast(self, "Look %d" % (i + 1), 1.2)
		Sfx.play("equip")
	Haptics.tick()
	_paint_looks()


func _show_draft(d: Dictionary) -> void:
	draft = d
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, draft)
		if not UIKit.reduced_motion():
			v.play_arrive()
	_refresh()


func _on_cancel() -> void:
	if first_run:
		var r := Cosmetics.bot_cosmetic(randi())
		# only owned (free) items for a random start
		for f in Cosmetics.ORDER:
			if not Wallet.owns(f, String(r[f])):
				r[f] = Cosmetics.DEFAULT[f]
		draft = Cosmetics.sanitize(r)
		var v := App.stage.local_character() if App.stage else null
		if v:
			v.set_appearance(TC.Role.RUNNER, draft)
		_refresh()
		return
	draft = saved.duplicate()
	draft_style = saved_style.duplicate()
	App.sync_stage_local()
	var v2 := App.stage.local_character() if App.stage else null
	if v2:
		v2.set_appearance(TC.Role.RUNNER, saved)
	_refresh()


func _back() -> void:
	confirm_leave(_leave)


## NavShell and Back: unsaved changes ask first; `go` runs after leaving.
func confirm_leave(go: Callable) -> void:
	if changed() and not first_run:
		dialog("Leave without saving your new look?", [["Keep editing", Callable()], ["Leave", func() -> void:
			_restore_stage()
			go.call()]])
		return
	_restore_stage()
	go.call()


func _restore_stage() -> void:
	Portraits.cancel_shared("tile:")
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, saved)


func _leave() -> void:
	Portraits.cancel_shared("tile:")
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
	Portraits.cancel_shared("tile:")


## Left area: drag horizontally to turn the runner.
## V6: one pointer owns the turn - the finger that went down first (touch
## index).  V5 listened to every touch and mouse event, so a second finger
## took the turn over and made the runner jump (test_stage_drag); mouse
## events (the engine's emulated twin of a finger) are ignored too.  Touch
## events always arrive: natively on iOS, from the mouse on desktop
## (pointing/emulate_touch_from_mouse).
class StageDrag:
	extends Control
	signal turned(dx: float)
	var creator: CreatorScreen
	var _last := -1.0
	var _owner := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			var st := e as InputEventScreenTouch
			if st.pressed and _owner < 0:
				_owner = st.index
				_last = st.position.x
			elif not st.pressed and st.index == _owner:
				release()
			else:
				return
			if creator:
				creator._drag_from = _last
		elif e is InputEventScreenDrag and (e as InputEventScreenDrag).index == _owner and _last >= 0.0:
			var d := e as InputEventScreenDrag
			var dx := d.position.x - _last
			_last = d.position.x
			turned.emit(dx)
			if creator:
				creator.drag_turn(dx)

	## Lifted, cancelled, or the screen lost focus.
	func release() -> void:
		_owner = -1
		_last = -1.0
		if creator:
			creator._drag_from = -1.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
				or what == NOTIFICATION_VISIBILITY_CHANGED:
			release()


## One card layout for every Locker item (V7): a picture well, the name
## (the grid's line count, so every card's state row lines up) and a state
## row ("Equipped"), with PAD on every side.  The well's height is a share of
## the card's width per content type (WELL).  The selected card has the teal
## edge and a check in its corner: one ring, never two.
static func name_line_h() -> float:
	return UIKit.font_w(600).get_height(NAME_FS) - 2.0


## Height of a name set in `n` lines (the label's own line height and its
## -2 line spacing between lines), so every card's state row lines up.
static func name_block_h(n: int) -> float:
	return ceilf(float(n) * UIKit.font_w(600).get_height(NAME_FS) - 2.0 * float(maxi(n - 1, 0)))


static func card_height(kind: String, w: float, lines: int) -> float:
	var well := roundf((w - PAD * 2.0) * float(WELL.get(kind, 1.0)))
	return PAD + well + ROW_GAP + name_block_h(lines) + ROW_GAP + STATE_H + PAD


## The card's column: well, name, state.
static func card_column(face: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(ROW_GAP))
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = PAD
	v.offset_right = -PAD
	v.offset_top = PAD
	v.offset_bottom = -PAD
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(v)
	return v


static func name_label(t: String) -> Label:
	var l := UIKit.styled(t, "label", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", -2)
	l.add_theme_font_size_override("font_size", NAME_FS)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func state_label() -> Label:
	var l := UIKit.styled("", "overline", UIKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size.y = STATE_H
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## An item card: the item's picture on your look (a cached portrait, framed
## for its type), or the emote's glyph centred in its well; the full name;
## the state row.
class ItemCard:
	extends Button
	var creator: CreatorScreen
	var field := ""
	var key := ""
	var framing := ""
	var kind := ""
	var pic: TextureRect
	var glyph: Icons.IconRect
	var holder: Control
	var name_l: Label
	var state_l: Label
	var check: Control
	var pic_key := ""
	var has_pic := false
	var lines := 1

	func setup(c: CreatorScreen, f: String, k: String, w: float, fr: String) -> void:
		creator = c
		field = f
		key = k
		framing = fr
		kind = fr if fr != "" else "emote"
		name = "Item_%s_%s" % [f, k]
		var it: Dictionary = Cosmetics.entry(f, k)
		UIKit.make_card(self, Vector2(w, 0), Color(UIKit.SLATE_HI, 0.96))
		var v := CreatorScreen.card_column(UIKit.face_of(self))
		holder = PicHolder.new()
		holder.name = "Well"
		holder.size_flags_horizontal = Control.SIZE_FILL
		v.add_child(holder)
		if fr != "":
			pic = TextureRect.new()
			pic.name = "Picture"
			pic.set_anchors_preset(Control.PRESET_FULL_RECT)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			# cover the well (the portrait is square; body wells are a little
			# taller, close-ups a little wider): no letterbox bars
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(pic)
		else:
			# centred by anchors in the well, inset on every side (V6: a
			# centre anchor plus a positive position pushed it past the corner)
			var id := TC.EMOTES.find(k)
			glyph = Icons.IconRect.new(Icons.emote_icon(id) if id >= 0 else "smile", UIKit.AMBER, 8.0)
			glyph.name = "Glyph"
			glyph.custom_minimum_size = Vector2.ZERO
			glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
			glyph.offset_left = PicHolder.INSET
			glyph.offset_top = PicHolder.INSET
			glyph.offset_right = -PicHolder.INSET
			glyph.offset_bottom = -PicHolder.INSET
			holder.add_child(glyph)
			(holder as PicHolder).placeholder = false
		name_l = CreatorScreen.name_label(String(it["name"]))
		v.add_child(name_l)
		state_l = CreatorScreen.state_label()
		v.add_child(state_l)
		check = CheckBadge.new()
		UIKit.face_of(self).add_child(check)
		fit_cell(w, name_lines(w))

	func name_lines(w: float) -> int:
		return mini(2, UIKit.lines_for(name_l.text, UIKit.font_w(600), NAME_FS, w - PAD * 2.0))

	## Lay the card out for a cell `w` wide with `n` name lines.
	func fit_cell(w: float, n: int) -> void:
		lines = n
		var iw := w - PAD * 2.0
		holder.custom_minimum_size = Vector2(0, roundf(iw * float(WELL.get(kind, 1.0))))
		name_l.custom_minimum_size = Vector2(iw, CreatorScreen.name_block_h(n))
		name_l.max_lines_visible = n
		custom_minimum_size = Vector2(w, CreatorScreen.card_height(kind, w, n))
		check.position = Vector2(w - PAD - check.size.x - 2.0, PAD + 2.0)

	func refresh() -> void:
		var st: Dictionary = creator.state_of(field, key)
		var it: Dictionary = Cosmetics.entry(field, key)
		state_l.text = "Equipped" if bool(st["equipped"]) and not creator.first_run else ""
		var sel: bool = String(creator.draft[field]) == key
		if field == "emote":
			# (2.2 build 17) which slot it is in; selected = in the slot being chosen
			state_l.text = String(st["text"]) if bool(st["equipped"]) else ""
			var ks := EmoteSlots.keys()
			sel = creator._emote_slot < ks.size() and String(ks[creator._emote_slot]) == key
		UIKit.set_selected(self, sel)
		check.visible = sel
		accessibility_name = "%s, %s%s" % [it["name"], st["text"], ", selected" if sel else ""]
		if framing != "":
			_request()

	## The item on the draft's look with neutral accessories, in this
	## card's framing (CommerceArt.preview_look).
	func _request() -> void:
		var app: Dictionary = CommerceArt.preview_look(creator.draft, field, key)
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


## A name card or badge in the Locker's Profile category ("" = none), drawn
## as it appears when equipped: the card with the player's name and the
## chosen badge.  Same layout as ItemCard.
class ProfileCard:
	extends Button
	var creator: CreatorScreen
	var field := ""
	var key := ""
	var kind := ""
	var pic_key := ""
	var holder: Control
	var art: Control
	var name_l: Label
	var state_l: Label
	var check: Control
	var lines := 1

	func setup(c: CreatorScreen, f: String, id: String, w: float) -> void:
		creator = c
		field = f
		key = id
		kind = "card" if f == "card" else "badge"
		name = "Profile_%s_%s" % [f, id.replace(":", "_")]
		UIKit.make_card(self, Vector2(w, 0), Color(UIKit.SLATE_HI, 0.96))
		var v := CreatorScreen.card_column(UIKit.face_of(self))
		holder = PicHolder.new()
		holder.name = "Well"
		(holder as PicHolder).placeholder = false
		v.add_child(holder)
		if id == "":
			art = CommerceArt.Pic.new("glyph", "close", UIKit.IVORY_DIM, 8.0)
		elif f == "card":
			art = CommerceArt.Pic.new("card", id, Color.WHITE, 8.0)
			(art as CommerceArt.Pic).text = Save.player_name()
		else:
			art = CommerceArt.Pic.new("badge", id, Color.WHITE, 8.0)
		art.name = "Art"
		art.custom_minimum_size = Vector2.ZERO
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		var inset := PicHolder.INSET if id == "" or f == "badge" else PicHolder.INSET * 0.5
		art.offset_left = inset
		art.offset_top = inset
		art.offset_right = -inset
		art.offset_bottom = -inset
		holder.add_child(art)
		name_l = CreatorScreen.name_label("None" if id == "" else Catalogue.display_name(id))
		v.add_child(name_l)
		state_l = CreatorScreen.state_label()
		v.add_child(state_l)
		check = CheckBadge.new()
		UIKit.face_of(self).add_child(check)
		fit_cell(w, name_lines(w))

	func name_lines(w: float) -> int:
		return mini(2, UIKit.lines_for(name_l.text, UIKit.font_w(600), NAME_FS, w - PAD * 2.0))

	func fit_cell(w: float, n: int) -> void:
		lines = n
		var iw := w - PAD * 2.0
		holder.custom_minimum_size = Vector2(0, roundf(iw * float(WELL.get(kind, 1.0))))
		name_l.custom_minimum_size = Vector2(iw, CreatorScreen.name_block_h(n))
		name_l.max_lines_visible = n
		custom_minimum_size = Vector2(w, CreatorScreen.card_height(kind, w, n))
		check.position = Vector2(w - PAD - check.size.x - 2.0, PAD + 2.0)

	func refresh() -> void:
		var st: Dictionary = creator.state_of(field, key)
		state_l.text = "Equipped" if bool(st["equipped"]) else ""
		var sel: bool = String(creator.draft_style.get(field, "")) == key
		UIKit.set_selected(self, sel)
		check.visible = sel
		if art is CommerceArt.Pic and field == "card":
			(art as CommerceArt.Pic).badge_id = String(creator.draft_style.get("badge", ""))
			art.queue_redraw()
		accessibility_name = "%s %s, %s%s" % [name_l.text, "name card" if field == "card" else "badge", st["text"], ", selected" if sel else ""]


## The picture's well: a soft rounded backdrop, and until the picture is
## ready a faint runner silhouette (no spinning or pulsing).  Its children
## fill it (anchors), so art is centred by construction.
class PicHolder:
	extends Control
	const INSET := 8.0
	var placeholder := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

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
		size = Vector2(26, 26)

	func _draw() -> void:
		draw_circle(size * 0.5, 13.0, UIKit.TEAL, true, -1.0, true)
		draw_arc(size * 0.5, 13.0, 0, TAU, 24, Color(UIKit.NAVY, 0.6), 1.5, true)
		Icons.draw_shape(self, "check", size * 0.5, 8.0, UIKit.NAVY)


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
