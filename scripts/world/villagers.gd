class_name Villagers
extends Node3D
## The islanders: a small simulation of daily life in every town.
##
## Everyone has a home, a town and a role (farmer, fisher, woodcutter,
## trader, shepherd, or a child). They walk the road network between home,
## work and the places people gather, and choose what to do next from what
## the season allows:
##
##   summer       work the fields, fish off the pier, chop wood, mind the
##                market stalls, chat at the well, sit on benches, play tag.
##   first snow   caught unprepared: children stop and stare at the flakes,
##                everyone else hurries home, shivering - and lights a fire.
##   bundling up  after a while they come back out in coats, scarves, bobble
##                hats and mittens to shovel paths and fetch firewood.
##   winter fun   snowball fights, snowmen, skating on the frozen pond and
##                lake, sledding down the hill, warming by the camp fire,
##                carol singing and ice fishing.
##
## Purely decorative: villagers never touch the snow simulation.

const ANIMATE_RANGE := 190.0
const WINTER_BUNDLE := 30.0     # town winter seconds before anyone comes back out
const WINTER_FUN := 70.0        # ... before the fun starts
const COATS: Array[Color] = [Color(0.72, 0.22, 0.20), Color(0.22, 0.38, 0.62), Color(0.30, 0.50, 0.30),
	Color(0.80, 0.62, 0.22), Color(0.48, 0.30, 0.52), Color(0.36, 0.36, 0.40), Color(0.62, 0.42, 0.26)]
const SHIRTS: Array[Color] = [Color(0.92, 0.90, 0.84), Color(0.70, 0.80, 0.88), Color(0.86, 0.78, 0.60), Color(0.62, 0.70, 0.52)]
const SKIN: Array[Color] = [Color(0.96, 0.80, 0.66), Color(0.82, 0.62, 0.46), Color(0.58, 0.40, 0.28), Color(0.92, 0.72, 0.58)]
const HAIR: Array[Color] = [Color(0.20, 0.14, 0.10), Color(0.45, 0.30, 0.16), Color(0.82, 0.66, 0.36), Color(0.62, 0.26, 0.12), Color(0.70, 0.70, 0.70)]
const KNIT: Array[Color] = [Color(0.85, 0.20, 0.22), Color(0.95, 0.80, 0.25), Color(0.25, 0.55, 0.85), Color(0.30, 0.65, 0.40),
	Color(0.90, 0.45, 0.70), Color(0.95, 0.95, 0.95)]


## One islander.
class Person:
	var root: Node3D
	var body: Node3D
	var torso: Node3D
	var head: Node3D
	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	var summer: Array[Node3D] = []
	var winter: Array[Node3D] = []
	var tools := {}
	var sled: Node3D
	var home := -1
	var town := 0
	var role := "adult"
	var kid := false
	var pos := Vector2.ZERO
	var yaw := 0.0
	var path := PackedVector2Array()
	var path_i := 0
	var speed := 1.3
	var mode := "idle"          # walk / do
	var act := "idle"
	var anim := "idle"
	var act_t := 0.0
	var act_data := {}
	var phase := 0.0
	var anim_t := 0.0
	var cold := 0.0
	var bundled := false
	var adapt_delay := 40.0
	var lane := 0.0
	var seen := false


var terrain: TerrainData
var coverage: SnowCoverage
var plan: SettlementPlan
var people: Array[Person] = []
var snowmen: Array = []          # {node, parts: Array[Node3D], pos, progress, town, spot}
var _balls: Array = []           # {node, a: Vector3, b: Vector3, t, dur, victim}
var _winter := PackedFloat32Array()      # per town: seconds it has been snowed in
var _snow_frac := PackedFloat32Array()   # per town: share of its ground under snow
var _winter_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _mat: StandardMaterial3D
var _ball_mesh: SphereMesh
var _clock := 0.0
# Road graph.
var _nodes := PackedVector2Array()
var _adj: Array = []
var _road_count := 0
var _spot_node := {}
var _door := {}                  # building index -> door point
var _door_node := {}
var _town_nodes: Array = []      # per town: road nodes inside it (for strolls)


func setup(t: TerrainData, cov: SnowCoverage, p_plan: SettlementPlan) -> void:
	terrain = t
	coverage = cov
	plan = p_plan
	_winter.resize(SettlementPlan.TOWNS.size())
	_winter.fill(0.0)
	_snow_frac.resize(SettlementPlan.TOWNS.size())
	_snow_frac.fill(0.0)
	_rng.seed = t.seed_value * 71 + 9
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 0.11
	_ball_mesh.height = 0.22
	_ball_mesh.radial_segments = 8
	_ball_mesh.rings = 4
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.97, 0.98, 1.0)
	bm.roughness = 0.8
	_ball_mesh.material = bm
	_build_graph()
	_populate()


# ------------------------------------------------------------- the season
## Seconds a town has been snowed in (more than ~40% of its ground white).
## Thawing (a new winter) winds it back down quickly.
func winter_time(town: int) -> float:
	return _winter[town] if town >= 0 and town < _winter.size() else 0.0


func snow_fraction(town: int) -> float:
	return _snow_frac[town] if town >= 0 and town < _snow_frac.size() else 0.0


## On loading a saved game, towns already under snow have long since
## settled into winter.
func prime(already_settled: bool) -> void:
	_winter_timer = 1.0
	_update_winter(0.0)
	for t in _winter.size():
		_winter[t] = 300.0 if already_settled and _snow_frac[t] > 0.4 else 0.0
	for p in people:
		p.bundled = winter_time(p.town) > p.adapt_delay
		_dress(p)


func _update_winter(delta: float) -> void:
	_winter_timer += delta
	if _winter_timer < 0.5:
		return
	var dt := _winter_timer
	_winter_timer = 0.0
	for t in SettlementPlan.TOWNS.size():
		var c: Vector2 = SettlementPlan.TOWNS[t]["center"]
		var r: float = float(SettlementPlan.TOWNS[t]["radius"]) * 0.6
		var n := 0.0
		var frozen := 0.0
		for k in 48:
			var p := c + Vector2.from_angle(k * 2.39996) * r * sqrt((k + 0.5) / 48.0)
			if terrain.is_ocean(p.x, p.y):
				continue
			n += 1.0
			if coverage.get_coverage(p.x, p.y) >= 1.0:
				frozen += 1.0
		_snow_frac[t] = frozen / maxf(n, 1.0)
		if _snow_frac[t] > 0.4:
			_winter[t] += dt
		else:
			_winter[t] = maxf(_winter[t] - dt * 4.0, 0.0)


func _frozen(p: Vector2) -> bool:
	var i := coverage.cell_index(p.x, p.y)
	return coverage.cov[i] >= 1.0 and not coverage.is_void(i)


## A spot is usable for winter fun when the snow (or ice) is really there.
func _spot_ready(s: Dictionary) -> bool:
	var c: Vector2 = s["pos"]
	var r: float = s.get("radius", 2.0)
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if not _frozen(c + o * 0.7):
			return false
	return true


