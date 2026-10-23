extends Node
## Builds the scene at runtime (world, weather, player, UI) and routes input
## between gameplay and the overlay screens.

var world: WorldBuilder
var weather: WeatherManager
var player: PlayerController
var ui: CanvasLayer
var hud: HUD
var shop: UpgradeShop
var pause_menu: PauseMenu
var settings_menu: SettingsMenu
var guide: WeatherGuide
var map_ui: OverviewMap
var completion: CompletionScreen
var main_menu: MainMenu
var loading: LoadingScreen
var letterbox: Control
var menu_cam: Camera3D
var beacons: Node3D
var ambient: GPUParticles3D
var cinematic: CompletionCinematic
var overlay := ""          # "", shop, pause, settings, guide, map, completion
var _settings_return := ""
var _guide_return := ""
var _menu_t := 0.0
var _tut_timer := 0.0


func _ready() -> void:
	Game.main = self
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	loading = LoadingScreen.new()
	ui.add_child(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	Game.world = world
	world.progress.connect(loading.set_progress)
	await world.generate(Game.seed_value, Settings.vegetation_density)
	world.foliage.apply_draw_distance(Settings.draw_distance)
	weather = WeatherManager.new()
	weather.name = "Weather"
	add_child(weather)
	Game.weather = weather
	weather.setup(world.terrain, world.coverage, Game.prog, true, Game.seed_value)
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.setup(world.terrain)
	Game.player = player
	player.spawn_at(TerrainData.SPAWN, 0.0)
	menu_cam = Camera3D.new()
	menu_cam.far = 3200.0
	menu_cam.fov = 60.0
	add_child(menu_cam)
	beacons = Node3D.new()
	add_child(beacons)
	_build_ambient()
	_build_ui()
	map_ui.build_relief(world.terrain, world.renderer.colors)
	# The title screen shows the saved world as the player left it.
	var d := SaveManager.read(Game.save_path)
	if not d.is_empty():
		SaveManager.restore_coverage(d, world.coverage)
		ShaderLib.set_global("wo_completion", world.coverage.world_completion())
	world.coverage.update_texture()
	EventBus.thaw_sense_pulse.connect(_on_thaw)
	EventBus.settings_changed.connect(_on_settings)
	EventBus.upgrade_purchased.connect(func(_id, _lv): hud.refresh_all())
	EventBus.cores_changed.connect(_on_cores_tutorial)
	_on_settings()
	var tw := create_tween()
	tw.tween_property(loading, "modulate:a", 0.0, 0.8)
	tw.tween_callback(loading.hide)
	show_main_menu()
	if "--autostart" in OS.get_cmdline_user_args():
		Game.start_new_game()


func _build_ui() -> void:
	hud = HUD.new()
	ui.add_child(hud)
	hud.visible = false
	shop = UpgradeShop.new()
	ui.add_child(shop)
	shop.visible = false
	shop.closed.connect(close_overlay)
	map_ui = OverviewMap.new()
	ui.add_child(map_ui)
	map_ui.visible = false
	map_ui.closed.connect(close_overlay)
	guide = WeatherGuide.new()
	ui.add_child(guide)
	guide.visible = false
	guide.closed.connect(_close_guide)
	pause_menu = PauseMenu.new()
	ui.add_child(pause_menu)
	pause_menu.visible = false
	pause_menu.resume.connect(close_overlay)
	pause_menu.open_settings.connect(func(): _open_settings("pause"))
	pause_menu.open_guide.connect(func(): _open_guide("pause"))
	pause_menu.to_main_menu.connect(func():
		Game.save_game()
		show_main_menu())
	pause_menu.quit_game.connect(func():
		Game.save_game()
		get_tree().quit())
	completion = CompletionScreen.new()
	ui.add_child(completion)
	completion.visible = false
	completion.keep_exploring.connect(func(): Game.keep_exploring())
	completion.new_winter_plus.connect(func(mods): Game.start_new_game(mods, Game.prog.plus_level + 1))
	completion.to_main_menu.connect(show_main_menu)
	main_menu = MainMenu.new()
	ui.add_child(main_menu)
	main_menu.new_game.connect(func(): Game.start_new_game())
	main_menu.continue_game.connect(func():
		if not Game.continue_game():
			main_menu.refresh())
	main_menu.new_winter_plus.connect(func():
		var s := Game.save_summary()
		Game.start_new_game(["extra_cloud"], int(s.get("plus", 0)) + 1))
	main_menu.open_settings.connect(func(): _open_settings("menu"))
	main_menu.quit_game.connect(func(): get_tree().quit())
	settings_menu = SettingsMenu.new()
	ui.add_child(settings_menu)
	settings_menu.visible = false
	settings_menu.closed.connect(_close_settings)
	letterbox = Control.new()
	UIKit.full_rect(letterbox)
	letterbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.01, 0.02, 0.05)
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 90)
		if not top:
			bar.position.y = -90
		letterbox.add_child(bar)
	letterbox.visible = false
	ui.add_child(letterbox)
	ui.move_child(loading, ui.get_child_count() - 1)


