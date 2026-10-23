class_name FoliageBuilder
extends Node3D
## Scatters grass, flowers, bushes, trees, stumps and rocks with seeded,
## clustered (not uniform) distributions, rendered with chunked MultiMeshes.
## MultiMeshes always carry instance colours (white) alongside custom data:
## the Compatibility renderer misreads vertex colours otherwise.
## Trees use two LODs: per-variant MultiMeshes up close and one merged
## low-poly mesh per chunk in the distance.

const TREE_CHUNK := 64.0
const GRASS_CHUNK := 32.0
const FLOWER_CHUNK := 64.0
const NEAR_END := 190.0

enum Kind { BROADLEAF, PINE, SMALL, BUSH }

var terrain: TerrainData
var density_scale := 1.0
var trees: Array = []        # {pos: Vector3, kind, variant, scale, rot, hue}
var rocks: Array = []        # {pos, variant, scale, rot}
var stumps: Array = []

var _rng := RandomNumberGenerator.new()
var _cluster := FastNoiseLite.new()
var _grove := FastNoiseLite.new()
var _flower_noise := FastNoiseLite.new()

var _tree_mat: ShaderMaterial
var _tree_far_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _grass_mat: ShaderMaterial
var _flower_mat: ShaderMaterial

var near_nodes: Array[GeometryInstance3D] = []
var far_nodes: Array[GeometryInstance3D] = []
var grass_nodes: Array[GeometryInstance3D] = []

const VARIANTS := {Kind.BROADLEAF: 4, Kind.PINE: 4, Kind.SMALL: 3, Kind.BUSH: 4}


func _mesh_for(kind: int, variant: int, lod: int) -> ArrayMesh:
	match kind:
		Kind.BROADLEAF:
			return MeshFactory.broadleaf_tree(variant, lod)
		Kind.PINE:
			return MeshFactory.pine_tree(variant, lod)
		Kind.SMALL:
			return MeshFactory.small_tree(variant, lod)
	return MeshFactory.bush(variant)


func setup(t: TerrainData, p_density: float) -> void:
	terrain = t
	density_scale = p_density
	_rng.seed = t.seed_value * 31 + 7
	_cluster.seed = t.seed_value + 401
	_cluster.frequency = 0.018
	_cluster.fractal_octaves = 3
	_grove.seed = t.seed_value + 402
	_grove.frequency = 0.011
	_grove.fractal_octaves = 2
	_flower_noise.seed = t.seed_value + 403
	_flower_noise.frequency = 0.035
	_flower_noise.fractal_octaves = 2
	_tree_mat = ShaderLib.material("tree")
	_tree_far_mat = ShaderLib.material("tree")
	_tree_far_mat.set_shader_parameter("merged", true)
	_rock_mat = ShaderLib.material("tree")
	_rock_mat.set_shader_parameter("per_vertex_snow", true)
	_rock_mat.set_shader_parameter("sway_amount", 0.0)
	_grass_mat = ShaderLib.material("foliage")
	_flower_mat = ShaderLib.material("foliage")
	_flower_mat.set_shader_parameter("is_flower", true)


# ------------------------------------------------------------ placement
func _blocked(x: float, z: float, clearance: float) -> bool:
	if not terrain.in_bounds(x, z, 8.0):
		return true
	var vi := terrain.vertex_index(x, z)
	if terrain.water_level[vi] > -100.0 and terrain.heights[vi] < terrain.water_level[vi] + 0.9:
		return true
	if terrain.river_dist[vi] < 5.0 + clearance:
		return true
	if terrain.path_dist[vi] < 1.6 + clearance:
		return true
	return false