# ------------------------------------------------------------- road graph
func _node_near(p: Vector2, tol: float, upto: int) -> int:
	for i in upto:
		if _nodes[i].distance_squared_to(p) < tol * tol:
			return i
	return -1


func _add_node(p: Vector2) -> int:
	_nodes.append(p)
	_adj.append(PackedInt32Array())
	return _nodes.size() - 1


func _link(a: int, b: int) -> void:
	if a == b or (_adj[a] as PackedInt32Array).has(b):
		return
	_adj[a].append(b)
	_adj[b].append(a)


func _nearest_road_node(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in _road_count:
		var d := _nodes[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _build_graph() -> void:
	for road in plan.roads:
		var line: PackedVector2Array = road
		var prev := -1
		for k in range(line.size() - 1):
			var a := line[k]
			var b := line[k + 1]
			var n := maxi(int(a.distance_to(b) / 7.0), 1)
			for s in n + (1 if k == line.size() - 2 else 0):
				var p := a.lerp(b, float(s) / n)
				var i := _node_near(p, 3.0, _nodes.size())
				if i < 0:
					i = _add_node(p)
				if prev >= 0:
					_link(prev, i)
				prev = i
	_road_count = _nodes.size()
	for t in SettlementPlan.TOWNS.size():
		var inside := PackedInt32Array()
		var c: Vector2 = SettlementPlan.TOWNS[t]["center"]
		var r: float = SettlementPlan.TOWNS[t]["radius"]
		for i in _road_count:
			if _nodes[i].distance_to(c) < r * 0.75:
				inside.append(i)
		_town_nodes.append(inside)
	for bi in plan.buildings.size():
		var b: Dictionary = plan.buildings[bi]
		var s: Vector3 = b["size"]
		var front := Vector2(0, s.z * 0.5 + 1.4).rotated(-float(b["rot"]))
		var door: Vector2 = b["pos"] + front
		_door[bi] = door
		var i := _add_node(door)
		_link(i, _nearest_road_node(door))
		_door_node[bi] = i
	for si in plan.spots.size():
		var sp: Dictionary = plan.spots[si]
		var i := _add_node(sp["pos"])
		_link(i, _nearest_road_node(sp["pos"]))
		_spot_node[si] = i


## A* over the road graph; returns the points to walk, ending at `to`.
func _route(from: Vector2, to: Vector2, to_node: int = -1) -> PackedVector2Array:
	var start := _nearest_road_node(from)
	var goal := to_node if to_node >= 0 else _nearest_road_node(to)
	var out := PackedVector2Array()
	if start == goal:
		out.append(to)
		return out
	var n := _nodes.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var open: Array[int] = [start]
	var fscore := {start: _nodes[start].distance_to(_nodes[goal])}
	g[start] = 0.0
	var found := false
	var guard := 0
	while not open.is_empty() and guard < 4000:
		guard += 1
		var bi := 0
		for k in range(1, open.size()):
			if float(fscore[open[k]]) < float(fscore[open[bi]]):
				bi = k
		var cur: int = open[bi]
		open.remove_at(bi)
		if cur == goal:
			found = true
			break
		for nb in (_adj[cur] as PackedInt32Array):
			var ng := g[cur] + _nodes[cur].distance_to(_nodes[nb])
			if ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				fscore[nb] = ng + _nodes[nb].distance_to(_nodes[goal])
				if not open.has(nb):
					open.append(nb)
	if not found:
		out.append(to)
		return out
	var chain: Array[int] = []
	var c := goal
	while c >= 0:
		chain.push_front(c)
		c = came[c]
	for i in chain:
		out.append(_nodes[i])
	out.append(to)
	return out


# ------------------------------------------------------------- population
func _populate() -> void:
	for bi in plan.buildings.size():
		var b: Dictionary = plan.buildings[bi]
		if not b["home"]:
			continue
		var town: int = b["town"]
		var count := 1 + (1 if _rng.randf() < 0.55 else 0)
		if b["kind"] == "tavern":
			count = 2
		for k in count:
			_spawn(bi, town, false)
		if _rng.randf() < (0.6 if town == SettlementPlan.HEARTHWICK else 0.4):
			_spawn(bi, town, true)
			if _rng.randf() < 0.35:
				_spawn(bi, town, true)
	# A few villagers mind the market stalls.
	var traders := 0
	for p in people:
		if p.town == SettlementPlan.HEARTHWICK and not p.kid and traders < 3:
			p.role = "trader"
			traders += 1


func _role_for(town: int) -> String:
	match town:
		SettlementPlan.BROOKFIELD:
			return "farmer"
		SettlementPlan.MERE_END:
			return "fisher" if _rng.randf() < 0.7 else "adult"
		SettlementPlan.SALTMOUTH:
			return "fisher" if _rng.randf() < 0.5 else "adult"
		SettlementPlan.FERNHOLLOW:
			return "woodcutter"
		SettlementPlan.HIGH_FOLD:
			return "shepherd"
	return "adult"


func _spawn(home: int, town: int, kid: bool) -> void:
	var p := Person.new()
	p.home = home
	p.town = town
	p.kid = kid
	p.role = "kid" if kid else _role_for(town)
	p.speed = _rng.randf_range(1.6, 1.9) if kid else _rng.randf_range(1.25, 1.6)
	p.adapt_delay = WINTER_BUNDLE + _rng.randf_range(0.0, 25.0)
	p.lane = _rng.randf_range(-0.8, 0.8)
	p.phase = _rng.randf() * TAU
	_build_body(p)
	# Start just outside home, about to decide what to do.
	var door: Vector2 = _door[home]
	p.pos = door + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
	p.act_t = _rng.randf_range(0.0, 6.0)
	p.mode = "do"
	people.append(p)


# ------------------------------------------------------------- the bodies
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


func _build_body(p: Person) -> void:
	var r := _rng
	var coat := COATS[r.randi() % COATS.size()]
	var shirt := SHIRTS[r.randi() % SHIRTS.size()]
	var skin := SKIN[r.randi() % SKIN.size()]
	var hair := HAIR[r.randi() % HAIR.size()]
	var knit := KNIT[r.randi() % KNIT.size()]
	var knit2 := KNIT[r.randi() % KNIT.size()]
	var pants := Color(0.25, 0.24, 0.28) if r.randf() < 0.6 else Color(0.36, 0.30, 0.22)
	var boots := Color(0.20, 0.15, 0.12)
	# In summer people wear their shirts; the coat goes on for winter.
	var top := shirt if p.role != "fisher" else Color(0.86, 0.80, 0.42)
	p.root = Node3D.new()
	add_child(p.root)
	var sc := (r.randf_range(0.72, 0.82) if p.kid else r.randf_range(1.12, 1.3))
	p.root.scale = Vector3.ONE * sc
	p.body = Node3D.new()
	p.root.add_child(p.body)
	# Torso (pivot at the hips) with the head and arms on it.
	var tb := MeshBuilder.new()
	_block(tb, Vector3(0, 0.3, 0), Vector3(0.2, 0.3, 0.12), top)
	_block(tb, Vector3(0, 0.02, 0), Vector3(0.205, 0.05, 0.125), Color(0.30, 0.22, 0.16))
	p.torso = _part(tb, p.body, Vector3(0, 0.82, 0))
	var cb := MeshBuilder.new()
	_block(cb, Vector3(0, 0.3, 0), Vector3(0.215, 0.31, 0.135), coat)
	_block(cb, Vector3(0, -0.12, 0), Vector3(0.22, 0.14, 0.14), coat.darkened(0.08))
	for k in 3:
		_block(cb, Vector3(0, 0.12 + k * 0.15, 0.137), Vector3(0.02, 0.02, 0.01), Color(0.9, 0.85, 0.6))
	p.winter.append(_part(cb, p.torso, Vector3.ZERO))
	var sb := MeshBuilder.new()
	_block(sb, Vector3(0, 0.6, 0), Vector3(0.15, 0.05, 0.14), knit)
	_block(sb, Vector3(0.08, 0.45, 0.14), Vector3(0.045, 0.14, 0.02), knit)
	_block(sb, Vector3(0.08, 0.33, 0.14), Vector3(0.05, 0.02, 0.022), knit2)
	p.winter.append(_part(sb, p.torso, Vector3.ZERO))
	var hb := MeshBuilder.new()
	_block(hb, Vector3(0, 0.13, 0), Vector3(0.13, 0.13, 0.13), skin)
	_block(hb, Vector3(0, 0.22, -0.02), Vector3(0.14, 0.06, 0.13), hair)
	_block(hb, Vector3(0, 0.12, -0.12), Vector3(0.135, 0.1, 0.03), hair)
	for sx in [-0.05, 0.05]:
		_block(hb, Vector3(sx, 0.15, 0.13), Vector3(0.018, 0.022, 0.01), Color(0.12, 0.1, 0.1))
	_block(hb, Vector3(0, 0.09, 0.135), Vector3(0.02, 0.025, 0.02), skin.darkened(0.1))
	p.head = _part(hb, p.torso, Vector3(0, 0.6, 0))
	if p.kid:
		p.head.scale = Vector3.ONE * 1.25
	# Summer hat: a straw or felt brim. Winter hat: a bobble hat with ear flaps.
	var sh := MeshBuilder.new()
	var straw := Color(0.86, 0.76, 0.46) if r.randf() < 0.6 else coat.lightened(0.15)
	_block(sh, Vector3(0, 0.29, 0), Vector3(0.21, 0.015, 0.21), straw)
	_block(sh, Vector3(0, 0.33, 0), Vector3(0.13, 0.05, 0.13), straw)
	_block(sh, Vector3(0, 0.3, 0), Vector3(0.135, 0.015, 0.135), straw.darkened(0.35))
	var summer_hat := _part(sh, p.head, Vector3.ZERO)
	if r.randf() < (0.3 if p.kid else 0.65):
		p.summer.append(summer_hat)
	else:
		summer_hat.visible = false
	var wh := MeshBuilder.new()
	_block(wh, Vector3(0, 0.27, 0), Vector3(0.145, 0.07, 0.145), knit2)
	_block(wh, Vector3(0, 0.22, 0), Vector3(0.15, 0.025, 0.15), knit)
	_block(wh, Vector3(0, 0.38, 0), Vector3(0.05, 0.05, 0.05), Color(0.97, 0.97, 0.97))
	for sx in [-0.14, 0.14]:
		_block(wh, Vector3(sx, 0.12, 0), Vector3(0.02, 0.07, 0.06), knit2)
	p.winter.append(_part(wh, p.head, Vector3.ZERO))
	for sx in [-0.26, 0.26]:
		var ab := MeshBuilder.new()
		_block(ab, Vector3(0, -0.27, 0), Vector3(0.055, 0.28, 0.06), top)
		_block(ab, Vector3(0, -0.6, 0), Vector3(0.05, 0.05, 0.05), skin)
		var arm := _part(ab, p.torso, Vector3(sx, 0.56, 0))
		var sl := MeshBuilder.new()
		_block(sl, Vector3(0, -0.27, 0), Vector3(0.065, 0.285, 0.07), coat)
		_block(sl, Vector3(0, -0.61, 0), Vector3(0.06, 0.06, 0.06), knit)
		p.winter.append(_part(sl, arm, Vector3.ZERO))
		p.arms.append(arm)
	for sx in [-0.1, 0.1]:
		var lb := MeshBuilder.new()
		_block(lb, Vector3(0, -0.38, 0), Vector3(0.075, 0.38, 0.085), pants)
		_block(lb, Vector3(0, -0.77, 0.03), Vector3(0.08, 0.05, 0.12), boots)
		p.legs.append(_part(lb, p.body, Vector3(sx, 0.82, 0)))
	_build_tools(p)
	_dress(p)


func _build_tools(p: Person) -> void:
	var hand := p.arms[1]
	var wood := Color(0.50, 0.36, 0.22)
	var metal := Color(0.62, 0.64, 0.68)
	var defs := {
		"hoe": [[Vector3(0, -0.6, 0), Vector3(0, -1.55, 0.0), 0.025, wood], [Vector3(0, -1.55, 0), Vector3(0, -1.55, 0.22), 0.04, metal]],
		"axe": [[Vector3(0, -0.6, 0), Vector3(0, -1.25, 0), 0.03, wood], [Vector3(0, -1.2, -0.02), Vector3(0, -1.2, 0.2), 0.06, metal]],
		"shovel": [[Vector3(0, -0.6, 0), Vector3(0, -1.45, 0.05), 0.025, wood], [Vector3(0, -1.45, 0.05), Vector3(0, -1.7, 0.12), 0.11, metal]],
		"rod": [[Vector3(0, -0.6, 0), Vector3(0, -2.6, 0.5), 0.015, wood]],
		"book": [[Vector3(0, -0.62, 0.06), Vector3(0, -0.62, 0.2), 0.08, Color(0.45, 0.16, 0.14)]],
		"logs": [[Vector3(-0.3, -0.62, 0.15), Vector3(0.3, -0.62, 0.15), 0.08, wood], [Vector3(-0.3, -0.5, 0.12), Vector3(0.3, -0.5, 0.12), 0.08, wood.darkened(0.1)]],
		"ball": [[Vector3(0, -0.66, 0), Vector3.ZERO, 0.11, Color(0.97, 0.98, 1.0)]],
	}
	for k in defs:
		var mb := MeshBuilder.new()
		for seg in defs[k]:
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			var col: Color = seg[3]
			if k == "ball":
				mb.add_blob(a, Vector3.ONE * float(seg[2]), 1, 0.0, _rng, col, col, 0.0)
			else:
				mb.add_tube(a, b, float(seg[2]), float(seg[2]), 6, col, col, true)
		var node := _part(mb, hand, Vector3.ZERO)
		node.visible = false
		p.tools[k] = node
	# A wooden sled with curled runners.
	var sm := MeshBuilder.new()
	_block(sm, Vector3(0, 0.22, 0), Vector3(0.28, 0.035, 0.6), Color(0.62, 0.30, 0.20))
	for sx in [-0.24, 0.24]:
		_block(sm, Vector3(sx, 0.09, -0.05), Vector3(0.025, 0.025, 0.62), Color(0.30, 0.24, 0.20))
		_block(sm, Vector3(sx, 0.16, 0.62), Vector3(0.025, 0.08, 0.025), Color(0.30, 0.24, 0.20))
		_block(sm, Vector3(sx, 0.15, -0.2), Vector3(0.02, 0.06, 0.02), Color(0.30, 0.24, 0.20))
	p.sled = _part(sm, p.root, Vector3.ZERO)
	p.sled.visible = false


func _show_tool(p: Person, name: String) -> void:
	for k in p.tools:
		(p.tools[k] as Node3D).visible = k == name


func _dress(p: Person) -> void:
	for n in p.winter:
		n.visible = p.bundled
	for n in p.summer:
		n.visible = not p.bundled


# ------------------------------------------------------------- deciding
func _spots_of(town: int, kinds: Array) -> Array:
	var out: Array = []
	for i in plan.spots.size():
		var s: Dictionary = plan.spots[i]
		if int(s["town"]) == town and String(s["kind"]) in kinds:
			out.append(i)
	return out


## Of the candidate spots, usually the one nearest to the person.
func _near_pick(p: Person, spots: Array) -> int:
	var a: int = spots[_rng.randi() % spots.size()]
	var b: int = spots[_rng.randi() % spots.size()]
	var da := (plan.spots[a]["pos"] as Vector2).distance_to(p.pos)
	var db := (plan.spots[b]["pos"] as Vector2).distance_to(p.pos)
	return a if da <= db else b


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var x := _rng.randf() * total
	for k in weights:
		x -= float(weights[k])
		if x <= 0.0:
			return k
	return weights.keys()[0]


func _go(p: Person, to: Vector2, to_node: int, act: String, data: Dictionary = {}) -> void:
	p.path = _route(p.pos, to, to_node)
	p.path_i = 0
	p.mode = "walk"
	p.act = act
	p.act_data = data
	p.root.visible = true
	_show_tool(p, "logs" if act == "carry" and data.get("loaded", false) else "")


func _go_spot(p: Person, si: int, act: String, data: Dictionary = {}) -> void:
	var s: Dictionary = plan.spots[si]
	var target: Vector2 = s["pos"]
	var r: float = s.get("radius", 0.0)
	if r > 0.0 and act != "skate":
		target += Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, 0.85) * r
	data["spot"] = si
	_go(p, target, _spot_node[si], act, data)


func _go_home(p: Person, hurry: bool = false) -> void:
	_go(p, _door[p.home], _door_node[p.home], "inside", {"hurry": hurry})


## Choose what to do next from the season, the town and the person's role.
func _choose(p: Person) -> void:
	var w := winter_time(p.town)
	var snowy := snow_fraction(p.town) > 0.4
	_show_tool(p, "")
	p.sled.visible = false
	if snowy and not p.bundled:
		if p.act != "inside":
			# Caught off guard: children stop to stare, everyone heads home.
			if p.kid and p.act != "wonder" and _rng.randf() < 0.6:
				_start(p, "wonder", _rng.randf_range(3.0, 5.0))
				return
			_go_home(p, true)
			return
		if w < p.adapt_delay:
			_start(p, "inside", 3.0)
			return
		# Warm again and wrapped up: out they come in winter gear.
		p.bundled = true
		_dress(p)
	elif not snowy and p.bundled and w <= 0.0:
		p.bundled = false
		_dress(p)
	var choice: Dictionary
	if not snowy:
		choice = _summer_choices(p)
	elif w < WINTER_FUN:
		choice = {"shovel": 3.0, "wood": 2.0, "chat": 2.0, "stroll": 1.5, "home": 1.5}
	else:
		choice = _winter_choices(p)
	_do(p, _pick(choice))


func _summer_choices(p: Person) -> Dictionary:
	var c := {"chat": 2.0, "stroll": 2.0, "home": 1.2, "sit": 1.0}
	match p.role:
		"farmer", "fisher", "woodcutter", "trader", "shepherd":
			c["work"] = 5.0
		"kid":
			c = {"play": 5.0, "chat": 1.0, "stroll": 1.0, "home": 1.0}
	return c


func _winter_choices(p: Person) -> Dictionary:
	var c := {"chat": 1.0, "stroll": 1.0, "home": 1.0, "shovel": 0.8, "snowball": 3.0, "snowman": 2.0,
		"skate": 2.5, "sled": 2.0, "carol": 1.0}
	if p.kid:
		c = {"snowball": 6.0, "snowman": 3.0, "skate": 3.0, "sled": 5.0, "home": 0.8}
	match p.role:
		"woodcutter":
			c["campfire"] = 4.0
			c["work"] = 2.0
		"fisher":
			c["icefish"] = 3.0
		"trader":
			c["work"] = 3.0
	return c


func _do(p: Person, what: String) -> void:
	match what:
		"work":
			var kinds: Array = {"farmer": ["field"], "fisher": ["pier_end"], "woodcutter": ["chop"], "trader": ["stall"],
				"shepherd": ["chat"]}.get(p.role, ["chat"])
			var spots := _spots_of(p.town, kinds)
			if spots.is_empty():
				_do(p, "stroll")
				return
			_go_spot(p, _near_pick(p, spots), "work")
		"chat", "sit", "carol", "campfire":
			var kinds: Array = {"chat": ["chat", "well", "square", "tavern", "stall"], "sit": ["bench"], "carol": ["church", "square"],
				"campfire": ["campfire"]}[what]
			var spots := _spots_of(p.town, kinds)
			if spots.is_empty():
				_do(p, "stroll")
				return
			_go_spot(p, _near_pick(p, spots), what)
		"play":
			var spots := _spots_of(p.town, ["square", "green"])
			if spots.is_empty():
				_do(p, "stroll")
				return
			_go_spot(p, _near_pick(p, spots), "play")
		"stroll":
			# A short walk around the neighbourhood.
			var nodes: PackedInt32Array = _town_nodes[p.town]
			var home: Vector2 = _door[p.home]
			var best := -1
			for k in 10:
				if nodes.is_empty():
					break
				var i := nodes[_rng.randi() % nodes.size()]
				if best < 0 or (_nodes[i].distance_to(home) < 45.0 and _rng.randf() < 0.7):
					best = i
					if _nodes[i].distance_to(home) < 45.0:
						break
			if best < 0:
				_go_home(p)
				return
			_go(p, _nodes[best], best, "idle")
		"home":
			_go_home(p)
		"shovel":
			var at: Vector2 = _door[p.home] + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5))
			_go(p, at, _door_node[p.home], "shovel")
		"wood":
			var piles := _spots_of(p.town, ["chop"])
			if piles.is_empty():
				_go(p, _door[p.home], _door_node[p.home], "carry", {"loaded": true})
			else:
				_go_spot(p, piles[0], "carry", {"fetch": true})
		"snowball", "snowman":
			var spots: Array = []
			for i in _spots_of(p.town, ["green", "square"]):
				if _spot_ready(plan.spots[i]):
					spots.append(i)
			if spots.is_empty():
				_do(p, "chat")
				return
			_go_spot(p, _near_pick(p, spots), what)
		"skate", "icefish":
			var spots: Array = []
			for i in _spots_of(p.town, ["rink", "pond"]):
				if _spot_ready(plan.spots[i]):
					spots.append(i)
			if spots.is_empty():
				_do(p, "snowball" if what == "skate" else "chat")
				return
			_go_spot(p, _near_pick(p, spots), what)
		"sled":
			var spots: Array = []
			for i in _spots_of(p.town, ["sled_top"]):
				if _frozen(plan.spots[i]["pos"]) and _frozen(plan.spots[i]["to"]):
					spots.append(i)
			if spots.is_empty():
				_do(p, "snowball")
				return
			_go_spot(p, spots[0], "sled", {"runs": _rng.randi_range(2, 3)})
		_:
			_do(p, "stroll")


