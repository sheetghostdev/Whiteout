class_name PlayerCloud
extends WeatherEffect
## You. A snow cloud that drifts where you steer it; snow falls wherever it
## goes. Every number comes from Progression.stat(), so upgrades bought in the
## web show up here immediately. Movement steps at the full 30 Hz; snowfall
## is applied every third tick as a sweep along the path flown since the last
## snowfall, so each pass lays an even layer and hovering lays nothing.
##
## Input is plain data (move_input) so the balance bot can fly the
## cloud headlessly exactly like a player.

var move_input := Vector2.ZERO   # world-space wish direction, length 0..1
var altitude_offset := 0.0
var distance := 0.0
var _av_timer := 0.0
var _snow_phase := 0
var vortex_t := 0.0
var vortex_len := 0.0
var vortex_mult := 1.0
var cloudlets: Array[SnowCloud] = []
var high_ground := false
var last_moved := 0.0      # metres flown in the latest snowfall step
var idle_time := 10.0      # seconds since the cloud last really moved
var _snow_from := Vector2.INF
var _resting := true

# visuals
var _body: Node3D
var _puffs: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _snow: GPUParticles3D
var _snow_mat: ParticleProcessMaterial
var _shadow: MeshInstance3D
var _ring: MeshInstance3D
var _spiral: MeshInstance3D
var _spiral_mat: ShaderMaterial
var _built_r := 0.0
var _y := 0.0
var _bob := 0.0
var _storm := 0.0


func _init() -> void:
	kind = "player_cloud"
	every_tick = true
	life = 1.0e9


func base_radius() -> float:
	return manager.prog.stat("radius")


func max_speed() -> float:
	var p := manager.prog
	var s := p.stat("speed")
	# Tailwind: fast over finished ground, so reaching fresh green is quick.
	# It only counts when nearly all of your snowfall is over frozen ground,
	# so skimming along the edge of your own trail gets no boost.
	if p.has("tailwind"):
		s *= 1.0 + 0.3 * smoothstep(0.8, 0.97, frozen_under())
	return s


## Fraction of the ground under your snowfall that is already frozen
## (centre plus two rings of samples across the footprint).
func frozen_under() -> float:
	var cov := manager.cov
	var w := snow_width()
	var n := 0.0
	var frozen := 0.0
	for k in 17:
		var off := Vector2.ZERO
		if k > 0:
			var ring := 0.45 if k <= 8 else 0.9
			off = Vector2.from_angle(TAU * float(k % 8) / 8.0 + (0.39 if k > 8 else 0.0)) * w * ring
		n += 1.0
		if cov.get_coverage(pos.x + off.x, pos.y + off.y) >= 1.0:
			frozen += 1.0
	return frozen / n


## 0..1 how far into Vortex Form the cloud is (eases in and out).
func vortex_amount() -> float:
	if vortex_t <= 0.0:
		return 0.0
	var into := vortex_len - vortex_t
	return clampf(minf(into / 0.8, vortex_t / 1.2), 0.0, 1.0)


func begin_vortex(mult: float, duration: float) -> void:
	vortex_mult = mult
	vortex_len = duration
	vortex_t = duration


func altitude() -> float:
	return GameBalance.CLOUD_ALTITUDE + radius * 0.35


func sim_step(dt: float) -> void:
	var prog := manager.prog
	age += dt
	# ----- movement
	var target := move_input.limit_length(1.0) * max_speed()
	vel = vel.lerp(target, 1.0 - exp(-dt * 4.0))
	var before := pos
	pos += vel * dt
	var lim := GameBalance.WORLD_HALF - 2.0
	pos = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	var moved := pos.distance_to(before)
	idle_time = 0.0 if moved > 0.6 * dt else idle_time + dt
	distance += moved
	prog.stats["distance"] = float(prog.stats.get("distance", 0.0)) + moved
	# ----- size
	if vortex_t > 0.0:
		vortex_t -= dt
		if vortex_t <= 0.0:
			_end_vortex()
	radius = base_radius() * lerpf(1.0, vortex_mult, vortex_amount())
	manager.note_storm_size(radius)
	# ----- snowfall, every third tick
	_snow_phase += 1
	if _snow_phase >= WeatherManager.PHASES:
		_snow_phase = 0
		_snowfall(dt * WeatherManager.PHASES)
		_sync_cloudlets()


## Half-width of the strip your snow freezes, in metres. Everything inside
## it freezes completely in one pass, so there is never half-done ground.
func snow_width() -> float:
	var w := radius
	if high_ground:
		w *= 1.3
	return w


