class_name SettingsMenu
extends Control
## Audio, controls (with rebinding) and graphics settings.

signal closed()

var _tabs: TabContainer
var _rebinding := ""
var _bind_buttons := {}
var _controls: Dictionary = {}


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuScreens.backdrop(self, 0.55)
	var vb := MenuScreens.centered_panel(self, Vector2(820, 640))
	vb.add_child(UIKit.title("SETTINGS", 30))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_tabs)
	_tabs.add_child(_audio_tab())
	_tabs.add_child(_controls_tab())
	_tabs.add_child(_graphics_tab())
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var back := UIKit.button("Back", 180)
	back.pressed.connect(_close)
	hb.add_child(back)


func open() -> void:
	visible = true
	_sync()


func _close() -> void:
	_rebinding = ""
	Settings.save_settings()
	closed.emit()


func _row(parent: Control, text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := UIKit.label(text, 17)
	l.custom_minimum_size = Vector2(260, 34)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	parent.add_child(hb)
	return hb


func _slider(parent: Control, text: String, min_v: float, max_v: float, step: float, getter: Callable, setter: Callable, fmt: String = "%d%%", mult: float = 100.0) -> void:
	var hb := _row(parent, text)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.custom_minimum_size = Vector2(320, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(s)
	var v := UIKit.label("", 16, UIKit.TEXT_DIM)
	v.custom_minimum_size = Vector2(70, 0)
	hb.add_child(v)
	s.value_changed.connect(func(x):
		setter.call(x)
		v.text = fmt % (x * mult)
		Settings.apply())
	_controls[text] = {"node": s, "get": getter, "label": v, "fmt": fmt, "mult": mult}


func _check(parent: Control, text: String, getter: Callable, setter: Callable) -> void:
	var hb := _row(parent, text)
	var c := CheckBox.new()
	hb.add_child(c)
	c.toggled.connect(func(on):
		setter.call(on)
		Settings.apply())
	_controls[text] = {"node": c, "get": getter}


func _option(parent: Control, text: String, items: Array, getter: Callable, setter: Callable) -> void:
	var hb := _row(parent, text)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(240, 36)
	for it in items:
		o.add_item(str(it))
	hb.add_child(o)
	o.item_selected.connect(func(i):
		setter.call(i)
		Settings.apply()
		_sync())
	_controls[text] = {"node": o, "get": getter}


func _page(name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return vb


func _audio_tab() -> Control:
	var vb := _page("Audio")
	_slider(vb, "Master Volume", 0, 1, 0.01, func(): return Settings.master_volume, func(x): Settings.master_volume = x)
	_slider(vb, "Music Volume", 0, 1, 0.01, func(): return Settings.music_volume, func(x): Settings.music_volume = x)
	_slider(vb, "Effects Volume", 0, 1, 0.01, func(): return Settings.sfx_volume, func(x): Settings.sfx_volume = x)
	return vb.get_parent()


func _controls_tab() -> Control:
	var vb := _page("Controls")
	_slider(vb, "Mouse Sensitivity", 0.02, 0.4, 0.005, func(): return Settings.mouse_sensitivity, func(x): Settings.mouse_sensitivity = x, "%.0f", 100.0)
	_check(vb, "Invert Y", func(): return Settings.invert_y, func(on): Settings.invert_y = on)
	vb.add_child(UIKit.label("Key bindings  (click, then press a key or mouse button)", 15, UIKit.TEXT_DIM))
	for a in InputSetup.ACTIONS:
		var action: String = a[0]
		var hb := _row(vb, a[1])
		var b := UIKit.button("", 240)
		b.custom_minimum_size = Vector2(240, 36)
		b.disabled = action in InputSetup.FIXED
		b.pressed.connect(func():
			_rebinding = action
			b.text = "Press a key...")
		hb.add_child(b)
		_bind_buttons[action] = b
	var reset := UIKit.button("Reset Bindings", 240)
	reset.pressed.connect(func():
		Settings.reset_bindings()
		_sync())
	vb.add_child(reset)
	return vb.get_parent()


func _graphics_tab() -> Control:
	var vb := _page("Graphics")
	_option(vb, "Quality Preset", Settings.QUALITY_NAMES, func(): return Settings.graphics_quality, func(i): Settings.set_quality_preset(i))
	var res_names: Array = []
	for r in Settings.RESOLUTIONS:
		res_names.append("%d × %d" % [r.x, r.y])
	_option(vb, "Resolution", res_names, func(): return maxi(Settings.RESOLUTIONS.find(Settings.resolution), 0), func(i): Settings.resolution = Settings.RESOLUTIONS[i])
	_check(vb, "Fullscreen", func(): return Settings.fullscreen, func(on): Settings.fullscreen = on)
	_slider(vb, "Field of View", 60, 100, 1, func(): return Settings.fov, func(x): Settings.fov = x, "%d°", 1.0)
	_slider(vb, "Particle Density", 0.2, 1.5, 0.05, func(): return Settings.particle_density, func(x): Settings.particle_density = x)
	_slider(vb, "Draw Distance", 0.6, 1.5, 0.05, func(): return Settings.draw_distance, func(x): Settings.draw_distance = x)
	_slider(vb, "Vegetation Density (on restart)", 0.4, 1.2, 0.05, func(): return Settings.vegetation_density, func(x): Settings.vegetation_density = x)
	_check(vb, "Motion Effects (head bob)", func(): return Settings.motion_effects, func(on): Settings.motion_effects = on)
	_check(vb, "Show FPS", func(): return Settings.show_fps, func(on): Settings.show_fps = on)
	_check(vb, "Show snowfall ring", func(): return Settings.show_snow_ring, func(on): Settings.show_snow_ring = on)
	vb.add_child(UIKit.label("Particle density only changes visuals - snowfall and Frost income are unaffected.", 14, UIKit.TEXT_DIM))
	return vb.get_parent()


func _sync() -> void:
	for k in _controls:
		var c: Dictionary = _controls[k]
		var node: Control = c["node"]
		var v = c["get"].call()
		if node is HSlider:
			(node as HSlider).set_value_no_signal(v)
			(c["label"] as Label).text = String(c["fmt"]) % (float(v) * float(c["mult"]))
		elif node is CheckBox:
			(node as CheckBox).set_pressed_no_signal(v)
		elif node is OptionButton:
			(node as OptionButton).select(int(v))
	for action in _bind_buttons:
		var list: Array = Settings.bindings.get(action, [])
		(_bind_buttons[action] as Button).text = InputSetup.describe(list[0]) if list.size() > 0 else "-"


func _input(event: InputEvent) -> void:
	if not visible or _rebinding == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_rebinding = ""
			_sync()
		else:
			Settings.set_binding(_rebinding, event)
			_rebinding = ""
			_sync()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		Settings.set_binding(_rebinding, event)
		_rebinding = ""
		_sync()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and _rebinding == "" and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
