class_name SettlementBuilder
extends Node3D
## Builds the island's village, hamlet and farm from the SettlementPlan:
## houses, a church, a barn, fields, fences, hay, a pier, chimney smoke and
## the villagers who walk the roads. Buildings use the shared tree shader's
## "rock" material, so snow settles on roofs from the coverage texture.

const WALLS: Array[Color] = [Color(0.93, 0.88, 0.76), Color(0.95, 0.91, 0.70), Color(0.92, 0.93, 0.92),
	Color(0.74, 0.84, 0.90), Color(0.62, 0.24, 0.19), Color(0.55, 0.40, 0.27)]
const ROOFS: Array[Color] = [Color(0.66, 0.30, 0.20), Color(0.30, 0.32, 0.38), Color(0.42, 0.30, 0.22), Color(0.36, 0.44, 0.30)]

var terrain: TerrainData
var plan: SettlementPlan
var villagers: Villagers
var coverage: SnowCoverage
var _mat: ShaderMaterial
var _crop_mat: ShaderMaterial
# Crop withering: each field cell ages once it is frozen, over WITHER_TIME.
const WITHER_TIME := 150.0
var _wither_origin := Vector2i.ZERO
var _wither_size := Vector2i.ONE
var _wither := PackedFloat32Array()
var _wither_cells := PackedInt32Array()   # coverage index per wither texel (-1 if not a field)
var _wither_img: Image
var _wither_tex: ImageTexture
var _wither_timer := 0.0
var _rng := RandomNumberGenerator.new()


func build(t: TerrainData, p_coverage: SnowCoverage) -> void:
	terrain = t
	coverage = p_coverage
	plan = t.settlements
	_rng.seed = t.seed_value * 13 + 3
	_mat = ShaderLib.material("tree")
	_mat.set_shader_parameter("per_vertex_snow", true)
	_mat.set_shader_parameter("per_pixel_snow", true)
	_mat.set_shader_parameter("sway_amount", 0.0)
	var mb := MeshBuilder.new()
	for b in plan.buildings:
		_building(mb, b)
	for p in plan.props:
		_prop(mb, p)
	for f in plan.fences:
		_fence(mb, f[0], f[1])
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = mb.commit()
	mi.material_override = _mat
	add_child(mi)
	var crops := MeshBuilder.new()
	for f in plan.fields:
		_field(crops, f)
	if crops.vertex_count() > 0:
		var cm := MeshInstance3D.new()
		cm.name = "Crops"
		cm.mesh = crops.commit()
		_crop_mat = ShaderLib.material("crops")
		_setup_wither()
		cm.material_override = _crop_mat
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cm.extra_cull_margin = 2.0
		add_child(cm)
	villagers = Villagers.new()
	villagers.name = "Villagers"
	add_child(villagers)
	villagers.setup(t, p_coverage, plan)


# ------------------------------------------------------------ withering
func _setup_wither() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for f in plan.fields:
		var c: Vector2 = f["center"]
		var r: float = (f["size"] as Vector2).length() * 0.5 + 2.0
		lo = lo.min(c - Vector2(r, r))
		hi = hi.max(c + Vector2(r, r))
	_wither_origin = Vector2i(int(floor(lo.x + TerrainData.HALF)), int(floor(lo.y + TerrainData.HALF)))
	_wither_size = Vector2i(int(ceil(hi.x - lo.x)), int(ceil(hi.y - lo.y)))
	var n := _wither_size.x * _wither_size.y
	_wither.resize(n)
	_wither.fill(0.0)
	_wither_cells.resize(n)
	for j in _wither_size.y:
		for i in _wither_size.x:
			var ci := _wither_origin.x + i
			var cj := _wither_origin.y + j
			var idx := -1
			if ci >= 0 and cj >= 0 and ci < TerrainData.N and cj < TerrainData.N and terrain.cell_built[cj * TerrainData.N + ci] == 2:
				idx = cj * TerrainData.N + ci
			_wither_cells[j * _wither_size.x + i] = idx
	_wither_img = Image.create(_wither_size.x, _wither_size.y, false, Image.FORMAT_R8)
	_wither_tex = ImageTexture.create_from_image(_wither_img)
	_crop_mat.set_shader_parameter("wither_tex", _wither_tex)
	_crop_mat.set_shader_parameter("wither_rect", Vector4(_wither_origin.x - TerrainData.HALF, _wither_origin.y - TerrainData.HALF,
		_wither_size.x, _wither_size.y))


