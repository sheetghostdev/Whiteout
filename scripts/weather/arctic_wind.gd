class_name ArcticWind
extends WeatherEffect
## A directional (or, with Cyclonic Flow, circular) gust. It contributes to
## the shared wind field that moves clouds and storms, speeds up frost
## fronts, and dusts the ground under its leading edge with frost.

const GUST_SPEED := 32.0

var origin := Vector2.ZERO
var dir := Vector2(0, -1)
var length := 45.0
var width := 12.0
var strength := 7.0
var transport := 0.12
var snowfield := 0.0
var steer := false
var cyclonic := false
var ring_r := 20.0
var front_dist := 0.0
var theta := 0.0
var swept := 0.0
var snow_load := 0.0

var _ribbons: Array[MeshInstance3D] = []
var _ribbon_mats: Array[ShaderMaterial] = []
var _particles: GPUParticles3D
var _arrows: MeshInstance3D


func init_from_stats(prog: Progression) -> void:
	kind = "arctic_wind"
	var jet := prog.has("jet_stream")
	strength = prog.stat("wind_strength") * (1.3 if jet else 1.0)
	width = prog.stat("wind_width")
	length = prog.stat("wind_range") * (1.5 if jet else 1.0)
	life = prog.stat("wind_duration") * prog.stat("duration_mult") * (2.5 if jet else 1.0)
	transport = prog.stat("wind_transport") * prog.stat("efficiency_mult")
	snowfield = prog.stat("wind_snowfield")
	steer = prog.has("wind_steering")
	radius = length * 0.5


func envelope() -> float:
	return smoothstep(0.0, 0.5, age) * (1.0 - smoothstep(life - 1.5, life, age))


## Wind velocity this gust contributes at point p.
func wind_contrib(p: Vector2) -> Vector2:
	var env := envelope()
	if env <= 0.0:
		return Vector2.ZERO
	if cyclonic:
		var rel := p - origin
		var d := rel.length()
		if d < 1.0 or d > ring_r * 1.6:
			return Vector2.ZERO
		var fall := clampf(1.0 - absf(d - ring_r) / (ring_r * 0.65), 0.0, 1.0)
		var tang := Vector2(-rel.y, rel.x) / d
		return (tang * strength - rel / d * strength * 0.12) * fall * env
	var r := p - origin
	var along := r.dot(dir)
	if along < -4.0 or along > length:
		return Vector2.ZERO
	var lat := absf(r.cross(dir))
	var hw := width * 0.5
	if lat > hw:
		return Vector2.ZERO
	var q := lat / hw
	var tail := 1.0 - smoothstep(length * 0.8, length, along)
	return dir * strength * (1.0 - q * q) * tail * env


func sim_step(dt: float) -> void:
	var cov := manager.cov
	age += dt
	if age >= life:
		kill()
		return
	if steer and not cyclonic:
		var aim := manager.player_aim
		if aim.length() > 0.1:
			dir = dir.slerp(aim.normalized(), 1.0 - exp(-dt * 1.5)).normalized()
	var amount := transport
	if cyclonic:
		if swept < TAU * 2.0:
			var dth := GUST_SPEED / ring_r * dt
			var a := origin + Vector2.from_angle(theta) * ring_r
			var b := origin + Vector2.from_angle(theta + dth) * ring_r
			var gain := cov.apply_sweep(a.x, a.y, b.x, b.y, width * 0.3, amount)
			manager.add_gain(gain, cov.last_cov_delta, self)
			theta += dth
			swept += dth
	elif front_dist < length:
		var nd := minf(front_dist + GUST_SPEED * dt, length)
		var a := origin + dir * front_dist
		var b := origin + dir * nd
		var c := cov.get_coverage(b.x, b.y)
		# Snowfield Updraft: pick up snow over white ground, drop it on green ground.
		if snowfield > 0.0:
			if c > 0.85:
				snow_load = minf(snow_load + dt * 1.5, 1.0)
			else:
				amount *= 1.0 + snow_load * snowfield * 3.0
				snow_load = maxf(snow_load - dt * 0.6, 0.0)
		var gain := cov.apply_sweep(a.x, a.y, b.x, b.y, width * 0.45, amount)
		manager.add_gain(gain, cov.last_cov_delta, self)
		front_dist = nd
	pos = origin + (Vector2.ZERO if cyclonic else dir * length * 0.5)