func _build_ambient() -> void:
	# Light drifting flakes around the camera once the world starts to whiten.
	ambient = WeatherFX.streaks(Vector3(40, 12, 40), 160, Vector3(0.6, -0.8, 0.3), 9.0)
	ambient.local_coords = false
	ambient.emitting = false
	add_child(ambient)


# --------------------------------------------------------------- flow
func show_main_menu() -> void:
	get_tree().paused = false
	overlay = ""
	_hide_overlays()
	if Game.state != "boot":
		weather.clear_all()
	Game.set_state("menu")
	player.input_enabled = false
	player.targeting.hide_all()
	hud.visible = false
	main_menu.visible = true
	main_menu.refresh()
	menu_cam.current = true
	letterbox.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func begin_play(is_new: bool) -> void:
	get_tree().paused = false
	main_menu.visible = false
	_hide_overlays()
	overlay = ""
	if cinematic != null:
		cinematic.queue_free()
		cinematic = null
	letterbox.visible = false
	if is_new:
		player.spawn_at(TerrainData.SPAWN, 0.0)
		world.coverage.update_texture()
		ShaderLib.set_global("wo_completion", 0.0)
		_tut_timer = 0.0
	player.camera.current = true
	player.input_enabled = true
	player.abilities.selected = "snow_cloud"
	hud.visible = true
	hud.refresh_all()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_new:
		EventBus.notify.emit("WELCOME TO WHITEOUT", "Aim at the grass and hold Left Mouse to summon a snow cloud.", "info")


func _hide_overlays() -> void:
	for c in [shop, pause_menu, settings_menu, guide, map_ui, completion]:
		c.visible = false


func open_overlay(which: String) -> void:
	overlay = which
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match which:
		"shop":
			shop.open()
			Audio.play("click", -6.0, 0.8)
		"map":
			map_ui.open()
		"pause":
			get_tree().paused = true
			pause_menu.open()
		"guide":
			guide.open()


func close_overlay() -> void:
	_hide_overlays()
	overlay = ""
	get_tree().paused = false
	if Game.state == "playing" or Game.state == "completed":
		player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.refresh_all()


func _open_settings(from: String) -> void:
	_settings_return = from
	pause_menu.visible = false
	main_menu.visible = false
	settings_menu.open()


func _close_settings() -> void:
	settings_menu.visible = false
	if _settings_return == "pause":
		pause_menu.open()
	else:
		main_menu.visible = true


func _open_guide(from: String) -> void:
	_guide_return = from
	pause_menu.visible = false
	if from != "pause":
		open_overlay("guide")
	else:
		guide.open()


func _close_guide() -> void:
	guide.visible = false
	if _guide_return == "pause":
		pause_menu.open()
	else:
		close_overlay()


func play_completion() -> void:
	_hide_overlays()
	overlay = "completion"
	player.input_enabled = false
	player.targeting.hide_all()
	hud.visible = false
	for e in weather.effects:
		e.life = minf(e.life, e.age + 2.5)
		if e is FrostFront or e is Avalanche or e is FrostPulse:
			e.kill()
	Audio.play("complete")
	letterbox.visible = true
	letterbox.modulate.a = 0.0
	create_tween().tween_property(letterbox, "modulate:a", 1.0, 1.5)
	cinematic = CompletionCinematic.new()
	add_child(cinematic)
	cinematic.start(player.camera.global_transform, world.terrain)
	cinematic.finished.connect(_on_cinematic_done)


