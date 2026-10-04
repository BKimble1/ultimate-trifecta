class_name UIKit
extends RefCounted
## Shared look for menus and HUD (V5).
##
## Type: Manrope (SIL OFL), a clean geometric sans with real Medium /
## SemiBold / Bold / ExtraBold instances (tools/fonts/make_manrope.py) and
## tabular digits for timers and counters.  Expressive lettering lives only in
## the game title graphic (Brand).  Scale, in canvas units of a 720-unit-high
## screen (an iPhone in landscape is ~1.85 units per point):
##   display 44 ExtraBold · title 34 Bold · headline 27 Bold · body 23 Medium
##   label 22 SemiBold · caption 20 Medium · overline 17 Bold, tracked
##
## Palette: deep navy #0C1324 (the startup background), card surfaces
## #1B2740 / #26355A, warm ivory text, gold #FFC65C for the one primary
## action, teal #5FD6C8 for selection, readiness and progress.
##
## Controls are cards with restrained corner radii, a thin upper highlight
## and a soft shadow (no heavy lower lip).  Every pressable is a Button that
## stays still as the hit region and layout box; its look is drawn by a
## child Face, and only the Face scales on press (Motion), so containers
## never fight the animation and the touch target never moves.  Focus is a
## distinct teal ring outside the control.  Disabled controls stay solid
## and readable with muted text (they don't fade like a broken control).
## Every tappable control is at least 44 pt (touch_min()).

const FONT_FILES := {
	500: "res://assets/fonts/Manrope-Medium.ttf",
	600: "res://assets/fonts/Manrope-SemiBold.ttf",
	700: "res://assets/fonts/Manrope-Bold.ttf",
	800: "res://assets/fonts/Manrope-ExtraBold.ttf",
}

const NAVY := Color("0c1324")
const SLATE := Color("1b2740")
const SLATE_HI := Color("26355a")
const SLATE_LO := Color("131c30")
const IVORY := Color("f6f3ec")
const AMBER := Color("ffc65c")
const AMBER_HI := Color("ffe0a3")
const TEAL := Color("5fd6c8")
const IVORY_MUTED := Color(0.965, 0.953, 0.925, 0.7)
const IVORY_DIM := Color(0.965, 0.953, 0.925, 0.5)
const DISABLED_BG := Color("2a3247")

# legacy names used across the HUD/screens, mapped onto the palette
const INK := NAVY
const PANEL := Color(0.106, 0.153, 0.251, 0.96)
const PANEL_LIGHT := SLATE_HI
const ACCENT := AMBER
const RUNNER := TEAL
const PATROL := Color("ffa05c")
const GOOD := Color("7fe0a4")
const BAD := Color("ff7a7a")
const TEXT := IVORY
const MUTED := Color("b9bdc8")

# type scale
const T_DISPLAY := 44
const T_TITLE := 34
const T_HEADLINE := 27
const T_BODY := 23
const T_LABEL := 22
const T_CAPTION := 20
const T_OVERLINE := 17

const R_SMALL := 12
const R_BUTTON := 16
const R_CARD := 18
const R_PANEL := 22
const T_FAST := Motion.FAST
const T_SHEET := Motion.PANEL
## V4 buttons had a 6-unit dark lower lip; kept as 0 for old layout maths.
const LIP := 0

static var _theme: Theme
static var _fonts: Dictionary = {}
static var _num_fonts: Dictionary = {}
static var _overline_font: FontVariation


## weight: 500 body, 600 labels/buttons, 700 headings, 800 display/numbers.
## Other values snap to the nearest shipped instance.
static func font_w(weight: int) -> Font:
	var w := 500 if weight < 550 else (600 if weight < 675 else (700 if weight < 760 else 800))
	if not _fonts.has(w):
		_fonts[w] = load(FONT_FILES[w])
	return _fonts[w]


static func font(bold: bool = false) -> Font:
	return font_w(600 if bold else 500)


## The same weight with tabular (fixed-width) digits: timers and counters
## don't jitter as their digits change.
static func font_num(weight: int = 700) -> Font:
	var base := font_w(weight)
	if not _num_fonts.has(base):
		var fv := FontVariation.new()
		fv.base_font = base
		fv.opentype_features = {"tnum": 1}
		_num_fonts[base] = fv
	return _num_fonts[base]


## Small tracked capitals for section overlines.
static func font_overline() -> Font:
	if _overline_font == null:
		_overline_font = FontVariation.new()
		_overline_font.base_font = font_w(700)
		_overline_font.spacing_glyph = 2
	return _overline_font


## 44 pt in canvas units on this device (phones in landscape: ~81 units).
static func touch_min() -> float:
	var vp := Engine.get_main_loop().root as Window if Engine.get_main_loop() is SceneTree else null
	var scale := DisplayServer.screen_get_scale()
	if vp == null:
		return 64.0
	var canvas_to_px := vp.get_final_transform().get_scale().y
	if canvas_to_px <= 0.0:
		return 64.0
	if OS.has_feature("mobile") or emulate_phone():
		# 44 pt at the device's point scale (@3x phones, or the emulated scale)
		return clampf(44.0 * (maxf(scale, 2.0) if OS.has_feature("mobile") else emulated_point_scale()) / canvas_to_px, 44.0, 96.0)
	return clampf(44.0 * scale / canvas_to_px, 44.0, 64.0)