func setup_visuals() -> void:
	var n := clampi(int(width / 4.0) + 2, 3, 8)
	for k in n:
		var ribbon := MeshInstance3D.new()
		ribbon.mesh = WeatherFX.strip_mesh()
		var mat := WeatherFX.effect_material(3, Color(0.92, 0.97, 1.0, 0.55))
		mat.set_shader_parameter("follow_terrain", true)
		mat.set_shader_parameter("terrain_lift", 1.2 + manager.rng.randf() * 3.5)
		mat.set_shader_parameter("speed", 0.7 + manager.rng.randf() * 0.5)
		ribbon.material_override = mat
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribbon.extra_cull_margin = 60.0
		ribbon.set_meta("lat", (float(k) / maxf(n - 1, 1) - 0.5) * width * 0.8)
		add_child(ribbon)
		_ribbons.append(ribbon)
		_ribbon_mats.append(mat)
	if cyclonic:
		_arrows = WeatherFX.decal(1, Color(0.85, 0.95, 1.0, 0.35))
	else:
		_arrows = WeatherFX.decal(4, Color(0.85, 0.95, 1.0, 0.35))
	_arrows.top_level = true
	add_child(_arrows)
	var box := Vector3(width * 0.4, 2.0, 2.0)
	var v := Vector3(0, 0, strength * 1.6)
	_particles = WeatherFX.streaks(box, int(30 + width * 3), v, length / maxf(v.length(), 1.0))
	_particles.local_coords = false
	add_child(_particles)
	global_position = Vector3(origin.x, sim_height(origin), origin.y)


func visual_update(_delta: float, _t: float) -> void:
	if _ribbons.is_empty():
		return
	var env := envelope() if alive else 0.0
	var f := vis * env
	if cyclonic:
		global_position = Vector3(origin.x, sim_height(origin) + 1.5, origin.y)
		rotation.y += _delta * strength / maxf(ring_r, 1.0)
		for k in _ribbons.size():
			var rb := _ribbons[k]
			var a := TAU * k / _ribbons.size()
			rb.position = Vector3(cos(a), 0, sin(a)) * ring_r
			rb.rotation = Vector3(0, -a, 0)
			rb.scale = Vector3(2.0, 1.0, ring_r * 0.9)
			_ribbon_mats[k].set_shader_parameter("fade", f)
		_arrows.global_position = Vector3(origin.x, 0, origin.y)
		_arrows.scale = Vector3(ring_r * 1.1, 1.0, ring_r * 1.1)
		(_arrows.material_override as ShaderMaterial).set_shader_parameter("intensity", f)
		_particles.emitting = alive
		return
	global_position = Vector3(origin.x, sim_height(origin), origin.y)
	rotation = Vector3(0, atan2(dir.x, dir.y), 0)
	for k in _ribbons.size():
		var rb := _ribbons[k]
		rb.position = Vector3(float(rb.get_meta("lat")), 0, 0)
		rb.scale = Vector3(1.6, 1.0, length)
		_ribbon_mats[k].set_shader_parameter("fade", f)
	_arrows.global_position = global_position
	_arrows.rotation = rotation
	_arrows.scale = Vector3(width, 1.0, length)
	(_arrows.material_override as ShaderMaterial).set_shader_parameter("intensity", f * 0.8)
	_particles.emitting = alive and env > 0.3


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d.merge({"origin": [origin.x, origin.y], "dir": [dir.x, dir.y], "length": length, "width": width,
		"strength": strength, "cyclonic": cyclonic, "ring_r": ring_r, "front": front_dist, "swept": swept, "theta": theta})
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	var o: Array = d.get("origin", [0, 0])
	origin = Vector2(o[0], o[1])
	var dd: Array = d.get("dir", [0, -1])
	dir = Vector2(dd[0], dd[1]).normalized()
	length = float(d.get("length", length))
	width = float(d.get("width", width))
	strength = float(d.get("strength", strength))
	cyclonic = bool(d.get("cyclonic", false))
	ring_r = float(d.get("ring_r", ring_r))
	front_dist = float(d.get("front", 0.0))
	swept = float(d.get("swept", 0.0))
	theta = float(d.get("theta", 0.0))
