class_name SnowCloud
extends WeatherEffect
## A small cloud that snows on the ground below it. Two roles:
##   "wake"     - Snow Wake flurries left behind the player; they hang in
##                place and fade after `life` seconds.
##   "cloudlet" - companions that orbit the player (or, with Wanderers, roam
##                to nearby green ground within reach and drift back).

var mode := "wake"
var slot := 0             # cloudlet index around the player
var seek := Vector2.INF
var seek_timer := 0.0
var new_cov := 0.0

var _cloud: MeshInstance3D
var _snow: GPUParticles3D
var _shadow: MeshInstance3D
var _mat: ShaderMaterial
var _y := 0.0
var _built_r := 0.0


func make_wake(at: Vector2, r: float, p_rate: float, p_life: float) -> void:
	kind = "snow_cloud"
	mode = "wake"
	pos = at
	radius = r
	rate = p_rate
	life = p_life


func make_cloudlet(at: Vector2, k: int) -> void:
	kind = "snow_cloud"
	mode = "cloudlet"
	slot = k
	pos = at
	life = 1.0e9


func area() -> float:
	return PI * radius * radius


func altitude() -> float:
	if mode == "wake":
		return GameBalance.CLOUD_ALTITUDE + radius * 0.3
	return GameBalance.CLOUD_ALTITUDE * 0.7 + radius * 0.4


func sim_step(dt: float) -> void:
	var cov := manager.cov
	age += dt
	if mode == "cloudlet":
		_cloudlet_motion(dt)
	var core := 0.4 if mode == "wake" else manager.prog.stat("core")
	var gain := cov.apply_disc(pos.x, pos.y, radius, rate * dt, 1, 0, core)
	new_cov += cov.last_cov_delta
	manager.add_gain(gain, cov.last_cov_delta, self)
	if age >= life:
		kill()


func _cloudlet_motion(dt: float) -> void:
	var host := manager.cloud
	if host == null or not host.alive:
		kill()
		return
	var prog := manager.prog
	radius = host.base_radius() * prog.stat("comp_size")
	rate = host.rate * 0.5
	var count := maxi(int(prog.stat("companions")), 1)
	var ang := host.age * 0.35 + TAU * slot / count
	var home := host.pos + Vector2.from_angle(ang) * (host.radius + radius * 1.2)
	var target := home
	if prog.has("wanderers"):
		var leash := prog.stat("comp_leash") + host.radius
		seek_timer -= dt
		var stale := seek == Vector2.INF or cov_at(seek) >= 0.98 or seek.distance_to(host.pos) > leash
		if seek_timer <= 0.0 or stale:
			seek = manager.cov.find_nearest_unfrozen_area(home, leash, 3, _avoid())
			if seek != Vector2.INF and seek.distance_to(host.pos) > leash:
				seek = Vector2.INF
			seek_timer = 1.2
		if seek != Vector2.INF:
			target = seek
	var to := target - pos
	var top := maxf(host.max_speed() * 1.15, 6.0)
	var own := to.normalized() * minf(to.length() * 2.0, top) if to.length() > 0.3 else Vector2.ZERO
	vel = vel.lerp(own, 1.0 - exp(-dt * 3.0))
	pos += vel * dt
	var lim := GameBalance.WORLD_HALF - 1.0
	pos = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))


func cov_at(p: Vector2) -> float:
	return manager.cov.get_coverage(p.x, p.y)


## Targets already claimed by other cloudlets, so they spread out.
func _avoid() -> Array:
	var out: Array = []
	for e in manager.effects_of("snow_cloud"):
		var c := e as SnowCloud
		if c != self and c.mode == "cloudlet" and c.seek != Vector2.INF:
			out.append(Vector3(c.seek.x, c.seek.y, c.radius * 2.5))
	return out


# --------------------------------------------------------------- visuals
func setup_visuals() -> void:
	_y = sim_height(pos) + altitude()
	_cloud = MeshInstance3D.new()
	_cloud.mesh = WeatherFX.cloud_mesh(uid, true)
	_mat = WeatherFX.cloud_material(Color(0.97, 0.98, 1.0) if mode == "cloudlet" else Color(0.9, 0.94, 1.0))
	_mat.set_shader_parameter("near_fade", 4.0)
	_cloud.material_override = _mat
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cloud)
	_shadow = WeatherFX.decal(3, Color(0.55, 0.68, 0.92, 0.2))
	_shadow.top_level = true
	add_child(_shadow)
	_build_snow()
	global_position = Vector3(pos.x, _y, pos.y)


func _build_snow() -> void:
	if _snow != null:
		_snow.queue_free()
	_built_r = maxf(radius, 0.5)
	var amount := int(clampf(24.0 + radius * radius * 2.0, 24.0, 300.0))
	_snow = WeatherFX.snowfall(_built_r * 0.85, altitude(), amount, 3.4, 0.15)
	add_child(_snow)


func visual_update(delta: float, t: float) -> void:
	if _cloud == null:
		return
	if absf(radius - _built_r) > _built_r * 0.3:
		_build_snow()
	var p := interp_pos(t)
	_y = lerpf(_y, sim_height(p) + altitude(), 1.0 - exp(-delta * 2.0))
	global_position = Vector3(p.x, _y, p.y)
	_cloud.rotation.y += delta * 0.08
	var f := vis
	var size := 1.0
	if mode == "wake":
		# Wake flurries are thin wisps: mostly falling snow, barely any cloud.
		f *= clampf((life - age) / 1.0, 0.0, 1.0) if alive else 1.0
		size = 0.45
	_mat.set_shader_parameter("fade", f * (0.45 if mode == "wake" else 1.0))
	var s := lerpf(0.6, 1.0, f) * size
	_cloud.scale = Vector3(radius * 1.05, radius * 0.7, radius * 1.05) * s
	_snow.emitting = alive and age < life - 0.6
	_shadow.global_position = Vector3(p.x, 0.0, p.y)
	_shadow.scale = Vector3(radius, 1.0, radius)
	(_shadow.material_override as ShaderMaterial).set_shader_parameter("intensity", f)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["mode"] = mode
	d["slot"] = slot
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	mode = String(d.get("mode", mode))
	slot = int(d.get("slot", 0))
