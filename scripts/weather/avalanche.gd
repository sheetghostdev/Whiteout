class_name Avalanche
extends WeatherEffect
## Terrain-guided wavefront. Each head slides down the height-field gradient,
## widening as it travels and occasionally splitting. Seeded RNG keeps a given
## avalanche deterministic. Coverage is applied exactly along the swept path.

var heads: Array = []
var max_dist := 120.0
var max_speed := 12.0
var momentum := 0.55
var split_rate := 0.08
var strength := 0.6
var max_heads := 3
var w0 := 7.0
var seed_value := 0
var rng := RandomNumberGenerator.new()

var _visuals := {}


func configure(width: float) -> void:
	kind = "avalanche"
	w0 = width
	max_dist = 90.0
	max_speed = 14.0
	momentum = 0.6
	split_rate = 0.06
	strength = 1.0
	max_heads = 2
	life = 999.0
	radius = w0


static func release_check(terrain: TerrainData, cov: SnowCoverage, p: Vector2) -> String:
	if not terrain.in_bounds(p.x, p.y, 4.0):
		return "Out of bounds"
	if terrain.is_water(p.x, p.y):
		return "Needs a snowy slope"
	if cov.sample_coverage(p.x, p.y) < 0.5:
		return "Needs a snowy slope"
	if terrain.slope(p.x, p.y) < 0.16:
		return "Slope too gentle"
	return ""


## How much green ground lies downhill of a release point (0..3).
static func downhill_green(terrain: TerrainData, cov: SnowCoverage, p: Vector2) -> float:
	var down := -terrain.gradient(p.x, p.y, 4.0).normalized()
	var score := 0.0
	for s in [20.0, 45.0, 75.0]:
		var q: Vector2 = p + down * s
		score += 1.0 - cov.sample_coverage(q.x, q.y)
	return score


func start(p: Vector2, p_seed: int) -> void:
	pos = p
	prev_pos = p
	seed_value = p_seed
	rng.seed = p_seed
	var down := -manager.terrain.gradient(p.x, p.y, 4.0)
	if down.length() < 0.01:
		down = Vector2(0, 1)
	heads = [_new_head(p, down.normalized() * max_speed * 0.6, w0)]


func _new_head(p: Vector2, v: Vector2, w: float) -> Dictionary:
	return {"p": p, "prev": p, "v": v, "w": w, "trav": 0.0, "age": 0.0, "alive": true, "split_cd": 1.0, "boost": 1.0, "id": rng.randi()}


func alive_heads() -> int:
	var n := 0
	for h in heads:
		if h["alive"]:
			n += 1
	return n


func sim_step(dt: float) -> void:
	var terrain := manager.terrain
	var cov := manager.cov
	age += dt
	var any := false
	var new_heads: Array = []
	for h in heads:
		if not h["alive"]:
			continue
		any = true
		var p: Vector2 = h["p"]
		var v: Vector2 = h["v"]
		# Heading + speed model: gravity speeds the slide up or down along its
		# heading and turns the heading toward downhill at a limited rate, so
		# the snow carries through dips and gullies instead of rocking in them.
		var g := terrain.gradient(p.x, p.y, 4.0)
		var heading := v.normalized() if v.length() > 0.05 else -g.normalized()
		var speed := v.length()
		speed += -g.dot(heading) * 9.0 * dt
		speed *= pow(momentum, dt)
		var down := -g
		if down.length() > 0.03 and heading.dot(down.normalized()) > -0.2:
			var turn := clampf(heading.angle_to(down.normalized()), -1.2 * dt, 1.2 * dt)
			heading = heading.rotated(turn)
		var cap := max_speed
		var trav: float = h["trav"]
		if trav < max_dist * 0.6 and -g.dot(heading) > -0.6:
			speed = maxf(speed, max_speed * 0.45)
		speed = clampf(speed, 0.0, cap)
		v = heading * speed
		h["age"] = float(h["age"]) + dt
		var sp := v.length()
		if (sp < 0.9 and float(h["age"]) > 1.5) or trav >= max_dist:
			h["alive"] = false
			continue
		var np := p + v * dt
		if not terrain.in_bounds(np.x, np.y, 3.0):
			h["alive"] = false
			continue
		var grow := 1.0 + trav / 90.0
		var grow_cap := 1.6
		# Snow fans out across gentle run-out ground at the foot of a slope.
		var fan := lerpf(1.3, 1.0, clampf(g.length() / 0.3, 0.0, 1.0))
		var w: float = float(h["w"]) * minf(grow, grow_cap) * float(h["boost"]) * fan
		var amt := strength * float(h["boost"])
		var gain := cov.apply_sweep(p.x, p.y, np.x, np.y, w * 0.5, amt, 1.0)
		manager.add_gain(gain, cov.last_cov_delta, self)
		h["boost"] = 1.0
		h["prev"] = p
		h["p"] = np
		h["v"] = v
		h["trav"] = trav + sp * dt
		h["cur_w"] = w
		manager.note_storm_size(w * 0.5)
		# Lake water stops the slide in a spray of snow. Streams are crossed.
		if terrain.is_water(np.x, np.y) and terrain.lake_distance(np.x, np.y) < 90.0:
			var g2 := cov.apply_disc(np.x, np.y, w * 0.8, 1.0, 1, 0, 1.0)
			manager.add_gain(g2, cov.last_cov_delta, self)
			h["alive"] = false
			continue
		# Splitting.
		h["split_cd"] = float(h["split_cd"]) - dt
		if split_rate > 0.0 and alive_heads() + new_heads.size() < max_heads and float(h["split_cd"]) <= 0.0:
			if rng.randf() < split_rate * dt * 3.0 and manager.avalanche_heads() < GameBalance.MAX_AVALANCHE_HEADS:
				h["split_cd"] = 1.2
				var a := 0.45
				h["v"] = v.rotated(-a)
				h["w"] = float(h["w"]) * 0.8
				var nh := _new_head(np, v.rotated(a), float(h["w"]))
				nh["trav"] = h["trav"]
				new_heads.append(nh)
			else:
				h["split_cd"] = 1.0
	heads.append_array(new_heads)
	if heads.size() > 0:
		var lead: Dictionary = heads[0]
		for h in heads:
			if h["alive"]:
				lead = h
				break
		prev_pos = pos
		pos = lead["p"]
	if not any:
		kill()


