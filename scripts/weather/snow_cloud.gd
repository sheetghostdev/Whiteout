class_name SnowCloud
extends WeatherEffect
## A cloudlet: a small companion cloud that snows on the ground below it.
## Cloudlets fly beside you, just outside your own snowfall, so their snow
## widens your swath instead of landing where you have been (behind) or
## where you are about to go (ahead). With Wanderers they roam to nearby
## green ground within reach, never into your path, and drift back.

var mode := "cloudlet"
var slot := 0             # cloudlet index around the player
var seek := Vector2.INF
var seek_timer := 0.0
var new_cov := 0.0
var heading := Vector2(0, -1)
var _snow_from := Vector2.INF

var _cloud: MeshInstance3D
var _snow: GPUParticles3D
var _shadow: MeshInstance3D
var _mat: ShaderMaterial
var _y := 0.0
var _built_r := 0.0


func make_cloudlet(at: Vector2, k: int) -> void:
	kind = "snow_cloud"
	mode = "cloudlet"
	slot = k
	pos = at
	life = 1.0e9


func area() -> float:
	return PI * radius * radius


func altitude() -> float:
	return GameBalance.CLOUD_ALTITUDE * 0.7 + radius * 0.4


func sim_step(dt: float) -> void:
	var cov := manager.cov
	age += dt
	if mode != "cloudlet":
		kill()   # Snow Wake flurries from old saves: that upgrade is gone.
		return
	_cloudlet_motion(dt)
	# Cloudlets lay snow along their path, like you do: one pass freezes.
	if _snow_from == Vector2.INF:
		_snow_from = pos
	if _snow_from.distance_to(pos) > 0.05:
		var gain := cov.apply_sweep(_snow_from.x, _snow_from.y, pos.x, pos.y, radius, 1.0, 1.0)
		_snow_from = pos
		new_cov += cov.last_cov_delta
		manager.add_gain(gain, cov.last_cov_delta, self)


## Where this cloudlet sits beside you: cloudlets alternate left and right,
## each one just outside your snowfall (or the cloudlet inside it), so the
## swath you lay together is one wide band.
func side_spot(host: PlayerCloud) -> Vector2:
	var side := 1.0 if slot % 2 == 0 else -1.0
	var row := slot / 2
	var w := host.snow_width()
	var out := w + radius * (0.85 + 1.7 * row)
	var lateral := Vector2(-heading.y, heading.x) * side
	return host.pos + lateral * out - heading * radius * 0.4 * row


func _cloudlet_motion(dt: float) -> void:
	var host := manager.cloud
	if host == null or not host.alive:
		kill()
		return
	var prog := manager.prog
	radius = host.base_radius() * prog.stat("comp_size")
	rate = 1.0
	if host.vel.length() > 0.5:
		heading = heading.lerp(host.vel.normalized(), 1.0 - exp(-dt * 3.0)).normalized()
	var home := side_spot(host)
	var target := home
	var w := host.snow_width()
	if prog.has("wanderers") and host.is_active():
		var leash := prog.stat("comp_leash") + w
		seek_timer -= dt
		var stale := seek == Vector2.INF or cov_at(seek) >= 0.98 or seek.distance_to(host.pos) > leash \
				or _in_your_way(host, seek)
		if seek_timer <= 0.0 or stale:
			seek = manager.cov.find_nearest_unfrozen_area(home, leash, 3, _avoid(host))
			if seek != Vector2.INF and (seek.distance_to(host.pos) > leash or _in_your_way(host, seek)):
				seek = Vector2.INF
			seek_timer = 1.2
		if seek != Vector2.INF:
			target = seek
	var to := target - pos
	var top := maxf(host.max_speed() * 1.15, 6.0)
	var own := to.normalized() * minf(to.length() * 2.0, top) if to.length() > 0.3 else Vector2.ZERO
	vel = vel.lerp(own, 1.0 - exp(-dt * 3.0))
	pos += vel * dt
	# Never drift into your own snowfall: step back out to its edge.
	var away := pos - host.pos
	var keep_out := w + radius * 0.8
	if away.length() < keep_out:
		var dir := away.normalized() if away.length() > 0.01 else Vector2(-heading.y, heading.x)
		pos = host.pos + dir * keep_out
	var lim := GameBalance.WORLD_HALF - 1.0
	pos = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))


## True when `p` is inside your snowfall or in the strip just ahead of you
## that you are about to snow on anyway.
func _in_your_way(host: PlayerCloud, p: Vector2) -> bool:
	var w := host.snow_width()
	var rel := p - host.pos
	if rel.length() < w + radius:
		return true
	var along := rel.dot(heading)
	var across := absf(rel.dot(Vector2(-heading.y, heading.x)))
	return host.is_active() and along > 0.0 and along < w * 6.0 and across < w + radius * 0.5


func cov_at(p: Vector2) -> float:
	return manager.cov.get_coverage(p.x, p.y)


## Places to stay away from: your snowfall, the strip just ahead of you,
## and targets already claimed by other cloudlets, so they spread out.
func _avoid(host: PlayerCloud) -> Array:
	var w := host.snow_width()
	var out: Array = [Vector3(host.pos.x, host.pos.y, w + radius)]
	if host.is_active():
		for k in range(1, 4):
			var a := host.pos + heading * w * 1.6 * k
			out.append(Vector3(a.x, a.y, w + radius * 0.5))
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
	var floor_y := maxf(sim_height(p) + altitude(), manager.terrain.obstacle_height(p.x, p.y) + radius * 0.6 + 1.0)
	_y = lerpf(_y, floor_y, 1.0 - exp(-delta * 2.0))
	global_position = Vector3(p.x, _y, p.y)
	_cloud.rotation.y += delta * 0.08
	var f := vis
	_mat.set_shader_parameter("fade", f)
	var s := lerpf(0.6, 1.0, f)
	_cloud.scale = Vector3(radius * 1.05, radius * 0.7, radius * 1.05) * s
	_snow.emitting = alive
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
