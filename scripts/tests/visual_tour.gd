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
		"snowcheck":
			await _snowcheck()
		"island":
			await _island()
		"round3":
			await _round3()
		"round4":
			await _round4()
		"edge":
			await _edge()
		"edgewake":
			for id in ["billow", "flurry", "snow_wake", "long_wake"]:
				Game.prog.levels[id] = 2 if id != "snow_wake" else 1
			await _edge()
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


func _look(yaw_deg: float, pitch_deg: float, zoom: float = 1.0) -> void:
	var p: CloudController = Game.player
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = deg_to_rad(pitch_deg)
	p.zoom = zoom


func _cloud() -> PlayerCloud:
	return Game.weather.cloud


func _skill(id: String, aim: Vector2 = Vector2(0, -1)) -> String:
	Game.weather.cooldowns[id] = 0.0
	return Game.weather.use_skill(id, aim)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, Game.world.terrain.surface_height(x, z), z)


func _fly(dir: Vector2, seconds: float) -> void:
	Game.player.autopilot = true
	var c := _cloud()
	c.move_input = dir
	await _sleep(seconds)
	c.move_input = Vector2.ZERO
	Game.player.autopilot = false


func _basic() -> void:
	Game.start_new_game()
	await _frames(20)
	_look(0, -32)
	await _sleep(1.5)
	await _shot("01_start")
	await _fly(Vector2(0, -1), 4.0)
	await _sleep(1.0)
	await _shot("02_drift")
	# A mid-game cloud: bigger, with cloudlets and a wake.
	var prog := Game.prog
	prog.add_frost(60000)
	for id in ["billow", "flurry", "breeze", "cloudlet", "squall", "more_cloudlets", "swell", "gale", "snow_wake", "heavy_snow"]:
		for i in 5:
			prog.purchase(id)
	Game.main.hud.refresh_all()
	await _sleep(1.0)
	await _fly(Vector2(-0.6, -0.8), 5.0)
	_look(30, -30)
	await _sleep(1.2)
	await _shot("03_mid_cloud")
	print("squall: ", _skill("squall"))
	await _sleep(0.6)
	await _shot("04_squall")
	Game.main.open_overlay("shop")
	await _frames(10)
	await _shot("05_web")
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
	_look(0, -25)
	await _sleep(1.5)
	await _shot("10_winter_meadow")
	_cloud().pos = Vector2(-48, 128)
	_look(-40, -20, 1.8)
	await _sleep(1.5)
	await _shot("11_winter_overlook")
	_cloud().pos = Vector2(100, 50)
	_look(-150, -18, 1.6)
	await _sleep(1.5)
	await _shot("12_winter_lake")


func _ui() -> void:
	Game.start_new_game()
	await _frames(10)
	Game.prog.add_frost(900)
	Game.main.hud.refresh_all()
	await _frames(10)
	await _shot("19_hud")
	Game.main.open_overlay("shop")
	await _frames(10)
	await _shot("20_web_start")
	for id in ["billow", "flurry", "squall", "breeze", "ice_creep"]:
		Game.main.web._buy(id)
	Game.prog.add_frost(400)
	Game.main.web._refresh()
	Game.main.web._set_hover("dense_core")
	await _frames(10)
	await _shot("20b_web_grown")
	Game.main.close_overlay()
	Game.main.open_overlay("pause")
	await _frames(5)
	await _shot("21_pause")
	Game.main.close_overlay()
	Game.prog.add_frost(500)
	Game.prog.purchase("ice_creep")
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


func _fx() -> void:
	Game.start_new_game()
	await _frames(10)
	var prog := Game.prog
	prog.add_frost(1e8)
	prog.world_fraction = 1.0
	TestEconomy.buy_everything(prog)
	prog.levels["thunderhead"] = 0
	prog.levels["sky_giant"] = 0
	prog.levels["towering"] = 0
	Game.main.hud.refresh_all()
	var cov := Game.world.coverage
	# Lake: partially frozen, with ice creeping outward.
	cov.apply_disc(120, -10, 30.0, 1.0)
	cov.apply_disc(120, -10, 30.0, 1.0)
	cov.apply_disc(150, 10, 18.0, 0.6)
	cov.update_texture()
	_cloud().pos = Vector2(95, 30)
	_look(-45, -25, 1.3)
	await _sleep(2.0)
	await _shot("30_lake_partial")
	_cloud().pos = Vector2(-20, 60)
	_look(0, -30, 1.2)
	await _sleep(2.0)
	print("wave ", _skill("frost_wave", Vector2(0, -1)))
	await _sleep(1.2)
	await _shot("31_frost_wave")
	print("vortex ", _skill("vortex_form"))
	await _sleep(2.5)
	_look(0, -40, 1.4)
	await _sleep(1.0)
	await _shot("32_vortex")
	await _sleep(prog.stat("vortex_time"))
	# Avalanche on a snowy mountain slope.
	cov.apply_disc(-40, -170, 45.0, 1.0)
	cov.apply_disc(-40, -170, 45.0, 1.0)
	cov.update_texture()
	var slope := _find_release(Vector2(-40, -170))
	print("slope ", slope)
	_cloud().pos = slope
	Game.weather.cooldowns["avalanche"] = 0.0
	print("av ", Game.weather.try_ride_avalanche(slope))
	_look(170, -25, 1.6)
	await _sleep(2.5)
	await _shot("33_avalanche")
	await _sleep(2.5)
	await _shot("34_avalanche_later")
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