## New winter: fresh crops. Loaded game: crops already under snow are dead.
func reset_crops(already_frozen_dead: bool) -> void:
	for k in _wither.size():
		var idx := _wither_cells[k]
		_wither[k] = 1.0 if already_frozen_dead and idx >= 0 and coverage.cov[idx] >= 1.0 else 0.0
	_upload_wither()


func _process(delta: float) -> void:
	if _crop_mat == null or coverage == null:
		return
	_wither_timer += delta
	if _wither_timer < 0.5:
		return
	var step := _wither_timer / WITHER_TIME
	_wither_timer = 0.0
	var changed := false
	for k in _wither.size():
		var idx := _wither_cells[k]
		if idx < 0 or _wither[k] >= 1.0:
			continue
		if coverage.cov[idx] >= 1.0:
			_wither[k] = minf(_wither[k] + step, 1.0)
			changed = true
	if changed:
		_upload_wither()


func _upload_wither() -> void:
	var bytes := PackedByteArray()
	bytes.resize(_wither.size())
	for k in _wither.size():
		bytes[k] = int(_wither[k] * 255.0)
	_wither_img.set_data(_wither_size.x, _wither_size.y, false, Image.FORMAT_R8, bytes)
	_wither_tex.update(_wither_img)


# ---------------------------------------------------------------- helpers
## Flat triangle that always faces `outward` (winding fixed automatically).
func _tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, col: Color, outward: Vector3) -> void:
	if (c - a).cross(b - a).dot(outward) < 0.0:
		mb.add_flat_tri(a, c, b, col, col, col)
	else:
		mb.add_flat_tri(a, b, c, col, col, col)


func _quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward: Vector3) -> void:
	_tri(mb, a, b, c, col, outward)
	_tri(mb, a, c, d, col, outward)


## Oriented box: centre, half-size, rotation about Y.
func _box(mb: MeshBuilder, c: Vector3, h: Vector3, rot: float, col: Color, skip_bottom: bool = true) -> void:
	var bs := Basis(Vector3.UP, rot)
	var ax := bs * Vector3(h.x, 0, 0)
	var ay := Vector3(0, h.y, 0)
	var az := bs * Vector3(0, 0, h.z)
	var faces := [[ay, ax, az], [-ax, az, ay], [ax, az, ay], [az, ax, ay], [-az, ax, ay]]
	if not skip_bottom:
		faces.append([-ay, ax, az])
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o: Vector3 = c + n
		_quad(mb, o - u - v, o + u - v, o + u + v, o - u + v, col, n.normalized())


func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 0.5)


func _ground(p: Vector2) -> float:
	return terrain.sample_height(p.x, p.y)