## Arrived (or decided to stay): begin the activity itself.
func _start(p: Person, act: String, duration: float) -> void:
	p.mode = "do"
	p.act = act
	p.act_t = duration
	p.anim_t = 0.0
	_show_tool(p, "")
	p.sled.visible = false
	p.root.visible = act != "inside"
	match act:
		"work":
			p.anim = {"farmer": "hoe", "fisher": "fish", "woodcutter": "chop", "trader": "talk", "shepherd": "idle"}.get(p.role, "idle")
			_show_tool(p, {"hoe": "hoe", "fish": "rod", "chop": "axe"}.get(p.anim, ""))
			_face_spot(p)
		"icefish":
			p.anim = "fish"
			_show_tool(p, "rod")
		"chat", "idle":
			p.anim = "talk" if act == "chat" else "idle"
		"sit":
			p.anim = "sit"
			_face_spot(p)
		"carol":
			p.anim = "carol"
			_show_tool(p, "book")
		"campfire":
			p.anim = "warm"
			_face_spot(p, true)
		"wonder":
			p.anim = "wonder"
		"shovel":
			p.anim = "shovel"
			_show_tool(p, "shovel")
		"play":
			p.anim = "run"
		"snowball":
			p.anim = "idle"
			p.act_data["cool"] = _rng.randf_range(0.3, 1.5)
		"snowman":
			p.anim = "roll"
			_join_snowman(p)
		"skate":
			p.anim = "skate"
			p.act_data["ang"] = _rng.randf() * TAU
			p.act_data["dir"] = 1.0 if _rng.randf() < 0.5 else -1.0
		"sled":
			p.anim = "sled"
			p.act_data["stage"] = "ride"
		_:
			p.anim = "idle"