## Desktop evidence runs at device resolution can pass --emulate-phone so
## touch-size rules match an @3x iPhone (--emulate-phone=2 for @2x devices:
## iPhone SE, iPad).
static func emulate_phone() -> bool:
	return emulated_point_scale() > 0.0


static func emulated_point_scale() -> float:
	if emulation.has("scale"):
		return float(emulation["scale"])
	for a in OS.get_cmdline_user_args():
		if a == "--emulate-phone":
			return 3.0
		if a.begins_with("--emulate-phone="):
			return clampf(a.get_slice("=", 1).to_float(), 1.0, 3.0)
	return 0.0


static func reduced_motion() -> bool:
	return bool(Save.get_setting("reduced_motion", false))


# ---------------------------------------------------------------------------
# Style boxes
# ---------------------------------------------------------------------------
static func box(col: Color, radius: int = R_BUTTON, border: int = 0, border_col: Color = Color.WHITE, pad: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.5
	s.content_margin_bottom = pad * 0.5
	s.anti_aliasing = true
	s.corner_detail = 10
	return s


## A raised card surface: a thin lighter rim along the top edge, a soft
## shadow underneath.  `lift` 0 = flat (pressed), 1 = resting.
static func card_box(bg: Color, radius: int = R_CARD, lift: float = 1.0, pad: int = 16, rim: float = 0.1) -> StyleBoxFlat:
	var s := box(bg, radius, 0, Color.WHITE, pad)
	if rim > 0.0 and bg.a > 0.5:
		s.border_width_top = 2 if lift > 0.0 else 1
		s.border_color = Color(bg.lightened(0.35), clampf(rim * 2.2, 0.0, 1.0) * bg.a) if bg.get_luminance() > 0.5 else Color(1, 1, 1, rim * bg.a)
	if lift > 0.0 and bg.a > 0.5:
		s.shadow_color = Color(0.0, 0.02, 0.06, 0.32 * lift)
		s.shadow_size = int(10.0 * lift)
		s.shadow_offset = Vector2(0, 4.0 * lift)
	return s


## Focus ring: drawn just outside the control, never covering its content.
static func focus_ring(radius: int = R_BUTTON, col: Color = TEAL) -> StyleBoxFlat:
	var s := box(Color(0, 0, 0, 0), radius + 5, 3, col, 0)
	s.draw_center = false
	s.expand_margin_left = 5
	s.expand_margin_right = 5
	s.expand_margin_top = 5
	s.expand_margin_bottom = 5
	return s


## Legacy name (V3/V4 lip box): now the raised card surface.
static func depth_box(bg: Color, pressed: bool = false, radius: int = R_BUTTON) -> StyleBoxFlat:
	return card_box(bg, radius, 0.0 if pressed else 1.0)


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font_w(500)
	t.default_font_size = T_BODY
	t.set_color("font_color", "Label", IVORY)
	t.set_color("font_outline_color", "Label", NAVY)
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 2)
	t.set_font("font", "Button", font_w(600))
	t.set_font_size("font_size", "Button", T_LABEL + 2)
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(st, "Button", card_box(SLATE_HI, R_BUTTON, 0.0 if st == "pressed" else 1.0))
	t.set_stylebox("focus", "Button", focus_ring())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "Button", IVORY)
	t.set_color("font_disabled_color", "Button", IVORY_DIM)
	t.set_stylebox("panel", "PanelContainer", card_box(PANEL, R_PANEL, 1.0, 22))
	t.set_stylebox("panel", "Panel", card_box(PANEL, R_PANEL))
	t.set_stylebox("normal", "LineEdit", box(SLATE_LO, R_SMALL, 2, SLATE_HI, 18))
	t.set_stylebox("focus", "LineEdit", box(SLATE_LO, R_SMALL, 2, TEAL, 18))
	t.set_font("font", "LineEdit", font_w(600))
	t.set_font_size("font_size", "LineEdit", 38)
	t.set_color("font_color", "LineEdit", IVORY)
	t.set_color("font_placeholder_color", "LineEdit", Color(IVORY, 0.35))
	t.set_stylebox("slider", "HSlider", box(SLATE_LO, 8, 0, Color.WHITE, 5))
	t.set_stylebox("grabber_area", "HSlider", box(TEAL, 8, 0, Color.WHITE, 5))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(TEAL.lightened(0.15), 8, 0, Color.WHITE, 5))
	t.set_stylebox("focus", "HSlider", focus_ring(10))
	t.set_font("font", "CheckButton", font_w(600))
	t.set_font_size("font_size", "CheckButton", T_LABEL)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "CheckButton", IVORY)
	t.set_stylebox("focus", "CheckButton", focus_ring(R_SMALL))
	t.set_stylebox("normal", "OptionButton", card_box(SLATE_HI, R_BUTTON))
	t.set_stylebox("hover", "OptionButton", card_box(SLATE_HI.lightened(0.05), R_BUTTON))
	t.set_stylebox("pressed", "OptionButton", card_box(SLATE_HI.darkened(0.06), R_BUTTON, 0.0))
	t.set_stylebox("focus", "OptionButton", focus_ring())
	t.set_font_size("font_size", "OptionButton", T_LABEL)
	t.set_stylebox("panel", "PopupMenu", card_box(SLATE_HI, R_SMALL, 1.0, 10))
	t.set_font_size("font_size", "PopupMenu", T_BODY)
	t.set_stylebox("panel", "TooltipPanel", box(SLATE_HI, 12))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.15), 8, 0, Color.WHITE, 3))
	t.set_stylebox("grabber", "VScrollBar", box(Color(IVORY, 0.3), 8, 0, Color.WHITE, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(IVORY, 0.45), 8, 0, Color.WHITE, 3))
	t.set_stylebox("scroll", "HScrollBar", box(Color(0, 0, 0, 0.0), 8, 0, Color.WHITE, 2))
	t.set_stylebox("grabber", "HScrollBar", box(Color(IVORY, 0.22), 8, 0, Color.WHITE, 2))
	_theme = t
	return t


