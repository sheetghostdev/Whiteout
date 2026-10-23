extends Node
## Headless test runner.
##   godot --headless --path . res://scenes/tests.tscn            (standard suite)
##   godot --headless --path . res://scenes/tests.tscn -- balance (adds the full strategy matrix)
##   godot --headless --path . res://scenes/tests.tscn -- only=economy

var passed := 0
var failed := 0
var failures: Array[String] = []
var current := ""
var terrain: TerrainData


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append("[%s] %s" % [current, msg])
		print("    FAIL: ", msg)


func approx(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (got %s, expected %s ± %s)" % [msg, a, b, eps])


func shared_terrain() -> TerrainData:
	if terrain == null:
		terrain = TerrainData.new()
		terrain.generate(Game.DEFAULT_SEED)
	return terrain


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	for a in args:
		if a.begins_with("only="):
			only = a.substr(5)
	var suites := [
		["coverage", TestCoverage.new()],
		["economy", TestEconomy.new()],
		["interactions", TestStormInteractions.new()],
		["save_load", TestSaveLoad.new()],
		["performance", TestPerformance.new()],
		["assets", TestNoAssets.new()],
		["game_flow", TestGameFlow.new()],
		["progression", TestProgressionBot.new()],
	]
	var t0 := Time.get_ticks_msec()
	for s in suites:
		if only != "" and s[0] != only:
			continue
		current = s[0]
		print("== ", current)
		var suite = s[1]
		await suite.run(self, "balance" in args)
	print("")
	print("Tests: %d passed, %d failed  (%.1f s)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	for f in failures:
		print("  ", f)
	get_tree().quit(1 if failed > 0 else 0)