## Turn to face along a spot's "look" direction, or towards its centre.
func _face_spot(p: Person, centre: bool = false) -> void:
	if not p.act_data.has("spot"):
		return
	var s: Dictionary = plan.spots[p.act_data["spot"]]
	if s.has("look") and not centre:
		var look: Vector2 = s["look"]
		p.yaw = atan2(look.x, look.y)
	elif centre:
		var d: Vector2 = (s["pos"] as Vector2) - p.pos
		if d.length() > 0.1:
			p.yaw = atan2(d.x, d.y)


func _arrive(p: Person) -> void:
	match p.act:
		"inside":
			var cold_home: bool = p.act_data.get("hurry", false)
			_start(p, "inside", 5.0 if cold_home else _rng.randf_range(10.0, 30.0))
		"work":
			_start(p, "work", _rng.randf_range(35.0, 70.0))
		"chat", "carol":
			_start(p, p.act, _rng.randf_range(18.0, 40.0))
		"sit":
			_start(p, "sit", _rng.randf_range(25.0, 50.0))
		"campfire", "icefish":
			_start(p, p.act, _rng.randf_range(25.0, 50.0))
		"shovel":
			_start(p, "shovel", _rng.randf_range(12.0, 22.0))
		"carry":
			if p.act_data.get("fetch", false):
				# Picked up an armful of logs at the woodpile; now take it home.
				_go(p, _door[p.home], _door_node[p.home], "carry", {"loaded": true})
			else:
				_go_home(p)
		"play":
			_start(p, "play", _rng.randf_range(20.0, 40.0))
		"snowball":
			_start(p, "snowball", _rng.randf_range(30.0, 60.0))
		"snowman":
			_start(p, "snowman", _rng.randf_range(14.0, 22.0))
		"skate":
			_start(p, "skate", _rng.randf_range(30.0, 60.0))
		"sled":
			_start(p, "sled", 90.0)
		_:
			_start(p, "idle", _rng.randf_range(2.0, 5.0))


