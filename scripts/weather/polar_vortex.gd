class_name PolarVortex
extends WeatherEffect
## The ultimate weather system: an enormous roaming spiral that freezes a vast
## radius, pulls other storms into orbit, absorbs clouds and emits pulses.

var speed := 3.0
var nav := 0.3
var attract := 1.6
var orbit_cap := 6
var pulse_rate := 2.0
var absorb := 1.0
var absolute_zero := false
var pulse_timer := 10.0
var az_timer := 15.0
var seek := Vector2.INF
var seek_timer := 0.0
var bonus := 0.0
var wander := 0.0
var step_count := 0
var orbiting := 0

var _spiral: MeshInstance3D
var _spiral_mat: ShaderMaterial
var _spiral2: MeshInstance3D
var _funnel: MeshInstance3D
var _funnel_mat: ShaderMaterial
var _ring_clouds: Node3D
var _cloud_mats: Array[ShaderMaterial] = []
var _snow: GPUParticles3D
var _ground: MeshInstance3D
var _y := 0.0
var _built_radius := 0.0


func init_from_stats(prog: Progression) -> void:
	kind = "polar_vortex"
	radius = prog.stat("pv_radius")
	life = prog.stat("pv_life") * prog.stat("duration_mult")
	speed = prog.stat("pv_speed")
	rate = prog.stat("pv_rate") * prog.stat("efficiency_mult")
	orbit_cap = int(prog.stat("pv_orbit"))
	attract = prog.stat("pv_attract")
	pulse_rate = prog.stat("pv_pulse")
	absorb = prog.stat("pv_absorb")
	nav = prog.stat("pv_nav")
	absolute_zero = prog.has("absolute_zero")
	if prog.has("endless_winter"):
		life *= 3.0
		nav = minf(nav * 1.5 + 0.2, 1.0)
	pulse_timer = 60.0 / pulse_rate * 0.5


func altitude() -> float:
	return 34.0 + radius * 0.2


func sim_step(dt: float) -> void:
	var cov := manager.cov
	age += dt
	if age >= life:
		kill()
		return
	seek_timer -= dt
	if seek_timer <= 0.0 or seek == Vector2.INF:
		seek = cov.find_nearest_unfrozen_area(pos, 420.0, 30, manager.avoid_list(self))
		seek_timer = 3.0
	wander += manager.rng.randf_range(-0.25, 0.25) * dt
	var own := Vector2.from_angle(wander) * speed * (1.0 - nav)
	if seek != Vector2.INF and seek.distance_to(pos) > radius * 0.2:
		own += (seek - pos).normalized() * speed * nav * 1.6 * manager.prog.stat("storm_nav")
	integrate_motion(dt, own, 0.25, 0.4)
	var area := PI * radius * radius
	var stride := clampi(int(area / 2500.0) + 1, 1, 8)
	step_count += 1
	var gain := cov.apply_disc(pos.x, pos.y, radius, rate * dt * (1.0 + bonus), stride, step_count % stride)
	manager.add_gain(gain, cov.last_cov_delta, self)
	pulse_timer -= dt
	if pulse_timer <= 0.0:
		pulse_timer = 60.0 / pulse_rate
		manager.spawn_pulse(pos, radius * 1.6, 0.35, root_id, "vortex")
	if absolute_zero:
		az_timer -= dt
		if az_timer <= 0.0:
			az_timer = 25.0
			manager.spawn_pulse(pos, radius * 3.2, 0.6, root_id, "absolute_zero")
	manager.note_storm_size(radius)


func absorb_storm(strength_gain: float, life_gain: float) -> void:
	bonus = minf(bonus + strength_gain * absorb, 1.5)
	life += life_gain * absorb