func _snowcheck() -> void:
	Game.start_new_game()
	await _frames(10)
	var cov := Game.world.coverage
	cov.apply_disc(0, 60, 40.0, 1.0)
	cov.apply_disc(0, 60, 40.0, 1.0)
	cov.update_texture()
	_cloud().pos = Vector2(0, 75)
	_look(0, -35, 0.7)
	await _sleep(2.0)
	await _shot("50_done_close")
	_look(60, -60, 1.0)
	await _sleep(1.5)
	await _shot("51_done_top")
	# A natural trail flown by the cloud.
	Game.prog.add_frost(500)
	for id in ["billow", "flurry", "breeze"]:
		for i in 5:
			Game.prog.purchase(id)
	_cloud().pos = Vector2(-60, 120)
	_look(90, -40, 1.0)
	await _fly(Vector2(1, 0), 6.0)
	await _sleep(1.0)
	await _shot("52_trail")


func _view(x: float, z: float, yaw: float, pitch: float, zoom: float, shot: String, wait: float = 1.5) -> void:
	_cloud().pos = Vector2(x, z)
	_cloud().vel = Vector2.ZERO
	_look(yaw, pitch, zoom)
	await _sleep(wait)
	await _shot(shot)


func _island() -> void:
	Game.start_new_game()
	await _frames(10)
	await _view(60, 112, 200, -28, 1.3, "60_village")
	await _view(-100, 72, 160, -30, 1.4, "61_farm")
	await _view(76, 40, 230, -25, 1.2, "62_hamlet")
	await _view(10, 170, 0, -18, 2.4, "63_south_coast")
	await _view(-30, -120, 180, -22, 2.4, "64_north_mountains")
	await _view(-20, -140, 220, -30, 1.6, "65_tarn")
	await _view(150, 150, 160, -28, 2.0, "66_river_mouth")
	# Snow on the village: people bundle up and shiver.
	var cov := Game.world.coverage
	for k in 3:
		cov.apply_disc(70, 145, 45.0, 0.35)
	cov.update_texture()
	await _view(62, 128, 200, -20, 0.5, "67_village_snowing", 3.0)
	for k in 3:
		cov.apply_disc(70, 145, 45.0, 1.0)
	cov.update_texture()
	await _view(60, 112, 200, -28, 1.3, "68_village_frozen", 2.0)
	await _view(60, 136, 230, -15, 0.45, "69_shivering", 2.5)


func _round3() -> void:
	Game.start_new_game()
	await _frames(10)
	var crops: MeshInstance3D = Game.world.settlements.get_node("Crops")
	(crops.material_override as ShaderMaterial).set_shader_parameter("grow_seconds", 20.0)
	await _sleep(3.0)
	await _view(-110, 104, 160, -24, 0.9, "70_crops_growing", 2.0)
	var cov := Game.world.coverage
	cov.apply_sweep(-150, 100, -100, 150, 9.0, 1.0, 1.0)
	cov.update_texture()
	await _view(-110, 104, 160, -24, 0.9, "71_crops_snowed", 3.0)
	await _view(-125, 118, 120, -14, 0.5, "72_crops_close", 2.0)
	# The cloud rises over rooftops.
	var church: Dictionary = Game.world.terrain.settlements.buildings[9]
	var cp: Vector2 = church["pos"]
	await _view(cp.x, cp.y, 90, -6, 1.1, "73_over_church", 4.0)
	var house: Dictionary = Game.world.terrain.settlements.buildings[2]
	var hp: Vector2 = house["pos"]
	await _view(hp.x, hp.y, 0, -6, 1.1, "74_over_house", 4.0)
	# A real flown trail seen low and close, like a player sees it.
	Game.player.autopilot = true
	_cloud().pos = Vector2(-40, 60)
	await _sleep(0.5)
	_look(30, -22, 0.8)
	await _fly(Vector2(0.8, 0.6).normalized(), 5.0)
	await _fly(Vector2(-0.6, 0.8).normalized(), 3.0)
	await _sleep(1.0)
	await _shot("75_trail_low")
	# The compass points to the last green ground.
	Game.prog.levels["snow_compass"] = 1
	for k in 3:
		cov.apply_disc(0, 0, 400.0, 1.0)
	cov.apply_disc(-140, -20, 6.0, -1.0)
	for z in range(-30, -10):
		for x in range(-150, -130):
			cov.cov[(z + 256) * SnowCoverage.N + x + 256] = 0.0
	cov.deserialize(cov.serialize())
	cov.update_texture()
	Game.prog.world_fraction = cov.world_completion()
	ShaderLib.set_global("wo_completion", cov.world_completion())
	await _view(60, 60, 0, -25, 1.2, "76_compass", 2.0)
	await _view(60, 60, 180, -25, 1.2, "76b_compass_behind", 2.0)
	await _view(-120, 10, 90, -30, 1.2, "77_last_green", 2.0)