func _tree_density(x: float, z: float) -> float:
	var h := terrain.sample_height(x, z)
	var s := terrain.slope(x, z)
	if s > 0.85:
		return 0.0
	var cl := _cluster.get_noise_2d(x, z) * 0.5 + 0.5
	var gr := _grove.get_noise_2d(x, z) * 0.5 + 0.5
	var region := terrain.region_at(x, z)
	var d := 0.0
	match region:
		TerrainData.REGION_WOODLAND:
			d = 0.036 * smoothstep(0.22, 0.45, cl) * (0.6 + cl * 0.7)
		TerrainData.REGION_MEADOWS:
			d = 0.0012 + 0.024 * smoothstep(0.66, 0.78, gr)
		TerrainData.REGION_LAKE:
			d = 0.003 + 0.02 * smoothstep(0.62, 0.76, gr)
		TerrainData.REGION_HIGHLANDS:
			d = (0.004 + 0.022 * smoothstep(0.45, 0.7, cl)) * (1.0 - smoothstep(42.0, 72.0, h))
	# Keep the spawn meadow open.
	d *= smoothstep(16.0, 34.0, Vector2(x, z).distance_to(TerrainData.SPAWN))
	return d


func _choose_kind(region: int, h: float) -> int:
	var r := _rng.randf()
	match region:
		TerrainData.REGION_WOODLAND:
			return Kind.BROADLEAF if r < 0.55 else (Kind.PINE if r < 0.9 else Kind.SMALL)
		TerrainData.REGION_MEADOWS:
			return Kind.BROADLEAF if r < 0.6 else Kind.SMALL
		TerrainData.REGION_LAKE:
			return Kind.BROADLEAF if r < 0.45 else (Kind.SMALL if r < 0.75 else Kind.PINE)
	return Kind.PINE if r < 0.9 or h > 35.0 else Kind.SMALL


func place_all() -> void:
	trees.clear()
	rocks.clear()
	stumps.clear()
	var cell := 4.0
	var count := int(512.0 / cell)
	var bushes: Array = []
	for j in count:
		for i in count:
			var x := -256.0 + (i + _rng.randf()) * cell
			var z := -256.0 + (j + _rng.randf()) * cell
			if _blocked(x, z, 1.0):
				continue
			var region := terrain.region_at(x, z)
			var h := terrain.sample_height(x, z)
			var p := _tree_density(x, z) * cell * cell
			if _rng.randf() < p:
				var kind := _choose_kind(region, h)
				var sc := _rng.randf_range(0.8, 1.25)
				if kind == Kind.PINE and region == TerrainData.REGION_HIGHLANDS:
					sc *= _rng.randf_range(0.75, 1.1)
				trees.append({"pos": Vector3(x, h - 0.1, z), "kind": kind, "variant": _rng.randi() % VARIANTS[kind],
					"scale": sc, "rot": _rng.randf() * TAU, "hue": _rng.randf()})
				continue
			# Understory and scatter.
			var cl := _cluster.get_noise_2d(x, z) * 0.5 + 0.5
			var bush_p := 0.004 if region != TerrainData.REGION_WOODLAND else 0.012
			if region == TerrainData.REGION_HIGHLANDS:
				bush_p *= 1.0 - smoothstep(30.0, 50.0, h)
			if _rng.randf() < bush_p * cell * cell * (0.4 + cl):
				bushes.append({"pos": Vector3(x, h - 0.05, z), "kind": Kind.BUSH, "variant": _rng.randi() % 4,
					"scale": _rng.randf_range(0.7, 1.3), "rot": _rng.randf() * TAU, "hue": _rng.randf()})
				continue
			var s := terrain.slope(x, z)
			var rock_p := 0.0004
			if region == TerrainData.REGION_HIGHLANDS:
				rock_p = 0.0008 + 0.0022 * smoothstep(0.3, 0.8, s)
			elif terrain.river_dist[terrain.vertex_index(x, z)] < 14.0:
				rock_p = 0.003
			if _rng.randf() < rock_p * cell * cell:
				var big := _rng.randf_range(0.6, 1.6) * (1.8 if region == TerrainData.REGION_HIGHLANDS else 1.0)
				rocks.append({"pos": Vector3(x, h, z), "variant": _rng.randi() % 6, "scale": big, "rot": _rng.randf() * TAU})
				# Natural little groups around larger boulders.
				for k in _rng.randi_range(0, 3):
					var a := _rng.randf() * TAU
					var off := Vector2(cos(a), sin(a)) * big * _rng.randf_range(1.2, 2.4)
					var rx := x + off.x
					var rz := z + off.y
					if not _blocked(rx, rz, 0.0):
						rocks.append({"pos": Vector3(rx, terrain.sample_height(rx, rz), rz), "variant": _rng.randi() % 6,
							"scale": big * _rng.randf_range(0.3, 0.6), "rot": _rng.randf() * TAU})
				continue
			if region == TerrainData.REGION_WOODLAND and _rng.randf() < 0.0012 * cell * cell:
				stumps.append({"pos": Vector3(x, h - 0.05, z), "scale": _rng.randf_range(0.7, 1.2), "rot": _rng.randf() * TAU})
	trees.append_array(bushes)