## True while the cloud is being flown (passive effects pause when you rest).
func is_active() -> bool:
	return idle_time < 1.5


func _snowfall(dt: float) -> void:
	var prog := manager.prog
	var cov := manager.cov
	high_ground = prog.has("mountain_air") and manager.terrain.highland_mask(pos.x, pos.y) > 0.5
	var width := snow_width()
	rate = width
	if _snow_from == Vector2.INF:
		_snow_from = pos
	last_moved = _snow_from.distance_to(pos)
	if last_moved > max_speed() * dt * 2.5 + 2.0:
		# Teleported (respawn, loading): start a fresh trail.
		_snow_from = pos
		last_moved = 0.0
	# Round off the trail where you set off and where you come to rest, so
	# trails end in soft rounded caps instead of square cut-offs.
	var resting := idle_time > 0.6
	if resting != _resting:
		_resting = resting
		var cap := cov.apply_disc(pos.x, pos.y, width, 1.0, 1, 0, 1.0)
		manager.add_gain(cap, cov.last_cov_delta, self)
	if last_moved > 0.05:
		var gain := cov.apply_sweep(_snow_from.x, _snow_from.y, pos.x, pos.y, width, 1.0, 1.0)
		manager.add_gain(gain, cov.last_cov_delta, self)
		_snow_from = pos
	# Avalanche Rider: drifting over a snowy slope sets the slope off.
	_av_timer -= dt
	if _av_timer <= 0.0:
		_av_timer = 0.4
		manager.try_ride_avalanche(pos)


func _sync_cloudlets() -> void:
	var want := int(manager.prog.stat("companions"))
	var i := cloudlets.size() - 1
	while i >= 0:
		if not is_instance_valid(cloudlets[i]) or not cloudlets[i].alive:
			cloudlets.remove_at(i)
		i -= 1
	while cloudlets.size() > want:
		cloudlets.pop_back().kill()
	while cloudlets.size() < want:
		var c := SnowCloud.new()
		c.make_cloudlet(pos + Vector2.from_angle(cloudlets.size() * 2.4) * radius, cloudlets.size())
		c.radius = base_radius() * manager.prog.stat("comp_size")
		manager.spawn(c, -1, "cloudlets")
		cloudlets.append(c)
	for k in cloudlets.size():
		cloudlets[k].slot = k


func _end_vortex() -> void:
	vortex_t = 0.0
	if manager.prog.has("absolute_zero"):
		manager.spawn_pulse(pos, base_radius() * vortex_mult * 2.5, 1.0, -1, "absolute_zero")


# --------------------------------------------------------------- visuals
# Puff layout: a broad, flat base with rounded crowns on top, so the cloud
# reads as a soft cumulus from above and from the side.
const PUFFS := [
	[Vector3(0.0, 0.05, 0.0), 1.0], [Vector3(0.62, -0.05, 0.18), 0.66], [Vector3(-0.58, -0.04, 0.22), 0.68],
	[Vector3(0.12, -0.06, -0.62), 0.64], [Vector3(-0.3, -0.05, 0.62), 0.6], [Vector3(0.45, 0.0, -0.4), 0.58],
	[Vector3(-0.55, 0.0, -0.38), 0.6], [Vector3(-0.12, 0.34, -0.1), 0.62], [Vector3(0.26, 0.3, 0.2), 0.55],
	[Vector3(-0.32, 0.26, 0.3), 0.5],
]


func setup_visuals() -> void:
	_body = Node3D.new()
	add_child(_body)
	for k in PUFFS.size():
		var mi := MeshInstance3D.new()
		mi.mesh = WeatherFX.cloud_mesh(k + 11)
		var mat := WeatherFX.cloud_material(Color(0.72, 0.74, 0.80))
		mat.set_shader_parameter("near_fade", 2.0)
		mat.set_shader_parameter("darkness", 0.5)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.y = k * 1.7
		_body.add_child(mi)
		_puffs.append(mi)
		_mats.append(mat)
	_spiral = MeshInstance3D.new()
	_spiral.mesh = MeshFactory.spiral(4, 1.35, 64)
	_spiral_mat = WeatherFX.effect_material(1, Color(0.9, 0.95, 1.0, 0.75))
	_spiral_mat.set_shader_parameter("speed", 1.5)
	_spiral.material_override = _spiral_mat
	_spiral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spiral.visible = false
	add_child(_spiral)
	_shadow = WeatherFX.decal(3, Color(0.5, 0.64, 0.92, 0.28))
	_shadow.top_level = true
	add_child(_shadow)
	# A clear ring on the ground marks exactly where your snow will fall.
	_ring = WeatherFX.decal(1, Color(0.92, 0.97, 1.0, 0.85))
	_ring.top_level = true
	add_child(_ring)
	_y = sim_height(pos) + altitude()
	_build_snow()
	global_position = Vector3(pos.x, _y, pos.y)