func setup_visuals() -> void:
	global_position = Vector3(pos.x, sim_height(pos), pos.y)


func _make_head_visual() -> Node3D:
	var n := Node3D.new()
	n.top_level = true
	var mass := MeshInstance3D.new()
	mass.name = "Mass"
	mass.mesh = WeatherFX.snow_mass_mesh(rng.randi())
	var mat := WeatherFX.cloud_material(Color(1, 1, 1))
	mat.set_shader_parameter("near_fade", 3.0)
	mass.material_override = mat
	mass.set_meta("mat", mat)
	n.add_child(mass)
	var spray := WeatherFX.streaks(Vector3(2.0, 0.6, 1.0), 60, Vector3(0, 3.5, 4.0), 1.1)
	spray.name = "Spray"
	spray.local_coords = false
	n.add_child(spray)
	add_child(n)
	return n


func visual_update(delta: float, t: float) -> void:
	for h in heads:
		var id: int = h["id"]
		var node: Node3D = _visuals.get(id)
		if node == null:
			if not h["alive"]:
				continue
			node = _make_head_visual()
			_visuals[id] = node
			node.set_meta("fade", 0.0)
		var a: Vector2 = h["prev"]
		var b: Vector2 = h["p"]
		var p := a.lerp(b, t)
		var v: Vector2 = h["v"]
		var w: float = h.get("cur_w", h["w"])
		var fade: float = node.get_meta("fade")
		fade = move_toward(fade, 1.0 if h["alive"] and alive else 0.0, delta * 2.0)
		node.set_meta("fade", fade)
		node.global_position = Vector3(p.x, sim_height(p) + w * 0.08, p.y)
		if v.length() > 0.1:
			node.rotation.y = atan2(v.x, v.y)
		var mass: MeshInstance3D = node.get_node("Mass")
		mass.scale = Vector3(w * 0.55, w * 0.3, w * 0.45) * lerpf(0.4, 1.0, fade)
		(mass.get_meta("mat") as ShaderMaterial).set_shader_parameter("fade", fade)
		var spray: GPUParticles3D = node.get_node("Spray")
		spray.emitting = fade > 0.5
		spray.scale = Vector3.ONE * clampf(w / 7.0, 0.7, 4.0)
		if fade <= 0.0 and not h["alive"]:
			node.queue_free()
			_visuals.erase(id)
	if not alive and _visuals.is_empty() and _dying:
		queue_free()


func begin_dissipate() -> void:
	_dying = true


func _process(delta: float) -> void:
	if manager == null or not manager.visuals:
		return
	if _dying:
		visual_update(delta, 1.0)
		vis = 0.0
		if _visuals.is_empty():
			queue_free()


func to_dict() -> Dictionary:
	var d := super.to_dict()
	var hs: Array = []
	for h in heads:
		if h["alive"]:
			var p: Vector2 = h["p"]
			var v: Vector2 = h["v"]
			hs.append([p.x, p.y, v.x, v.y, h["w"], h["trav"]])
	d.merge({"heads": hs, "seed": seed_value, "w0": w0})
	return d


func from_dict(d: Dictionary) -> void:
	super.from_dict(d)
	seed_value = int(d.get("seed", 0))
	rng.seed = seed_value
	w0 = float(d.get("w0", w0))
	heads = []
	for a in d.get("heads", []):
		var h := _new_head(Vector2(a[0], a[1]), Vector2(a[2], a[3]), float(a[4]))
		h["trav"] = float(a[5])
		heads.append(h)
