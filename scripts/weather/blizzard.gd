class_name Blizzard
extends WeatherEffect
## A large drifting storm. Absorbs snow clouds, can fuse with other blizzards
## (Superstorm), seek unfrozen land (Roaming Winter) and spawn storm cells.

var speed := 2.0
var wind_resp := 0.4
var roaming := false
var cells := 0.0
var cell_timer := 4.0
var heading := 0.0
var seek := Vector2.INF
var seek_timer := 0.0
var boost := 1.0
var overlap_boost := 1.0
var base_rate := 0.3
var max_radius := 60.0
var step_count := 0
var merged := 0

var _clouds: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _snow: GPUParticles3D
var _streaks: GPUParticles3D
var _shadow: MeshInstance3D
var _pivot: Node3D
var _y := 0.0
var _built_radius := 0.0


func init_from_stats(prog: Progression) -> void:
	kind = "blizzard"
	radius = prog.stat("bz_radius")
	life = prog.stat("bz_life") * prog.stat("duration_mult")
	rate = prog.stat("bz_rate") * prog.stat("efficiency_mult")
	base_rate = rate
	speed = prog.stat("bz_speed")
	wind_resp = prog.stat("bz_wind")
	roaming = prog.has("roaming_winter")
	cells = prog.stat("bz_cells")
	max_radius = radius * 1.6


func altitude() -> float:
	return 20.0 + radius * 0.35


func sim_step(dt: float) -> void:
	var prog := manager.prog
	var cov := manager.cov
	age += dt
	if age >= life:
		kill()
		return
	heading += manager.rng.randf_range(-0.35, 0.35) * dt
	var own := Vector2.from_angle(heading) * speed * 0.5 + manager.prevailing * 0.6
	if roaming:
		seek_timer -= dt
		if seek_timer <= 0.0 or seek == Vector2.INF:
			seek = cov.find_nearest_unfrozen_area(pos, 160.0, 24, manager.avoid_list(self))
			seek_timer = 2.5
		if seek != Vector2.INF and seek.distance_to(pos) > radius * 0.25:
			own = (seek - pos).normalized() * speed * prog.stat("storm_nav")
	integrate_motion(dt, own, wind_resp, 0.6)
	var area := PI * radius * radius
	var stride := clampi(int(area / 2500.0) + 1, 1, 6)
	step_count += 1
	var gain := cov.apply_disc(pos.x, pos.y, radius, rate * dt * boost * overlap_boost, stride, step_count % stride)
	manager.add_gain(gain, cov.last_cov_delta, self)
	boost = 1.0
	overlap_boost = 1.0
	if cells > 0.0:
		cell_timer -= dt
		if cell_timer <= 0.0:
			cell_timer = 10.0 / cells
			if manager.can_spawn("snow_cloud"):
				var c := SnowCloud.new()
				c.init_from_stats(prog, 0.85)
				c.player_owned = false
				c.generation = 1
				var a := manager.rng.randf() * TAU
				c.pos = pos + Vector2.from_angle(a) * radius * 1.05
				c.vel = Vector2.from_angle(a) * 2.0
				manager.spawn(c, root_id)
	manager.note_storm_size(radius)


func absorb_cloud(c: SnowCloud) -> void:
	life += (c.life - c.age) * 0.5
	rate = minf(rate * 1.015, base_rate * 1.6)
	radius = minf(radius + 0.25, max_radius)


func merge_from(other: Blizzard) -> void:
	var r := sqrt(radius * radius + other.radius * other.radius) * 1.08
	radius = minf(r, 95.0)
	max_radius = maxf(max_radius, radius * 1.2)
	rate = maxf(rate, other.rate) * 1.15
	base_rate = maxf(base_rate, other.base_rate) * 1.15
	var remain := maxf(life - age, other.life - other.age) + 10.0
	age = 0.0
	life = remain
	pos = (pos * radius + other.pos * other.radius) / (radius + other.radius)
	merged += 1
	if _pivot != null:
		_rebuild_clouds()


func setup_visuals() -> void:
	_y = sim_height(pos) + altitude()
	_pivot = Node3D.new()
	add_child(_pivot)
	_rebuild_clouds()
	_shadow = WeatherFX.decal(3, Color(0.42, 0.52, 0.72, 0.28))
	_shadow.top_level = true
	add_child(_shadow)
	global_position = Vector3(pos.x, _y, pos.y)


func _rebuild_clouds() -> void:
	for c in _clouds:
		c.queue_free()
	_clouds.clear()
	_mats.clear()
	if _snow != null:
		_snow.queue_free()
	if _streaks != null:
		_streaks.queue_free()
	_built_radius = radius
	var n := clampi(int(5 + radius / 8.0 * WeatherFX.visual_complexity), 5, 12)
	for k in n:
		var mi := MeshInstance3D.new()
		mi.mesh = WeatherFX.cloud_mesh(uid + k)
		var mat := WeatherFX.cloud_material(Color(0.92, 0.94, 0.98))
		mat.set_shader_parameter("darkness", 0.45)
		mat.set_shader_parameter("near_fade", 12.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * k / n
		var ring := 0.0 if k == 0 else radius * (0.45 + 0.2 * sin(k * 2.3))
		mi.position = Vector3(cos(a) * ring, sin(k * 1.7) * 2.0 + (4.0 if k == 0 else 0.0), sin(a) * ring)
		var s := radius * (0.62 if k == 0 else 0.42)
		mi.scale = Vector3(s, s * 0.6, s)
		mi.rotation.y = a
		_pivot.add_child(mi)
		_clouds.append(mi)
		_mats.append(mat)
	var amount := int(clampf(radius * radius * 0.9, 250.0, 1800.0) * WeatherFX.visual_complexity)
	_snow = WeatherFX.snowfall(radius * 0.9, altitude(), amount, 6.0, 0.26)
	add_child(_snow)
	_streaks = WeatherFX.streaks(Vector3(radius * 0.8, altitude() * 0.4, radius * 0.8), int(radius * 4.0), Vector3(3.0, -4.0, 0.0), 2.0)
	_streaks.position = Vector3(0, -altitude() * 0.5, 0)
	add_child(_streaks)


func visual_update(delta: float, t: float) -> void:
	if _pivot == null:
		return
	if absf(_built_radius - radius) > 4.0:
		_rebuild_clouds()
	var p := interp_pos(t)
	_y = lerpf(_y, sim_height(p) + altitude(), 1.0 - exp(-delta * 1.0))
	global_position = Vector3(p.x, _y, p.y)
	_pivot.rotation.y += delta * 0.04
	var end_fade := clampf((life - age) / 3.0, 0.0, 1.0) if alive else 0.0
	var f := vis * (end_fade if alive else 1.0)
	for m in _mats:
		m.set_shader_parameter("fade", f)
	_snow.emitting = alive and age < life - 2.0
	_streaks.emitting = alive and age < life - 2.0
	var w := manager.wind_at(p)
	_streaks.rotation.y = atan2(w.x, w.y) - PI * 0.5 if w.length() > 0.5 else _streaks.rotation.y
	_shadow.global_position = Vector3(p.x, 0, p.y)
	_shadow.scale = Vector3(radius, 1.0, radius)
	(_shadow.material_override as ShaderMaterial).set_shader_parameter("intensity", f)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d.merge({"speed": speed, "base_rate": base_rate, "max_radius": max_radius, "heading": heading})
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	speed = float(d.get("speed", speed))
	base_rate = float(d.get("base_rate", base_rate))
	max_radius = float(d.get("max_radius", max_radius))
	heading = float(d.get("heading", 0.0))