# ---------------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------------
static func label(t: String, size: int = T_BODY, col: Color = IVORY, bold: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font_w(600))
	l.horizontal_alignment = align
	return l


static func heading(t: String, size: int = T_TITLE, col: Color = IVORY) -> Label:
	var l := label(t, size, col)
	l.add_theme_font_override("font", font_w(700 if size < T_DISPLAY else 800))
	return l


## Styled text from the type scale: "display", "title", "headline", "body",
## "label", "caption", "overline" (upper case, tracked) or "num" (tabular).
static func styled(t: String, style: String = "body", col: Color = IVORY, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	var spec: Array = {
		"display": [T_DISPLAY, 800], "title": [T_TITLE, 700], "headline": [T_HEADLINE, 700], "body": [T_BODY, 500],
		"label": [T_LABEL, 600], "caption": [T_CAPTION, 500], "overline": [T_OVERLINE, -1], "num": [T_LABEL, -2],
	}.get(style, [T_BODY, 500])
	l.add_theme_font_size_override("font_size", int(spec[0]))
	match int(spec[1]):
		-1:
			l.add_theme_font_override("font", font_overline())
			l.uppercase = true
		-2:
			l.add_theme_font_override("font", font_num(700))
		_:
			l.add_theme_font_override("font", font_w(int(spec[1])))
	l.add_theme_color_override("font_color", col)
	l.text = t
	return l


## Text drawn over the 3D world: a thin edge and a soft shadow instead of
## V4's thick outline.  `px` is kept for old callers and caps the edge.
static func outlined(l: Label, px: int = 8) -> Label:
	l.add_theme_constant_override("outline_size", clampi(px / 3, 2, 4))
	l.add_theme_color_override("font_outline_color", Color(NAVY, 0.55))
	l.add_theme_color_override("font_shadow_color", Color(NAVY, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", clampi(px / 2, 3, 6))
	return l


## Keep a name readable: on resize, use the largest of `sizes` at which the
## whole text fits the label's width; only the smallest size trims (and the
## full text stays available on tap).
static func fit_text(l: Label, sizes: Array = [T_LABEL, T_CAPTION, 18]) -> void:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var refit := func() -> void:
		var f: Font = l.get_theme_font("font")
		var w := l.size.x
		if w <= 1.0:
			return
		for fs in sizes:
			if f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x <= w:
				l.add_theme_font_size_override("font_size", int(fs))
				return
		l.add_theme_font_size_override("font_size", int(sizes[-1]))
	l.resized.connect(refit)
	l.set_meta(&"refit", refit)


static func refit(l: Label) -> void:
	if l.has_meta(&"refit"):
		(l.get_meta(&"refit") as Callable).call()


# ---------------------------------------------------------------------------
# Buttons: a still hit region + a Face that draws and animates
# ---------------------------------------------------------------------------
## Legacy signature (colour picks the style): amber = primary, everything
## else becomes a calm surface button.
static func button(t: String, col: Color = SLATE_HI, min_size: Vector2 = Vector2(240, 72), font_size: int = T_LABEL + 2) -> Button:
	if col.is_equal_approx(AMBER) or (col.r > 0.95 and col.g > 0.6 and col.g < 0.85 and col.b < 0.45):
		return primary(t, min_size, font_size + 4)
	var b := _base_button(t, min_size, font_size)
	var bg := SLATE_HI if col.get_luminance() > 0.35 or col.s > 0.35 else col
	if col.is_equal_approx(BAD) or (col.r > 0.55 and col.g < 0.45 and col.b < 0.45):
		bg = Color("5a2f3d")
	_apply(b, bg, IVORY)
	return b


## The screen's one main action: warm gold, navy text.
static func primary(t: String, min_size: Vector2 = Vector2(320, 92), font_size: int = 30) -> Button:
	var b := _base_button(t, min_size, font_size)
	_apply(b, AMBER, NAVY)
	b.add_theme_font_override("font", font_w(800))
	return b


static func secondary(t: String, min_size: Vector2 = Vector2(260, 80), font_size: int = T_LABEL + 2) -> Button:
	var b := _base_button(t, min_size, font_size)
	_apply(b, SLATE_HI, IVORY)
	return b


## Low-emphasis action: a quiet translucent surface with a fine edge.
static func quiet(t: String, min_size: Vector2 = Vector2(220, 72), font_size: int = T_LABEL) -> Button:
	var b := _base_button(t, min_size, font_size)
	var f := face_of(b)
	var n := box(Color(NAVY, 0.62), R_BUTTON, 0, Color.WHITE)
	n.set_border_width_all(2)
	n.border_color = Color(IVORY, 0.16)
	f.styles = {
		"normal": n,
		"hover": _with_bg(n, Color(SLATE, 0.85)),
		"pressed": _with_bg(n, Color(SLATE_LO, 0.95)),
		"disabled": _with_border(_with_bg(n, Color(SLATE_LO, 0.6)), Color(IVORY, 0.08)),
		# a restrained selection: tinted, with a teal edge (never a solid fill)
		"selected": _with_border(_with_bg(n, Color(TEAL.darkened(0.35), 0.45)), TEAL),
	}
	f.fg = {"normal": IVORY, "disabled": IVORY_DIM, "selected": IVORY}
	f.queue_redraw()
	return b


## Square icon button (drawn glyph from Icons) with an optional caption.
static func icon_button(icon: String, caption: String = "", size_units: float = 0.0) -> Button:
	var s := maxf(size_units, touch_min())
	var b := _base_button("", Vector2(s if caption == "" else maxf(s * 2.0, 150.0), s), T_LABEL)
	var f := face_of(b)
	f.styles = {
		"normal": card_box(Color(SLATE, 0.9), R_BUTTON, 1.0, 16, 0.08),
		"hover": card_box(Color(SLATE_HI, 0.95), R_BUTTON, 1.0, 16, 0.1),
		"pressed": card_box(Color(SLATE_LO, 0.95), R_BUTTON, 0.0),
		"disabled": box(Color(SLATE_LO, 0.75), R_BUTTON),
		"selected": card_box(TEAL, R_BUTTON, 1.0),
	}
	f.fg = {"normal": IVORY, "disabled": IVORY_DIM, "selected": NAVY}
	f.icon = icon
	f.caption = caption
	b.tooltip_text = caption
	if caption != "":
		# the caption is drawn by the face; the button's own text only sizes it
		b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, s * 0.95 + font_w(600).get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, T_LABEL).x + 26.0)
	return b


## A large card that holds custom content (item tiles, roster rows, emote
## tiles): add children to face_of(button).  `selected` gives the restrained
## accent edge.
static func card_button(min_size: Vector2, bg: Color = SLATE) -> Button:
	return make_card(Button.new(), min_size, bg)


## Turn an existing Button (or a Button subclass) into a card.
static func make_card(b: Button, min_size: Vector2, bg: Color = SLATE) -> Button:
	adopt(b, "", min_size, T_LABEL)
	var f := face_of(b)
	var sel := card_box(bg.lightened(0.04), R_CARD, 1.0)
	sel.set_border_width_all(3)
	sel.border_color = TEAL
	f.styles = {
		"normal": card_box(bg, R_CARD, 1.0),
		"hover": card_box(bg.lightened(0.05), R_CARD, 1.0),
		"pressed": card_box(bg.darkened(0.08), R_CARD, 0.0),
		"disabled": box(Color(bg, 0.7), R_CARD),
		"selected": sel,
	}
	f.fg = {"normal": IVORY}
	f.draw_text = false
	b.add_theme_stylebox_override("focus", focus_ring(R_CARD))
	return b


## A content card sizes itself to its content's width (labels only know
## their size once themed in the tree).
static func fit_card(b: Control, content: Control, pad: float = 36.0) -> void:
	var upd := func() -> void:
		if is_instance_valid(b) and is_instance_valid(content):
			b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, content.get_combined_minimum_size().x + pad)
	content.minimum_size_changed.connect(upd)
	upd.call()