# -------------------------------------------------------------- buildings
func _building(mb: MeshBuilder, b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var s: Vector3 = b["size"]
	var rot: float = b["rot"]
	var kind: String = b["kind"]
	var r := RandomNumberGenerator.new()
	r.seed = int(b["seed"])
	var y0 := _ground(pos) - 0.15
	var bs := Basis(Vector3.UP, rot)
	var origin := Vector3(pos.x, y0, pos.y)
	var wall := WALLS[r.randi() % WALLS.size()]
	var roof := ROOFS[r.randi() % ROOFS.size()]
	if kind == "barn":
		wall = Color(0.62, 0.18, 0.14)
		roof = Color(0.32, 0.30, 0.30)
	elif kind == "church":
		wall = Color(0.94, 0.93, 0.90)
		roof = Color(0.30, 0.32, 0.38)
	elif kind == "shed":
		wall = Color(0.50, 0.38, 0.26)
	wall.a = 0.5
	roof.a = 0.5
	var hw := s.x * 0.5
	var hd := s.z * 0.5
	var h := s.y
	# Stone footing so the house sits into the slope.
	_box(mb, origin + Vector3(0, 0.25, 0), Vector3(hw + 0.15, 0.4, hd + 0.15), rot, Color(0.55, 0.54, 0.52, 0.5))
	_box(mb, origin + Vector3(0, 0.65 + h * 0.5, 0), Vector3(hw, h * 0.5, hd), rot, wall)
	var top := 0.65 + h
	if kind == "shed":
		_shed_roof(mb, origin, bs, hw, hd, top, roof)
		return
	# Gable roof with the ridge along the house's length (local z).
	var rise := hw * (1.1 if kind == "church" else (0.85 if kind == "barn" else 0.7))
	var over := 0.45
	var L := func(x: float, y: float, z: float) -> Vector3: return origin + bs * Vector3(x, y, z)
	var e0: Vector3 = L.call(-hw - over, top - 0.25, -hd - over)
	var e1: Vector3 = L.call(-hw - over, top - 0.25, hd + over)
	var r0: Vector3 = L.call(0.0, top + rise, -hd - over)
	var r1: Vector3 = L.call(0.0, top + rise, hd + over)
	var f0: Vector3 = L.call(hw + over, top - 0.25, -hd - over)
	var f1: Vector3 = L.call(hw + over, top - 0.25, hd + over)
	_quad(mb, e0, e1, r1, r0, roof, (bs * Vector3(-1, 1.2, 0)).normalized())
	_quad(mb, f0, r0, r1, f1, roof, (bs * Vector3(1, 1.2, 0)).normalized())
	# Undersides of the eaves.
	_quad(mb, e0, r0, r1, e1, _shade(roof, 0.55), (bs * Vector3(1, -1.2, 0)).normalized())
	_quad(mb, f0, f1, r1, r0, _shade(roof, 0.55), (bs * Vector3(-1, -1.2, 0)).normalized())
	# Gable ends.
	for side in [-1.0, 1.0]:
		var zz: float = side * hd
		var out: Vector3 = (bs * Vector3(0, 0, side)).normalized()
		_tri(mb, L.call(-hw, top, zz), L.call(hw, top, zz), L.call(0.0, top + rise - 0.2, zz), wall, out)
	# Door and windows on the front (+z), windows on the sides.
	var door := Color(0.36, 0.24, 0.16, 0.5)
	var glass := Color(0.98, 0.85, 0.52, 0.5) if r.randf() < 0.6 else Color(0.36, 0.48, 0.62, 0.5)
	var frame := Color(0.95, 0.95, 0.92, 0.5)
	var dx := r.randf_range(-hw * 0.4, hw * 0.4) if kind == "house" else 0.0
	var dw := 0.55 if kind != "barn" else hw * 0.55
	var dh := 1.1 if kind != "barn" else h * 0.42
	_box(mb, origin + bs * Vector3(dx, 0.65 + dh, hd + 0.03), Vector3(dw, dh, 0.06), rot, door)
	if kind == "barn":
		# White cross braces on the big doors.
		_box(mb, origin + bs * Vector3(dx, 0.65 + dh, hd + 0.1), Vector3(dw, 0.08, 0.04), rot, frame)
		_box(mb, origin + bs * Vector3(dx, 0.65 + dh * 2.0, hd + 0.1), Vector3(dw, 0.08, 0.04), rot, frame)
	else:
		var wy := 0.65 + h * 0.6
		for wx in [-hw * 0.62, hw * 0.62]:
			if absf(wx - dx) < 1.1:
				continue
			_box(mb, origin + bs * Vector3(wx, wy, hd + 0.03), Vector3(0.48, 0.5, 0.05), rot, frame)
			_box(mb, origin + bs * Vector3(wx, wy, hd + 0.07), Vector3(0.38, 0.4, 0.04), rot, glass)
		for wz in [-hd * 0.45, hd * 0.45]:
			for side in [-1.0, 1.0]:
				_box(mb, origin + bs * Vector3(side * (hw + 0.03), wy, wz), Vector3(0.05, 0.48, 0.45), rot, frame)
				_box(mb, origin + bs * Vector3(side * (hw + 0.07), wy, wz), Vector3(0.04, 0.38, 0.35), rot, glass)
	if kind == "church":
		_steeple(mb, origin, bs, rot, hd, top, wall, roof)
	elif kind == "house":
		var cx := hw * 0.45 * (1.0 if r.randf() < 0.5 else -1.0)
		var cz := r.randf_range(-hd * 0.4, hd * 0.4)
		var ch_top := top + rise * (1.0 - absf(cx) / hw) + 0.9
		var stone := Color(0.52, 0.47, 0.44, 0.5)
		_box(mb, origin + bs * Vector3(cx, ch_top - 0.9, cz), Vector3(0.32, 0.9, 0.32), rot, stone)
		_smoke(origin + bs * Vector3(cx, ch_top + 0.1, cz))


func _shed_roof(mb: MeshBuilder, origin: Vector3, bs: Basis, hw: float, hd: float, top: float, roof: Color) -> void:
	var L := func(x: float, y: float, z: float) -> Vector3: return origin + bs * Vector3(x, y, z)
	var a: Vector3 = L.call(-hw - 0.3, top + 0.9, -hd - 0.3)
	var b: Vector3 = L.call(hw + 0.3, top - 0.1, -hd - 0.3)
	var c: Vector3 = L.call(hw + 0.3, top - 0.1, hd + 0.3)
	var d: Vector3 = L.call(-hw - 0.3, top + 0.9, hd + 0.3)
	_quad(mb, a, b, c, d, roof, (bs * Vector3(0.4, 1, 0)).normalized())
	_quad(mb, a, d, c, b, _shade(roof, 0.55), (bs * Vector3(-0.4, -1, 0)).normalized())
	var wall := Color(0.50, 0.38, 0.26, 0.5)
	for side in [-1.0, 1.0]:
		var zz: float = side * hd
		_tri(mb, L.call(-hw, top, zz), L.call(hw, top, zz), L.call(-hw, top + 0.85, zz), wall, (bs * Vector3(0, 0, side)).normalized())


func _steeple(mb: MeshBuilder, origin: Vector3, bs: Basis, rot: float, hd: float, top: float, wall: Color, roof: Color) -> void:
	var tower_c := origin + bs * Vector3(0, 0, hd + 1.6)
	var th := top + 6.0
	_box(mb, tower_c + Vector3(0, th * 0.5, 0), Vector3(1.6, th * 0.5, 1.6), rot, wall)
	var tip := tower_c + Vector3(0, th + 5.0, 0)
	for k in 4:
		var a := rot + PI * 0.25 + k * PI * 0.5
		var b := a + PI * 0.5
		var pa := tower_c + Vector3(sin(a) * 2.3, th, cos(a) * 2.3)
		var pb := tower_c + Vector3(sin(b) * 2.3, th, cos(b) * 2.3)
		var mid := (pa + pb) * 0.5 - tower_c
		_tri(mb, pa, pb, tip, roof, Vector3(mid.x, 1.0, mid.z).normalized())
	var gold := Color(0.85, 0.70, 0.30, 0.5)
	_box(mb, tip + Vector3(0, 0.6, 0), Vector3(0.06, 0.6, 0.06), rot, gold)
	_box(mb, tip + Vector3(0, 0.8, 0), Vector3(0.3, 0.06, 0.06), rot, gold)
	# Belfry openings.
	for k in 4:
		var d := Basis(Vector3.UP, rot + k * PI * 0.5) * Vector3(0, 0, 1.62)
		_box(mb, tower_c + Vector3(0, th - 1.4, 0) + d, Vector3(0.5, 0.8, 0.04).rotated(Vector3.UP, 0.0), rot + k * PI * 0.5, Color(0.2, 0.2, 0.24, 0.5))


func _smoke(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = maxi(3, int(9 * WeatherFX.particle_density))
	p.lifetime = 4.5
	p.preprocess = 4.0
	p.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	p.draw_pass_1 = sm
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.0
	m.gravity = Vector3(0.25, 0.05, 0.1)
	m.scale_min = 0.6
	m.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.86, 0.88, 0.55))
	g.set_color(1, Color(0.9, 0.92, 0.95, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 14, 8))
	add_child(p)
	p.position = at


