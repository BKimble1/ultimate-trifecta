class_name UIKit
extends RefCounted
## Shared look for menus and HUD: chunky rounded panels, bright accents,
## big touch targets, visible focus rings for controller navigation.

const FONT_PATH := "res://assets/fonts/Fredoka-Variable.ttf"
const INK := Color(0.10, 0.11, 0.22)
const PANEL := Color(0.12, 0.15, 0.32, 0.92)
const PANEL_LIGHT := Color(0.20, 0.25, 0.48, 0.95)
const ACCENT := Color(1.0, 0.78, 0.28)
const RUNNER := Color(0.35, 0.85, 1.0)
const PATROL := Color(1.0, 0.55, 0.30)
const GOOD := Color(0.45, 0.95, 0.55)
const BAD := Color(1.0, 0.45, 0.45)
const TEXT := Color(0.97, 0.97, 1.0)
const MUTED := Color(0.72, 0.76, 0.92)

static var _theme: Theme
static var _font: FontVariation
static var _font_bold: FontVariation


static func font(bold: bool = false) -> Font:
	if _font == null:
		var base: FontFile = load(FONT_PATH)
		_font = FontVariation.new()
		_font.base_font = base
		_font.variation_opentype = {"wght": 500}
		_font_bold = FontVariation.new()
		_font_bold.base_font = base
		_font_bold.variation_opentype = {"wght": 650}
	return _font_bold if bold else _font


static func box(col: Color, radius: int = 22, border: int = 0, border_col: Color = Color.WHITE, pad: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 26
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0.05, 0.06, 0.15))
	t.set_constant("outline_size", "Label", 0)
	# buttons
	t.set_stylebox("normal", "Button", box(Color(0.25, 0.32, 0.62), 22, 0))
	t.set_stylebox("hover", "Button", box(Color(0.32, 0.40, 0.75), 22, 0))
	t.set_stylebox("pressed", "Button", box(Color(0.18, 0.24, 0.50), 22, 0))
	t.set_stylebox("disabled", "Button", box(Color(0.22, 0.24, 0.34, 0.7), 22, 0))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 24, 5, ACCENT, 0))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.65, 0.68, 0.8))
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 28)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 28, 0, Color.WHITE, 22))
	t.set_stylebox("panel", "Panel", box(PANEL, 28))
	# line edit (room code)
	t.set_stylebox("normal", "LineEdit", box(Color(0.08, 0.10, 0.22), 18, 3, Color(0.4, 0.5, 0.9), 16))
	t.set_stylebox("focus", "LineEdit", box(Color(0.08, 0.10, 0.22), 18, 4, ACCENT, 16))
	t.set_font("font", "LineEdit", font(true))
	t.set_font_size("font_size", "LineEdit", 40)
	t.set_color("font_color", "LineEdit", TEXT)
	# sliders / checkboxes
	t.set_stylebox("slider", "HSlider", box(Color(0.10, 0.12, 0.25), 8, 0, Color.WHITE, 4))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 8, 0, Color.WHITE, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT.lightened(0.2), 8, 0, Color.WHITE, 4))
	t.set_stylebox("focus", "HSlider", box(Color(0, 0, 0, 0), 10, 3, ACCENT, 0))
	t.set_font_size("font_size", "CheckButton", 26)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), 14, 3, ACCENT, 4))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), 22, 5, ACCENT, 0))
	t.set_stylebox("normal", "OptionButton", box(Color(0.25, 0.32, 0.62), 22, 0))
	t.set_stylebox("hover", "OptionButton", box(Color(0.32, 0.40, 0.75), 22, 0))
	t.set_stylebox("pressed", "OptionButton", box(Color(0.18, 0.24, 0.50), 22, 0))
	t.set_font_size("font_size", "OptionButton", 24)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_LIGHT, 18, 0, Color.WHITE, 10))
	t.set_font_size("font_size", "PopupMenu", 26)
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_LIGHT, 12))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0.1, 0.12, 0.25, 0.6), 8, 0, Color.WHITE, 4))
	t.set_stylebox("grabber", "VScrollBar", box(Color(0.5, 0.6, 1.0, 0.8), 8, 0, Color.WHITE, 4))
	_theme = t
	return t


static func label(text: String, size: int = 26, col: Color = TEXT, bold: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font(true))
	l.horizontal_alignment = align
	return l


static func outlined(l: Label, px: int = 8) -> Label:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.14, 0.95))
	return l


static func button(text: String, col: Color = Color(0.25, 0.32, 0.62), min_size: Vector2 = Vector2(260, 72), font_size: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", box(col, 24))
	b.add_theme_stylebox_override("hover", box(col.lightened(0.12), 24))
	b.add_theme_stylebox_override("pressed", box(col.darkened(0.18), 24))
	b.add_theme_font_size_override("font_size", font_size)
	var dark := col.get_luminance() > 0.62
	if dark:
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
		b.add_theme_color_override("font_focus_color", INK)
	b.pressed.connect(func() -> void: Sfx.play("click"))
	return b


static func panel(col: Color = PANEL, radius: int = 28, pad: int = 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col, radius, 0, Color.WHITE, pad))
	return p


static func vbox(sep: int = 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


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