## V6: every scrolling list is made here, so a finger swipe scrolls it from
## anywhere on its content and a drag never activates the card it started
## on (TouchScroll).  Vertical by default; horizontal for strips and tracks.
static func scroll_area(horizontal: bool = false) -> ScrollContainer:
	var sc := ScrollContainer.new()
	if horizontal:
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	TouchScroll.attach(sc)
	return sc


## Focus for controllers and keys; on touch the ring stays hidden until a
## directional input moves it (Godot shows it again on navigation).
static func soft_focus(c: Control) -> void:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or not c.is_visible_in_tree():
		return
	# a control can't take focus while it, or a parent's recursive focus
	# behaviour (a sheet over it), disables focus: nothing to do then
	var mode: int = c.call("get_focus_mode_with_override") if c.has_method("get_focus_mode_with_override") else c.focus_mode
	if mode == Control.FOCUS_NONE:
		return
	c.grab_focus(Controls.device == "touch")


static func face_of(b: Control) -> Face:
	return b.get_meta(&"face") if b != null and b.has_meta(&"face") else null


static func _base_button(t: String, min_size: Vector2, font_size: int) -> Button:
	return adopt(Button.new(), t, min_size, font_size)


## Give an existing Button the UIKit structure: a still, invisible hit
## region with a Face child that draws and animates.
static func adopt(b: Button, t: String, min_size: Vector2, font_size: int) -> Button:
	if b.has_meta(&"face"):
		return b
	b.text = t
	var tm := touch_min()
	b.custom_minimum_size = Vector2(maxf(min_size.x, tm), maxf(min_size.y, tm))
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", font_w(600))
	b.clip_text = false
	# fixed-width buttons trim long text with an ellipsis; content-sized ones
	# (min width 0) must not trim, or their minimum width ignores the text
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if min_size.x > 0.0 else TextServer.OVERRUN_NO_TRIMMING
	# the button itself draws nothing but its focus ring (the Face draws the
	# look); its stylebox margins still size it around the text
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 18
	empty.content_margin_right = 18
	empty.content_margin_top = 8
	empty.content_margin_bottom = 8
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_stylebox_override("focus", focus_ring())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(k, Color(0, 0, 0, 0))
	var f := Face.new()
	f.btn = b
	b.add_child(f)
	b.set_meta(&"face", f)
	b.pressed.connect(func() -> void: Sfx.play("click"))
	press_feedback(b)
	return b


