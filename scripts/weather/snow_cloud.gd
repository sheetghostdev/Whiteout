class_name SnowCloud
extends WeatherEffect
## The first ability: a small cloud that snows on the ground below it.
## Evolutions add drifting, seeking, division, rebirth and thunder pulses.

var drift := false
var chase := false
var player_owned := true
var wander := 0.0
var seek := Vector2.INF
var seek_timer := 0.0
var new_cov := 0.0
var overlap_boost := 1.0
var in_wind := 0.0
var thunder_cd := 0.0
var bursts := {}
var absorbed_target := Vector2.INF

var _cloud: MeshInstance3D
var _snow: GPUParticles3D
var _shadow: MeshInstance3D
var _mat: ShaderMaterial
var _y := 0.0


func init_from_stats(prog: Progression, scale: float = 1.0) -> void:
	kind = "snow_cloud"
	radius = prog.stat("cloud_radius") * scale
	rate = prog.stat("cloud_rate") * prog.stat("efficiency_mult")
	life = prog.stat("cloud_duration") * prog.stat("duration_mult") * lerpf(1.0, 0.65, 1.0 - scale)
	drift = prog.has("cloud_drift")
	chase = prog.has("storm_chaser")


func area() -> float:
	return PI * radius * radius


func setup_visuals() -> void:
	_y = sim_height(pos) + altitude()
	_cloud = MeshInstance3D.new()
	_cloud.mesh = WeatherFX.cloud_mesh(uid, radius < 3.0)
	_mat = WeatherFX.cloud_material()
	_mat.set_shader_parameter("near_fade", 4.0)
	_cloud.material_override = _mat
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud.scale = Vector3(radius * 1.05, radius * 0.75, radius * 1.05)
	add_child(_cloud)
	var amount := int(clampf(30.0 + radius * radius * 2.5, 30.0, 420.0))
	_snow = WeatherFX.snowfall(radius * 0.85, altitude(), amount, 3.2, 0.16)
	add_child(_snow)
	_shadow = WeatherFX.decal(3, Color(0.55, 0.68, 0.92, 0.22))
	_shadow.top_level = true
	add_child(_shadow)
	global_position = Vector3(pos.x, _y, pos.y)


func altitude() -> float:
	return 3.2 + radius * 0.45


func sim_step(dt: float) -> void:
	var prog := manager.prog
	var cov := manager.cov
	var w := manager.wind_at(pos)
	in_wind = w.length()
	var age_rate := 1.0
	var responsiveness := 1.4
	if prog.has("jet_stream"):
		responsiveness = 0.5
		if in_wind > 3.0:
			age_rate = 0.25
	age += dt * age_rate
	var own := Vector2.ZERO
	if drift:
		wander += manager.rng.randf_range(-0.8, 0.8) * dt
		own += Vector2.from_angle(wander) * 0.9
	if chase:
		seek_timer -= dt
		if seek_timer <= 0.0 or seek == Vector2.INF or cov.get_coverage(seek.x, seek.y) >= 1.0:
			seek = cov.find_nearest_unfrozen_area(pos, 40.0 + radius * 3.0, 3, manager.avoid_list(self))
			seek_timer = 1.5
		if seek != Vector2.INF:
			var to := seek - pos
			if to.length() > radius * 0.3:
				own += to.normalized() * 2.6 * prog.stat("storm_nav")
	if absorbed_target != Vector2.INF:
		own = (absorbed_target - pos) * 2.0
	integrate_motion(dt, own, 1.0, responsiveness)
	var gain := cov.apply_disc(pos.x, pos.y, radius, rate * dt * overlap_boost)
	new_cov += cov.last_cov_delta
	manager.add_gain(gain, cov.last_cov_delta, self)
	# Thunder Snow: freezing fresh ground occasionally releases a pulse.
	var tc := prog.stat("cloud_thunder")
	thunder_cd -= dt
	if tc > 0.0 and thunder_cd <= 0.0 and cov.last_new_full >= 3:
		if manager.rng.randf() < tc:
			manager.spawn_pulse(pos, radius * 2.6, 0.5, root_id, "thunder")
			thunder_cd = 2.5
		else:
			thunder_cd = 1.0
	overlap_boost = 1.0
	if age >= life:
		_expire()


func _expire() -> void:
	kill()
	if absorbed_target != Vector2.INF:
		return
	var prog := manager.prog
	var cap := float(GameBalance.MAX_CLOUDS)
	var count := float(manager.count_kind("snow_cloud"))
	# Cloud Division: split into two smaller clouds.
	var div := int(prog.stat("cloud_division"))
	if generation < div and manager.rng.randf() < 1.0 - count / cap:
		var side := Vector2.from_angle(wander + PI * 0.5) if vel.length() < 0.2 else vel.normalized().orthogonal()
		for s in [-1.0, 1.0]:
			if not manager.can_spawn("snow_cloud"):
				break
			var c := SnowCloud.new()
			c.init_from_stats(prog, 0.75)
			c.radius = radius * 0.75
			c.generation = generation + 1
			c.player_owned = false
			c.pos = pos + side * s * radius * 0.7
			c.vel = vel + side * s * 1.5
			c.wander = wander + s
			manager.spawn(c, root_id)
	# Snowstorm Rebirth: productive clouds may reform.
	var rb := prog.stat("cloud_rebirth")
	if rb > 0.0 and generation < 4 and new_cov >= area() * 0.35:
		if manager.rng.randf() < rb * (1.0 - count / cap) and manager.can_spawn("snow_cloud"):
			var c2 := SnowCloud.new()
			c2.init_from_stats(prog)
			c2.radius = radius
			c2.generation = generation + 1
			c2.player_owned = false
			c2.pos = pos
			c2.vel = vel
			manager.spawn(c2, root_id)


func visual_update(delta: float, t: float) -> void:
	if _cloud == null:
		return
	var p := interp_pos(t)
	var target_y := sim_height(p) + altitude()
	_y = lerpf(_y, target_y, 1.0 - exp(-delta * 2.0))
	global_position = Vector3(p.x, _y, p.y)
	_cloud.rotation.y += delta * 0.05
	var end_fade := clampf((life - age) / 1.2, 0.0, 1.0) if alive else 0.0
	var f := vis * (end_fade if alive else 1.0)
	_mat.set_shader_parameter("fade", f)
	var s := lerpf(0.6, 1.0, f)
	_cloud.scale = Vector3(radius * 1.05, radius * 0.75, radius * 1.05) * s
	_snow.emitting = alive and age < life - 0.6
	_shadow.global_position = Vector3(p.x, 0.0, p.y)
	_shadow.scale = Vector3(radius, 1.0, radius)
	(_shadow.material_override as ShaderMaterial).set_shader_parameter("intensity", f)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["player"] = player_owned
	d["new_cov"] = new_cov
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	player_owned = bool(d.get("player", true))
	new_cov = float(d.get("new_cov", 0.0))