func _on_cinematic_done() -> void:
	Game.finish_cinematic()
	letterbox.visible = false
	completion.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_after_completion() -> void:
	completion.visible = false
	if cinematic != null:
		cinematic.queue_free()
		cinematic = null
	overlay = ""
	player.camera.current = true
	player.input_enabled = true
	hud.visible = true
	hud.refresh_all()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# -------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if Game.state != "playing" and Game.state != "completed":
		return
	if overlay == "":
		if event.is_action_pressed("pause"):
			open_overlay("pause")
		elif event.is_action_pressed("upgrades"):
			open_overlay("shop")
		elif event.is_action_pressed("map"):
			if Game.prog.has("overview_map"):
				open_overlay("map")
			else:
				EventBus.ability_failed.emit("map", "Buy the Overview Map in the General upgrades")
		elif event.is_action_pressed("guide"):
			_open_guide("game")
		elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if Game.state == "playing" and overlay == "":
			open_overlay("pause")


func _process(delta: float) -> void:
	if world == null or not world.built:
		return
	if Game.state == "menu":
		_menu_t += delta * 0.025
		var c := Vector3(10, 0, -10)
		var p := c + Vector3(sin(_menu_t) * 250.0, 0.0, cos(_menu_t) * 250.0)
		p.y = world.terrain.surface_height(p.x, p.z) + 70.0
		menu_cam.global_position = menu_cam.global_position.lerp(p, 1.0 - exp(-delta * 2.0)) if menu_cam.global_position != Vector3.ZERO else p
		menu_cam.look_at(c + Vector3(0, 20, 0))
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var cp := cam.global_position
		ambient.global_position = cp + Vector3(0, 6, 0)
		ambient.emitting = world.coverage.world_completion() > 0.12 and Game.state != "menu"
		var presence := weather.storm_presence(Vector2(cp.x, cp.z))
		world.atmosphere.set_storm_darkness(presence * 0.8, delta)
		Audio.storm_level = presence
		Audio.wind_level = clampf(weather.wind_at(Vector2(cp.x, cp.z)).length() / 15.0, 0.0, 1.0)
		ShaderLib.set_global("wo_wind", weather.wind_at(Vector2(cp.x, cp.z)))
	_update_tutorial(delta)


func _update_tutorial(delta: float) -> void:
	if Game.state != "playing":
		return
	var st := Game.prog.stats
	var tut: Array = st.get("tut", [])
	_tut_timer += delta
	if not "shop" in tut and Game.prog.frost >= 10.0:
		tut.append("shop")
		EventBus.notify.emit("FROST EARNED", "Freshly frozen ground earns Frost. Press TAB to spend it on upgrades.", "info")
	if not "move" in tut and _tut_timer > 70.0:
		tut.append("move")
		EventBus.notify.emit("TIP", "Snow only pays once per patch of ground - keep moving to fresh green grass.", "info")
	st["tut"] = tut


func _on_cores_tutorial(n: int) -> void:
	if n <= 0 or Game.state != "playing":
		return
	var tut: Array = Game.prog.stats.get("tut", [])
	if not "core" in tut:
		tut.append("core")
		Game.prog.stats["tut"] = tut
		EventBus.notify.emit("WINTER CORE", "Winter Cores unlock new weather powers. Look in the upgrade menu (TAB).", "core")


func _on_thaw(origin: Vector3) -> void:
	for b in beacons.get_children():
		b.queue_free()
	var patches := world.coverage.unfrozen_patches(14)
	for p in patches:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshFactory.open_cylinder(1.6, 0.6, 16, 6)
		var mat := WeatherFX.effect_material(2, Color(1.0, 0.72, 0.38, 0.7))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var y := world.terrain.surface_height(p.x, p.z)
		mi.position = Vector3(p.x, y, p.z)
		mi.scale = Vector3(1.0 + p.y / 80.0, 70.0, 1.0 + p.y / 80.0)
		beacons.add_child(mi)
		var delay := origin.distance_to(mi.position) / (760.0 / Game.THAW_DURATION)
		mat.set_shader_parameter("fade", 0.0)
		var tw := mi.create_tween()
		tw.tween_interval(delay)
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.6)
		tw.tween_interval(14.0)
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, 2.0)
		tw.tween_callback(mi.queue_free)
	EventBus.notify.emit("THAW SENSE", "%d unfrozen patches revealed" % patches.size() if patches.size() > 0 else "No unfrozen ground remains.", "hint")


func _on_settings() -> void:
	if world == null or world.foliage == null:
		return
	world.foliage.apply_draw_distance(Settings.draw_distance)
	world.atmosphere.apply_quality([0, 1, 2, 3][Settings.graphics_quality], Settings.graphics_quality >= 1)
	if ambient:
		ambient.amount = maxi(4, int(160 * Settings.particle_density))
