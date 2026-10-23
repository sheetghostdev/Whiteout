class_name WeatherEffect
extends Node3D
## Base for every active weather system. Simulation state (pos, vel, radius,
## lifetime...) is advanced by WeatherManager at a fixed rate; the node's
## visuals interpolate between simulation steps every rendered frame.

var kind := ""
var uid := 0
var root_id := 0          # id of the cast that started this chain
var source := ""          # ability whose cast started this chain
var generation := 0
var manager: WeatherManager
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var vel := Vector2.ZERO
var ext_v := Vector2.ZERO  # extra target velocity from interactions (vortex orbits)
var radius := 1.0
var rate := 0.0
var life := 1.0
var age := 0.0
var alive := true
var frost_gained := 0.0
var guide_target := Vector2.INF
var guide_time := 0.0
var last_step_time := 0.0
var step_dt := 0.1
var vis := 0.0            # visual fade 0..1
var _dying := false


func setup_visuals() -> void:
	pass


## Advances the simulation by dt seconds.
func sim_step(_dt: float) -> void:
	pass


## Per-frame visual update; t is 0..1 between the previous and current step.
func visual_update(_delta: float, _t: float) -> void:
	pass


func sim_height(p: Vector2) -> float:
	return manager.terrain.surface_height(p.x, p.y)


func interp_pos(t: float) -> Vector2:
	return prev_pos.lerp(pos, t)


func remaining_fraction() -> float:
	return clampf(1.0 - age / maxf(life, 0.001), 0.0, 1.0)


func kill() -> void:
	alive = false


## Movement shared by drifting storms. `own` is self-propelled velocity.
func integrate_motion(dt: float, own: Vector2, wind_response: float, responsiveness: float) -> void:
	var target_v := own + manager.wind_at(pos) * wind_response + ext_v
	ext_v = Vector2.ZERO
	if guide_target != Vector2.INF and guide_time > 0.0:
		var to := guide_target - pos
		if to.length() > 2.0:
			target_v += to.normalized() * minf(to.length(), 12.0) * manager.prog.stat("guide_strength")
		guide_time -= dt
	vel = vel.lerp(target_v, 1.0 - exp(-dt * responsiveness))
	pos += vel * dt
	var lim := GameBalance.WORLD_HALF - 1.0
	if absf(pos.x) > lim:
		pos.x = signf(pos.x) * lim
		vel.x *= -0.5
	if absf(pos.y) > lim:
		pos.y = signf(pos.y) * lim
		vel.y *= -0.5


func to_dict() -> Dictionary:
	return {"kind": kind, "pos": [pos.x, pos.y], "vel": [vel.x, vel.y], "radius": radius, "rate": rate,
		"life": life, "age": age, "gen": generation}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0])
	pos = Vector2(p[0], p[1])
	prev_pos = pos
	var v: Array = d.get("vel", [0, 0])
	vel = Vector2(v[0], v[1])
	radius = float(d.get("radius", radius))
	rate = float(d.get("rate", rate))
	life = float(d.get("life", life))
	age = float(d.get("age", 0.0))
	generation = int(d.get("gen", 0))


## Starts a short visual fade-out after the simulation removed this effect.
func begin_dissipate() -> void:
	_dying = true


func _process(delta: float) -> void:
	if manager == null or not manager.visuals:
		return
	if _dying:
		vis = maxf(vis - delta * 1.2, 0.0)
		visual_update(delta, 1.0)
		if vis <= 0.0:
			queue_free()
	else:
		vis = minf(vis + delta * 1.5, 1.0)
