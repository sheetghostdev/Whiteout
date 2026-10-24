class_name TerrainRenderer
extends Node3D
## Builds the visible terrain chunks, collision, water surfaces, the sea and
## the distant islands on the horizon from a TerrainData.

const CHUNK_CELLS := 64
const FIELD_COLORS := {
	"wheat": Color(0.55, 0.45, 0.28), "corn": Color(0.47, 0.36, 0.23), "sprouts": Color(0.45, 0.34, 0.22),
	"greens": Color(0.42, 0.34, 0.22), "pasture": Color(0.45, 0.62, 0.27),
}

var terrain: TerrainData
var terrain_material: ShaderMaterial
var water_material: ShaderMaterial
var colors := PackedColorArray()
var _color_noise := FastNoiseLite.new()
var _color_noise2 := FastNoiseLite.new()


func build(t: TerrainData) -> void:
	terrain = t
	_color_noise.seed = t.seed_value + 101
	_color_noise.frequency = 0.02
	_color_noise.fractal_octaves = 3
	_color_noise2.seed = t.seed_value + 202
	_color_noise2.frequency = 0.08
	_color_noise2.fractal_octaves = 2
	terrain_material = ShaderLib.material("terrain")
	_compute_colors()
	_build_chunks()
	_build_collision()
	_build_water()
	_build_sea()
	_build_backdrop()


# ------------------------------------------------------------------ colours
func _compute_colors() -> void:
	var V := TerrainData.V
	colors.resize(V * V)
	var grass := Color(0.36, 0.60, 0.22)
	var grass_light := Color(0.53, 0.69, 0.27)
	var grass_deep := Color(0.22, 0.46, 0.17)
	var forest := Color(0.22, 0.40, 0.15)
	var forest_brown := Color(0.36, 0.31, 0.19)
	var alpine := Color(0.40, 0.54, 0.25)
	var rock_tan := Color(0.50, 0.44, 0.37)
	var rock_gray := Color(0.44, 0.43, 0.44)
	var sand := Color(0.80, 0.74, 0.56)
	var wet := Color(0.50, 0.47, 0.36)
	var dirt := Color(0.56, 0.42, 0.27)
	for j in V:
		var z := -TerrainData.HALF + j
		for i in V:
			var x := -TerrainData.HALF + i
			var idx := j * V + i
			var h := terrain.heights[idx]
			var n := _color_noise.get_noise_2d(x, z) * 0.5 + 0.5
			var n2 := _color_noise2.get_noise_2d(x, z) * 0.5 + 0.5
			var slope := _slope_at(i, j)
			var region := terrain.region_at(x, z)
			var c := grass.lerp(grass_light, smoothstep(0.45, 0.85, n)).lerp(grass_deep, smoothstep(0.5, 0.15, n) * 0.8)
			# Woodland floor.
			var wood := smoothstep(-50.0, -110.0, x + (n - 0.5) * 30.0)
			c = c.lerp(forest.lerp(forest_brown, smoothstep(0.55, 0.8, n2) * 0.6), wood * 0.85)
			# Highlands: alpine grass to warm rock to grey stone.
			var hl := terrain.highland_mask(x, z)
			if hl > 0.0:
				c = c.lerp(alpine, hl * 0.6)
				var rockiness := clampf(smoothstep(0.65, 1.15, slope) + smoothstep(50.0, 90.0, h + (n2 - 0.5) * 16.0), 0.0, 1.0)
				var rc := rock_tan.lerp(rock_gray, smoothstep(55.0, 95.0, h))
				c = c.lerp(rc, rockiness * hl)
			elif slope > 0.7:
				c = c.lerp(rock_tan, smoothstep(0.7, 1.1, slope) * 0.7)
			# Beaches around the island; rocky shores under the mountains.
			var cd := terrain.coast[idx]
			if cd < 16.0:
				var shore := 1.0 - smoothstep(5.0 + n * 4.0, 15.0, cd)
				var shore_c := sand.lerp(rock_gray, smoothstep(0.3, 0.8, hl) * 0.8)
				c = c.lerp(shore_c, shore * (1.0 - smoothstep(4.0, 9.0, h)))
			# Shores and river banks.
			var wl := terrain.water_level[idx]
			if wl > -100.0:
				var above := h - wl
				c = c.lerp(sand, (1.0 - smoothstep(0.2, 1.4, above)) * 0.85)
				if above < 0.0:
					c = wet.lerp(sand, clampf(1.0 + above * 0.5, 0.0, 1.0) * 0.4)
			var rd := terrain.river_dist[idx]
			if rd < 9.0 and region != TerrainData.REGION_HIGHLANDS:
				c = c.lerp(Color(0.48, 0.47, 0.40), (1.0 - smoothstep(4.0, 9.0, rd)) * 0.35)
			# Farm fields and village yards.
			var field := terrain.settlements.field_at(Vector2(x, z), 1.0)
			if not field.is_empty():
				c = FIELD_COLORS.get(field["crop"], c)
			# Footpaths.
			var pd := terrain.path_dist[idx]
			if pd < 2.2:
				c = c.lerp(dirt.lerp(dirt.lightened(0.12), n2), (1.0 - smoothstep(0.8, 2.2, pd)) * 0.9)
			colors[idx] = c