func setup_visuals() -> void:
	_y = sim_height(pos) + altitude()
	_spiral = MeshInstance3D.new()
	_spiral.mesh = MeshFactory.spiral(4, 1.35, 64)
	_spiral_mat = WeatherFX.effect_material(1, Color(0.9, 0.95, 1.0, 0.75))
	_spiral_mat.set_shader_parameter("speed", 1.5)
	_spiral.material_override = _spiral_mat
	_spiral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spiral)
	_spiral2 = MeshInstance3D.new()
	_spiral2.mesh = _spiral.mesh
	_spiral2.material_override = _spiral_mat
	_spiral2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spiral2)
	_funnel = MeshInstance3D.new()
	_funnel.mesh = MeshFactory.open_cylinder(0.12, 1.0, 32, 8)
	_funnel_mat = WeatherFX.effect_material(4, Color(0.86, 0.93, 1.0, 0.45))
	_funnel_mat.set_shader_parameter("speed", 1.2)
	_funnel.material_override = _funnel_mat
	_funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_funnel)
	_ring_clouds = Node3D.new()
	add_child(_ring_clouds)
	_ground = WeatherFX.decal(1, Color(0.8, 0.92, 1.0, 0.4))
	_ground.top_level = true
	(_ground.material_override as ShaderMaterial).set_shader_parameter("ring_width", 0.04)
	add_child(_ground)
	_build_ring()
	global_position = Vector3(pos.x, _y, pos.y)


func _build_ring() -> void:
	for c in _ring_clouds.get_children():
		c.queue_free()
	_cloud_mats.clear()
	if _snow != null:
		_snow.queue_free()
	_built_radius = radius
	var n := clampi(int(10 * WeatherFX.visual_complexity), 6, 14)
	for k in n:
		var mi := MeshInstance3D.new()
		mi.mesh = WeatherFX.cloud_mesh(k, true)
		var mat := WeatherFX.cloud_material(Color(0.95, 0.97, 1.0))
		mat.set_shader_parameter("darkness", 0.25)
		mat.set_shader_parameter("near_fade", 16.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * k / n
		var rr := radius * (0.8 + 0.12 * sin(k * 3.1))
		mi.position = Vector3(cos(a) * rr, sin(k * 1.3) * 3.0, sin(a) * rr)
		var s := radius * 0.28
		mi.scale = Vector3(s, s * 0.55, s)
		mi.rotation.y = -a
		_ring_clouds.add_child(mi)
		_cloud_mats.append(mat)
	var amount := int(clampf(radius * radius * 0.35, 400.0, 2400.0) * WeatherFX.visual_complexity)
	_snow = WeatherFX.snowfall(radius * 0.85, altitude(), amount, 8.0, 0.3)
	add_child(_snow)


func visual_update(delta: float, t: float) -> void:
	if _spiral == null:
		return
	if absf(_built_radius - radius) > 6.0:
		_build_ring()
	var p := interp_pos(t)
	_y = lerpf(_y, sim_height(p) + altitude(), 1.0 - exp(-delta * 0.8))
	global_position = Vector3(p.x, _y, p.y)
	var end_fade := clampf((life - age) / 4.0, 0.0, 1.0) if alive else 0.0
	var f := vis * (end_fade if alive else 1.0)
	_spiral.scale = Vector3(radius * 1.1, 6.0, radius * 1.1)
	_spiral.rotation.y -= delta * 0.35
	_spiral2.scale = Vector3(radius * 0.7, 4.0, radius * 0.7)
	_spiral2.position = Vector3(0, -altitude() * 0.45, 0)
	_spiral2.rotation.y -= delta * 0.6
	_funnel.scale = Vector3(radius * 0.35, altitude(), radius * 0.35)
	_funnel.position = Vector3(0, -altitude(), 0)
	_funnel.rotation.y -= delta * 0.9
	_ring_clouds.rotation.y -= delta * 0.22
	_spiral_mat.set_shader_parameter("fade", f)
	_funnel_mat.set_shader_parameter("fade", f)
	for m in _cloud_mats:
		m.set_shader_parameter("fade", f)
	_snow.emitting = alive and age < life - 3.0
	_snow.rotation.y -= delta * 0.4
	_ground.global_position = Vector3(p.x, 0, p.y)
	_ground.scale = Vector3(radius, 1.0, radius)
	(_ground.material_override as ShaderMaterial).set_shader_parameter("intensity", f)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d.merge({"bonus": bonus, "pulse_timer": pulse_timer, "az_timer": az_timer, "wander": wander})
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	bonus = float(d.get("bonus", 0.0))
	pulse_timer = float(d.get("pulse_timer", pulse_timer))
	az_timer = float(d.get("az_timer", az_timer))
	wander = float(d.get("wander", 0.0))
