class_name TestGameFlow
extends RefCounted
## Boots the real main scene (headless) and drives the full loop:
## new game -> drift -> buy -> save -> main menu -> continue -> complete world.

const PATH := "user://test_flow_save.json"


func _frames(t, n: int) -> void:
	for i in n:
		await (t as Node).get_tree().process_frame


func _until(t, cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await (t as Node).get_tree().process_frame
	return cond.call()


func run(t, _full: bool) -> void:
	SaveManager.delete_save(PATH)
	Game.save_path = PATH
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(t as Node).get_tree().root.add_child.call_deferred(main)
	t.check(await _until(t, func(): return Game.state == "menu", 3000), "game boots to the main menu")
	t.check(Game.save_summary().is_empty(), "no save before the first game")
	Game.start_new_game()
	await _frames(t, 3)
	t.check(Game.state == "playing", "new game starts")
	t.check(Game.main.hud.visible and not Game.main.main_menu.visible, "HUD replaces the menu")
	var p: CloudController = Game.player
	var c: PlayerCloud = Game.weather.cloud
	t.check(c != null and c.alive, "you start as a snow cloud")
	t.check(p.camera.current, "third-person camera is active")
	p.autopilot = true
	for i in 60:
		Game.weather.advance(0.05)
	t.check(Game.prog.frost == 0.0, "a resting cloud earns nothing")
	c.move_input = Vector2(1, 0)
	for i in 120:
		Game.weather.advance(0.05)
	c.move_input = Vector2.ZERO
	await _frames(t, 2)
	t.check(Game.prog.frost > 0.0, "snowfall earns Frost in the running game")
	Game.prog.add_frost(100.0)
	t.check(Game.prog.purchase("billow"), "web purchase works in game")
	c.move_input = Vector2(1, 0)
	for i in 40:
		Game.weather.advance(0.05)
	c.move_input = Vector2.ZERO
	await _frames(t, 2)
	t.check(p.global_position.distance_to(Vector3(c.pos.x, p.global_position.y, c.pos.y)) < 1.0, "the rig follows the cloud")
	p.autopilot = false
	Game.main.open_overlay("shop")
	await _frames(t, 2)
	t.check(Game.main.web.visible and not p.input_enabled, "upgrade web opens and stops steering")
	var shown := 0
	for id in GameBalance.NODES:
		if (Game.main.web._buttons[id] as Control).visible:
			shown += 1
	t.check(shown > 3 and shown < 20, "the web shows only the nearby part of itself (%d nodes)" % shown)
	Game.main.close_overlay()
	Game.main.open_overlay("pause")
	await _frames(t, 1)
	t.check((t as Node).get_tree().paused, "pause menu pauses the game")
	Game.main.close_overlay()
	t.check(not (t as Node).get_tree().paused, "resume unpauses")
	var frac := Game.world.coverage.world_completion()
	var frost := Game.prog.frost
	c.pos += Vector2(5, 0)
	var pos := c.pos
	p.yaw = 1.0
	t.check(Game.save_game(), "game saves")
	Game.main.show_main_menu()
	await _frames(t, 2)
	t.check(Game.state == "menu", "returned to the main menu")
	t.check(not Game.save_summary().is_empty(), "menu sees the saved game")
	Game.world.coverage.reset()
	t.check(Game.continue_game(), "continue loads the save")
	await _frames(t, 2)
	t.approx(Game.world.coverage.world_completion(), frac, 0.0001, "coverage restored on continue")
	t.approx(Game.prog.frost, frost, 0.01, "Frost restored on continue")
	t.check(Game.prog.level("billow") == 1, "upgrades restored on continue")
	t.check(Game.weather.cloud != null and Game.weather.cloud.pos.distance_to(pos) < 0.5, "cloud position restored")
	t.approx(p.yaw, 1.0, 0.001, "camera restored")
	# Completion flow, sped up.
	Engine.time_scale = 8.0
	for k in 3:
		Game.world.coverage.apply_disc(0, 0, 400.0, 1.0)
	Game.complete_world()
	t.check(Game.state == "cinematic" and Game.prog.completed, "completing the world starts the ending")
	t.check(Game.world.coverage.world_completion() == 1.0, "world is fully frozen at completion")
	t.check(await _until(t, func(): return Game.main.completion.visible, 4000), "completion screen appears after the cinematic")
	Engine.time_scale = 1.0
	Game.keep_exploring()
	await _frames(t, 2)
	t.check(Game.state == "completed" and p.input_enabled, "player can keep exploring the frozen world")
	t.check(Game.save_summary().get("completed", false), "completed state saved")
	# New Winter+ resets the world but keeps the run count.
	Game.start_new_game(["extra_cloud"], 1)
	await _frames(t, 2)
	t.check(Game.world.coverage.world_completion() == 0.0 and Game.prog.plus_level == 1, "New Winter+ starts a fresh world")
	t.check(Game.prog.stat("companions") == 1.0, "New Winter+ modifier applies")
	Game.main.show_main_menu()
	main.queue_free()
	await _frames(t, 2)
	SaveManager.delete_save(PATH)
	Game.save_path = SaveManager.PATH