# ------------------------------------------------------------- snowmen
func _join_snowman(p: Person) -> void:
	var si: int = p.act_data.get("spot", -1)
	for s in snowmen:
		if int(s["spot"]) == si and float(s["progress"]) < 1.0:
			p.act_data["snowman"] = s
			return
	var count := 0
	for s in snowmen:
		if int(s["spot"]) == si:
			count += 1
	if count >= 3:
		# This green is full of snowmen; have a snowball fight instead.
		p.act = "snowball"
		p.anim = "idle"
		p.act_data["cool"] = 0.5
		return
	var pos := p.pos + Vector2(sin(p.yaw), cos(p.yaw)) * 1.3
	var s := _make_snowman(pos, p.town, si)
	snowmen.append(s)
	p.act_data["snowman"] = s


func _make_snowman(pos: Vector2, town: int, si: int) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	node.position = Vector3(pos.x, terrain.surface_height(pos.x, pos.y) - 0.05, pos.y)
	node.rotation.y = _rng.randf() * TAU
	var white := Color(0.96, 0.97, 1.0)
	var shade := Color(0.80, 0.86, 0.96)
	var parts: Array[Node3D] = []
	for spec in [[0.42, 0.55], [1.12, 0.42], [1.66, 0.3]]:
		var mb := MeshBuilder.new()
		mb.add_blob(Vector3(0, float(spec[0]), 0), Vector3.ONE * float(spec[1]), 1, 0.04, _rng, white, shade, -0.4)
		parts.append(_part(mb, node, Vector3.ZERO))
	var deco := MeshBuilder.new()
	deco.add_tube(Vector3(0, 1.66, 0.26), Vector3(0, 1.64, 0.55), 0.05, 0.0, 6, Color(0.95, 0.5, 0.12), Color(0.95, 0.5, 0.12))
	for sx in [-0.1, 0.1]:
		_block(deco, Vector3(sx, 1.75, 0.27), Vector3(0.03, 0.03, 0.02), Color(0.1, 0.1, 0.1))
	for k in 3:
		_block(deco, Vector3(0, 1.0 + k * 0.17, 0.41 - absf(k - 1) * 0.02), Vector3(0.035, 0.035, 0.02), Color(0.1, 0.1, 0.1))
	for sx in [-1.0, 1.0]:
		deco.add_tube(Vector3(sx * 0.38, 1.2, 0), Vector3(sx * 0.9, 1.55, 0.05), 0.025, 0.018, 4, Color(0.36, 0.25, 0.16), Color(0.36, 0.25, 0.16))
	var knit := KNIT[_rng.randi() % KNIT.size()]
	if _rng.randf() < 0.5:
		_block(deco, Vector3(0, 1.98, 0), Vector3(0.2, 0.02, 0.2), Color(0.12, 0.12, 0.14))
		_block(deco, Vector3(0, 2.12, 0), Vector3(0.13, 0.14, 0.13), Color(0.12, 0.12, 0.14))
	else:
		_block(deco, Vector3(0, 1.42, 0), Vector3(0.3, 0.05, 0.3), knit)
		_block(deco, Vector3(0.12, 1.3, 0.28), Vector3(0.05, 0.14, 0.02), knit)
	parts.append(_part(deco, node, Vector3.ZERO))
	for part in parts:
		part.visible = false
	return {"node": node, "parts": parts, "pos": pos, "progress": 0.0, "town": town, "spot": si}


