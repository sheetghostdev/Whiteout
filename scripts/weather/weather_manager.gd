class_name WeatherManager
extends Node3D
## Owns all active weather. Simulation runs on a fixed 30 Hz clock; each
## effect advances every third tick (staggered by id) so heavy storms spread
## their cost across frames. Visuals interpolate at the render rate and never
## affect the simulation.

signal effect_spawned(effect: WeatherEffect)
signal ability_cast(ability_id: String, at: Vector3)

const TICK := 1.0 / 30.0
const PHASES := 3

var terrain: TerrainData
var cov: SnowCoverage
var prog: Progression
var visuals := true
var effects: Array[WeatherEffect] = []
var abilities := {}
var cooldowns := {}
var rng := RandomNumberGenerator.new()
var sim_time := 0.0
var tick := 0
var prevailing := Vector2(0.35, 0.15)
var player_pos := Vector3.ZERO
var player_aim := Vector2(0, -1)
var chain_counts := {}
var water_rate := 0.18
var frost_rate := 0.0        # smoothed Frost per second for the HUD
var _acc := 0.0
var _uid := 1
var _pending_frost := 0.0
var _rate_window := 0.0
var _rate_accum := 0.0
var _combo_cd := {}
var _hints := {}


func setup(p_terrain: TerrainData, p_cov: SnowCoverage, p_prog: Progression, p_visuals: bool, p_seed: int) -> void:
	terrain = p_terrain
	cov = p_cov
	prog = p_prog
	visuals = p_visuals
	rng.seed = p_seed * 7919 + 13
	abilities = {
		"snow_cloud": SnowCloudAbility.new(),
		"frost_front": FrostFrontAbility.new(),
		"arctic_wind": ArcticWindAbility.new(),
		"blizzard": BlizzardAbility.new(),
		"avalanche": AvalancheAbility.new(),
		"polar_vortex": PolarVortexAbility.new(),
	}
	for id in abilities:
		abilities[id].id = id
		abilities[id].manager = self
		cooldowns[id] = 0.0
	if "west_wind" in prog.modifiers:
		prevailing = Vector2(0.9, -0.2)
	if "north_wind" in prog.modifiers:
		prevailing = Vector2(0.1, 0.9)


func _process(delta: float) -> void:
	advance(delta)
	if visuals:
		var now := sim_time + _acc
		for e in effects:
			var t := clampf((now - e.last_step_time) / (TICK * PHASES), 0.0, 1.0)
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
	var dt := TICK * PHASES
	var snapshot := effects.duplicate()
	for e in snapshot:
		if e.alive and (e.uid + tick) % PHASES == 0:
			e.prev_pos = e.pos
			e.sim_step(dt)
			e.last_step_time = sim_time
	if tick % PHASES == 0:
		WeatherInteractions.run(self, dt)
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
	# Ice creeps across water bodies from frozen spots.
	if tick % 15 == 0:
		var g := cov.water_spread_tick(0.5, water_rate * (2.5 if prog.has("frozen_highway") else 1.0))
		_add_frost_raw(g)


# -------------------------------------------------------------- spawning
func spawn(e: WeatherEffect, root: int = -1) -> WeatherEffect:
	e.uid = _uid
	_uid += 1
	e.root_id = root if root >= 0 else e.uid
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
	spawn(p, root)


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


func can_spawn(k: String, _child: bool = false) -> bool:
	match k:
		"snow_cloud":
			return count_kind(k) < GameBalance.MAX_CLOUDS
		"frost_front":
			return count_kind(k) < GameBalance.MAX_FRONTS
		"blizzard":
			return count_kind(k) < GameBalance.MAX_BLIZZARDS
		"avalanche":
			return avalanche_heads() < GameBalance.MAX_AVALANCHE_HEADS
		"polar_vortex":
			return count_kind(k) < GameBalance.MAX_VORTICES
		"arctic_wind":
			return count_kind(k) < GameBalance.MAX_WINDS
	return true


## Targets already claimed by other self-steering storms, so they spread out.
func avoid_list(exclude: WeatherEffect) -> Array:
	var out: Array = []
	for e in effects:
		if e == exclude or not e.alive:
			continue
		if e is SnowCloud and (e as SnowCloud).seek != Vector2.INF:
			out.append(Vector3(e.seek.x, e.seek.y, e.radius * 2.0))
		elif e is Blizzard and (e as Blizzard).seek != Vector2.INF:
			out.append(Vector3(e.seek.x, e.seek.y, e.radius))
		elif e is PolarVortex and (e as PolarVortex).seek != Vector2.INF:
			out.append(Vector3(e.seek.x, e.seek.y, e.radius))
	return out


func wind_at(p: Vector2) -> Vector2:
	var w := prevailing * 0.3
	for e in effects:
		if e.kind == "arctic_wind" and e.alive:
			w += (e as ArcticWind).wind_contrib(p)
	return w