# ------------------------------------------------------------ building
func _xform(pos: Vector3, rot: float, sc: float, origin: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, rot).scaled(Vector3(sc, sc, sc))
	return Transform3D(b, pos - origin)


func build_trees() -> void:
	var chunks := int(512.0 / TREE_CHUNK)
	var buckets := {}
	for t in trees:
		var p: Vector3 = t["pos"]
		var ci := clampi(int((p.x + 256.0) / TREE_CHUNK), 0, chunks - 1)
		var cj := clampi(int((p.z + 256.0) / TREE_CHUNK), 0, chunks - 1)
		var key := cj * chunks + ci
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(t)
	var near_meshes := {}
	var far_arrays := {}
	for kind in VARIANTS:
		for v in VARIANTS[kind]:
			near_meshes[Vector2i(kind, v)] = _mesh_for(kind, v, 0)
			if kind != Kind.BUSH:
				far_arrays[Vector2i(kind, v)] = _mesh_for(kind, v, 1).surface_get_arrays(0)
	var near_end := NEAR_END
	for key in buckets:
		var list: Array = buckets[key]
		var ci: int = key % chunks
		var cj: int = key / chunks
		var origin := Vector3(-256.0 + (ci + 0.5) * TREE_CHUNK, 0.0, -256.0 + (cj + 0.5) * TREE_CHUNK)
		var by_variant := {}
		for t in list:
			var vk := Vector2i(t["kind"], t["variant"])
			if not by_variant.has(vk):
				by_variant[vk] = []
			by_variant[vk].append(t)
		for vk in by_variant:
			var items: Array = by_variant[vk]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = near_meshes[vk]
			mm.instance_count = items.size()
			for k in items.size():
				var t: Dictionary = items[k]
				mm.set_instance_transform(k, _xform(t["pos"], t["rot"], t["scale"], origin))
				mm.set_instance_color(k, Color.WHITE)
				mm.set_instance_custom_data(k, Color(t["hue"], 0, 0, 0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _tree_mat
			mmi.position = origin
			var is_bush: bool = vk.x == Kind.BUSH
			mmi.visibility_range_end = 150.0 if is_bush else near_end
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if is_bush else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if is_bush:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.set_meta("bush", true)
			add_child(mmi)
			near_nodes.append(mmi)
		# Merged far mesh for the whole chunk.
		var mb := MeshBuilder.new()
		for t in list:
			if t["kind"] == Kind.BUSH:
				continue
			var arr: Array = far_arrays[Vector2i(t["kind"], t["variant"])]
			var xf := _xform(t["pos"], t["rot"], t["scale"], origin)
			var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var sc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var base := mb.vertex_count()
			var p: Vector3 = t["pos"]
			for k in sv.size():
				mb.verts.append(xf * sv[k])
				mb.normals.append(xf.basis.orthonormalized() * sn[k])
				mb.colors.append(sc[k])
				mb.uvs.append(Vector2(t["hue"], 0.0))
				mb.uv2s.append(Vector2(p.x, p.z))
			for k in si.size():
				mb.indices.append(base + si[k])
		if mb.vertex_count() > 0:
			var mesh := mb.commit()
			var far := MeshInstance3D.new()
			far.mesh = mesh
			far.material_override = _tree_far_mat
			far.position = origin
			far.visibility_range_begin = near_end
			far.visibility_range_begin_margin = 10.0
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(far)
			far_nodes.append(far)


func build_rocks_and_stumps() -> void:
	var by_variant := {}
	for r in rocks:
		var v: int = r["variant"]
		if not by_variant.has(v):
			by_variant[v] = []
		by_variant[v].append(r)
	for v in by_variant:
		var items: Array = by_variant[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = MeshFactory.rock(v)
		mm.instance_count = items.size()
		for k in items.size():
			var r: Dictionary = items[k]
			mm.set_instance_transform(k, _xform(r["pos"], r["rot"], r["scale"], Vector3.ZERO))
			mm.set_instance_color(k, Color.WHITE)
			mm.set_instance_custom_data(k, Color(_rng.randf(), 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _rock_mat
		add_child(mmi)
	if stumps.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = MeshFactory.stump()
		mm.instance_count = stumps.size()
		for k in stumps.size():
			var s: Dictionary = stumps[k]
			mm.set_instance_transform(k, _xform(s["pos"], s["rot"], s["scale"], Vector3.ZERO))
			mm.set_instance_color(k, Color.WHITE)
			mm.set_instance_custom_data(k, Color(0.5, 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _tree_mat
		add_child(mmi)


func build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "SceneryCollision"
	for t in trees:
		if t["kind"] == Kind.BUSH:
			continue
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35 * float(t["scale"])
		cyl.height = 5.0
		cs.shape = cyl
		cs.position = t["pos"] + Vector3(0, 2.5, 0)
		body.add_child(cs)
	for r in rocks:
		var sc: float = r["scale"]
		if sc < 1.1:
			continue
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = sc * 0.75
		cs.shape = sph
		cs.position = r["pos"] + Vector3(0, sc * 0.1, 0)
		body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------ ground cover
func _grass_density(x: float, z: float) -> float:
	var vi := terrain.vertex_index(x, z)
	var h := terrain.heights[vi]
	var wl := terrain.water_level[vi]
	if wl > -100.0 and h < wl + 0.7:
		return 0.0
	if terrain.path_dist[vi] < 1.3:
		return 0.0
	var s := terrain.slope(x, z)
	if s > 0.9:
		return 0.0
	var region := terrain.region_at(x, z)
	var cl := _cluster.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5
	var d := 0.9
	match region:
		TerrainData.REGION_WOODLAND:
			d = 0.45
		TerrainData.REGION_LAKE:
			d = 0.85
		TerrainData.REGION_HIGHLANDS:
			d = 0.75 * (1.0 - smoothstep(32.0, 62.0, h)) * (1.0 - smoothstep(0.4, 0.8, s))
	return d * (0.55 + 0.6 * cl) * (1.0 - smoothstep(0.6, 0.9, s))


func build_grass() -> void:
	var meshes := [MeshFactory.grass_clump(0), MeshFactory.grass_clump(1), MeshFactory.grass_clump(2)]
	var chunks := int(512.0 / GRASS_CHUNK)
	var spacing := 0.95 / sqrt(maxf(density_scale, 0.1))
	var per := int(GRASS_CHUNK / spacing)
	for cj in chunks:
		for ci in chunks:
			var origin := Vector3(-256.0 + (ci + 0.5) * GRASS_CHUNK, 0.0, -256.0 + (cj + 0.5) * GRASS_CHUNK)
			var buf := PackedFloat32Array()
			var n := 0
			for j in per:
				for i in per:
					var x := origin.x - GRASS_CHUNK * 0.5 + (i + _rng.randf()) * spacing
					var z := origin.z - GRASS_CHUNK * 0.5 + (j + _rng.randf()) * spacing
					if _rng.randf() > _grass_density(x, z):
						continue
					var y := terrain.sample_height(x, z) - 0.03
					var a := _rng.randf() * TAU
					var s := _rng.randf_range(0.75, 1.35)
					var sy := s * _rng.randf_range(0.8, 1.25)
					var c := cos(a) * s
					var si := sin(a) * s
					buf.append_array([c, 0.0, si, x - origin.x, 0.0, sy, 0.0, y, -si, 0.0, c, z - origin.z,
						1.0, 1.0, 1.0, 1.0, _rng.randf(), 0.0, 0.0, 0.0])
					n += 1
			if n == 0:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = meshes[(ci * 7 + cj * 3) % 3]
			mm.instance_count = n
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _grass_mat
			mmi.position = origin
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 95.0
			add_child(mmi)
			grass_nodes.append(mmi)


func build_flowers() -> void:
	var mesh := MeshFactory.flower()
	var chunks := int(512.0 / FLOWER_CHUNK)
	var spacing := 0.7
	var per := int(FLOWER_CHUNK / spacing)
	for cj in chunks:
		for ci in chunks:
			var origin := Vector3(-256.0 + (ci + 0.5) * FLOWER_CHUNK, 0.0, -256.0 + (cj + 0.5) * FLOWER_CHUNK)
			var buf := PackedFloat32Array()
			var n := 0
			for j in per:
				for i in per:
					var x := origin.x - FLOWER_CHUNK * 0.5 + (i + _rng.randf()) * spacing
					var z := origin.z - FLOWER_CHUNK * 0.5 + (j + _rng.randf()) * spacing
					var fn := _flower_noise.get_noise_2d(x, z) * 0.5 + 0.5
					if fn < 0.66:
						continue
					var region := terrain.region_at(x, z)
					if region == TerrainData.REGION_HIGHLANDS and terrain.sample_height(x, z) > 30.0:
						continue
					var p := smoothstep(0.66, 0.8, fn) * (0.5 if region == TerrainData.REGION_WOODLAND else 0.9) * density_scale
					if _rng.randf() > p or _grass_density(x, z) <= 0.0:
						continue
					var y := terrain.sample_height(x, z) - 0.02
					var a := _rng.randf() * TAU
					var s := _rng.randf_range(0.8, 1.3)
					var c := cos(a) * s
					var si := sin(a) * s
					# Colour family varies by patch so flowers group naturally.
					var family := fmod(_flower_noise.get_noise_2d(x * 0.3 + 50.0, z * 0.3) * 2.0 + 2.0 + _rng.randf() * 0.35, 1.0)
					buf.append_array([c, 0.0, si, x - origin.x, 0.0, s, 0.0, y, -si, 0.0, c, z - origin.z,
						1.0, 1.0, 1.0, 1.0, _rng.randf(), family, 0.0, 0.0])
					n += 1
			if n == 0:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = n
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _flower_mat
			mmi.position = origin
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 95.0
			add_child(mmi)
			grass_nodes.append(mmi)


## Draw distance scaling (settings). 1.0 = default.
func apply_draw_distance(scale: float) -> void:
	for n in grass_nodes:
		n.visibility_range_end = 95.0 * scale
	for n in near_nodes:
		var bush: bool = n.get_meta("bush", false)
		n.visibility_range_end = (150.0 if bush else NEAR_END) * scale
	for n in far_nodes:
		n.visibility_range_begin = NEAR_END * scale
	var shader_fade := 80.0 * scale
	_grass_mat.set_shader_parameter("fade_start", shader_fade - 20.0)
	_grass_mat.set_shader_parameter("fade_end", shader_fade)
	_flower_mat.set_shader_parameter("fade_start", shader_fade - 20.0)
	_flower_mat.set_shader_parameter("fade_end", shader_fade)