func _round4() -> void:
	Game.start_new_game()
	await _frames(10)
	var cov := Game.world.coverage
	# A real flown trail, low and close, with the snowfall ring showing.
	_cloud().pos = Vector2(-40, 60)
	await _sleep(0.5)
	_look(30, -24, 0.8)
	await _fly(Vector2(0.8, 0.6).normalized(), 5.0)
	await _fly(Vector2(-0.6, 0.8).normalized(), 3.0)
	await _sleep(1.0)
	await _shot("80_trail_ring")
	# Crops frost over at once, then wither slowly.
	var sb: SettlementBuilder = Game.world.settlements
	cov.apply_sweep(-150, 100, -100, 150, 9.0, 1.0, 1.0)
	cov.update_texture()
	await _view(-110, 104, 160, -24, 0.9, "81_crops_frosted", 2.0)
	for k in sb._wither.size():
		if sb._wither_cells[k] >= 0 and cov.cov[sb._wither_cells[k]] >= 1.0:
			sb._wither[k] = 0.5
	sb._upload_wither()
	await _view(-110, 104, 160, -24, 0.9, "82_crops_half", 1.0)
	for k in sb._wither.size():
		if sb._wither_cells[k] >= 0 and cov.cov[sb._wither_cells[k]] >= 1.0:
			sb._wither[k] = 1.0
	sb._upload_wither()
	await _view(-110, 104, 160, -24, 0.9, "83_crops_dead", 1.0)
	# Snow covering only the front of a roof.
	var house: Dictionary = Game.world.terrain.settlements.buildings[2]
	var hp: Vector2 = house["pos"]
	cov.apply_disc(hp.x - 6.0, hp.y + 4.0, 5.0, 1.0, 1, 0, 1.0)
	cov.update_texture()
	await _view(hp.x - 14.0, hp.y + 14.0, 225, -20, 0.8, "84_roof_partial", 2.0)
	# Water: lake outlet, river mouth, the stream entering the lake.
	await _view(150, 40, 200, -30, 1.3, "85_outlet", 2.0)
	await _view(176, 196, 210, -26, 1.3, "86_mouth", 2.0)
	await _view(118, -30, 140, -30, 1.3, "87_lake_inflow", 2.0)
	# Everything frozen: the snow reaches the waterline on the beach.
	for k in 3:
		cov.apply_disc(0, 0, 400.0, 1.0)
	cov.update_texture()
	await _view(176, 196, 210, -26, 1.3, "88_mouth_frozen", 2.0)
	var t: TerrainData = Game.world.terrain
	var beach := Vector2(0, 0)
	for k in 260:
		var q := Vector2(-40.0, 0.0 + k)
		if t.sample_height(q.x, q.y) < TerrainData.SEA_LEVEL:
			beach = q - Vector2(0, 12)
			break
	await _view(beach.x, beach.y, 180, -26, 1.1, "89_beach_frozen", 2.0)


## Close looks at a freshly flown snow edge, from above and from low down.
func _edge() -> void:
	var keep: Dictionary = Game.prog.levels.duplicate()
	Game.start_new_game()
	await _frames(10)
	for id in keep:
		Game.prog.levels[id] = keep[id]
	_cloud().pos = Vector2(-40, 60)
	await _sleep(0.5)
	await _fly(Vector2(0.8, 0.6).normalized(), 4.0)
	await _fly(Vector2(-0.6, 0.8).normalized(), 2.0)
	await _sleep(1.0)
	_look(30, -70, 0.6)
	await _sleep(1.0)
	await _shot("90_edge_top")
	_look(120, -30, 0.5)
	await _sleep(1.0)
	await _shot("91_edge_low")
	# While flying, seen from behind and above like the player sees it.
	Game.player.autopilot = true
	_look(200, -55, 1.0)
	_cloud().move_input = Vector2(-0.8, 0.6).normalized()
	await _sleep(2.5)
	await _shot("92_edge_flying")
	await _sleep(0.7)
	await _shot("93_edge_flying2")
	_cloud().move_input = Vector2.ZERO
