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
var strikes := 0                 # Thunderstrike: lightning bolts so far
var strike_at := Vector2.INF
var _strike_timer := 2.0
var last_moved := 0.0      # metres flown in the latest snowfall step
var idle_time := 10.0      # seconds since the cloud last really moved
var _snow_from := Vector2.INF
var _resting := true

# visuals
var _body: Node3D
var _puffs: Array[MeshInstance3D] = []
var _layout: Array = []          # per puff: [unit position, size, phase]
var _layout_r := 0.0
var _layout_shape := ""
var _mat: ShaderMaterial
var _wisp_mat: ShaderMaterial
var _wisps: Array = []           # {node, age, life, drift: Vector3, size}
var _wisp_acc := 0.0
var _pop := 0.0
var _last_r := 0.0
var _flash := 0.0
var _flash_timer := 6.0
var _light: OmniLight3D
var _seen_strikes := 0
var _bolt: MeshInstance3D
var _bolt_t := 0.0
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
	_thunderstrike(dt)
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


## Thunderstrike: every few seconds while you fly, lightning hits the
## nearest green ground within reach and freezes a patch around the strike.
func _thunderstrike(dt: float) -> void:
	if not manager.prog.has("thunderstrike") or not is_active():
		return
	_strike_timer -= dt
	if _strike_timer > 0.0:
		return
	_strike_timer = 3.2
	var reach := snow_width() * 3.0 + 24.0
	var target := manager.cov.find_nearest_unfrozen_area(pos, reach, 3)
	if target == Vector2.INF:
		return
	strike_at = target
	strikes += 1
	manager.spawn_pulse(target, snow_width() * 0.8 + 2.0, 1.0, -1, "thunderstrike")


func _end_vortex() -> void:
	vortex_t = 0.0
	if manager.prog.has("absolute_zero"):
		manager.spawn_pulse(pos, base_radius() * vortex_mult * 2.5, 1.0, -1, "absolute_zero")


# --------------------------------------------------------------- visuals
## How the cloud is built: a broad, flat base of puffs with rounded crowns
## piled on top. Bigger clouds get more, relatively smaller puffs (more
## detail); a Towering Cloud stacks its crowns higher and a Thunderhead
## spreads an anvil across the top.
func _shape() -> String:
	var prog := manager.prog
	if prog.has("thunderhead"):
		return "thunderhead"
	if prog.has("towering"):
		return "towering"
	return "cumulus"


func _make_layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + int(_layout_r * 10.0)
	var shape := _shape()
	var count := clampi(int(9 + base_radius() * 1.1), 10, 26)
	var tower := 1.0
	if shape == "towering":
		tower = 1.6
	elif shape == "thunderhead":
		tower = 2.2
	var out: Array = []
	out.append([Vector3(0.0, 0.16, 0.0), 1.0, rng.randf()])
	var ring := int(count * 0.5)
	for k in ring:
		var a := TAU * (k + rng.randf_range(-0.25, 0.25)) / ring
		var rr := rng.randf_range(0.55, 0.78)
		out.append([Vector3(cos(a) * rr, rng.randf_range(-0.08, 0.02), sin(a) * rr * 0.92), rng.randf_range(0.48, 0.64), rng.randf()])
	var crowns := count - ring - 1
	for k in crowns:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 0.45
		var lift := rng.randf_range(0.32, 0.62) * tower * (1.0 - rr * 0.7)
		out.append([Vector3(cos(a) * rr, lift, sin(a) * rr), rng.randf_range(0.46, 0.66), rng.randf()])
	if shape == "thunderhead":
		# The anvil: wide, flat puffs fanning out across the top.
		for k in 6:
			var a := TAU * k / 6.0 + 0.3
			out.append([Vector3(cos(a) * 0.62, 1.05, sin(a) * 0.62), 0.5, rng.randf()])
	return out


