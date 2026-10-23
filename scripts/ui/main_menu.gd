class_name MainMenu
extends Control
## Title screen shown over a slowly orbiting view of the world.

signal new_game()
signal continue_game()
signal new_winter_plus()
signal open_settings()
signal quit_game()

var _buttons: VBoxContainer
var _info: Label
var _confirm: Control


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	var grad := TextureRect.new()
	grad.texture = _vignette()
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	UIKit.full_rect(grad)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)
	MenuScreens.snow_layer(self, 70)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.position = Vector2(110, -230)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var crest := HBoxContainer.new()
	crest.add_theme_constant_override("separation", 14)
	col.add_child(crest)
	crest.add_child(ProceduralIcon.make("snowflake", 64, Color(0.95, 0.98, 1.0)))
	var t := UIKit.title("WHITEOUT", 78, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	crest.add_child(t)
	var sub := UIKit.label("Bring the world into an ice age.", 20, Color(0.9, 0.95, 1.0, 0.9))
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	col.add_child(gap)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	col.add_child(_buttons)
	_info = UIKit.label("", 15, UIKit.TEXT_DIM)
	col.add_child(_info)
	var foot := UIKit.label("A procedural weather game  ·  every model, texture, sound and icon generated in code", 13, Color(1, 1, 1, 0.55))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(110, -40)
	add_child(foot)


func refresh() -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var summary := Game.save_summary()
	if not summary.is_empty():
		var b := UIKit.button("Continue", 300)
		b.pressed.connect(func(): continue_game.emit())
		_buttons.add_child(b)
		_info.text = "Saved world: %.1f%% frozen  ·  %s played" % [float(summary["fraction"]) * 100.0, UIKit.fmt_time(summary["time"])]
		if summary["completed"]:
			var plus := UIKit.button("New Winter+", 300)
			plus.pressed.connect(func(): new_winter_plus.emit())
			_buttons.add_child(plus)
	else:
		_info.text = ""
	var ng := UIKit.button("New Game", 300)
	ng.pressed.connect(func():
		if summary.is_empty():
			new_game.emit()
		else:
			_ask_overwrite())
	_buttons.add_child(ng)
	var st := UIKit.button("Settings", 300)
	st.pressed.connect(func(): open_settings.emit())
	_buttons.add_child(st)
	var q := UIKit.button("Quit", 300)
	q.pressed.connect(func(): quit_game.emit())
	_buttons.add_child(q)


func _ask_overwrite() -> void:
	if _confirm != null:
		_confirm.queue_free()
	_confirm = Control.new()
	UIKit.full_rect(_confirm)
	add_child(_confirm)
	MenuScreens.backdrop(_confirm, 0.5)
	var vb := MenuScreens.centered_panel(_confirm, Vector2(520, 220))
	vb.add_child(UIKit.title("START A NEW WORLD?", 26))
	var l := UIKit.label("Your saved world will be replaced when the new game saves.", 16, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var yes := UIKit.button("New Game", 200)
	yes.pressed.connect(func():
		_confirm.queue_free()
		new_game.emit())
	hb.add_child(yes)
	var no := UIKit.button("Cancel", 200)
	no.pressed.connect(func(): _confirm.queue_free())
	hb.add_child(no)


func _vignette() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.06, 0.14, 0.72))
	g.set_color(1, Color(0.02, 0.06, 0.14, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0.5)
	t.fill_to = Vector2(0.75, 0.5)
	t.width = 256
	t.height = 16
	return t
