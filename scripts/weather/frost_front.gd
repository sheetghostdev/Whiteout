class_name FrostFront
extends WeatherEffect
## Frost Wave: a low wave of freezing air that rolls across the terrain
## surface, depositing a fixed amount of snow on every cell it sweeps.

var dir := Vector2(0, -1)
var width := 4.0
var speed := 9.0
var remaining := 35.0
var total := 35.0
var strength := 0.45
var rebounds := 0
var branch_chance := 0.0
var splinter := false
var glide := 0.15
var traveled := 0.0

var _curtain: MeshInstance3D
var _mat: ShaderMaterial
var _spray: GPUParticles3D
var _rot := 0.0


func configure(p_width: float, p_length: float, p_splinter: bool) -> void:
	kind = "frost_front"
	width = p_width
	speed = 26.0
	total = p_length
	remaining = total
	strength = 1.0
	rebounds = 0
	branch_chance = 0.0
	splinter = p_splinter
	glide = 0.15
	life = 999.0
	radius = width * 0.5


func setup_visuals() -> void:
	_curtain = MeshInstance3D.new()
	_curtain.mesh = MeshFactory.curtain(24, 4, 0.12)
	_mat = WeatherFX.effect_material(0, Color(0.88, 0.95, 1.0, 0.85))
	_mat.set_shader_parameter("follow_terrain", true)
	_mat.set_shader_parameter("terrain_lift", -0.2)
	_mat.set_shader_parameter("height_scale", 1.6 + width * 0.09)
	_mat.set_shader_parameter("speed", 1.0)
	_curtain.material_override = _mat
	_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_curtain.extra_cull_margin = 40.0
	add_child(_curtain)
	_spray = WeatherFX.streaks(Vector3(width * 0.5, 0.4, 0.4), int(20 + width * 6), Vector3(0, 1.2, speed * 0.4), 0.9)
	_spray.local_coords = false
	add_child(_spray)
	_rot = atan2(dir.x, dir.y)
	global_position = Vector3(pos.x, sim_height(pos), pos.y)


func sim_step(dt: float) -> void:
	var cov := manager.cov
	var terrain := manager.terrain
	age += dt
	var boost := 1.0
	var consume := 1.0
	# Waves glide faster over ground that is already white.
	if cov.get_coverage(pos.x, pos.y) >= 0.95:
		boost *= 1.0 + glide
	var step := speed * boost * dt
	var ahead := pos + dir * 3.0
	var out := not terrain.in_bounds(ahead.x, ahead.y, 5.0)
	var climb := (terrain.sample_height(ahead.x, ahead.y) - terrain.sample_height(pos.x, pos.y)) / 3.0
	if out or climb > 1.8:
		if rebounds > 0:
			rebounds -= 1
			var n: Vector2
			if out:
				n = -Vector2(signf(ahead.x) if absf(ahead.x) > absf(ahead.y) else 0.0, signf(ahead.y) if absf(ahead.y) >= absf(ahead.x) else 0.0)
			else:
				n = -terrain.gradient(ahead.x, ahead.y).normalized()
			dir = dir.bounce(n).normalized()
			return
		_finish()
		return
	var np := pos + dir * step
	var gain := cov.apply_sweep(pos.x, pos.y, np.x, np.y, width * 0.5, strength, 1.0)
	manager.add_gain(gain, cov.last_cov_delta, self)
	pos = np
	traveled += step
	remaining -= step * consume
	if branch_chance > 0.0 and generation < 2 and manager.rng.randf() < branch_chance * step / 10.0:
		var s := 1.0 if manager.rng.randf() < 0.5 else -1.0
		_spawn_child(dir.rotated(s * 1.1), width * 0.5, minf(remaining * 0.5, 40.0))
	if remaining <= 0.0:
		_finish()


func _spawn_child(d: Vector2, w: float, dist: float) -> void:
	if not manager.can_spawn("frost_front"):
		return
	var f := FrostFront.new()
	f.configure(w, dist, false)
	f.dir = d.normalized()
	f.width = maxf(w, 2.0)
	f.radius = f.width * 0.5
	f.splinter = splinter
	f.generation = generation + 1
	f.pos = pos
	manager.spawn(f, root_id)


func _finish() -> void:
	kill()
	if splinter and generation < 2:
		for s in [-1.0, 1.0]:
			_spawn_child(dir.rotated(s * 0.87), width * 0.65, total * 0.5)


func visual_update(delta: float, t: float) -> void:
	if _curtain == null:
		return
	var p := interp_pos(t)
	global_position = Vector3(p.x, sim_height(p), p.y)
	var target := atan2(dir.x, dir.y)
	_rot = lerp_angle(_rot, target, 1.0 - exp(-delta * 8.0))
	rotation = Vector3(0, _rot, 0)
	_curtain.scale = Vector3(width * 1.1, 1.0, 1.0)
	var f := vis
	if alive:
		f *= clampf(remaining / 6.0, 0.2, 1.0)
	_mat.set_shader_parameter("fade", f)
	_spray.emitting = alive


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d.merge({"dir": [dir.x, dir.y], "width": width, "speed": speed, "remaining": remaining, "total": total,
		"strength": strength, "rebounds": rebounds})
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	var dd: Array = d.get("dir", [0, -1])
	dir = Vector2(dd[0], dd[1]).normalized()
	width = float(d.get("width", width))
	speed = float(d.get("speed", speed))
	remaining = float(d.get("remaining", remaining))
	total = float(d.get("total", total))
	strength = float(d.get("strength", strength))
	rebounds = int(d.get("rebounds", 0))
