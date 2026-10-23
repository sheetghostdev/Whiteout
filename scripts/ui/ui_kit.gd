class_name UIKit
extends RefCounted
## Code-built UI theme (frosted translucent panels, soft corners) and small
## helpers. Uses the engine's built-in font - no font files.

const TEXT := Color(0.93, 0.96, 1.0)
const TEXT_DIM := Color(0.72, 0.80, 0.90)
const ACCENT := Color(0.58, 0.84, 1.0)
const FROST := Color(0.70, 0.90, 1.0)
const CORE := Color(0.80, 0.78, 1.0)
const GOOD := Color(0.62, 0.95, 0.78)
const BAD := Color(1.0, 0.62, 0.58)
const PANEL := Color(0.09, 0.14, 0.22, 0.72)
const PANEL_LIGHT := Color(0.16, 0.24, 0.36, 0.72)
const BORDER := Color(0.78, 0.90, 1.0, 0.28)

static var _theme: Theme
static var _title_font: FontVariation
static var _number_font: FontVariation


static func panel_style(bg: Color = PANEL, radius: int = 14, border: Color = BORDER, pad: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.75
	s.content_margin_bottom = pad * 0.75
	s.shadow_color = Color(0.0, 0.03, 0.08, 0.25)
	s.shadow_size = 8
	s.anti_aliasing = true
	return s


static func title_font() -> FontVariation:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = ThemeDB.fallback_font
		_title_font.variation_embolden = 0.6
		_title_font.spacing_glyph = 6
	return _title_font


## Bold font without letter spacing, for numbers.
static func number_font() -> FontVariation:
	if _number_font == null:
		_number_font = FontVariation.new()
		_number_font.base_font = ThemeDB.fallback_font
		_number_font.variation_embolden = 0.5
	return _number_font


## Anchors a control and sets explicit offsets (robust before first layout).
static func place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0.05, 0.12, 0.45))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	var normal := panel_style(Color(0.20, 0.31, 0.45, 0.78), 10, Color(0.8, 0.92, 1.0, 0.25), 12)
	var hover := panel_style(Color(0.28, 0.43, 0.60, 0.88), 10, Color(0.85, 0.95, 1.0, 0.6), 12)
	var pressed := panel_style(Color(0.40, 0.58, 0.78, 0.95), 10, Color(0.9, 0.97, 1.0, 0.8), 12)
	var disabled := panel_style(Color(0.14, 0.18, 0.24, 0.6), 10, Color(0.6, 0.7, 0.8, 0.15), 12)
	var focus := panel_style(Color(0, 0, 0, 0), 10, Color(0.85, 0.95, 1.0, 0.7), 12)
	focus.draw_center = false
	for k in [normal, hover, pressed, disabled]:
		k.shadow_size = 3
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.66, 0.74))
	t.set_font_size("font_size", "Button", 18)
	# Option buttons / popups.
	t.set_stylebox("normal", "OptionButton", normal)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_stylebox("focus", "OptionButton", focus)
	t.set_stylebox("panel", "PopupMenu", panel_style(Color(0.10, 0.16, 0.25, 0.97), 10))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", panel_style(Color(0.3, 0.45, 0.62, 0.9), 6, Color(0, 0, 0, 0), 4))
	# Sliders.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.6, 0.75, 0.9, 0.25)
	track.set_corner_radius_all(4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.86, 1.0, 0.85)
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_texture(18, Color(0.95, 0.98, 1.0)))
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(20, Color.WHITE))
	# Progress bars.
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0.5, 0.65, 0.85, 0.22)
	pbg.set_corner_radius_all(6)
	var pfg := StyleBoxFlat.new()
	pfg.bg_color = Color(0.85, 0.95, 1.0, 0.92)
	pfg.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", pfg)
	t.set_color("font_color", "ProgressBar", Color(0.1, 0.2, 0.3))
	# Check boxes.
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_icon("checked", "CheckBox", _check_texture(true))
	t.set_icon("unchecked", "CheckBox", _check_texture(false))
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", empty)
	# Scroll bars.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.7, 0.85, 1.0, 0.35)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0.5, 0.6, 0.8, 0.08)
	sbg.set_corner_radius_all(4)
	sbg.content_margin_left = 4
	sbg.content_margin_right = 4
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", sbg)
	t.set_stylebox("panel", "TabContainer", panel_style(PANEL, 12))
	t.set_stylebox("tab_selected", "TabContainer", panel_style(Color(0.30, 0.45, 0.62, 0.9), 8, BORDER, 10))
	t.set_stylebox("tab_unselected", "TabContainer", panel_style(Color(0.16, 0.22, 0.32, 0.7), 8, BORDER, 10))
	t.set_stylebox("tab_hovered", "TabContainer", panel_style(Color(0.24, 0.36, 0.50, 0.8), 8, BORDER, 10))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	_theme = t
	return t


static func _circle_texture(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * c.a))
	return ImageTexture.create_from_image(img)


static func _check_texture(on: bool) -> ImageTexture:
	var s := 22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var edge := x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			var c := Color(0.8, 0.92, 1.0, 0.7) if edge else Color(0.2, 0.3, 0.45, 0.5)
			if on and not edge and x > 5 and y > 5 and x < s - 6 and y < s - 6:
				c = Color(0.75, 0.92, 1.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 18, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func title(text: String, size: int = 40, color: Color = TEXT) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", title_font())
	return l


static func button(text: String, min_w: float = 240.0) -> FrostButton:
	var b := FrostButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	return b


static func fmt(n: float) -> String:
	var a := absf(n)
	if a < 10000.0:
		var i := int(floor(n))
		var s := str(absi(i))
		if s.length() > 3:
			s = s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)
		return ("-" if i < 0 else "") + s
	var units := ["K", "M", "B", "T"]
	var u := -1
	while a >= 1000.0 and u < units.size() - 1:
		a /= 1000.0
		u += 1
	var txt := ("%.2f" % a) if a < 10.0 else (("%.1f" % a) if a < 100.0 else str(int(a)))
	return ("-" if n < 0 else "") + txt + units[u]


static func fmt_time(seconds: float) -> String:
	var s := int(seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%d:%02d" % [m, sec]


static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