func _rebuild_puffs() -> void:
	_layout_r = base_radius()
	_layout_shape = _shape()
	_layout = _make_layout()
	while _puffs.size() < _layout.size():
		var mi := MeshInstance3D.new()
		mi.mesh = WeatherFX.cloud_mesh(_puffs.size() + 11)
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.y = _puffs.size() * 1.7
		_body.add_child(mi)
		mi.set_instance_shader_parameter("puff_seed", float(_puffs.size()) * 0.37)
		_puffs.append(mi)
	for k in _puffs.size():
		_puffs[k].visible = k < _layout.size()


func setup_visuals() -> void:
	_body = Node3D.new()
	add_child(_body)
	_mat = WeatherFX.cloud_material(Color(0.86, 0.87, 0.90))
	_mat.set_shader_parameter("near_fade", 2.0)
	_mat.set_shader_parameter("darkness", 0.4)
	_wisp_mat = ShaderLib.material("cloud_wisp")
	_wisp_mat.set_shader_parameter("tint", Vector3(0.82, 0.84, 0.9))
	_rebuild_puffs()
	_last_r = radius
	_light = OmniLight3D.new()
	_light.light_color = Color(0.80, 0.86, 1.0)
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
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
	# The cloud leans into its motion; puffs breathe, drift and boil.
	var lean := Vector3(vel.y, 0, -vel.x) * 0.012
	_body.rotation = _body.rotation.lerp(Vector3(lean.x, _body.rotation.y, lean.z), 1.0 - exp(-delta * 3.0))
	_body.rotation.y += delta * (0.025 + 2.2 * vortex_amount())
	if absf(base_radius() - _layout_r) > _layout_r * 0.12 or _shape() != _layout_shape:
		_rebuild_puffs()
	# Growing (an upgrade) makes the cloud swell with a little bounce.
	if radius > _last_r * 1.02 and vortex_amount() <= 0.0:
		_pop = 1.0
	_last_r = radius
	_pop = maxf(_pop - delta * 1.2, 0.0)
	var pop := 1.0 + sin(_pop * PI * 2.5) * 0.12 * _pop
	var speed := vel.length()
	for k in _layout.size():
		var mi := _puffs[k]
		var home: Vector3 = _layout[k][0]
		var sz: float = _layout[k][1]
		var ph: float = float(_layout[k][2]) * TAU
		var breathe := 1.0 + sin(_bob * 0.8 + ph) * 0.05 + sin(_bob * 1.9 + ph * 2.0) * 0.02
		var drift := Vector3(sin(_bob * 0.31 + ph) * 0.05, sin(_bob * 0.6 + ph) * 0.04, cos(_bob * 0.27 + ph) * 0.05)
		# Crowns lag a little behind when the cloud moves, like a towering
		# cumulus sheared by the wind.
		var shear := Vector3(-vel.x, 0, -vel.y) * 0.02 * maxf(home.y, 0.0)
		mi.position = (home + drift) * radius + shear
		mi.scale = Vector3(1.1, 0.9, 1.1) * radius * sz * breathe * pop
	_mat.set_shader_parameter("base_y", global_position.y - radius * 0.38)
	_update_wisps(delta, speed)
	_update_lightning(delta)
	var f := vis
	# A soft grey cloud; over white ground it deepens toward a snow-storm grey
	# so it stays easy to see.
	var under := manager.cov.sample_coverage(p.x, p.y)
	_storm = lerpf(_storm, smoothstep(0.3, 0.9, under), 1.0 - exp(-delta * 1.5))
	_mat.set_shader_parameter("fade", f)
	var dark := 0.12 + 0.6 * _storm
	if _layout_shape == "thunderhead":
		dark += 0.2
	_mat.set_shader_parameter("darkness", dark)
	_mat.set_shader_parameter("boil", 1.0 + minf(speed * 0.05, 0.6))
	_wisp_mat.set_shader_parameter("darkness", dark * 0.8)
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


