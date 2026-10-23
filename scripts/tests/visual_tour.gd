extends Node
## Development tool: boots the real game, performs scripted actions and saves
## screenshots to user://tour/. Run with a display (or xvfb):
##   godot --path . res://scenes/visual_tour.tscn -- [scenario]

var main: Node
var out_dir := "user://tour"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _wait_until(func(): return Game.world != null and Game.world.built and Game.state == "menu", 120.0)
	await _frames(30)
	await _shot("00_menu")
	var args := OS.get_cmdline_user_args()
	var scenario := args[0] if args.size() > 0 else "basic"
	match scenario:
		"basic":
			await _basic()
		"late":
			await _late()
		"ui":
			await _ui()
		"fx":
			await _fx()
		"complete":
			await _complete()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


func _look(yaw_deg: float, pitch_deg: float) -> void:
	var p: PlayerController = Game.player
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = deg_to_rad(pitch_deg)
	p.rotation = Vector3(0, p.yaw, 0)
	p.head.rotation = Vector3(p.pitch, 0, 0)


func _cast(id: String, target: Vector3) -> String:
	var p: PlayerController = Game.player
	var ctx := {"origin": p.eye_position(), "aim": (target - p.eye_position()).normalized(), "target": target, "hit": true, "feet": p.global_position}
	Game.weather.cooldowns[id] = 0.0
	return Game.weather.try_cast(id, ctx)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, Game.world.terrain.surface_height(x, z), z)


func _basic() -> void:
	Game.start_new_game()
	await _frames(20)
	_look(0, -12)
	await _shot("01_start")
	print("cloud: ", _cast("snow_cloud", _ground(3, 72)))
	await _sleep(2.5)
	await _shot("02_cloud")
	await _sleep(3.0)
	await _shot("03_after_cloud")
	# Unlock everything for an effects showcase.
	var prog := Game.prog
	prog.add_frost(1e7)
	prog.add_cores(30)
	for id in ["unlock_frost_front", "unlock_arctic_wind", "unlock_blizzard", "unlock_avalanche", "unlock_polar_vortex", "cloud_drift"]:
		prog.purchase(id)
	for i in 6:
		prog.purchase("cloud_radius")
	for i in 10:
		prog.purchase("cast_range")
	Game.main.hud.refresh_all()
	print("front: ", _cast("frost_front", _ground(0, 40)))
	await _sleep(1.5)
	await _shot("04_front")
	print("wind: ", _cast("arctic_wind", _ground(0, 40)))
	_cast("snow_cloud", _ground(-6, 58))
	await _sleep(2.0)
	await _shot("05_wind_cloud")
	print("blizzard: ", _cast("blizzard", _ground(10, 20)))
	await _sleep(3.0)
	_look(0, -5)
	await _shot("06_blizzard")
	print("vortex: ", _cast("polar_vortex", _ground(-60, -20)))
	await _sleep(4.0)
	_look(-30, 2)
	await _shot("07_vortex")
	Game.main.open_overlay("shop")
	await _frames(10)
	await _shot("08_shop")
	Game.main.close_overlay()


func _late() -> void:
	Game.start_new_game()
	await _frames(10)
	var cov := Game.world.coverage
	# Freeze almost everything, leaving a few green patches for contrast.
	var keep := [Vector2(10, 90), Vector2(-150, 40), Vector2(140, 10), Vector2(-60, -170)]
	for z in range(-256, 257, 6):
		for x in range(-256, 257, 6):
			var near := false
			for k in keep:
				if Vector2(x, z).distance_to(k) < 26.0:
					near = true
			if not near:
				cov.apply_disc(x, z, 5.0, 1.0)
	cov.update_texture()
	ShaderLib.set_global("wo_completion", 1.0)
	_look(0, -10)
	await _frames(20)
	await _shot("10_winter_meadow")
	var p: PlayerController = Game.player
	p.global_position = Vector3(-48, Game.world.terrain.surface_height(-48, 128) + 0.5, 128)
	_look(-40, -12)
	await _frames(20)
	await _shot("11_winter_overlook")
	p.global_position = Vector3(100, Game.world.terrain.surface_height(100, 50) + 0.5, 50)
	_look(-150, -8)
	await _frames(20)
	await _shot("12_winter_lake")