func _slope_at(i: int, j: int) -> float:
	var V := TerrainData.V
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, V - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, V - 1)
	var hx := (terrain.heights[j * V + i1] - terrain.heights[j * V + i0]) / float(i1 - i0)
	var hz := (terrain.heights[j1 * V + i] - terrain.heights[j0 * V + i]) / float(j1 - j0)
	return sqrt(hx * hx + hz * hz)


func _normal_at(i: int, j: int) -> Vector3:
	var V := TerrainData.V
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, V - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, V - 1)
	var hx := (terrain.heights[j * V + i1] - terrain.heights[j * V + i0]) / float(i1 - i0)
	var hz := (terrain.heights[j1 * V + i] - terrain.heights[j0 * V + i]) / float(j1 - j0)
	return Vector3(-hx, 1.0, -hz).normalized()


# ------------------------------------------------------------------- chunks
func _build_chunks() -> void:
	var V := TerrainData.V
	var per := CHUNK_CELLS + 1
	var idx := PackedInt32Array()
	for j in CHUNK_CELLS:
		for i in CHUNK_CELLS:
			var a := j * per + i
			var b := a + 1
			var c := a + per
			var d := c + 1
			# Alternate the diagonal for a less regular look.
			if (i + j) % 2 == 0:
				idx.append_array([a, b, c, b, d, c])
			else:
				idx.append_array([a, b, d, a, d, c])
	var chunks := TerrainData.N / CHUNK_CELLS
	for cj in chunks:
		for ci in chunks:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			verts.resize(per * per)
			norms.resize(per * per)
			cols.resize(per * per)
			var k := 0
			for j in per:
				var gj := cj * CHUNK_CELLS + j
				for i in per:
					var gi := ci * CHUNK_CELLS + i
					var gidx := gj * V + gi
					verts[k] = Vector3(-TerrainData.HALF + gi, terrain.heights[gidx], -TerrainData.HALF + gj)
					norms[k] = _normal_at(gi, gj)
					cols[k] = colors[gidx]
					k += 1
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [ci, cj]
			mi.mesh = mesh
			mi.material_override = terrain_material
			# Snow lift happens in the vertex shader; pad the cull box.
			mi.extra_cull_margin = 1.0
			add_child(mi)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var shape := HeightMapShape3D.new()
	shape.map_width = TerrainData.V
	shape.map_depth = TerrainData.V
	shape.map_data = terrain.heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# Invisible walls keep the player inside the playable world.
	var lim := TerrainData.HALF - 6.0
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := CollisionShape3D.new()
		var ws := WorldBoundaryShape3D.new()
		ws.plane = Plane(-d, -lim)
		wall.shape = ws
		body.add_child(wall)
	add_child(body)


# -------------------------------------------------------------------- water
## One mesh for every lake, tarn and river, following the water level of
## each vertex exactly, so water can never float above dry land. Vertex
## colours carry the river flow for the shader.
func _build_water() -> void:
	water_material = ShaderLib.material("water")
	var V := TerrainData.V
	var N := TerrainData.N
	var H := TerrainData.HALF
	var wl := terrain.water_level
	var level := PackedFloat32Array()
	level.resize(V * V)
	for j in V:
		for i in V:
			var idx := j * V + i
			var w := wl[idx]
			if w < -100.0:
				# Extend the surface one vertex under the banks (where the
				# higher ground hides it) at the lowest neighbouring level, so
				# the edge dips under the bank instead of standing up as a wall.
				var lowest := 1.0e9
				for oj in range(-1, 2):
					for oi in range(-1, 2):
						var ni := clampi(i + oi, 0, V - 1)
						var nj := clampi(j + oj, 0, V - 1)
						var nw := wl[nj * V + ni]
						if nw > -100.0:
							lowest = minf(lowest, nw)
				if lowest < 1.0e8:
					w = minf(lowest, terrain.heights[idx] - 0.05)
			level[idx] = w
	var mb := MeshBuilder.new()
	var vmap := PackedInt32Array()
	vmap.resize(V * V)
	vmap.fill(-1)
	for cj in N:
		for ci in N:
			if terrain.cell_ocean[cj * N + ci] == 1:
				continue
			var a := cj * V + ci
			var corners := [a, a + 1, a + V, a + V + 1]
			var wet := false
			var lo := 1.0e9
			var hi := -1.0e9
			for k in corners:
				if wl[k] > -100.0 and wl[k] > terrain.heights[k] - 0.6:
					wet = true
				lo = minf(lo, level[k])
				hi = maxf(hi, level[k])
			if not wet or lo < -100.0:
				continue
			# Where the river reaches the sea, the sea itself is the surface.
			if hi <= TerrainData.SEA_LEVEL + 0.15:
				continue
			var ids := []
			for k in corners:
				if vmap[k] < 0:
					var vi: int = k % V
					var vj: int = k / V
					var f := terrain.flow[k]
					vmap[k] = mb.add_vertex(Vector3(-H + vi, level[k] + 0.02, -H + vj), Vector3.UP,
						Color(f.x * 0.25 + 0.5, f.y * 0.25 + 0.5, 0.0, 1.0))
				ids.append(vmap[k])
			mb.add_tri_idx(ids[0], ids[1], ids[2])
			mb.add_tri_idx(ids[1], ids[3], ids[2])
	var mi := MeshInstance3D.new()
	mi.name = "InlandWater"
	mi.mesh = mb.commit()
	mi.material_override = water_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The sea: a wide disc of rings around the island out to the horizon.
