class_name FrostPulse
extends WeatherEffect
## An expanding ring of frost. Each cell inside the final radius is swept
## exactly once, receiving `strength` coverage.

var max_r := 10.0
var r := 0.0
var speed := 18.0
var strength := 0.5
var style := "thunder"

var _ring: MeshInstance3D
var _mat: ShaderMaterial
var _burst: GPUParticles3D


func setup(center: Vector2, p_max_r: float, p_strength: float, p_style: String) -> void:
	kind = "frost_pulse"
	pos = center
	prev_pos = center
	max_r = p_max_r
	strength = p_strength
	style = p_style
	speed = clampf(max_r * 0.9, 14.0, 70.0)
	life = max_r / speed + 0.1
	radius = 0.0


func sim_step(dt: float) -> void:
	var cov := manager.cov
	age += dt
	var nr := minf(r + speed * dt, max_r)
	var gain := cov.apply_ring(pos.x, pos.y, r, nr, strength)
	manager.add_gain(gain, cov.last_cov_delta, self)
	r = nr
	radius = r
	if r >= max_r:
		kill()


func setup_visuals() -> void:
	var col := Color(0.82, 0.95, 1.0, 0.85)
	if style == "absolute_zero":
		col = Color(0.75, 0.88, 1.0, 0.95)
	elif style == "shock":
		col = Color(0.7, 0.95, 1.0, 0.95)
	_ring = WeatherFX.decal(1, col)
	_ring.top_level = true
	_mat = _ring.material_override
	add_child(_ring)
	_burst = WeatherFX.burst(Color(0.9, 0.97, 1.0), int(20 + max_r), 6.0 + max_r * 0.15, 1.5)
	add_child(_burst)
	_burst.emitting = true
	global_position = Vector3(pos.x, sim_height(pos) + 1.0, pos.y)


func visual_update(_delta: float, t: float) -> void:
	if _ring == null:
		return
	var cur := minf(r + speed * WeatherManager.TICK * WeatherManager.PHASES * t, max_r) if alive else max_r
	_ring.global_position = Vector3(pos.x, 0, pos.y)
	_ring.scale = Vector3(maxf(cur, 0.5), 1.0, maxf(cur, 0.5))
	_mat.set_shader_parameter("ring_width", clampf(3.0 / maxf(cur, 1.0), 0.015, 0.6))
	var f := vis * (1.0 - smoothstep(0.75, 1.0, cur / max_r)) if alive else vis
	_mat.set_shader_parameter("intensity", f * 1.4)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d.merge({"max_r": max_r, "r": r, "speed": speed, "strength": strength, "style": style})
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	max_r = float(d.get("max_r", max_r))
	r = float(d.get("r", 0.0))
	speed = float(d.get("speed", speed))
	strength = float(d.get("strength", strength))
	style = String(d.get("style", style))