# ------------------------------------------------------------------ props
func _prop(mb: MeshBuilder, p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var rot: float = p["rot"]
	var y := _ground(pos)
	var at := Vector3(pos.x, y, pos.y)
	var wood := Color(0.48, 0.34, 0.22, 0.5)
	match String(p["kind"]):
		"well":
			var stone := Color(0.58, 0.56, 0.53, 0.5)
			for k in 8:
				var a := k * TAU / 8.0
				_box(mb, at + Vector3(sin(a) * 0.9, 0.4, cos(a) * 0.9), Vector3(0.35, 0.4, 0.2), a, stone)
			_box(mb, at + Vector3(-0.9, 1.3, 0), Vector3(0.08, 0.9, 0.08), rot, wood)
			_box(mb, at + Vector3(0.9, 1.3, 0), Vector3(0.08, 0.9, 0.08), rot, wood)
			_box(mb, at + Vector3(0, 2.25, 0), Vector3(1.2, 0.08, 0.8), rot, Color(0.55, 0.28, 0.20, 0.5))
		"pier":
			var water_y := TerrainData.LAKE_LEVEL + 0.35
			var bs := Basis(Vector3.UP, rot)
			for k in 7:
				var c := at + bs * Vector3(0, 0, k * 2.0)
				c.y = water_y
				_box(mb, c, Vector3(1.2, 0.08, 1.0), rot, wood)
				for sx in [-1.1, 1.1]:
					var post := at + bs * Vector3(sx, 0, k * 2.0)
					_box(mb, Vector3(post.x, water_y - 1.0, post.z), Vector3(0.1, 1.2, 0.1), rot, Color(0.36, 0.26, 0.18, 0.5))
		"hay":
			var hay := Color(0.86, 0.74, 0.38, 0.5)
			mb.add_tube(at + Vector3(0, 0.75, 0) + Basis(Vector3.UP, rot) * Vector3(-0.7, 0, 0),
				at + Vector3(0, 0.75, 0) + Basis(Vector3.UP, rot) * Vector3(0.7, 0, 0), 0.75, 0.75, 10, hay, hay, true)
			mb.add_tube(at + Vector3(0, 0.75, 0) + Basis(Vector3.UP, rot) * Vector3(0.7, 0, 0),
				at + Vector3(0, 0.75, 0) + Basis(Vector3.UP, rot) * Vector3(-0.7, 0, 0), 0.0, 0.75, 10, hay, hay, false)
		"scarecrow":
			_box(mb, at + Vector3(0, 1.0, 0), Vector3(0.06, 1.0, 0.06), rot, wood)
			_box(mb, at + Vector3(0, 1.5, 0), Vector3(0.8, 0.06, 0.06), rot, wood)
			_box(mb, at + Vector3(0, 1.45, 0), Vector3(0.3, 0.35, 0.18), rot, Color(0.30, 0.42, 0.62, 0.5))
			_box(mb, at + Vector3(0, 2.0, 0), Vector3(0.18, 0.18, 0.18), rot, Color(0.85, 0.74, 0.40, 0.5))
			_box(mb, at + Vector3(0, 2.25, 0), Vector3(0.38, 0.04, 0.38), rot, Color(0.45, 0.30, 0.18, 0.5))


func _fence(mb: MeshBuilder, a: Vector2, b: Vector2) -> void:
	var wood := Color(0.52, 0.38, 0.24, 0.5)
	var len := a.distance_to(b)
	var n := int(len / 3.0)
	var rot := atan2(b.x - a.x, b.y - a.y)
	for k in n + 1:
		var p := a.lerp(b, float(k) / maxf(n, 1))
		if terrain.path_dist[terrain.vertex_index(p.x, p.y)] < 2.5:
			continue
		var y := _ground(p)
		_box(mb, Vector3(p.x, y + 0.55, p.y), Vector3(0.07, 0.6, 0.07), rot, wood)
		if k < n:
			var q := a.lerp(b, float(k + 1) / maxf(n, 1))
			if terrain.path_dist[terrain.vertex_index(q.x, q.y)] < 2.5:
				continue
			var m := (p + q) * 0.5
			var my := (y + _ground(q)) * 0.5
			for rh in [0.45, 0.85]:
				_box(mb, Vector3(m.x, my + rh, m.y), Vector3(0.04, 0.05, p.distance_to(q) * 0.5), rot, wood)


## Crops in rows. Each plant carries its base point so the crop shader can
## grow it, sway it and make it wilt where the snow lands.
const CROPS := {
	"wheat": {"row": 0.75, "step": 0.45, "color": Color(0.88, 0.74, 0.34)},
	"corn": {"row": 1.1, "step": 0.8, "color": Color(0.52, 0.66, 0.26)},
	"greens": {"row": 0.9, "step": 0.7, "color": Color(0.42, 0.66, 0.30)},
	"sprouts": {"row": 0.8, "step": 0.5, "color": Color(0.40, 0.68, 0.28)},
}


func _field(mb: MeshBuilder, f: Dictionary) -> void:
	var crop: String = f["crop"]
	if not CROPS.has(crop):
		return
	var spec: Dictionary = CROPS[crop]
	var c: Vector2 = f["center"]
	var size: Vector2 = f["size"] - Vector2(1.5, 1.5)
	var rot: float = f["rot"]
	var tr := Transform2D(-rot, c)
	var rows := int(size.x / float(spec["row"]))
	var per := int(size.y / float(spec["step"]))
	for k in rows:
		var x := -size.x * 0.5 + (k + 0.5) * float(spec["row"])
		for j in per:
			var z := -size.y * 0.5 + (j + 0.5) * float(spec["step"]) + _rng.randf_range(-0.1, 0.1)
			var p: Vector2 = tr * Vector2(x + _rng.randf_range(-0.08, 0.08), z)
			_plant(mb, crop, p, _ground(p) - 0.03, spec["color"])


func _blade(mb: MeshBuilder, base: Vector3, tip: Vector3, half_w: float, side: Vector3, col: Color,
		p: Vector2, phase: float, t0: float = 0.0, t1: float = 1.0) -> void:
	var a := base - side * half_w
	var b := base + side * half_w
	var c0 := Color(col.r, col.g, col.b, t0)
	var c1 := Color(col.r, col.g, col.b, t1)
	for v in [[a, c0], [b, c0], [tip, c1]]:
		mb.add_vertex(v[0], Vector3.UP, v[1], p)
		mb.uv2s.append(Vector2(phase, base.y if t0 == 0.0 else 0.0))
	var i := mb.vertex_count() - 3
	mb.add_tri_idx(i, i + 1, i + 2)


func _plant(mb: MeshBuilder, crop: String, p: Vector2, y: float, col: Color) -> void:
	var phase := _rng.randf()
	var root := Vector3(p.x, y, p.y)
	var yaw := _rng.randf() * TAU
	var start := mb.vertex_count()
	match crop:
		"wheat":
			for k in 3:
				var a := yaw + k * 2.1
				var lean := Vector3(cos(a), 0, sin(a)) * 0.12
				var h := _rng.randf_range(0.8, 1.05)
				_blade(mb, root, root + lean + Vector3(0, h, 0), 0.035, Vector3(-sin(a), 0, cos(a)), col, p, phase)
				# Ear of grain near the top.
				_blade(mb, root + lean * 0.8 + Vector3(0, h * 0.78, 0), root + lean * 1.1 + Vector3(0, h * 1.02, 0), 0.06,
					Vector3(-sin(a), 0, cos(a)), col.lightened(0.1), p, phase, 0.78, 1.0)
		"corn":
			var h := _rng.randf_range(1.5, 1.9)
			for k in 2:
				var a := yaw + k * PI * 0.5
				_blade(mb, root, root + Vector3(0, h, 0), 0.06, Vector3(cos(a), 0, sin(a)), col, p, phase)
			for k in 3:
				var a := yaw + k * 2.2
				var out := Vector3(cos(a), 0, sin(a))
				_blade(mb, root + Vector3(0, h * (0.3 + k * 0.18), 0), root + out * 0.55 + Vector3(0, h * (0.45 + k * 0.18), 0), 0.07,
					out.cross(Vector3.UP).normalized(), col.darkened(0.1), p, phase, 0.3 + k * 0.18, 0.5 + k * 0.18)
			_blade(mb, root + Vector3(0, h * 0.95, 0), root + Vector3(0, h * 1.15, 0), 0.05, Vector3(cos(yaw), 0, sin(yaw)),
				Color(0.86, 0.76, 0.42), p, phase, 0.95, 1.0)
		"greens":
			# A round head of leaves.
			for k in 5:
				var a := yaw + k * TAU / 5.0
				var out := Vector3(cos(a), 0, sin(a))
				_blade(mb, root + out * 0.05, root + out * 0.3 + Vector3(0, 0.32, 0), 0.16, out.cross(Vector3.UP).normalized(),
					col, p, phase)
			_blade(mb, root, root + Vector3(0, 0.38, 0), 0.14, Vector3(cos(yaw), 0, sin(yaw)), col.lightened(0.15), p, phase)
		"sprouts":
			for k in 2:
				var a := yaw + k * PI
				var out := Vector3(cos(a), 0, sin(a))
				_blade(mb, root, root + out * 0.12 + Vector3(0, 0.28, 0), 0.05, out.cross(Vector3.UP).normalized(), col, p, phase)
	# Every vertex of a plant shares its base height (for the shader's growth).
	for i in range(start, mb.vertex_count()):
		mb.uv2s[i] = Vector2(phase, y)