func _grow_snowman(s: Dictionary, amount: float) -> void:
	var prog := minf(float(s["progress"]) + amount, 1.0)
	s["progress"] = prog
	var parts: Array = s["parts"]
	for k in parts.size():
		var t := clampf((prog - k * 0.25) / 0.25, 0.0, 1.0)
		var part: Node3D = parts[k]
		part.visible = t > 0.0
		if k < 3:
			part.scale = Vector3.ONE * lerpf(0.25, 1.0, t)


## Snowmen finished so far.
func snowmen_built() -> int:
	var n := 0
	for s in snowmen:
		if float(s["progress"]) >= 1.0:
			n += 1
	return n


## How many people are doing each activity right now (for tests).
func census() -> Dictionary:
	var out := {}
	for p in people:
		var k := p.act if p.mode == "do" else "walking"
		out[k] = int(out.get(k, 0)) + 1
	return out


# ------------------------------------------------------------- snowballs
func _throw(p: Person) -> void:
	var targets: Array[Person] = []
	for o in people:
		if o != p and o.act == "snowball" and o.mode == "do" and o.pos.distance_to(p.pos) < 16.0:
			targets.append(o)
	var aim: Vector2
	var victim: Person = null
	if targets.is_empty():
		aim = p.pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(4.0, 8.0)
	else:
		victim = targets[_rng.randi() % targets.size()]
		aim = victim.pos + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
	var d := aim - p.pos
	p.yaw = atan2(d.x, d.y)
	p.anim = "throw"
	p.anim_t = 0.0
	p.act_data["release"] = 0.42
	p.act_data["aim"] = aim
	p.act_data["victim"] = victim


func _release(p: Person) -> void:
	var aim: Vector2 = p.act_data.get("aim", p.pos)
	var node := MeshInstance3D.new()
	node.mesh = _ball_mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var s := p.root.scale.x
	var a := Vector3(p.pos.x, p.root.position.y + 1.6 * s, p.pos.y)
	var b := Vector3(aim.x, terrain.surface_height(aim.x, aim.y) + 1.1, aim.y)
	var dur := clampf(a.distance_to(b) / 11.0, 0.35, 1.0)
	node.position = a
	_balls.append({"node": node, "a": a, "b": b, "t": 0.0, "dur": dur, "victim": p.act_data.get("victim")})
	_show_tool(p, "")


func _update_balls(delta: float) -> void:
	var i := _balls.size() - 1
	while i >= 0:
		var b: Dictionary = _balls[i]
		b["t"] = float(b["t"]) + delta
		var k := clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
		var a: Vector3 = b["a"]
		var e: Vector3 = b["b"]
		var node: MeshInstance3D = b["node"]
		node.position = a.lerp(e, k) + Vector3(0, sin(k * PI) * a.distance_to(e) * 0.18, 0)
		if k >= 1.0:
			var victim = b.get("victim")
			if victim != null and (victim as Person).mode == "do" and (victim as Person).pos.distance_to(Vector2(e.x, e.z)) < 1.2:
				(victim as Person).anim = "hit"
				(victim as Person).anim_t = 0.0
			node.queue_free()
			_balls.remove_at(i)
		i -= 1


# ------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if coverage == null:
		return
	_update_winter(delta)
	_clock += delta
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	var cp := cam.global_position if cam != null else Vector3.ZERO
	for p in people:
		var near := Vector2(p.pos.x - cp.x, p.pos.y - cp.z).length() < ANIMATE_RANGE
		_step(p, delta)
		_place(p, delta, near or not p.seen)
		p.seen = true
	_update_balls(delta)


func _step(p: Person, delta: float) -> void:
	# Cold: unprepared people out in the snow feel it; bundled-up ones barely.
	var target_cold := 0.0
	var indoors := p.mode == "do" and p.act == "inside"
	if not indoors and _frozen(p.pos):
		target_cold = 0.12 if p.bundled else 1.0
	if p.act in ["campfire", "skate", "sled", "snowball", "play", "snowman"]:
		target_cold *= 0.4
	p.cold = lerpf(p.cold, target_cold, 1.0 - exp(-delta * 1.2))
	# The first snow interrupts whatever unprepared people were doing.
	if not p.bundled and p.act not in ["inside", "wonder"] and snow_fraction(p.town) > 0.4:
		_choose(p)
	if p.mode == "walk":
		_walk(p, delta)
		return
	p.act_t -= delta
	p.anim_t += delta
	match p.act:
		"play":
			_play(p, delta)
		"snowball":
			_snowball(p, delta)
		"snowman":
			var s = p.act_data.get("snowman")
			if s != null:
				_grow_snowman(s, delta / 26.0)
				if float(s["progress"]) >= 1.0 and p.anim != "admire":
					p.anim = "admire"
					p.act_t = minf(p.act_t, 3.0)
				elif p.anim == "roll":
					# Push the growing ball round in little loops.
					p.yaw += delta * 0.9
					p.pos += Vector2(sin(p.yaw), cos(p.yaw)) * delta * 0.35
		"skate":
			_skate(p, delta)
		"sled":
			_sled(p, delta)
	if p.anim == "hit" and p.anim_t > 0.6:
		p.anim = "idle"
	if p.act_t <= 0.0:
		_choose(p)


