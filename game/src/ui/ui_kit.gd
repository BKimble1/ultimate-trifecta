class_name UIKit
extends RefCounted
## Shared look for menus and HUD (V2).
##
## Palette: deep navy #11192B (menu backgrounds), slate #223049 (panels),
## warm ivory #F4F2EC (text), amber #FFC668 (the one primary action per
## screen), muted teal #6FD8CC (secondary accents, focus, water highlights).
## Spacing 8/12/16/24/32, radii 14/20/26.  Every tappable control is at
## least 44 pt (touch_min(), in canvas units for the current device).
## Transitions run 150-220 ms; Reduced Motion turns slides into fades.

## Static weight instances (tools/fonts/make_static_fonts.py).  The variable
## font rendered every requested weight at its default Light instance.
const FONT_FILES := {
	500: "res://assets/fonts/Fredoka-Medium.ttf",
	600: "res://assets/fonts/Fredoka-SemiBold.ttf",
	700: "res://assets/fonts/Fredoka-Bold.ttf",
}

const NAVY := Color("11192b")
const SLATE := Color("223049")
const SLATE_HI := Color("2e3f5e")
const SLATE_LO := Color("1a2539")
const IVORY := Color("f4f2ec")
const AMBER := Color("ffc668")
const TEAL := Color("6fd8cc")
const IVORY_MUTED := Color(0.957, 0.949, 0.925, 0.66)

# legacy names used across the HUD/screens, mapped onto the V2 palette
const INK := Color("11192b")
const PANEL := Color(0.133, 0.188, 0.286, 0.94)
const PANEL_LIGHT := Color("2e3f5e")
const ACCENT := AMBER
const RUNNER := TEAL
const PATROL := Color("ffa05c")
const GOOD := Color("7fe0a4")
const BAD := Color("ff7a7a")
const TEXT := IVORY
const MUTED := Color("b9bdc8")

const R_SMALL := 14
const R_BUTTON := 20
const R_PANEL := 26
const T_FAST := 0.15
const T_SHEET := 0.2

static var _theme: Theme
static var _fonts: Dictionary = {}


## weight: 500 body, 600 emphasis/buttons, 700 headings and the wordmark.
## Other values snap to the nearest shipped instance.
static func font_w(weight: int) -> Font:
	var w := 500 if weight < 550 else (600 if weight < 675 else 700)
	if not _fonts.has(w):
		_fonts[w] = load(FONT_FILES[w])
	return _fonts[w]


static func font(bold: bool = false) -> Font:
	return font_w(600 if bold else 500)


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
	for a in OS.get_cmdline_user_args():
		if a == "--emulate-phone":
			return 3.0
		if a.begins_with("--emulate-phone="):
			return clampf(a.get_slice("=", 1).to_float(), 1.0, 3.0)
	return 0.0


static func reduced_motion() -> bool:
	return bool(Save.get_setting("reduced_motion", false))


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


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font_w(500)
	t.default_font_size = 24
	t.set_color("font_color", "Label", IVORY)
	t.set_color("font_outline_color", "Label", NAVY)
	t.set_constant("outline_size", "Label", 0)
	_style_button(t, "Button", SLATE_HI, IVORY)
	t.set_font("font", "Button", font_w(650))
	t.set_font_size("font_size", "Button", 26)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, R_PANEL, 0, Color.WHITE, 22))
	t.set_stylebox("panel", "Panel", box(PANEL, R_PANEL))
	t.set_stylebox("normal", "LineEdit", box(SLATE_LO, R_SMALL, 2, SLATE_HI, 18))
	t.set_stylebox("focus", "LineEdit", box(SLATE_LO, R_SMALL, 3, TEAL, 18))
	t.set_font("font", "LineEdit", font_w(650))
	t.set_font_size("font_size", "LineEdit", 40)
	t.set_color("font_color", "LineEdit", IVORY)
	t.set_color("font_placeholder_color", "LineEdit", Color(IVORY, 0.35))
	t.set_stylebox("slider", "HSlider", box(SLATE_LO, 8, 0, Color.WHITE, 5))
	t.set_stylebox("grabber_area", "HSlider", box(TEAL, 8, 0, Color.WHITE, 5))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(TEAL.lightened(0.15), 8, 0, Color.WHITE, 5))
	t.set_stylebox("focus", "HSlider", box(Color(0, 0, 0, 0), 10, 3, TEAL, 0))
	t.set_font_size("font_size", "CheckButton", 24)
	t.set_color("font_color", "CheckButton", IVORY)
	t.set_color("font_hover_color", "CheckButton", IVORY)
	t.set_color("font_pressed_color", "CheckButton", IVORY)
	t.set_color("font_focus_color", "CheckButton", IVORY)
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), R_SMALL, 3, TEAL, 4))
	_style_button(t, "OptionButton", SLATE_HI, IVORY)
	t.set_font_size("font_size", "OptionButton", 22)
	t.set_stylebox("panel", "PopupMenu", box(SLATE_HI, R_SMALL, 0, Color.WHITE, 10))
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_stylebox("panel", "TooltipPanel", box(SLATE_HI, 12))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.15), 8, 0, Color.WHITE, 3))
	t.set_stylebox("grabber", "VScrollBar", box(Color(IVORY, 0.3), 8, 0, Color.WHITE, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(IVORY, 0.45), 8, 0, Color.WHITE, 3))
	_theme = t
	return t


