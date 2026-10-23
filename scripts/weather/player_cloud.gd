class_name PlayerCloud
extends WeatherEffect
## You. A snow cloud that drifts where you steer it; snow falls wherever it
## goes. Every number comes from Progression.stat(), so upgrades bought in the
## web show up here immediately. Movement steps at the full 30 Hz; snowfall
## is applied every third tick.
##
## Input is plain data (move_input, dashing) so the balance bot can fly the
## cloud headlessly exactly like a player.

var move_input := Vector2.ZERO   # world-space wish direction, length 0..1
var dashing := false
var altitude_offset := 0.0
var distance := 0.0
var _wake_acc := 0.0
var _av_timer := 0.0
var _snow_phase := 0
var _stride_phase := 0
var vortex_t := 0.0
var vortex_len := 0.0
var vortex_mult := 1.0
var cloudlets: Array[SnowCloud] = []
var high_ground := false

# visuals
var _body: Node3D
var _puffs: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _face: Node3D
var _eyes: Array[MeshInstance3D] = []
var _snow: GPUParticles3D
var _snow_mat: ParticleProcessMaterial
var _shadow: MeshInstance3D
var _spiral: MeshInstance3D
var _spiral_mat: ShaderMaterial
var _built_r := 0.0
var _y := 0.0
var _blink := 2.0
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
	return p.stat("speed") * (p.stat("dash") if dashing else 1.0)


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
		_wake(moved)
	else:
		_wake_acc += moved


func current_rate() -> float:
	var prog := manager.prog
	var r := prog.stat("rate")
	if dashing and prog.has("tailwind"):
		r *= 1.6
	if high_ground:
		r *= 1.5
	r *= 1.0 + 0.5 * vortex_amount()
	return r


func _snowfall(dt: float) -> void:
	var prog := manager.prog
	var cov := manager.cov
	high_ground = prog.has("mountain_air") and manager.terrain.highland_mask(pos.x, pos.y) > 0.5
	rate = current_rate()
	# Very large discs update interleaved rows to keep the frame cost flat.
	var stride := clampi(int(ceil(radius * radius * PI / 2500.0)), 1, 12)
	_stride_phase = (_stride_phase + 1) % stride
	var snap := 0.5 if prog.has("deep_freeze") else SnowCoverage.FULL_SNAP
	var gain := cov.apply_disc(pos.x, pos.y, radius, rate * dt, stride, _stride_phase, prog.stat("core"), snap)
	manager.add_gain(gain, cov.last_cov_delta, self)
	# Avalanche Rider: drifting over a snowy slope sets the slope off.
	_av_timer -= dt
	if _av_timer <= 0.0:
		_av_timer = 0.4
		manager.try_ride_avalanche(pos)


func _wake(moved: float) -> void:
	_wake_acc += moved
	var life_s := manager.prog.stat("wake_life")
	if life_s <= 0.0:
		_wake_acc = 0.0
		return
	var spacing := maxf(radius * 0.9, 2.5)
	if _wake_acc < spacing:
		return
	_wake_acc = 0.0
	if not manager.can_spawn("snow_cloud"):
		return
	var w := SnowCloud.new()
	w.make_wake(pos, base_radius() * 0.7, current_rate() * 0.55, life_s)
	manager.spawn(w, -1, "snow_wake")


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
		manager.spawn_pulse(pos, base_radius() * vortex_mult * 2.5, 0.8, -1, "absolute_zero")


# --------------------------------------------------------------- visuals
func setup_visuals() -> void:
	_body = Node3D.new()
	add_child(_body)
	# A main puff with a ring of smaller ones gives the cloud a soft silhouette.
	var layout := [Vector3(0, 0, 0), Vector3(0.55, -0.08, 0.15), Vector3(-0.5, -0.06, 0.2),
		Vector3(0.1, -0.1, -0.55), Vector3(-0.2, 0.18, -0.2), Vector3(0.3, 0.2, 0.35)]
	var sizes := [1.0, 0.62, 0.66, 0.6, 0.55, 0.5]
	for k in layout.size():
		var mi := MeshInstance3D.new()
		mi.mesh = WeatherFX.cloud_mesh(k + 11)
		var mat := WeatherFX.cloud_material(Color(0.95, 0.97, 1.0))
		mat.set_shader_parameter("near_fade", 2.0)
		mat.set_shader_parameter("darkness", 0.12)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("home", layout[k])
		mi.set_meta("size", sizes[k])
		_body.add_child(mi)
		_puffs.append(mi)
		_mats.append(mat)
	_face = Node3D.new()
	_body.add_child(_face)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(0.13, 0.17, 0.3)
	var glint_mat := StandardMaterial3D.new()
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.albedo_color = Color(1, 1, 1)
	for s in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 16
		sm.rings = 8
		eye.mesh = sm
		eye.material_override = eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.set_meta("side", s)
		var glint := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.18
		gm.height = 0.36
		gm.radial_segments = 8
		gm.rings = 4
		glint.mesh = gm
		glint.material_override = glint_mat
		glint.position = Vector3(0.18, 0.2, 0.38)
		eye.add_child(glint)
		_face.add_child(eye)
		_eyes.append(eye)
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
	_y = sim_height(pos) + altitude()
	_build_snow()
	global_position = Vector3(pos.x, _y, pos.y)