func _build_sea() -> void:
	var mb := MeshBuilder.new()
	var radii: Array[float] = []
	var r := 0.0
	while r < 3600.0:
		radii.append(r)
		r += clampf(r * 0.08, 6.0, 160.0)
	var seg := 160
	var still := Color(0.5, 0.5, 0.0, 1.0)
	for ri in radii.size():
		for k in seg:
			var a := TAU * k / seg
			mb.add_vertex(Vector3(cos(a) * radii[ri], TerrainData.SEA_LEVEL, sin(a) * radii[ri]), Vector3.UP, still)
	for ri in radii.size() - 1:
		for k in seg:
			var a0 := ri * seg + k
			var a1 := ri * seg + (k + 1) % seg
			var b0 := a0 + seg
			var b1 := a1 + seg
			mb.add_tri_idx(a0, b0, a1)
			mb.add_tri_idx(a1, b0, b1)
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = mb.commit()
	var mat := ShaderLib.material("water")
	mat.set_shader_parameter("open_sea", true)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 100.0
	add_child(mi)


# ----------------------------------------------------------------- backdrop
## A few distant islands on the horizon give the sea some depth.
func _build_backdrop() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = terrain.seed_value + 909
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	var islands := [
		[Vector2(-300, -1250), 380.0, 190.0], [Vector2(700, -950), 260.0, 110.0], [Vector2(-1150, -500), 300.0, 140.0],
		[Vector2(1250, 250), 220.0, 70.0], [Vector2(-1000, 800), 200.0, 55.0], [Vector2(450, 1200), 260.0, 80.0],
	]
	var spacing := 24.0
	var mb := MeshBuilder.new()
	for isl in islands:
		var c: Vector2 = isl[0]
		var rad: float = isl[1]
		var peak: float = isl[2]
		var n := int(rad * 2.4 / spacing)
		var base := mb.vertex_count()
		var hts := PackedFloat32Array()
		hts.resize((n + 1) * (n + 1))
		for j in n + 1:
			for i in n + 1:
				var p := c + Vector2(-rad * 1.2 + i * spacing, -rad * 1.2 + j * spacing)
				var d := p.distance_to(c) / rad + noise.get_noise_2d(p.x * 0.5, p.y * 0.5) * 0.25
				var ridge := noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
				var shape := 1.0 - smoothstep(0.0, 1.0, d)
				hts[j * (n + 1) + i] = shape * (peak * (0.45 + 0.55 * ridge)) - 10.0 * (1.0 - shape)
		for j in n + 1:
			for i in n + 1:
				var h := hts[j * (n + 1) + i]
				var hx := hts[j * (n + 1) + mini(i + 1, n)] - hts[j * (n + 1) + maxi(i - 1, 0)]
				var hz := hts[mini(j + 1, n) * (n + 1) + i] - hts[maxi(j - 1, 0) * (n + 1) + i]
				var nrm := Vector3(-hx / (2.0 * spacing), 1.0, -hz / (2.0 * spacing)).normalized()
				mb.add_vertex(Vector3(c.x - rad * 1.2 + i * spacing, h, c.y - rad * 1.2 + j * spacing), nrm, Color.WHITE)
		for j in n:
			for i in n:
				var a0 := j * (n + 1) + i
				if maxf(maxf(hts[a0], hts[a0 + 1]), maxf(hts[a0 + n + 1], hts[a0 + n + 2])) < -1.0:
					continue
				mb.add_tri_idx(base + a0, base + a0 + 1, base + a0 + n + 1)
				mb.add_tri_idx(base + a0 + 1, base + a0 + n + 2, base + a0 + n + 1)
	var mi := MeshInstance3D.new()
	mi.name = "DistantIslands"
	mi.mesh = mb.commit()
	mi.material_override = ShaderLib.material("backdrop")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