func _ui() -> void:
	Game.start_new_game()
	await _frames(10)
	Game.prog.add_frost(5000)
	Game.prog.add_cores(3)
	Game.main.open_overlay("shop")
	await _frames(10)
	await _shot("20_shop")
	Game.main.close_overlay()
	Game.main.open_overlay("pause")
	await _frames(5)
	await _shot("21_pause")
	Game.main.close_overlay()
	Game.prog.purchase("cloud_radius")
	Game.prog.purchase("cloud_radius")
	Game.prog.purchase("overview_map")
	Game.main.open_overlay("map")
	await _frames(10)
	await _shot("22_map")
	Game.main.close_overlay()
	Game.main._open_guide("game")
	await _frames(5)
	await _shot("23_guide")
	Game.main._close_guide()
	Game.main._open_settings("menu")
	await _frames(5)
	await _shot("24_settings")


func _place(x: float, z: float, yaw: float, pitch: float, lift: float = 0.0) -> void:
	var p: PlayerController = Game.player
	p.global_position = Vector3(x, Game.world.terrain.surface_height(x, z) + lift, z)
	p.velocity = Vector3.ZERO
	p.flying = lift > 1.0
	_look(yaw, pitch)


func _fx() -> void:
	Game.start_new_game()
	await _frames(10)
	var prog := Game.prog
	prog.add_frost(1e8)
	prog.add_cores(40)
	TestStormInteractions.buy_everything(prog)
	Game.main.hud.refresh_all()
	var cov := Game.world.coverage
	# Lake: partially frozen, with ice creeping outward.
	cov.apply_disc(120, -10, 30.0, 1.0)
	cov.apply_disc(120, -10, 30.0, 1.0)
	cov.apply_disc(150, 10, 18.0, 0.6)
	cov.update_texture()
	_place(88, 40, -45, -12, 6.0)
	await _sleep(1.0)
	await _shot("30_lake_partial")
	# Blizzard seen from a distance.
	print("bz ", _cast("blizzard", _ground(-20, 0)))
	_place(-20, 90, 0, -6, 25.0)
	await _sleep(4.0)
	await _shot("31_blizzard_far")
	# Polar vortex from high up.
	print("pv ", _cast("polar_vortex", _ground(-60, -60)))
	_place(-60, 60, 0, -18, 60.0)
	await _sleep(5.0)
	await _shot("32_vortex_far")
	# Avalanche on a snowy mountain slope.
	cov.apply_disc(-40, -170, 45.0, 1.0)
	cov.apply_disc(-40, -170, 45.0, 1.0)
	cov.update_texture()
	var slope := _find_release(Vector2(-40, -170))
	print("slope ", slope)
	_place(slope.x + 10, slope.y + 70, 10, -12, 30.0)
	print("av ", _cast("avalanche", _ground(slope.x, slope.y)))
	await _sleep(2.5)
	await _shot("33_avalanche")
	await _sleep(2.5)
	await _shot("34_avalanche_later")
	# Frost fronts and wind from behind the player.
	_place(-120, 160, 20, -8, 0.5)
	await _sleep(0.5)
	print("ff ", _cast("frost_front", _ground(-130, 130)))
	await _sleep(1.5)
	await _shot("35_fronts")
	print("aw ", _cast("arctic_wind", _ground(-130, 130)))
	for k in 4:
		Game.weather.cooldowns["snow_cloud"] = 0.0
		_cast("snow_cloud", _ground(-125 + k * 6, 140))
	await _sleep(2.5)
	await _shot("36_wind_clouds")
	Game.use_thaw_sense(Game.player.global_position)
	await _sleep(2.0)
	await _shot("37_thaw_sense")


func _find_release(around: Vector2) -> Vector2:
	var t := Game.world.terrain
	var best := around
	var bs := 0.0
	for z in range(-30, 31, 4):
		for x in range(-30, 31, 4):
			var p := around + Vector2(x, z)
			if Avalanche.release_check(t, Game.world.coverage, p) == "":
				var s := t.slope(p.x, p.y)
				if s > bs:
					bs = s
					best = p
	return best


func _complete() -> void:
	Game.start_new_game()
	await _frames(10)
	Game.world.coverage.apply_disc(0, 0, 400.0, 1.0)
	Game.world.coverage.apply_disc(0, 0, 400.0, 1.0)
	Game.world.coverage.apply_disc(0, 0, 400.0, 1.0)
	Game.prog.stats["time"] = 3655.0
	Game.complete_world()
	await _sleep(3.0)
	await _shot("40_cinematic_a")
	await _sleep(6.0)
	await _shot("41_cinematic_b")
	await _wait_until(func(): return Game.main.completion.visible, 40.0)
	await _sleep(1.5)
	await _shot("42_completion")


func _sleep(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()