func _build_snow() -> void:
	if _snow != null:
		_snow.queue_free()
	_built_r = radius
	var amount := int(clampf(60.0 + radius * radius * 3.0, 60.0, 1600.0) * WeatherFX.visual_complexity)
	_snow = WeatherFX.snowfall(radius * 0.85, altitude(), amount, 4.0, 0.17)
	_snow_mat = _snow.process_material
	add_child(_snow)


## Height that keeps the cloud above hills under its whole footprint.
func _clearance(p: Vector2) -> float:
	var h := sim_height(p)
	var r := radius * 0.7
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		h = maxf(h, sim_height(p + d) - 2.0)
	return h


func visual_update(delta: float, t: float) -> void:
	if _body == null:
		return
	if absf(radius - _built_r) > _built_r * 0.25:
		_build_snow()
	_snow_mat.emission_ring_radius = radius * 0.85
	var p := interp_pos(t)
	_bob += delta
	var target_y := _clearance(p) + altitude() + altitude_offset
	_y = lerpf(_y, target_y, 1.0 - exp(-delta * 2.5))
	global_position = Vector3(p.x, _y + sin(_bob * 1.3) * 0.25, p.y)
	# Body puffs breathe gently; the cloud leans into its motion.
	var lean := Vector3(vel.y, 0, -vel.x) * 0.012
	_body.rotation = _body.rotation.lerp(Vector3(lean.x, _body.rotation.y, lean.z), 1.0 - exp(-delta * 3.0))
	_body.rotation.y += delta * (0.04 + 2.2 * vortex_amount())
	for k in _puffs.size():
		var mi := _puffs[k]
		var home: Vector3 = mi.get_meta("home")
		var sz: float = mi.get_meta("size")
		var breathe := 1.0 + sin(_bob * 1.1 + k * 1.7) * 0.04
		mi.position = home * radius
		mi.scale = Vector3(1.1, 0.75, 1.1) * radius * sz * breathe
	var f := vis
	# Over white ground the cloud greys into a storm cloud so it stays readable.
	var under := manager.cov.sample_coverage(p.x, p.y)
	_storm = lerpf(_storm, smoothstep(0.3, 0.9, under), 1.0 - exp(-delta * 1.5))
	for m in _mats:
		m.set_shader_parameter("fade", f)
		m.set_shader_parameter("darkness", 0.12 + 1.15 * _storm)
	# The face turns toward the camera so you can always see your cloud.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var to := cam.global_position - global_position
		var yaw := atan2(to.x, to.z) - _body.rotation.y
		_face.rotation.y = lerp_angle(_face.rotation.y, yaw, 1.0 - exp(-delta * 6.0))
	_blink -= delta
	var lid := 1.0
	if _blink < 0.12:
		lid = 0.12
		if _blink <= 0.0:
			_blink = randf_range(2.5, 5.5)
	for e in _eyes:
		var s: float = e.get_meta("side")
		var es := radius * 0.13
		e.position = Vector3(s * radius * 0.28, radius * 0.3, radius * 0.95)
		e.scale = Vector3(es, es * 1.25 * lid, es * 0.6)
	_snow.emitting = alive
	_shadow.global_position = Vector3(p.x, 0.0, p.y)
	_shadow.scale = Vector3(radius, 1.0, radius)
	(_shadow.material_override as ShaderMaterial).set_shader_parameter("intensity", f)
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
	distance = float(d.get("distance", 0.0))
	vel = Vector2.ZERO
	life = 1.0e9
	age = 0.0