static func _style_button(t: Theme, type: String, col: Color, fg: Color) -> void:
	t.set_stylebox("normal", type, depth_box(col))
	t.set_stylebox("hover", type, depth_box(col.lightened(0.08)))
	t.set_stylebox("pressed", type, depth_box(col.darkened(0.08), true))
	t.set_stylebox("disabled", type, box(Color(col, 0.45), R_BUTTON))
	t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), R_BUTTON + 3, 3, TEAL, 0))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, type, fg)
	t.set_color("font_disabled_color", type, Color(fg, 0.45))


static func label(text: String, size: int = 24, col: Color = IVORY, bold: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font_w(600))
	l.horizontal_alignment = align
	return l


static func heading(text: String, size: int = 40, col: Color = IVORY) -> Label:
	var l := label(text, size, col)
	l.add_theme_font_override("font", font_w(700))
	return l


static func outlined(l: Label, px: int = 8) -> Label:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", Color(NAVY, 0.92))
	return l


## Legacy signature (colour picks the style): amber = primary, everything
## else becomes a calm slate button with the colour as a thin accent.
static func button(text: String, col: Color = SLATE_HI, min_size: Vector2 = Vector2(240, 72), font_size: int = 26) -> Button:
	if col.is_equal_approx(AMBER) or (col.r > 0.95 and col.g > 0.6 and col.g < 0.85 and col.b < 0.45):
		return primary(text, min_size, font_size)
	var b := _base_button(text, min_size, font_size)
	var bg := SLATE_HI if col.get_luminance() > 0.35 or col.s > 0.35 else col
	if col.is_equal_approx(BAD) or (col.r > 0.55 and col.g < 0.45 and col.b < 0.45):
		bg = Color("5a2f3d")
	_apply(b, bg, IVORY)
	return b


static func primary(text: String, min_size: Vector2 = Vector2(320, 96), font_size: int = 32) -> Button:
	var b := _base_button(text, min_size, font_size)
	_apply(b, AMBER, NAVY)
	b.add_theme_font_override("font", font_w(700))
	return b


static func secondary(text: String, min_size: Vector2 = Vector2(260, 80), font_size: int = 26) -> Button:
	var b := _base_button(text, min_size, font_size)
	_apply(b, SLATE_HI, IVORY)
	return b


## Low-emphasis action: transparent with a soft outline.
static func quiet(text: String, min_size: Vector2 = Vector2(220, 72), font_size: int = 24) -> Button:
	var b := _base_button(text, min_size, font_size)
	var n := box(Color(SLATE, 0.55), R_BUTTON, 2, Color(IVORY, 0.22))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", box(Color(SLATE_HI, 0.75), R_BUTTON, 2, Color(IVORY, 0.3)))
	var pq := box(Color(SLATE_LO, 0.9), R_BUTTON, 2, Color(IVORY, 0.3))
	pq.content_margin_top += 2
	b.add_theme_stylebox_override("pressed", pq)
	b.add_theme_stylebox_override("disabled", box(Color(SLATE, 0.3), R_BUTTON, 2, Color(IVORY, 0.1)))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), R_BUTTON + 3, 3, TEAL, 0))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, IVORY)
	return b


## Square icon button (drawn glyph from Icons) with an optional caption.
static func icon_button(icon: String, caption: String = "", size_units: float = 0.0) -> Button:
	var s := maxf(size_units, touch_min())
	var b := _base_button("", Vector2(s if caption == "" else maxf(s * 2.1, 150.0), s), 22)
	_apply(b, Color(SLATE, 0.82), IVORY)
	var g := IconGlyph.new()
	g.icon = icon
	g.caption = caption
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(g)
	b.tooltip_text = caption
	return b