func _walk(p: Person, delta: float) -> void:
	if p.path_i >= p.path.size():
		_arrive(p)
		return
	var target := p.path[p.path_i]
	var hurry: bool = p.act_data.get("hurry", false)
	var spd := p.speed * (1.45 if hurry else 1.0) * (1.0 - p.cold * 0.15)
	var to := target - p.pos
	var step := spd * delta
	if to.length() <= step + 0.05:
		p.pos = target
		p.path_i += 1
	else:
		p.pos += to.normalized() * step
		p.yaw = lerp_angle(p.yaw, atan2(to.x, to.y), 1.0 - exp(-delta * 8.0))
	p.phase += delta * spd * 4.4
	p.anim = "hurry" if hurry or p.cold > 0.5 else "walk"


func _play(p: Person, delta: float) -> void:
	var si: int = p.act_data.get("spot", -1)
	if si < 0:
		return
	var s: Dictionary = plan.spots[si]
	var c: Vector2 = s["pos"]
	var r: float = s.get("radius", 6.0)
	if not p.act_data.has("goal") or p.pos.distance_to(p.act_data["goal"]) < 0.4:
		p.act_data["goal"] = c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, r)
	var to: Vector2 = p.act_data["goal"] - p.pos
	p.pos += to.normalized() * minf(to.length(), delta * p.speed * 1.9)
	p.yaw = lerp_angle(p.yaw, atan2(to.x, to.y), 1.0 - exp(-delta * 10.0))
	p.phase += delta * p.speed * 1.9 * 4.4
	p.anim = "run"


func _snowball(p: Person, delta: float) -> void:
	if p.anim == "throw":
		if p.act_data.has("release") and p.anim_t >= float(p.act_data["release"]):
			p.act_data.erase("release")
			_release(p)
		if p.anim_t > 0.8:
			p.anim = "idle"
			p.act_data["cool"] = _rng.randf_range(0.8, 2.2)
		return
	if p.anim == "hit":
		return
	if p.anim == "scoop":
		if p.anim_t > 0.9:
			p.anim = "idle"
		return
	p.act_data["cool"] = float(p.act_data.get("cool", 1.0)) - delta
	if float(p.act_data["cool"]) <= 0.0:
		_show_tool(p, "ball")
		if _rng.randf() < 0.3:
			# Duck down to scoop up more snow first.
			p.anim = "scoop"
			p.anim_t = 0.0
			p.act_data["cool"] = 0.4
		else:
			_throw(p)


func _skate(p: Person, delta: float) -> void:
	var si: int = p.act_data.get("spot", -1)
	if si < 0:
		return
	var s: Dictionary = plan.spots[si]
	var c: Vector2 = s["pos"]
	var r: float = float(s.get("radius", 6.0)) * 0.75
	var ang: float = p.act_data["ang"]
	var dir: float = p.act_data["dir"]
	# A loose figure of eight around the rink.
	ang += dir * delta * 2.6 / maxf(r, 1.0)
	p.act_data["ang"] = ang
	var target := c + Vector2(cos(ang) * r, sin(ang * 2.0) * r * 0.55)
	var to := target - p.pos
	p.pos += to.normalized() * minf(to.length(), delta * 3.2)
	if to.length() > 0.05:
		p.yaw = lerp_angle(p.yaw, atan2(to.x, to.y), 1.0 - exp(-delta * 5.0))
	p.phase += delta * 2.4
	p.anim = "skate"


func _sled(p: Person, delta: float) -> void:
	var si: int = p.act_data.get("spot", -1)
	if si < 0:
		return
	var s: Dictionary = plan.spots[si]
	var top: Vector2 = s["pos"]
	var bottom: Vector2 = s["to"]
	match String(p.act_data.get("stage", "ride")):
		"ride":
			var v: float = p.act_data.get("v", 0.0)
			v = minf(v + delta * 3.0, 7.5)
			p.act_data["v"] = v
			var to := bottom - p.pos
			p.yaw = atan2(to.x, to.y)
			p.pos += to.normalized() * minf(to.length(), v * delta)
			p.anim = "sled"
			if to.length() < 0.5:
				p.act_data["stage"] = "climb"
				p.act_data["v"] = 0.0
				p.act_data["runs"] = int(p.act_data.get("runs", 2)) - 1
		"climb":
			var to := top - p.pos
			p.yaw = lerp_angle(p.yaw, atan2(to.x, to.y), 1.0 - exp(-delta * 6.0))
			p.pos += to.normalized() * minf(to.length(), p.speed * 0.8 * delta)
			p.phase += delta * p.speed * 3.6
			p.anim = "drag"
			if to.length() < 0.5:
				if int(p.act_data.get("runs", 0)) <= 0:
					p.act_t = 0.0
				else:
					p.act_data["stage"] = "ride"


## Position, height and pose. Far away only the position is kept up to date.
func _place(p: Person, delta: float, animate: bool) -> void:
	var fwd := Vector2(sin(p.yaw), cos(p.yaw))
	var at := p.pos + Vector2(-fwd.y, fwd.x) * p.lane * (0.6 if p.mode == "walk" else 0.0)
	var y := terrain.surface_height(at.x, at.y)
	var water := terrain.sample_water_level(at.x, at.y)
	if water > -100.0:
		y = maxf(y, plan.bridge_height(at, water))
	p.root.position = Vector3(at.x, y, at.y)
	if not animate or not p.root.visible:
		return
	p.root.rotation.y = lerp_angle(p.root.rotation.y, p.yaw, 1.0 - exp(-delta * 10.0))
	_pose(p, delta)