## Strongest storm influence at a point (0..1), for subtle lighting changes.
func storm_presence(p: Vector2) -> float:
	var s := 0.0
	for e in effects:
		if not e.alive:
			continue
		if e.kind == "blizzard" or e.kind == "polar_vortex":
			var d := e.pos.distance_to(p)
			s = maxf(s, 1.0 - smoothstep(e.radius * 0.6, e.radius * 1.4, d))
	return s


# ------------------------------------------------------------------ frost
func add_gain(raw: float, cov_delta: float, source: WeatherEffect) -> void:
	if raw <= 0.0:
		return
	var mult := prog.stat("frost_mult")
	if source != null and source.kind == "avalanche":
		mult *= 1.0 + prog.stat("av_bounty")
	if source != null:
		source.frost_gained += raw * mult
	_pending_frost += raw * mult
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


# ----------------------------------------------------------------- combos
func discover(combo_id: String, at: Vector2) -> void:
	if not combo_id in prog.discovered_combos:
		prog.discovered_combos.append(combo_id)
		var c: Dictionary = WeatherInteractions.COMBOS[combo_id]
		EventBus.combo_discovered.emit(combo_id)
		EventBus.notify.emit("NEW COMBINATION: " + String(c["name"]).to_upper(), c["desc"], "combo")
	if sim_time - float(_combo_cd.get(combo_id, -100.0)) > 2.5:
		_combo_cd[combo_id] = sim_time
		var y := terrain.surface_height(at.x, at.y)
		EventBus.combo_triggered.emit(combo_id, Vector3(at.x, y, at.y))
		if visuals:
			var b := WeatherFX.burst(Color(0.85, 0.95, 1.0), 40, 8.0, 2.0)
			b.top_level = true
			add_child(b)
			b.global_position = Vector3(at.x, y + 3.0, at.y)
			b.emitting = true
			get_tree().create_timer(2.5).timeout.connect(b.queue_free)


func hint_once(key: String, title: String, body: String) -> void:
	if _hints.has(key) or key in prog.discovered_combos:
		return
	_hints[key] = true
	EventBus.notify.emit(title, body, "hint")


# ----------------------------------------------------------------- casting
func ability(id: String) -> WeatherAbility:
	return abilities[id]


func cooldown_remaining(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


## Returns "" on success or a short reason for failure.
func try_cast(id: String, ctx: Dictionary) -> String:
	if not prog.is_ability_unlocked(id):
		return "Locked"
	if cooldown_remaining(id) > 0.0:
		return "Recharging"
	var ab: WeatherAbility = abilities[id]
	var reason := ab.validate(ctx)
	if reason != "":
		return reason
	if not ab.cast(ctx):
		return "Too much weather"
	cooldowns[id] = prog.cooldown_for(id)
	prog.record_cast(id)
	var at: Vector3 = ctx.get("target", Vector3.ZERO)
	ability_cast.emit(id, at)
	EventBus.ability_cast.emit(id, at)
	return ""


func try_alt(id: String, ctx: Dictionary) -> String:
	if not prog.is_ability_unlocked(id):
		return "Locked"
	var ab: WeatherAbility = abilities[id]
	return ab.alt_cast(ctx)


func guide_kind(kind_id: String, target: Vector2, duration: float) -> int:
	var n := 0
	for e in effects:
		if e.alive and e.kind == kind_id:
			e.guide_target = target
			e.guide_time = duration
			n += 1
	return n


# ------------------------------------------------------------- persistence
func to_array() -> Array:
	var out: Array = []
	for e in effects:
		if e.alive:
			out.append(e.to_dict())
	return out


func from_array(list: Array) -> void:
	for d in list:
		var e: WeatherEffect = null
		match String(d.get("kind", "")):
			"snow_cloud":
				var c := SnowCloud.new()
				c.init_from_stats(prog)
				e = c
			"frost_front":
				var f := FrostFront.new()
				f.init_from_stats(prog)
				e = f
			"arctic_wind":
				var w := ArcticWind.new()
				w.init_from_stats(prog)
				e = w
			"blizzard":
				var b := Blizzard.new()
				b.init_from_stats(prog)
				e = b
			"avalanche":
				var a := Avalanche.new()
				a.init_from_stats(prog)
				e = a
			"polar_vortex":
				var v := PolarVortex.new()
				v.init_from_stats(prog)
				e = v
			"frost_pulse":
				var p := FrostPulse.new()
				p.setup(Vector2.ZERO, 10.0, 0.5, "thunder")
				e = p
		if e == null:
			continue
		e.from_dict(d)
		spawn(e)


func clear_all() -> void:
	for e in effects:
		e.queue_free()
	effects.clear()