static func _with_bg(s: StyleBoxFlat, bg: Color) -> StyleBoxFlat:
	var c := s.duplicate() as StyleBoxFlat
	c.bg_color = bg
	return c


static func _with_border(s: StyleBoxFlat, col: Color) -> StyleBoxFlat:
	var c := s.duplicate() as StyleBoxFlat
	c.border_color = col
	return c


## Restyle a button for a surface colour and text colour.
static func _apply(b: Button, bg: Color, fg: Color) -> void:
	var f := face_of(b)
	if f == null:
		# a plain Button (not from UIKit): style it directly
		b.add_theme_stylebox_override("normal", card_box(bg, R_BUTTON))
		b.add_theme_stylebox_override("hover", card_box(bg.lightened(0.06), R_BUTTON))
		b.add_theme_stylebox_override("pressed", card_box(bg.darkened(0.08), R_BUTTON, 0.0))
		b.add_theme_stylebox_override("disabled", box(DISABLED_BG, R_BUTTON))
		b.add_theme_stylebox_override("focus", focus_ring(R_BUTTON, TEAL if bg != TEAL else IVORY))
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, fg)
		b.add_theme_color_override("font_disabled_color", IVORY_DIM)
		return
	var gold := bg.is_equal_approx(AMBER)
	var normal := card_box(bg, R_BUTTON, 1.0, 16, 0.12)
	if gold:
		normal.border_color = AMBER_HI
		normal.shadow_color = Color(0.25, 0.14, 0.0, 0.38)
	f.styles = {
		"normal": normal,
		"hover": _with_bg(normal, bg.lightened(0.06)),
		"pressed": card_box(bg.darkened(0.07), R_BUTTON, 0.0),
		"disabled": box(DISABLED_BG, R_BUTTON),
		"selected": card_box(TEAL, R_BUTTON, 1.0),
	}
	f.fg = {"normal": fg, "disabled": Color(IVORY, 0.55), "selected": NAVY}
	f.queue_redraw()
	b.add_theme_stylebox_override("focus", focus_ring(R_BUTTON, TEAL if bg != TEAL else IVORY))


## Press feedback: the face sinks 4.5% in ~85 ms on touch-down and settles
## back in ~190 ms on release.  One animation owns the face's scale at a time
## (Motion), so rapid taps never leave an old spring running.  A control
## without a Face (custom buttons) animates its first child marked
## `press_visual`, or nothing: the hit region itself never scales.
static func press_feedback(c: Control) -> void:
	if c.has_meta(&"press_fb"):
		return
	c.set_meta(&"press_fb", true)
	if not (c is BaseButton):
		return
	var bb := c as BaseButton
	bb.button_down.connect(func() -> void: Motion.press(_press_visual(c), true))
	bb.button_up.connect(func() -> void: Motion.press(_press_visual(c), false))
	# hidden or disabled while held: settle at once (no stuck, shrunken face)
	c.visibility_changed.connect(func() -> void:
		var v := _press_visual(c)
		if v and not c.is_visible_in_tree():
			Motion.stop(v, "scale")
			v.scale = Vector2.ONE)


static func _press_visual(c: Control) -> Control:
	var f := face_of(c)
	if f != null:
		return f
	if c.has_meta(&"press_visual"):
		var v: Variant = c.get_meta(&"press_visual")
		if v is Control and is_instance_valid(v):
			return v
	return null


## Mark a button as selected (cards, tabs, choice buttons): the face uses
## its "selected" style; selecting plays a tiny one-shot sheen.
static func set_selected(b: Control, on: bool) -> void:
	var f := face_of(b)
	if f == null:
		return
	if on and not f.selected:
		f.flash()
	f.selected = on
	f.queue_redraw()


# ---------------------------------------------------------------------------
# Panels and layout
# ---------------------------------------------------------------------------
static func panel(col: Color = PANEL, radius: int = R_PANEL, pad: int = 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_box(col, radius, 1.0 if col.a > 0.5 else 0.0, pad, 0.07))
	return p


## A soft scrim behind text over the 3D room (not a slab: low opacity,
## rounded, sized to its content).
static func scrim(radius: int = R_PANEL, pad: int = 18, alpha: float = 0.55) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(NAVY, alpha), radius, 0, Color.WHITE, pad))
	return p


static func chip(t: String, col: Color = SLATE_HI, fg: Color = IVORY, size: int = T_CAPTION) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col, 999, 0, Color.WHITE, 14))
	var l := label(t, size, fg, true)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func vbox(sep: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer_h() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func spacer_v() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Fade a control in with a slight scale settle (layout-safe: containers own
## position, so nothing here moves it).  Reduced Motion: fade only.
static func appear(c: Control, _from: Vector2 = Vector2.ZERO, dur: float = T_SHEET) -> void:
	if c.is_inside_tree() and c.size == Vector2.ZERO:
		c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5, CONNECT_ONE_SHOT)
	Motion.settle_in(c, dur)


## Short message that fades out by itself, above the bottom controls.
static func toast(parent: Control, t: String, seconds: float = 1.8) -> void:
	for old in parent.get_children():
		if old.has_meta(&"toast"):
			old.queue_free()     # one at a time: the newest message wins
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_box(Color(SLATE_HI, 0.98), 999, 1.0, 22))
	var l := label(t, T_LABEL, IVORY, true)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.set_meta(&"toast", true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var sz := p.get_combined_minimum_size()
	p.position = Vector2((parent.size.x - sz.x) * 0.5, parent.size.y * 0.74 - sz.y)
	Motion.appear(p, 8.0, T_FAST)
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func() -> void: Motion.vanish(p, p.queue_free, 0.2))


