extends Node
## Run orchestration: new game / continue / save, milestone checks, world
## completion, Thaw Sense, and per-frame syncing of the coverage texture.
## Scene construction lives in main.gd; this node holds run state.

const DEFAULT_SEED := 1337
const AUTOSAVE_INTERVAL := 90.0
const TEXTURE_HZ := 15.0
const THAW_COOLDOWN := 12.0
const THAW_DURATION := 7.0

var prog: Progression
var regions: RegionTracker
var main: Node
var world: WorldBuilder
var weather: WeatherManager
var player: Node3D
var seed_value := DEFAULT_SEED
var state := "boot"   # boot, menu, playing, cinematic, completed

var _tex_timer := 0.0
var _check_timer := 0.0
var _complete_timer := 0.0
var _autosave_timer := 0.0
var thaw_cd := 0.0
var thaw_t := -1.0
var thaw_origin := Vector2.ZERO
var current_region := -1


func _ready() -> void:
	_new_progression()


func _new_progression() -> void:
	prog = Progression.new()
	prog.frost_changed.connect(func(v): EventBus.frost_changed.emit(v))
	prog.cores_changed.connect(func(v): EventBus.cores_changed.emit(v))
	prog.purchased.connect(func(id, lv): EventBus.upgrade_purchased.emit(id, lv))
	prog.ability_unlocked.connect(_on_ability_unlocked)
	regions = RegionTracker.new()
	regions.region_milestone.connect(_on_region_milestone)
	regions.world_milestone.connect(_on_world_milestone)


func coverage() -> SnowCoverage:
	return world.coverage if world != null else null


func set_state(s: String) -> void:
	state = s
	EventBus.game_state_changed.emit(s)


# ------------------------------------------------------------------ runs
func start_new_game(modifiers: Array = [], plus_level: int = 0) -> void:
	var old_plus := plus_level
	_new_progression()
	prog.modifiers = modifiers.duplicate()
	prog.plus_level = old_plus
	if "frost_head_start" in modifiers:
		prog.add_frost(150.0 * maxi(old_plus, 1))
	world.coverage.reset()
	weather.clear_all()
	weather.setup(world.terrain, world.coverage, prog, true, seed_value + old_plus)
	current_region = -1
	_autosave_timer = 0.0
	main.begin_play(true)
	set_state("playing")
	EventBus.frost_changed.emit(prog.frost)
	EventBus.cores_changed.emit(prog.cores)
	EventBus.coverage_changed.emit(0.0)


func continue_game() -> bool:
	var d := SaveManager.read()
	if d.is_empty():
		return false
	_new_progression()
	prog.from_dict(d.get("progression", {}))
	regions.from_array(d.get("regions", []))
	if not SaveManager.restore_coverage(d, world.coverage):
		world.coverage.reset()
	prog.world_fraction = world.coverage.world_completion()
	weather.clear_all()
	weather.setup(world.terrain, world.coverage, prog, true, seed_value)
	weather.from_array(d.get("weather", []))
	current_region = -1
	_autosave_timer = 0.0
	main.begin_play(false)
	if player != null and player.has_method("restore_state"):
		player.restore_state(d.get("player", {}))
	set_state("playing")
	EventBus.frost_changed.emit(prog.frost)
	EventBus.cores_changed.emit(prog.cores)
	EventBus.coverage_changed.emit(prog.world_fraction)
	return true


func save_game() -> bool:
	if world == null or state == "menu" or state == "boot":
		return false
	var pdata := {}
	if player != null and player.has_method("save_state"):
		pdata = player.save_state()
	var data := SaveManager.build(seed_value, prog, regions, world.coverage, pdata, weather.to_array())
	var ok := SaveManager.write(data)
	if ok:
		EventBus.save_written.emit()
	return ok


func save_summary() -> Dictionary:
	var d := SaveManager.read()
	if d.is_empty():
		return {}
	var p: Dictionary = d.get("progression", {})
	var st: Dictionary = p.get("stats", {})
	return {"fraction": float(d.get("world_fraction", 0.0)), "time": float(st.get("time", 0.0)),
		"completed": bool(p.get("completed", false)), "plus": int(p.get("plus_level", 0))}


