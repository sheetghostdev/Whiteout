class_name WeatherManager
extends Node3D
## Owns all active weather: the player's cloud and everything it sets off.
## Simulation runs on a fixed 30 Hz clock. The player cloud steps every tick
## so steering stays crisp; other effects advance every third tick
## (staggered by id) so heavy storms spread their cost across frames.
## Visuals interpolate at the render rate and never affect the simulation.

signal effect_spawned(effect: WeatherEffect)

const TICK := 1.0 / 30.0
const PHASES := 3

var terrain: TerrainData
var cov: SnowCoverage
var prog: Progression
var visuals := true
var effects: Array[WeatherEffect] = []
var cloud: PlayerCloud
var cooldowns := {}
var rng := RandomNumberGenerator.new()
var sim_time := 0.0
var tick := 0
var prevailing := Vector2(0.35, 0.15)
var chain_counts := {}
var root_sources := {}       # root uid -> what started the chain
var area_by_source := {}     # source -> m² frozen by its whole chain
var frost_rate := 0.0        # smoothed Frost per second for the HUD
var _acc := 0.0
var _uid := 1
var _pending_frost := 0.0
var _rate_window := 0.0
var _rate_accum := 0.0


func setup(p_terrain: TerrainData, p_cov: SnowCoverage, p_prog: Progression, p_visuals: bool, p_seed: int) -> void:
	terrain = p_terrain
	cov = p_cov
	prog = p_prog
	visuals = p_visuals
	rng.seed = p_seed * 7919 + 13
	cooldowns = {}
	for id in GameBalance.SKILLS:
		cooldowns[id] = 0.0
	cooldowns["avalanche"] = 0.0


## Creates the player's cloud at a world position (replacing any old one).
func spawn_player_cloud(at: Vector2) -> PlayerCloud:
	if cloud != null and is_instance_valid(cloud):
		cloud.kill()
		effects.erase(cloud)
		cloud.queue_free()
	var c := PlayerCloud.new()
	c.pos = at
	spawn(c)
	cloud = c
	return c


func _process(delta: float) -> void:
	advance(delta)
	if visuals:
		var now := sim_time + _acc
		for e in effects:
			var span := TICK if e.every_tick else TICK * PHASES
			var t := clampf((now - e.last_step_time) / span, 0.0, 1.0)
			e.visual_update(delta, t)


## Advances the simulation clock. Also used directly by headless tests.
func advance(delta: float) -> void:
	_acc += minf(delta, 0.25)
	while _acc >= TICK:
		_acc -= TICK
		_step()
	_flush_frost(delta)


func _step() -> void:
	tick += 1
	sim_time += TICK
	for id in cooldowns:
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - TICK)
	var snapshot := effects.duplicate()
	for e in snapshot:
		if not e.alive:
			continue
		if e.every_tick:
			e.prev_pos = e.pos
			e.sim_step(TICK)
			e.last_step_time = sim_time
		elif (e.uid + tick) % PHASES == 0:
			e.prev_pos = e.pos
			e.sim_step(TICK * PHASES)
			e.last_step_time = sim_time
	var i := effects.size() - 1
	while i >= 0:
		var e := effects[i]
		if not e.alive:
			effects.remove_at(i)
			if visuals and e.is_inside_tree():
				e.begin_dissipate()
			else:
				e.queue_free()
		i -= 1
	if tick % 15 == 0:
		# Snow drifts into small gaps where you have been snowing.
		_add_frost_raw(cov.drift_fill(24))
		# Ice creeps across water from frozen spots - only while you are
		# flying, so a resting cloud earns nothing.
		if cloud != null and cloud.is_active():
			_add_frost_raw(cov.water_spread_tick(0.5, prog.stat("ice_creep")))