## Safe-area margins in canvas units (notch / home indicator aware).
static func safe_margins(vp: Viewport) -> Rect2:
	var emu := emulated_safe_points()
	if emu.size != Vector2.ZERO or emu.position != Vector2.ZERO:
		# desktop evidence of a notched phone: insets given in points
		var u := units_per_point()
		return Rect2(Vector2(maxf(emu.position.x * u, 16.0), maxf(emu.position.y * u, 12.0)),
			Vector2(maxf(emu.size.x * u, 16.0), maxf(emu.size.y * u, 12.0)))
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var vsize := vp.get_visible_rect().size
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0:
		return Rect2(Vector2(16, 12), Vector2(16, 12))
	var sx := vsize.x / float(win.x)
	var sy := vsize.y / float(win.y)
	var left := maxf(float(safe.position.x) * sx, 16.0)
	var top := maxf(float(safe.position.y) * sy, 12.0)
	var right := maxf(float(win.x - safe.end.x) * sx, 16.0)
	var bottom := maxf(float(win.y - safe.end.y) * sy, 12.0)
	return Rect2(Vector2(left, top), Vector2(right, bottom))


## The safe area as a rect in canvas units (for a control of `view` size).
static func safe_rect(vp: Viewport, view: Vector2) -> Rect2:
	var m := safe_margins(vp) if vp != null else Rect2(Vector2(16, 12), Vector2(16, 12))
	return Rect2(m.position, view - m.position - m.size)


## Canvas units per iOS point on this device (TouchLayout.units_per_point):
## the device's point scale over its pixels per canvas unit.  Desktop runs
## act as a 390-pt-tall phone unless --emulate-phone gives the scale.
static func units_per_point() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 720.0 / 390.0
	var c2px := tree.root.get_final_transform().get_scale().y
	if OS.has_feature("mobile"):
		return TouchLayout.units_per_point(c2px, maxf(DisplayServer.screen_get_scale(), 2.0))
	if emulate_phone():
		return TouchLayout.units_per_point(c2px, emulated_point_scale())
	return 720.0 / 390.0