static func _base_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	var tm := touch_min()
	b.custom_minimum_size = Vector2(maxf(min_size.x, tm), maxf(min_size.y, tm))
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", font_w(600))
	b.clip_text = false
	# fixed-width buttons trim long text with an ellipsis; content-sized ones
	# (min width 0) must not trim, or their minimum width ignores the text
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if min_size.x > 0.0 else TextServer.OVERRUN_NO_TRIMMING
	b.pressed.connect(func() -> void: Sfx.play("click"))
	press_feedback(b)
	return b


## Raised button face: a darker lip under the face gives depth; pressed, the
## face sinks onto the lip (layout size never changes).
const LIP := 6


static func depth_box(bg: Color, pressed: bool = false, radius: int = R_BUTTON) -> StyleBoxFlat:
	var s := box(bg, radius)
	var lip := LIP if not pressed else 2
	s.border_width_bottom = lip
	s.border_color = Color(bg.darkened(0.38), maxf(bg.a, 0.6))
	s.content_margin_bottom += lip
	if pressed:
		s.expand_margin_top = -float(LIP - 2)
		s.content_margin_top += float(LIP - 2)
	return s


static func _apply(b: Button, bg: Color, fg: Color) -> void:
	b.add_theme_stylebox_override("normal", depth_box(bg))
	b.add_theme_stylebox_override("hover", depth_box(bg.lightened(0.07)))
	b.add_theme_stylebox_override("pressed", depth_box(bg.darkened(0.08), true))
	b.add_theme_stylebox_override("disabled", box(Color(bg, 0.4), R_BUTTON))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), R_BUTTON + 3, 3, TEAL if bg != TEAL else IVORY, 0))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.5))


## Pressed feedback: a quick 4% press-in, then a small spring back on
## release (about 200 ms; none with Reduced Motion, the lip still shows it).
static func press_feedback(c: Control) -> void:
	if c.has_meta("press_fb"):
		return
	c.set_meta("press_fb", true)
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	if c is BaseButton:
		var bb := c as BaseButton
		bb.button_down.connect(func() -> void: _scale_to(c, 0.96))
		bb.button_up.connect(func() -> void: _scale_to(c, 1.0, true))


static func _scale_to(c: Control, s: float, spring: bool = false) -> void:
	if not c.is_inside_tree():
		return
	if reduced_motion():
		c.scale = Vector2.ONE
		return
	var tw := c.create_tween()
	if spring:
		tw.tween_property(c, "scale", Vector2(s, s), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(c, "scale", Vector2(s, s), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func panel(col: Color = PANEL, radius: int = R_PANEL, pad: int = 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col, radius, 0, Color.WHITE, pad))
	return p


static func chip(text: String, col: Color = SLATE_HI, fg: Color = IVORY, size: int = 20) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col, 999, 0, Color.WHITE, 14))
	var l := label(text, size, fg, true)
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
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not reduced_motion():
		c.pivot_offset = c.size * 0.5
		if not c.resized.is_connected(_center_pivot.bind(c)):
			c.resized.connect(_center_pivot.bind(c))
		c.scale = Vector2(0.975, 0.975)
		tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5


## Short message that fades out by itself.
static func toast(parent: Control, text: String, seconds: float = 1.8) -> void:
	var t := chip(text, Color(SLATE_HI, 0.97), IVORY, 22)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	t.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	t.position = Vector2((parent.size.x - t.get_combined_minimum_size().x) * 0.5, parent.size.y - 170)
	appear(t, Vector2(0, 12), T_FAST)
	var tw := t.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(t, "modulate:a", 0.0, 0.2)
	tw.tween_callback(t.queue_free)


## Safe-area margins in canvas units (notch / home indicator aware).
static func safe_margins(vp: Viewport) -> Rect2:
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


## Icon (+ caption) drawn inside an icon_button.
class IconGlyph:
	extends Control
	var icon := ""
	var caption := ""

	func _draw() -> void:
		var h := size.y
		if caption == "":
			Icons.draw_shape(self, icon, size * 0.5, h * 0.24, UIKit.IVORY)
			return
		var ih := minf(h, 72.0)
		Icons.draw_shape(self, icon, Vector2(ih * 0.55, h * 0.5), ih * 0.22, UIKit.IVORY)
		var f := UIKit.font_w(650)
		draw_string(f, Vector2(ih * 1.0, h * 0.5 + 8), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - ih * 1.05, 22, UIKit.IVORY)