# --------------------------------------------------------------- skills
func cooldown_remaining(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


## Fires an unlocked skill from the cloud. `aim` is the flat direction the
## camera faces. Returns "" on success or a short reason.
func use_skill(id: String, aim: Vector2) -> String:
	if cloud == null or not GameBalance.SKILLS.has(id):
		return "No cloud"
	if not prog.has(id):
		return "Not unlocked"
	if cooldown_remaining(id) > 0.0:
		return "Recharging"
	if aim.length() < 0.01:
		aim = Vector2(0, -1)
	aim = aim.normalized()
	match id:
		"squall":
			if count_kind("frost_pulse") >= GameBalance.MAX_PULSES:
				return "Too much weather"
			var p := FrostPulse.new()
			p.setup(cloud.pos, prog.stat("squall_radius") + cloud.radius, 0.25, "squall")
			spawn(p, -1, "squall")
		"frost_wave":
			if not can_spawn("frost_front"):
				return "Too much weather"
			var f := FrostFront.new()
			f.configure(prog.stat("wave_width"), prog.stat("wave_length"), prog.has("splinter"))
			f.dir = aim
			f.pos = cloud.pos + aim * cloud.radius * 0.5
			spawn(f, -1, "frost_wave")
		"vortex_form":
			cloud.begin_vortex(prog.stat("vortex_mult"), prog.stat("vortex_time"))
	cooldowns[id] = prog.skill_cooldown(id)
	prog.record_cast(id)
	var at := Vector3(cloud.pos.x, terrain.surface_height(cloud.pos.x, cloud.pos.y), cloud.pos.y)
	EventBus.skill_used.emit(id, at)
	return ""


## Avalanche Rider: called by the cloud when it drifts over a snowy slope.
func try_ride_avalanche(at: Vector2) -> bool:
	if not prog.has("avalanche") or cooldown_remaining("avalanche") > 0.0:
		return false
	if Avalanche.release_check(terrain, cov, at) != "":
		return false
	if Avalanche.downhill_green(terrain, cov, at) < 0.8 or not can_spawn("avalanche"):
		return false
	var av := Avalanche.new()
	av.configure(prog.stat("av_width"))
	spawn(av, -1, "avalanche")
	av.start(at, rng.randi())
	cooldowns["avalanche"] = prog.stat("av_cd")
	prog.record_cast("avalanche")
	EventBus.skill_used.emit("avalanche", Vector3(at.x, terrain.surface_height(at.x, at.y), at.y))
	return true


# -------------------------------------------------------------- spawning
func spawn(e: WeatherEffect, root: int = -1, source: String = "") -> WeatherEffect:
	e.uid = _uid
	_uid += 1
	e.root_id = root if root >= 0 else e.uid
	if root < 0:
		root_sources[e.uid] = source if source != "" else e.kind
	e.source = root_sources.get(e.root_id, e.kind)
	e.manager = self
	e.prev_pos = e.pos
	e.last_step_time = sim_time
	add_child(e)
	if visuals:
		e.setup_visuals()
	effects.append(e)
	if root >= 0:
		add_chain_link(root)
	effect_spawned.emit(e)
	return e


func add_chain_link(root: int) -> void:
	chain_counts[root] = int(chain_counts.get(root, 1)) + 1
	prog.stats["longest_chain"] = maxi(int(prog.stats.get("longest_chain", 0)), int(chain_counts[root]))


func note_storm_size(r: float) -> void:
	if r > float(prog.stats.get("largest_storm", 0.0)):
		prog.stats["largest_storm"] = r


func spawn_pulse(center: Vector2, max_r: float, strength: float, root: int, style: String) -> void:
	if count_kind("frost_pulse") >= GameBalance.MAX_PULSES:
		return
	var p := FrostPulse.new()
	p.setup(center, max_r, strength, style)
	spawn(p, root, style)


func count_kind(k: String) -> int:
	var n := 0
	for e in effects:
		if e.alive and e.kind == k:
			n += 1
	return n


func effects_of(k: String) -> Array:
	var out: Array = []
	for e in effects:
		if e.alive and e.kind == k:
			out.append(e)
	return out


func avalanche_heads() -> int:
	var n := 0
	for e in effects:
		if e.alive and e.kind == "avalanche":
			n += (e as Avalanche).alive_heads()
	return n


func can_spawn(k: String) -> bool:
	match k:
		"snow_cloud":
			return count_kind(k) < GameBalance.MAX_CLOUDS
		"frost_front":
			return count_kind(k) < GameBalance.MAX_FRONTS
		"frost_pulse":
			return count_kind(k) < GameBalance.MAX_PULSES
		"avalanche":
			return avalanche_heads() < GameBalance.MAX_AVALANCHE_HEADS
	return true


func wind_at(_p: Vector2) -> Vector2:
	return prevailing * 0.3


## Strongest storm influence at a point (0..1), for subtle lighting changes.
func storm_presence(p: Vector2) -> float:
	if cloud == null or not cloud.alive:
		return 0.0
	var d := cloud.pos.distance_to(p)
	var r := cloud.radius
	return (0.25 + 0.75 * cloud.vortex_amount()) * (1.0 - smoothstep(r * 0.8, r * 2.5 + 10.0, d))


# ------------------------------------------------------------------ frost
func add_gain(raw: float, cov_delta: float, source: WeatherEffect) -> void:
	if raw <= 0.0:
		return
	var gain := raw * prog.stat("frost_mult")
	_pending_frost += gain
	if source != null:
		source.frost_gained += gain
		area_by_source[source.source] = float(area_by_source.get(source.source, 0.0)) + cov_delta
	prog.stats["area_frozen"] = float(prog.stats.get("area_frozen", 0.0)) + cov_delta


func _add_frost_raw(raw: float) -> void:
	if raw > 0.0:
		_pending_frost += raw * prog.stat("frost_mult")


func _flush_frost(delta: float) -> void:
	_rate_window += delta
	if _pending_frost > 0.0:
		prog.add_frost(_pending_frost)
		_rate_accum += _pending_frost
		_pending_frost = 0.0
	if _rate_window >= 1.0:
		frost_rate = lerpf(frost_rate, _rate_accum / _rate_window, 0.5)
		_rate_window = 0.0
		_rate_accum = 0.0


# ------------------------------------------------------------- persistence
## Only the cloud itself is saved; short-lived storms are not worth keeping.
func to_array() -> Array:
	var out: Array = []
	for e in effects:
		if e.alive and e.kind == "player_cloud":
			out.append(e.to_dict())
	return out


func from_array(list: Array) -> void:
	for d in list:
		if String(d.get("kind", "")) == "player_cloud":
			var p: Array = d.get("pos", [TerrainData.SPAWN.x, TerrainData.SPAWN.y])
			var c := spawn_player_cloud(Vector2(p[0], p[1]))
			c.from_dict(d)


func clear_all() -> void:
	for e in effects:
		e.queue_free()
	effects.clear()
	cloud = null
