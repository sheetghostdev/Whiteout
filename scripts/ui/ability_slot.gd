class_name AbilitySlot
extends Control
## One ability in the HUD bar: icon, key number and a radial cooldown sweep.

var ability_id := "snow_cloud"
var locked := false
var selected := false
var key_label := ""
var cooldown := 0.0
var _icon: ProceduralIcon


func _ready() -> void:
	custom_minimum_size = Vector2(68, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_id: String = GameBalance.ABILITIES[ability_id]["icon"]
	_icon = ProceduralIcon.make("lock" if locked else icon_id, 40, Color(0.92, 0.97, 1.0, 0.45 if locked else 1.0))
	_icon.position = Vector2(14, 12)
	_icon.size = Vector2(40, 40)
	add_child(_icon)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := Color(0.10, 0.16, 0.25, 0.7)
	var border := Color(0.8, 0.92, 1.0, 0.25)
	if selected:
		bg = Color(0.22, 0.36, 0.52, 0.85)
		border = Color(0.85, 0.96, 1.0, 0.95)
	var sb := UIKit.panel_style(bg, 12, border, 0)
	if selected:
		sb.set_border_width_all(2)
	draw_style_box(sb, r)
	if cooldown > 0.0 and not locked:
		# Dim the slot and sweep a ring for the remaining recharge time.
		var inner := UIKit.panel_style(Color(0.02, 0.05, 0.1, 0.45), 12, Color(0, 0, 0, 0), 0)
		draw_style_box(inner, r)
		var c := size * 0.5
		draw_arc(c, size.x * 0.4, -PI * 0.5, -PI * 0.5 + cooldown * TAU, 40, Color(0.8, 0.93, 1.0, 0.9), 3.0, true)
	if key_label != "":
		draw_string(ThemeDB.fallback_font, Vector2(6, 16), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.93, 1.0, 0.8))
