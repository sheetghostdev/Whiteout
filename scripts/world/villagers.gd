class_name Villagers
extends Node3D
## Little low-poly islanders who stroll along the roads. Once snow starts
## settling around them they slow down, hug themselves, shiver and stamp
## their feet. Purely decorative: they never touch the simulation.

const COATS: Array[Color] = [Color(0.72, 0.22, 0.20), Color(0.22, 0.38, 0.62), Color(0.30, 0.50, 0.30),
	Color(0.80, 0.62, 0.22), Color(0.48, 0.30, 0.52), Color(0.36, 0.36, 0.40)]
const SKIN: Array[Color] = [Color(0.96, 0.80, 0.66), Color(0.82, 0.62, 0.46), Color(0.58, 0.40, 0.28), Color(0.92, 0.72, 0.58)]
const ANIMATE_RANGE := 160.0

var terrain: TerrainData
var coverage: SnowCoverage
var people: Array = []
var _rng := RandomNumberGenerator.new()
var _mat: StandardMaterial3D


func setup(t: TerrainData, cov: SnowCoverage, plan: SettlementPlan) -> void:
	terrain = t
	coverage = cov
	_rng.seed = t.seed_value * 71 + 9
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9
	var counts := [8, 3, 4, 2, 2, 2]
	for r in plan.routes.size():
		var route: PackedVector2Array = plan.routes[r]
		var lens := PackedFloat32Array([0.0])
		for k in range(1, route.size()):
			lens.append(lens[k - 1] + route[k - 1].distance_to(route[k]))
		for n in counts[mini(r, counts.size() - 1)]:
			_spawn(route, lens)


