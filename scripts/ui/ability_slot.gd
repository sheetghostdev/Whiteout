class_name AbilitySlot
extends Control
## One skill in the HUD bar: icon, key hint and a radial cooldown sweep.

var skill_id := "squall"
var key_label := ""
var cooldown := 0.0
var _icon: ProceduralIcon
var _was_cooling := false
var _flash := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(68, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_id: String = GameBalance.SKILLS[skill_id]["icon"] if GameBalance.SKILLS.has(skill_id) else "eye"
	_icon = ProceduralIcon.make(icon_id, 40, Color(0.92, 0.97, 1.0))
	_icon.position = Vector2(14, 10)
	_icon.size = Vector2(40, 40)
	add_child(_icon)


func set_cooldown(v: float) -> void:
	if _was_cooling and v <= 0.0:
		_flash = 1.0
	_was_cooling = v > 0.0
	cooldown = v
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var ready := cooldown <= 0.0
	var bg := Color(0.16, 0.27, 0.40, 0.8) if ready else Color(0.08, 0.12, 0.2, 0.7)
	var border := Color(0.85, 0.96, 1.0, 0.6 + 0.4 * _flash) if ready else Color(0.8, 0.92, 1.0, 0.2)
	var sb := UIKit.panel_style(bg.lerp(Color(0.5, 0.75, 1.0, 0.9), _flash * 0.6), 12, border, 0)
	sb.set_border_width_all(2 if ready else 1)
	draw_style_box(sb, r)
	_icon.modulate.a = 1.0 if ready else 0.45
	if not ready:
		var c := size * 0.5
		draw_arc(c, size.x * 0.4, -PI * 0.5, -PI * 0.5 + (1.0 - cooldown) * TAU, 40, Color(0.8, 0.93, 1.0, 0.9), 3.0, true)
	if key_label != "":
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(key_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
		draw_string(f, Vector2((size.x - w) * 0.5, size.y - 5), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.93, 1.0, 0.85))