## Wisps: little shreds of cloud that peel off the back of the cloud while it
## flies, drift away, spread and thin out.
func _update_wisps(delta: float, speed: float) -> void:
	_wisp_acc += delta * clampf((speed - 0.8) * 0.9, 0.0, 4.0)
	if _wisp_acc >= 1.0:
		_wisp_acc = 0.0
		var back := -Vector3(vel.x, 0, vel.y).normalized()
		var side := Vector3(-back.z, 0, back.x) * randf_range(-0.7, 0.7)
		var node: MeshInstance3D = null
		for w in _wisps:
			if float(w["age"]) >= float(w["life"]):
				node = w["node"]
				_wisps.erase(w)
				break
		if node == null and _wisps.size() < 14:
			node = MeshInstance3D.new()
			node.mesh = WeatherFX.cloud_mesh(_wisps.size() + 3, true)
			node.material_override = _wisp_mat
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.top_level = true
			add_child(node)
		if node != null:
			node.visible = true
			node.global_position = global_position + (back * 0.8 + side) * radius + Vector3(0, randf_range(-0.25, 0.15) * radius, 0)
			_wisps.append({"node": node, "age": 0.0, "life": randf_range(1.4, 2.2),
				"drift": Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.3), randf_range(-0.4, 0.4)), "size": radius * randf_range(0.28, 0.42)})
	for w in _wisps:
		w["age"] = float(w["age"]) + delta
		var k := clampf(float(w["age"]) / float(w["life"]), 0.0, 1.0)
		var node: MeshInstance3D = w["node"]
		node.visible = k < 1.0
		node.global_position += (w["drift"] as Vector3) * delta
		node.scale = Vector3(1.2, 0.6, 1.2) * float(w["size"]) * lerpf(0.7, 1.5, k)
		node.set_instance_shader_parameter("puff_fade", (1.0 - k) * 0.85 * vis)


## Thunderhead: now and then lightning flickers inside the cloud; with
## Thunderstrike a jagged bolt reaches down to the ground it freezes.
func _update_lightning(delta: float) -> void:
	if strikes != _seen_strikes:
		_seen_strikes = strikes
		_draw_bolt()
		_flash = 1.0
		_flash_timer = randf_range(5.0, 12.0)
	if _bolt != null:
		_bolt_t -= delta
		_bolt.visible = _bolt_t > 0.0 and fmod(_bolt_t, 0.08) > 0.025
	if _layout_shape != "thunderhead":
		_mat.set_shader_parameter("flash", 0.0)
		_light.visible = false
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash_timer = randf_range(5.0, 12.0)
		_flash = 1.0
	_flash = maxf(_flash - delta * 3.0, 0.0)
	var f := _flash * (0.6 + 0.4 * sin(_flash * 40.0))
	_mat.set_shader_parameter("flash", f * 1.4)
	_light.visible = f > 0.01
	_light.light_energy = f * 3.0
	_light.omni_range = radius * 4.0
	_light.position = Vector3(0, -radius * 0.2, 0)


func _draw_bolt() -> void:
	if strike_at == Vector2.INF:
		return
	var a := global_position + Vector3(0, -radius * 0.3, 0)
	var b := Vector3(strike_at.x, manager.terrain.surface_height(strike_at.x, strike_at.y), strike_at.y)
	var mb := MeshBuilder.new()
	var col := Color(0.85, 0.92, 1.0)
	var pts: Array[Vector3] = [a]
	var n := 9
	for k in range(1, n):
		var t := float(k) / n
		var p := a.lerp(b, t) + Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)) * (1.0 - t * 0.5) * 1.6
		pts.append(p)
	pts.append(b)
	for k in pts.size() - 1:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		for side in [Vector3(0.38, 0, 0), Vector3(0, 0, 0.38)]:
			mb.add_flat_tri(p0 - side, p0 + side, p1 + side, col, col, col)
			mb.add_flat_tri(p0 - side, p1 + side, p1 - side, col, col, col)
	if _bolt == null:
		_bolt = MeshInstance3D.new()
		_bolt.top_level = true
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.9, 0.95, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.7, 0.85, 1.0)
		m.emission_energy_multiplier = 8.0
		_bolt.material_override = m
		_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bolt)
	_bolt.mesh = mb.commit()
	_bolt.global_transform = Transform3D.IDENTITY
	_bolt_t = 0.3


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
