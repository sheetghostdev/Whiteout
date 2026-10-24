extends Node
## Player preferences, persisted separately from save games.

const PATH := "user://settings.cfg"
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]

var master_volume := 0.8
var music_volume := 0.55
var sfx_volume := 0.8
var mouse_sensitivity := 0.12
var invert_y := false
var graphics_quality := 2
var resolution := Vector2i(1600, 900)
var fullscreen := false
var fov := 75.0
var motion_effects := true
var particle_density := 1.0
var vegetation_density := 1.0
var draw_distance := 1.0
var show_fps := false
var show_snow_ring := true
var bindings := {}


func _ready() -> void:
	bindings = InputSetup.defaults()
	load_settings()
	InputSetup.apply(bindings)
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master_volume = float(cf.get_value("audio", "master", master_volume))
	music_volume = float(cf.get_value("audio", "music", music_volume))
	sfx_volume = float(cf.get_value("audio", "sfx", sfx_volume))
	mouse_sensitivity = float(cf.get_value("controls", "sensitivity", mouse_sensitivity))
	invert_y = bool(cf.get_value("controls", "invert_y", invert_y))
	graphics_quality = int(cf.get_value("graphics", "quality", graphics_quality))
	resolution = cf.get_value("graphics", "resolution", resolution)
	fullscreen = bool(cf.get_value("graphics", "fullscreen", fullscreen))
	fov = float(cf.get_value("graphics", "fov", fov))
	motion_effects = bool(cf.get_value("graphics", "motion_effects", motion_effects))
	particle_density = float(cf.get_value("graphics", "particles", particle_density))
	vegetation_density = float(cf.get_value("graphics", "vegetation", vegetation_density))
	draw_distance = float(cf.get_value("graphics", "draw_distance", draw_distance))
	show_fps = bool(cf.get_value("graphics", "show_fps", show_fps))
	show_snow_ring = bool(cf.get_value("graphics", "show_snow_ring", show_snow_ring))
	var saved: Dictionary = cf.get_value("controls", "bindings", {})
	for k in saved:
		if bindings.has(k) and saved[k] is Array:
			bindings[k] = saved[k]


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("controls", "sensitivity", mouse_sensitivity)
	cf.set_value("controls", "invert_y", invert_y)
	cf.set_value("controls", "bindings", bindings)
	cf.set_value("graphics", "quality", graphics_quality)
	cf.set_value("graphics", "resolution", resolution)
	cf.set_value("graphics", "fullscreen", fullscreen)
	cf.set_value("graphics", "fov", fov)
	cf.set_value("graphics", "motion_effects", motion_effects)
	cf.set_value("graphics", "particles", particle_density)
	cf.set_value("graphics", "vegetation", vegetation_density)
	cf.set_value("graphics", "draw_distance", draw_distance)
	cf.set_value("graphics", "show_fps", show_fps)
	cf.set_value("graphics", "show_snow_ring", show_snow_ring)
	cf.save(PATH)


func set_binding(action: String, event: InputEvent) -> void:
	var d := InputSetup.event_to_dict(event)
	if d.is_empty():
		return
	# One binding per action; steal it from any other action that used it.
	for k in bindings:
		var list: Array = bindings[k]
		for i in range(list.size() - 1, -1, -1):
			if list[i] == d:
				list.remove_at(i)
	bindings[action] = [d]
	InputSetup.apply(bindings)


func reset_bindings() -> void:
	bindings = InputSetup.defaults()
	InputSetup.apply(bindings)


func set_quality_preset(q: int) -> void:
	graphics_quality = clampi(q, 0, 3)
	particle_density = [0.4, 0.7, 1.0, 1.3][graphics_quality]
	draw_distance = [0.7, 0.85, 1.0, 1.3][graphics_quality]


func apply() -> void:
	_apply_audio()
	_apply_window()
	WeatherFX.particle_density = particle_density
	WeatherFX.visual_complexity = [0.6, 0.8, 1.0, 1.2][clampi(graphics_quality, 0, 3)]
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(graphics_quality, 0, 3)]
		vp.scaling_3d_scale = 0.8 if graphics_quality == 0 else 1.0
	EventBus.settings_changed.emit()


func _apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Ambience", sfx_volume)


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var screen := DisplayServer.screen_get_size()
		var size := Vector2i(mini(resolution.x, screen.x), mini(resolution.y, screen.y)) if screen.x > 0 else resolution
		DisplayServer.window_set_size(size)