## --emulate-safe=L,T,R,B (points): desktop captures of notched phones,
## e.g. 59,0,59,21 for a Dynamic Island iPhone in landscape.
static func emulated_safe_points() -> Rect2:
	if emulation.has("safe"):
		return emulation["safe"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--emulate-safe="):
			var v := a.get_slice("=", 1).split(",")
			if v.size() == 4:
				return Rect2(Vector2(v[0].to_float(), v[1].to_float()), Vector2(v[2].to_float(), v[3].to_float()))
	return Rect2()


# ---------------------------------------------------------------------------
# V7 compact layout system
# ---------------------------------------------------------------------------
# Every menu lays out inside the screen's allocated safe content rect
# (content_rect): the viewport minus the safe area minus a small edge
# padding.  Navigation and actions are placed first at their natural height
# (one row: touch_min(), 44 pt); whatever height is left goes to content,
# which scrolls in its own region or sizes itself to it (region()).  Grids
# pick their column count from their final allocated width (AutoGrid), never
# from a requested minimum size.  Text keeps the type scale above: nothing is
# shrunk to make it fit.

## Spacing scale (canvas units; a phone in landscape has ~1.85 units per pt).
const SP_XS := 4
const SP_S := 8
const SP_M := 12
const SP_L := 16
const SP_XL := 24
## Screen padding inside the safe area: sides, top and bottom.
const EDGE_X := 20
const EDGE_Y := 12
## Padding of compact panels (the Locker, Shop and Pass panels).
const PAD_PANEL := 12
## Grid gap between cards.
const GAP_CARD := 10

## Test seam: emulate a device's point scale and safe area (in points)
## without command-line arguments, e.g. {"scale": 3.0, "safe":
## Rect2(47, 0, 47, 21)} (left, top, right, bottom).  Empty = off.
static var emulation: Dictionary = {}


## Height of one row of controls (a tab bar, an action row): 44 pt.
static func row_h() -> float:
	return touch_min()


## The allocated safe content rect of a screen in canvas units: the
## viewport minus the safe area minus the edge padding.  Layout derives
## from this, never from screenshot pixels.
static func content_rect(vp: Viewport) -> Rect2:
	var view := vp.get_visible_rect().size
	var s := safe_margins(vp)
	var pos := s.position + Vector2(EDGE_X, EDGE_Y)
	return Rect2(pos, view - pos - s.size - Vector2(EDGE_X, EDGE_Y))


## How many cells at least `min_w` wide fit `avail` with `gap` between them.
static func columns_for(avail: float, min_w: float, gap: float = GAP_CARD, min_cols: int = 1, max_cols: int = 8) -> int:
	return clampi(int(floor((avail + gap) / maxf(1.0, min_w + gap))), min_cols, max_cols)


## The width of each of `cols` cells sharing `avail` with `gap` between them.
static func cell_width(avail: float, cols: int, gap: float = GAP_CARD) -> float:
	return floorf((avail - gap * float(maxi(cols, 1) - 1)) / float(maxi(cols, 1)))


## A region that takes the space its parent gives it and never asks for
## more: `child` fills it, and the child's minimum size never grows the
## parent past the screen (V6's Season track forced its parents below the
## safe area this way).  Content that must fit sizes itself from the
## region's size; anything that may not fit scrolls inside.
static func region(child: Control, clip: bool = true) -> Control:
	var r := Control.new()
	r.name = "Region"
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.clip_contents = clip
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.add_child(child)
	return r


## A compact text link ("6 more in the Shop ›"): no slab, teal text, a full
## 44 pt hit area, content-sized.
static func link(t: String, font_size: int = T_LABEL) -> Button:
	var b := _base_button(t, Vector2(0, 0), font_size)
	var f := face_of(b)
	var n := box(Color(0, 0, 0, 0), 999, 0, Color.WHITE)
	f.styles = {"normal": n, "hover": box(Color(IVORY, 0.06), 999), "pressed": box(Color(IVORY, 0.1), 999),
		"disabled": n, "selected": n}
	f.fg = {"normal": TEAL, "hover": TEAL.lightened(0.2), "disabled": IVORY_DIM}
	return b


## A grid whose column count comes from its final allocated width: as many
## cells of at least `min_cell` as fit (within min_cols..max_cols), each
## exactly `cell_w` wide.  Children that implement fit_cell(w, lines) lay
## themselves out for that width; `lines` is the most lines any child's name
## needs at that width (name_lines(w)), so every card's state row lines up.
## Re-fits only when the width really changes (no relayout while scrolling).
class AutoGrid:
	extends GridContainer
	var min_cell := 140.0
	var min_cols := 2
	var max_cols := 6
	var gap := float(UIKit.GAP_CARD)
	var cell_w := 0.0
	var lines := 1
	var _w := -1.0

	func _init(min_cell_w: float = 140.0, min_c: int = 2, max_c: int = 6, g: float = float(UIKit.GAP_CARD)) -> void:
		min_cell = min_cell_w
		min_cols = min_c
		max_cols = max_c
		gap = g
		columns = min_c
		add_theme_constant_override("h_separation", int(g))
		add_theme_constant_override("v_separation", int(g))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		child_entered_tree.connect(_on_child)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			refit()

	## Lay the cells out for the current width (`force`: even if unchanged).
	func refit(force: bool = false) -> void:
		var w := size.x
		if w < 1.0 or (not force and absf(w - _w) < 0.5):
			return
		_w = w
		var cols := UIKit.columns_for(w, min_cell, gap, min_cols, max_cols)
		cell_w = UIKit.cell_width(w, cols, gap)
		columns = cols
		lines = 1
		for c in get_children():
			if c.has_method("name_lines"):
				lines = maxi(lines, int(c.call("name_lines", cell_w)))
		for c in get_children():
			_apply(c)

	func _apply(c: Node) -> void:
		if not (c is Control) or cell_w <= 0.0:
			return
		if c.has_method("fit_cell"):
			c.call("fit_cell", cell_w, lines)
		else:
			(c as Control).custom_minimum_size.x = cell_w

	func _on_child(c: Node) -> void:
		if cell_w > 0.0:
			if c.has_method("name_lines") and int(c.call("name_lines", cell_w)) > lines:
				refit(true)
			else:
				_apply(c)


## Entry for a panel of controls: a fade only.  Its hit targets are where
## they are drawn from the first frame (a scale settle moves them for a
## moment, and its pivot isn't known before the first layout).
static func fade_in(c: Control, dur: float = T_SHEET) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.modulate.a = 0.0
	Motion.animate(c, "modulate:a", 1.0, dur, Tween.TRANS_QUAD, Tween.EASE_OUT)


## Lines a text needs at a width (word wrap, no trimming).
static func lines_for(t: String, f: Font, font_size: int, width: float) -> int:
	if t == "" or width <= 1.0:
		return 1
	var para := TextParagraph.new()
	para.add_string(t, f, font_size)
	para.width = width
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	return maxi(1, para.get_line_count())


## The look of a UIKit button: a style per state, its text (or icon and
## caption) and a one-shot selection sheen.  Child of the button, filling
## it, ignoring input; only this node scales on press.
class Face:
	extends Control
	var btn: BaseButton
	var styles := {}          # normal / hover / pressed / disabled / selected
	var fg := {}              # text colour per state (falls back to normal)
	var draw_text := true
	var selected := false
	var icon := ""
	var caption := ""
	var glow := 0.0:
		set(v):
			glow = v
			queue_redraw()
	var _line := TextLine.new()
	var _line_key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		resized.connect(func() -> void: pivot_offset = size * 0.5)

	func _ready() -> void:
		if btn:
			btn.draw.connect(queue_redraw)
			btn.resized.connect(queue_redraw)

	func state() -> String:
		if btn == null:
			return "normal"
		if btn.disabled:
			return "disabled"
		if selected:
			return "selected"
		var dm := btn.get_draw_mode()
		if dm == BaseButton.DRAW_PRESSED or dm == BaseButton.DRAW_HOVER_PRESSED:
			return "pressed"
		if dm == BaseButton.DRAW_HOVER:
			return "hover"
		return "normal"

	func color_for(st: String) -> Color:
		return fg.get(st, fg.get("normal", UIKit.IVORY))

	func flash() -> void:
		if UIKit.reduced_motion() or not is_inside_tree():
			return
		glow = 1.0
		Motion.animate(self, "glow", 0.0, 0.32, Tween.TRANS_QUAD, Tween.EASE_OUT)

	func _draw() -> void:
		var st := state()
		var sb: StyleBox = styles.get(st, styles.get("normal"))
		var r := Rect2(Vector2.ZERO, size)
		if sb:
			draw_style_box(sb, r)
		if glow > 0.01:
			var g := UIKit.box(Color(0, 0, 0, 0), UIKit.R_CARD + 3, 2, Color(UIKit.TEAL, 0.7 * glow), 0)
			g.draw_center = false
			g.expand_margin_left = 3
			g.expand_margin_right = 3
			g.expand_margin_top = 3
			g.expand_margin_bottom = 3
			draw_style_box(g, r)
		var col := color_for(st)
		if icon != "":
			_draw_icon(col)
			return
		if not draw_text or btn == null or not (btn is Button):
			return
		var b := btn as Button
		if b.text == "":
			return
		var f: Font = b.get_theme_font("font")
		var fs: int = b.get_theme_font_size("font_size")
		var pad := text_pad()
		var key := "%s|%d|%d|%d|%d" % [b.text, fs, f.get_instance_id(), int(size.x), int(pad)]
		if key != _line_key:
			_line_key = key
			_line.clear()
			_line.add_string(b.text, f, fs)
			_line.width = maxf(1.0, size.x - pad * 2.0)
			_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_line.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var h := _line.get_size().y
		_line.draw(get_canvas_item(), Vector2(pad, (size.y - h) * 0.5), col)

	## Side padding of the text: 14 units, or less when the button itself
	## was sized with tighter padding (a fitted tab strip), so a word that
	## sized the button is never trimmed inside it.
	func text_pad() -> float:
		var b := btn as Button
		if b == null:
			return 14.0
		return minf(14.0, b.get_theme_stylebox("normal").content_margin_left)

	func _draw_icon(col: Color) -> void:
		var h := size.y
		if caption == "":
			Icons.draw_shape(self, icon, size * 0.5, h * 0.24, col)
			return
		var ih := minf(h, 72.0)
		Icons.draw_shape(self, icon, Vector2(ih * 0.56, h * 0.5), ih * 0.21, col)
		var f := UIKit.font_w(600)
		var fs := UIKit.T_LABEL
		var asc := f.get_ascent(fs)
		var desc := f.get_descent(fs)
		draw_string(f, Vector2(ih * 1.02, h * 0.5 + (asc - desc) * 0.5), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - ih * 1.08, fs, col)


# ---------------------------------------------------------------------------
# V7 screens (Play with Friends, Settings and the screens swept with them).
# Append-only helpers; nothing above this block depends on them.
# ---------------------------------------------------------------------------
## Desktop captures and tests: an emulated on-screen keyboard height in
## points (below 0: off, the device's own keyboard is read instead).
static var v7_emulated_keyboard_pt := -1.0


## The on-screen keyboard's height in canvas units (0 while it is hidden).
## iOS reports it in pixels (DisplayServer.virtual_keyboard_get_height());
## the canvas is scaled to the window by the root's final transform.
static func v7_keyboard_height(vp: Viewport) -> float:
	var view_h := vp.get_visible_rect().size.y if vp != null else 720.0
	if v7_emulated_keyboard_pt >= 0.0:
		return clampf(v7_emulated_keyboard_pt * units_per_point(), 0.0, view_h)
	var px := DisplayServer.virtual_keyboard_get_height()
	if px <= 0 or vp == null:
		return 0.0
	var c2px := vp.get_final_transform().get_scale().y
	if c2px <= 0.0:
		return 0.0
	return clampf(float(px) / c2px, 0.0, view_h)


## Width of a single line of text in a control's own theme font and size.
static func v7_text_width(c: Control, text: String, font_name: StringName = &"font", size_name: StringName = &"font_size") -> float:
	var f: Font = c.get_theme_font(font_name)
	var fs: int = c.get_theme_font_size(size_name)
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else 0.0


## True when a UIKit button's label is drawn whole (its Face trims text that
## doesn't fit the button minus the Face's side padding).
static func v7_button_text_fits(b: Button) -> bool:
	if b.text == "":
		return true
	var f := face_of(b)
	var pad := f.text_pad() if f != null else 8.0
	return v7_text_width(b, b.text) <= b.size.x - pad * 2.0 + 0.5


## Back (Escape, controller B) on a confirmation takes its safe choice.
## Screen.dialog() maps Back only for a fixed set of words ("Cancel", "OK",
## "Done", …), so a confirmation whose safe choice reads "Stay" or "Keep
## playing" ignored Back.  `choice` runs after it closes (optional).
static func v7_back_chooses(screen: Screen, dlg: Control, choice: Callable = Callable()) -> void:
	for m in screen._modals:
		if m["node"] == dlg:
			m["cancel"] = func() -> void:
				if is_instance_valid(dlg):
					dlg.queue_free()
				if choice.is_valid():
					choice.call()


## A list as tall as its content up to `max_h`, then scrolled by finger:
## for sheets and dialogs whose rows grow with the data (blocked players,
## series standings) and must still fit on a phone.
static func v7_capped_list(content: Control, max_h: float) -> ScrollContainer:
	var sc := scroll_area()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	var fit := func() -> void:
		if is_instance_valid(sc) and is_instance_valid(content):
			sc.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, max_h)
	content.minimum_size_changed.connect(fit)
	fit.call()
	return sc