func _build_snow() -> void:
	if _snow != null:
		_snow.queue_free()
	_built_r = radius
	var amount := int(clampf(80.0 + radius * radius * 3.5, 80.0, 1200.0) * WeatherFX.visual_complexity)
	_snow = WeatherFX.snowfall(radius * 0.85, altitude(), amount, 4.0, 0.17)
	_snow_mat = _snow.process_material
	add_child(_snow)


## Height that keeps the cloud above hills and rooftops under its whole
## footprint (it rises over a house just as it rises over a hill).
func _clearance(p: Vector2) -> float:
	var terrain := manager.terrain
	var h := sim_height(p)
	var roof := terrain.obstacle_height(p.x, p.y)
	var r := radius * 0.7
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
			Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		h = maxf(h, sim_height(p + d) - 2.0)
		roof = maxf(roof, terrain.obstacle_height(p.x + d.x, p.y + d.y))
	# The cloud's underside sits about half a radius below its centre.
	return maxf(h, roof + radius * 0.55 + 3.0 - altitude())


func visual_update(delta: float, t: float) -> void:
	if _body == null:
		return
	# Rebuild the snowfall only when you have really grown (an upgrade), not
	# while a vortex swells and shrinks: the ring radius follows you anyway.
	if vortex_amount() <= 0.0 and absf(radius - _built_r) > _built_r * 0.25:
		_build_snow()
	_snow_mat.emission_ring_radius = radius * 0.85
	var p := interp_pos(t)
	_bob += delta
	var target_y := _clearance(p) + altitude() + altitude_offset
	_y = lerpf(_y, target_y, 1.0 - exp(-delta * 1.6))
	global_position = Vector3(p.x, _y + sin(_bob * 1.3) * 0.25, p.y)
	# Puffs breathe gently; the cloud leans into its motion and stretches a
	# little when it moves fast.
	var lean := Vector3(vel.y, 0, -vel.x) * 0.01
	_body.rotation = _body.rotation.lerp(Vector3(lean.x, _body.rotation.y, lean.z), 1.0 - exp(-delta * 3.0))
	_body.rotation.y += delta * (0.03 + 2.2 * vortex_amount())
	for k in _puffs.size():
		var mi := _puffs[k]
		var home: Vector3 = PUFFS[k][0]
		var sz: float = PUFFS[k][1]
		var breathe := 1.0 + sin(_bob * 0.9 + k * 1.7) * 0.035
		mi.position = home * radius + Vector3(0, sin(_bob * 0.7 + k) * 0.04 * radius, 0)
		mi.scale = Vector3(1.15, 0.72, 1.15) * radius * sz * breathe
	var f := vis
	# A soft grey cloud; over white ground it deepens toward a snow-storm grey
	# so it stays easy to see.
	var under := manager.cov.sample_coverage(p.x, p.y)
	_storm = lerpf(_storm, smoothstep(0.3, 0.9, under), 1.0 - exp(-delta * 1.5))
	for m in _mats:
		m.set_shader_parameter("fade", f)
		m.set_shader_parameter("darkness", 0.5 + 0.7 * _storm)
	_snow.emitting = alive
	_shadow.global_position = Vector3(p.x, 0.0, p.y)
	_shadow.scale = Vector3(radius, 1.0, radius)
	(_shadow.material_override as ShaderMaterial).set_shader_parameter("intensity", f)
	var w := snow_width()
	_ring.global_position = Vector3(p.x, 0.0, p.y)
	_ring.scale = Vector3(w, 1.0, w)
	var rm := _ring.material_override as ShaderMaterial
	rm.set_shader_parameter("ring_width", clampf(0.45 / maxf(w, 0.5), 0.01, 0.3))
	rm.set_shader_parameter("intensity", f * (1.0 if Settings.show_snow_ring else 0.0))
	var va := vortex_amount()
	_spiral.visible = va > 0.01
	if _spiral.visible:
		_spiral.scale = Vector3(radius * 1.1, 5.0, radius * 1.1)
		_spiral.position = Vector3(0, -altitude() * 0.35, 0)
		_spiral.rotation.y -= delta * 0.9
		_spiral_mat.set_shader_parameter("fade", va)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["distance"] = distance
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	_snow_from = pos
	distance = float(d.get("distance", 0.0))
	vel = Vector2.ZERO
	life = 1.0e9
	age = 0.0