# ------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if world == null or not world.built:
		return
	var cov := world.coverage
	_tex_timer += delta
	if _tex_timer >= 1.0 / TEXTURE_HZ:
		_tex_timer = 0.0
		cov.update_texture()
	_update_thaw(delta)
	if state != "playing" and state != "completed":
		return
	prog.stats["time"] = float(prog.stats.get("time", 0.0)) + delta
	_check_timer += delta
	if _check_timer >= 0.5:
		_check_timer = 0.0
		var wf := cov.world_completion()
		prog.world_fraction = wf
		regions.check(cov, prog)
		EventBus.coverage_changed.emit(wf)
		ShaderLib.set_global("wo_completion", wf)
		_update_region()
	if not prog.completed and state == "playing":
		_complete_timer += delta
		if _complete_timer >= 1.0:
			_complete_timer = 0.0
			_check_completion()
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game()


func _update_region() -> void:
	if player == null:
		return
	var r := world.terrain.region_at(player.global_position.x, player.global_position.z)
	if r != current_region:
		current_region = r
		EventBus.region_changed.emit(r)


func _check_completion() -> void:
	var cov := world.coverage
	if cov.world_completion() < 0.985:
		return
	var g := cov.cleanup_pass()
	if g > 0.0:
		prog.add_frost(g * prog.stat("frost_mult"))
	if cov.is_world_complete():
		complete_world()


func complete_world() -> void:
	if prog.completed:
		return
	var g := world.coverage.freeze_all()
	prog.add_frost(g * prog.stat("frost_mult"))
	regions.check(world.coverage, prog)
	prog.world_fraction = 1.0
	prog.completed = true
	EventBus.coverage_changed.emit(1.0)
	ShaderLib.set_global("wo_completion", 1.0)
	EventBus.world_completed.emit()
	set_state("cinematic")
	save_game()
	main.play_completion()


func finish_cinematic() -> void:
	set_state("completed")


func keep_exploring() -> void:
	set_state("completed")
	main.resume_after_completion()


# ------------------------------------------------------------ thaw sense
func can_thaw_sense() -> bool:
	return prog.has("thaw_sense") and thaw_cd <= 0.0


func use_thaw_sense(origin: Vector3) -> bool:
	if not can_thaw_sense():
		return false
	thaw_cd = THAW_COOLDOWN
	thaw_t = 0.0
	thaw_origin = Vector2(origin.x, origin.z)
	EventBus.thaw_sense_pulse.emit(origin)
	return true


func _update_thaw(delta: float) -> void:
	thaw_cd = maxf(thaw_cd - delta, 0.0)
	if thaw_t < 0.0:
		return
	thaw_t += delta
	var radius := thaw_t / THAW_DURATION * 760.0
	var strength := 1.0 - smoothstep(THAW_DURATION * 0.6, THAW_DURATION, thaw_t)
	ShaderLib.set_global("wo_thaw", Vector4(thaw_origin.x, thaw_origin.y, radius, strength))
	if thaw_t >= THAW_DURATION:
		thaw_t = -1.0
		ShaderLib.set_global("wo_thaw", Vector4.ZERO)


# --------------------------------------------------------------- signals
func _on_ability_unlocked(id: String) -> void:
	EventBus.ability_unlocked.emit(id)
	EventBus.notify.emit("NEW WEATHER POWER", GameBalance.ABILITIES[id]["name"].to_upper(), "unlock")
	Audio.play("core")
	save_game()


func _on_region_milestone(r: int, percent: int, bonus: float, core: bool) -> void:
	EventBus.region_milestone.emit(r, percent, bonus, core)
	if core:
		Audio.play("milestone")
		save_game()
	else:
		Audio.play("purchase", -4.0, 0.8)


func _on_world_milestone(fraction: float, n: int) -> void:
	EventBus.world_milestone.emit(fraction, n)
	EventBus.notify.emit("WINTER CORE EARNED", "The world is %d%% frozen" % int(round(fraction * 100.0)), "core")
	Audio.play("core")