func _pose(p: Person, delta: float) -> void:
	var t := _clock + p.phase * 0.1
	var ph := p.phase
	var l0 := 0.0
	var l1 := 0.0
	var lz0 := 0.0
	var lz1 := 0.0
	var a0 := 0.0
	var a1 := 0.0
	var az0 := 0.08
	var az1 := -0.08
	var tx := 0.0
	var tz := 0.0
	var hx := 0.0
	var hy := 0.0
	var by := 0.0
	var sled_on := false
	match p.anim:
		"walk", "hurry", "drag":
			var sw := sin(ph) * (0.6 if p.anim != "hurry" else 0.7)
			l0 = sw
			l1 = -sw
			a0 = -sw * 0.8
			a1 = sw * 0.8
			by = absf(sin(ph)) * 0.04
			tx = 0.12 if p.anim == "hurry" else 0.04
			if p.act == "carry" and p.act_data.get("loaded", false):
				a0 = -1.0
				a1 = -1.0
			if p.anim == "drag":
				a1 = 0.7
				tx = 0.2
				sled_on = true
		"run":
			var sw := sin(ph) * 0.95
			l0 = sw
			l1 = -sw
			a0 = -sw * 1.1
			a1 = sw * 1.1
			by = absf(sin(ph)) * 0.08
			tx = 0.18
		"idle":
			hy = sin(t * 0.5) * 0.3
			a0 = sin(t * 1.3) * 0.03
			a1 = -a0
		"talk":
			a1 = -0.5 + sin(t * 3.0) * 0.35
			az1 = -0.25
			a0 = sin(t * 1.7) * 0.15
			hx = sin(t * 2.3) * 0.08
			hy = sin(t * 0.7) * 0.25
		"sit":
			l0 = -1.45
			l1 = -1.45
			by = -0.38
			tx = -0.08
			a0 = -0.35
			a1 = -0.35
			hy = sin(t * 0.4) * 0.3
		"hoe":
			var k := sin(t * 2.4)
			tx = 0.35 + k * 0.2
			a0 = -0.9 - k * 0.5
			a1 = -0.8 - k * 0.55
			az0 = 0.25
			az1 = -0.25
			l0 = 0.25
			l1 = -0.2
		"chop":
			var k := fposmod(t * 1.1, 1.0)
			var lift := 1.0 - pow(1.0 - minf(k / 0.6, 1.0), 2.0)
			var strike := clampf((k - 0.6) / 0.15, 0.0, 1.0)
			var arm := lerpf(-0.4, -2.7, lift * (1.0 - strike))
			a0 = arm
			a1 = arm
			az0 = 0.2
			az1 = -0.2
			tx = 0.1 + strike * 0.35
		"shovel":
			var dig := sin(fposmod(t * 0.7, 1.0) * TAU)
			tx = 0.4 + dig * 0.2
			a0 = -1.0 - dig * 0.4
			a1 = -0.7 - dig * 0.6
			az0 = 0.3
			az1 = -0.3
			l0 = 0.3
			l1 = -0.25
		"fish":
			l0 = -1.45
			l1 = -1.45
			by = -0.6
			a1 = -0.8 + sin(t * 0.8) * 0.05
			a0 = -0.6
			az0 = -0.2
		"wonder":
			hx = -0.55
			hy = sin(t * 0.8) * 0.4
			a0 = -0.6
			a1 = -0.6
			az0 = 0.9
			az1 = -0.9
			by = maxf(sin(t * 4.0), 0.0) * 0.05
		"throw":
			var k := p.anim_t
			if k < 0.42:
				a1 = lerpf(0.0, 1.9, k / 0.42)
				tx = -0.15
				hx = -0.1
			else:
				a1 = lerpf(1.9, -1.6, clampf((k - 0.42) / 0.12, 0.0, 1.0))
				tx = 0.25
			a0 = -0.5
			l0 = -0.3
			l1 = 0.25
		"scoop":
			var k := sin(clampf(p.anim_t / 0.9, 0.0, 1.0) * PI)
			tx = 0.9 * k
			a0 = -1.2 * k
			a1 = -1.3 * k
			l0 = 0.3 * k
			l1 = -0.4 * k
			by = -0.15 * k
		"hit":
			var k := sin(clampf(p.anim_t / 0.6, 0.0, 1.0) * PI)
			tx = -0.45 * k
			a0 = 0.6 * k
			a1 = 0.6 * k
			az0 = 0.8 * k
			az1 = -0.8 * k
			hx = -0.3 * k
		"skate":
			var push := sin(ph)
			tx = 0.38
			lz0 = maxf(push, 0.0) * 0.45
			lz1 = -maxf(-push, 0.0) * 0.45
			l0 = maxf(push, 0.0) * -0.3
			l1 = maxf(-push, 0.0) * -0.3
			a0 = push * 0.5
			a1 = -push * 0.5
			az0 = 0.55
			az1 = -0.55
			tz = push * 0.06
		"sled":
			l0 = -1.4
			l1 = -1.4
			by = -0.45
			tx = -0.15
			a0 = -0.5
			a1 = -0.5
			az0 = 0.45
			az1 = -0.45
			sled_on = true
		"roll":
			tx = 0.75
			a0 = -1.35
			a1 = -1.35
			var sw := sin(t * 3.0) * 0.35
			l0 = sw
			l1 = -sw
			by = -0.08
		"admire":
			a0 = -1.0
			a1 = -1.0
			az0 = -0.35 + absf(sin(t * 7.0)) * 0.3
			az1 = 0.35 - absf(sin(t * 7.0)) * 0.3
			hx = -0.15
		"warm":
			a0 = -1.15
			a1 = -1.15
			az0 = -0.3 + sin(t * 6.0) * 0.08
			az1 = 0.3 - sin(t * 6.0) * 0.08
			tx = 0.1
		"carol":
			a0 = -0.95
			a1 = -0.95
			az0 = -0.2
			az1 = 0.2
			tz = sin(t * 1.6) * 0.08
			hx = -0.12 + sin(t * 1.6) * 0.06
			hy = sin(t * 0.8) * 0.1
	# Cold, unprepared people hug themselves, hunch and shiver.
	var c := p.cold * (1.0 if p.anim in ["walk", "hurry", "idle", "talk"] else 0.3)
	if c > 0.01:
		a0 = lerpf(a0, -1.25, c)
		a1 = lerpf(a1, -1.25, c)
		az0 = lerpf(az0, -0.75, c)
		az1 = lerpf(az1, 0.75, c)
		tx += 0.15 * c
		if p.anim in ["idle", "talk"]:
			l0 += maxf(sin(t * 9.0 + ph), 0.0) * 0.35 * c
			l1 += maxf(sin(t * 9.0 + ph + PI), 0.0) * 0.35 * c
	var shiver := sin(t * 52.0 + ph * 3.0) * 0.022 * p.cold
	var k := 1.0 - exp(-delta * 14.0)
	var legs := p.legs
	var arms := p.arms
	legs[0].rotation.x = lerpf(legs[0].rotation.x, l0, k)
	legs[1].rotation.x = lerpf(legs[1].rotation.x, l1, k)
	legs[0].rotation.z = lerpf(legs[0].rotation.z, lz0, k)
	legs[1].rotation.z = lerpf(legs[1].rotation.z, lz1, k)
	arms[0].rotation.x = lerpf(arms[0].rotation.x, a0, k)
	arms[1].rotation.x = lerpf(arms[1].rotation.x, a1, k if p.anim != "throw" else 1.0)
	arms[0].rotation.z = lerpf(arms[0].rotation.z, az0, k)
	arms[1].rotation.z = lerpf(arms[1].rotation.z, az1, k)
	p.torso.rotation.x = lerpf(p.torso.rotation.x, tx, k)
	p.torso.rotation.z = lerpf(p.torso.rotation.z, tz + sin(t * 47.0 + ph) * 0.04 * p.cold, k)
	p.head.rotation.x = lerpf(p.head.rotation.x, hx, k)
	p.head.rotation.y = lerpf(p.head.rotation.y, hy, k)
	p.body.position = Vector3(shiver, lerpf(p.body.position.y, by, k), 0)
	p.sled.visible = sled_on
	p.sled.position = Vector3(0, 0, -1.3) if p.anim == "drag" else Vector3.ZERO