func _part(mb: MeshBuilder, parent: Node3D, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	return pivot


static func _block(mb: MeshBuilder, c: Vector3, h: Vector3, col: Color) -> void:
	var faces := [[Vector3(0, h.y, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z)],
		[Vector3(0, -h.y, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z)],
		[Vector3(h.x, 0, 0), Vector3(0, 0, h.z), Vector3(0, h.y, 0)],
		[Vector3(-h.x, 0, 0), Vector3(0, 0, h.z), Vector3(0, h.y, 0)],
		[Vector3(0, 0, h.z), Vector3(h.x, 0, 0), Vector3(0, h.y, 0)],
		[Vector3(0, 0, -h.z), Vector3(h.x, 0, 0), Vector3(0, h.y, 0)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o: Vector3 = c + n
		var a := o - u - v
		var b := o + u - v
		var cc := o + u + v
		var d := o - u + v
		var outward := n.normalized()
		for tri in [[a, b, cc], [a, cc, d]]:
			var p0: Vector3 = tri[0]
			var p1: Vector3 = tri[1]
			var p2: Vector3 = tri[2]
			if (p2 - p0).cross(p1 - p0).dot(outward) < 0.0:
				mb.add_flat_tri(p0, p2, p1, col, col, col)
			else:
				mb.add_flat_tri(p0, p1, p2, col, col, col)


func _spawn(route: PackedVector2Array, lens: PackedFloat32Array) -> void:
	var coat := COATS[_rng.randi() % COATS.size()]
	var skin := SKIN[_rng.randi() % SKIN.size()]
	var pants := Color(0.25, 0.24, 0.28) if _rng.randf() < 0.6 else Color(0.36, 0.30, 0.22)
	var hat := COATS[_rng.randi() % COATS.size()].lightened(0.15)
	var root := Node3D.new()
	add_child(root)
	var sc := _rng.randf_range(1.15, 1.35)
	root.scale = Vector3.ONE * sc
	var body := Node3D.new()
	root.add_child(body)
	var tb := MeshBuilder.new()
	_block(tb, Vector3(0, 0.3, 0), Vector3(0.2, 0.3, 0.12), coat)
	_block(tb, Vector3(0, 0.72, 0), Vector3(0.13, 0.13, 0.13), skin)
	_block(tb, Vector3(0, 0.88, 0), Vector3(0.14, 0.06, 0.14), hat)
	_block(tb, Vector3(0, 0.98, 0), Vector3(0.05, 0.05, 0.05), hat.lightened(0.3))
	_block(tb, Vector3(0, 0.58, 0.02), Vector3(0.15, 0.04, 0.12), hat)
	var torso := _part(tb, body, Vector3(0, 0.82, 0))
	var legs: Array[Node3D] = []
	for sx in [-0.1, 0.1]:
		var lb := MeshBuilder.new()
		_block(lb, Vector3(0, -0.4, 0), Vector3(0.07, 0.4, 0.08), pants)
		legs.append(_part(lb, body, Vector3(sx, 0.82, 0)))
	var arms: Array[Node3D] = []
	for sx in [-0.26, 0.26]:
		var ab := MeshBuilder.new()
		_block(ab, Vector3(0, -0.27, 0), Vector3(0.055, 0.28, 0.06), coat)
		arms.append(_part(ab, body, Vector3(sx, 1.36, 0)))
	var total: float = lens[lens.size() - 1]
	people.append({"root": root, "body": body, "torso": torso, "legs": legs, "arms": arms, "route": route, "lens": lens,
		"s": _rng.randf() * total, "dir": 1.0 if _rng.randf() < 0.5 else -1.0, "speed": _rng.randf_range(1.0, 1.5),
		"phase": _rng.randf() * TAU, "cold": 0.0, "pause": 0.0, "next_pause": _rng.randf_range(3.0, 9.0), "total": total,
		"lane": _rng.randf_range(-1.0, 1.0)})


func _route_point(p: Dictionary, s: float) -> Array:
	var route: PackedVector2Array = p["route"]
	var lens: PackedFloat32Array = p["lens"]
	var k := 1
	while k < lens.size() - 1 and lens[k] < s:
		k += 1
	var a := route[k - 1]
	var b := route[k]
	var t := clampf((s - lens[k - 1]) / maxf(lens[k] - lens[k - 1], 0.001), 0.0, 1.0)
	return [a.lerp(b, t), (b - a).normalized()]


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or coverage == null:
		return
	var cp := cam.global_position
	var t := Time.get_ticks_msec() * 0.001
	for p in people:
		var root: Node3D = p["root"]
		var d := Vector2(root.position.x - cp.x, root.position.z - cp.z).length()
		if d > ANIMATE_RANGE and p.has("placed"):
			continue
		p["placed"] = true
		var pt: Array = _route_point(p, p["s"])
		var here: Vector2 = pt[0]
		var c := coverage.sample_coverage(here.x, here.y)
		var cold: float = lerpf(p["cold"], smoothstep(0.2, 0.85, c), 1.0 - exp(-delta * 1.2))
		p["cold"] = cold
		# Walk the route back and forth; the cold slows everyone down and
		# makes them stop to shiver every now and then.
		var walking := true
		p["next_pause"] = float(p["next_pause"]) - delta
		if float(p["pause"]) > 0.0:
			p["pause"] = float(p["pause"]) - delta
			walking = false
		elif float(p["next_pause"]) <= 0.0:
			p["next_pause"] = _rng.randf_range(4.0, 10.0) * (1.0 - cold * 0.5)
			if _rng.randf() < 0.25 + cold * 0.6:
				p["pause"] = _rng.randf_range(1.5, 3.5)
		var speed: float = float(p["speed"]) * (1.0 - cold * 0.45)
		if walking:
			var s: float = float(p["s"]) + speed * delta * float(p["dir"])
			if s <= 0.0 or s >= float(p["total"]):
				p["dir"] = -float(p["dir"])
				s = clampf(s, 0.0, float(p["total"]))
			p["s"] = s
			p["phase"] = float(p["phase"]) + delta * speed * 4.2
		pt = _route_point(p, p["s"])
		here = pt[0]
		var fwd: Vector2 = pt[1] * float(p["dir"])
		var side := Vector2(-fwd.y, fwd.x) * float(p["lane"]) * 0.9
		var at := here + side
		root.position = Vector3(at.x, terrain.surface_height(at.x, at.y), at.y)
		var yaw := atan2(fwd.x, fwd.y)
		root.rotation.y = lerp_angle(root.rotation.y, yaw, 1.0 - exp(-delta * 6.0))
		var ph: float = p["phase"]
		var swing := sin(ph) * (0.55 if walking else 0.0) * (1.0 - cold * 0.5)
		var legs: Array = p["legs"]
		var arms: Array = p["arms"]
		var body: Node3D = p["body"]
		# Stamping feet while standing in the cold.
		var stamp := 0.0
		if not walking and cold > 0.3:
			stamp = maxf(sin(t * 9.0 + ph), 0.0) * 0.35 * cold
		(legs[0] as Node3D).rotation.x = swing + stamp
		(legs[1] as Node3D).rotation.x = -swing + (maxf(sin(t * 9.0 + ph + PI), 0.0) * 0.35 * cold if stamp > 0.0 else 0.0)
		# Arms swing when warm, wrap around the body when cold.
		for k in 2:
			var arm: Node3D = arms[k]
			var sgn := -1.0 if k == 0 else 1.0
			var free := -swing * sgn * 0.8
			arm.rotation.x = lerpf(free, -1.25, cold)
			arm.rotation.z = lerpf(0.08 * sgn, -0.75 * sgn, cold)
		# Shivering: a fast little tremble, hunched shoulders.
		var shiver := sin(t * 52.0 + ph * 3.0) * 0.025 * cold
		body.position.x = shiver
		body.rotation.z = sin(t * 47.0 + ph) * 0.05 * cold
		body.rotation.x = 0.18 * cold
		body.position.y = absf(sin(ph)) * 0.04 * (1.0 if walking else 0.0)
