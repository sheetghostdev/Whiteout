class_name TerrainRenderer
extends Node3D
## Builds the visible terrain chunks, collision, water surfaces and the
## distant backdrop ring from a TerrainData.

const CHUNK_CELLS := 64

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
	_build_skirt()
	_build_collision()
	_build_water()
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


## Downward skirt around the edge hides any gap to the backdrop ring.
func _build_skirt() -> void:
	var mb := MeshBuilder.new()
	var V := TerrainData.V
	var H := TerrainData.HALF
	var edges := [
		[Vector2i(0, 0), Vector2i(1, 0), Vector3(0, 0, -1)],
		[Vector2i(V - 1, 0), Vector2i(0, 1), Vector3(1, 0, 0)],
		[Vector2i(V - 1, V - 1), Vector2i(-1, 0), Vector3(0, 0, 1)],
		[Vector2i(0, V - 1), Vector2i(0, -1), Vector3(-1, 0, 0)],
	]
	for e in edges:
		var start: Vector2i = e[0]
		var step: Vector2i = e[1]
		var out: Vector3 = e[2]
		for k in V - 1:
			var a := start + step * k
			var b := a + step
			var pa := Vector3(-H + a.x, terrain.heights[a.y * V + a.x], -H + a.y)
			var pb := Vector3(-H + b.x, terrain.heights[b.y * V + b.x], -H + b.y)
			var ca := colors[a.y * V + a.x].darkened(0.25)
			var cb := colors[b.y * V + b.x].darkened(0.25)
			var i0 := mb.add_vertex(pa, out, ca)
			var i1 := mb.add_vertex(pb, out, cb)
			var i2 := mb.add_vertex(pa - Vector3(0, 30, 0), out, ca)
			var i3 := mb.add_vertex(pb - Vector3(0, 30, 0), out, cb)
			mb.add_tri_idx(i0, i1, i2)
			mb.add_tri_idx(i1, i3, i2)
	var mi := MeshInstance3D.new()
	mi.name = "Skirt"
	mi.mesh = mb.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mi.material_override = mat
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
func _build_water() -> void:
	water_material = ShaderLib.material("water")
	# Lake: a finely subdivided plane over the basin bounding box.
	var mb := MeshBuilder.new()
	var x0 := 60.0
	var x1 := 215.0
	var z0 := -95.0
	var z1 := 85.0
	var step := 2.0
	var nx := int((x1 - x0) / step)
	var nz := int((z1 - z0) / step)
	for j in nz + 1:
		for i in nx + 1:
			mb.add_vertex(Vector3(x0 + i * step, TerrainData.LAKE_LEVEL, z0 + j * step), Vector3.UP, Color.WHITE)
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			mb.add_tri_idx(a, b, c)
			mb.add_tri_idx(b, d, c)
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	lake.mesh = mb.commit()
	lake.material_override = water_material
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	# Rivers: strips along the carved channels.
	for r in terrain.rivers:
		var pts: PackedVector3Array = r["points"]
		var widths: PackedFloat32Array = r["widths"]
		var rb := MeshBuilder.new()
		for k in pts.size():
			var p := pts[k]
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, pts.size() - 1)]
			var t := Vector2(b.x - a.x, b.z - a.z).normalized()
			var nrm := Vector3(-t.y, 0, t.x)
			var hw := widths[k] * 1.35
			rb.add_vertex(p + nrm * hw + Vector3(0, 0.02, 0), Vector3.UP, Color.WHITE, Vector2(0, k * 0.1))
			rb.add_vertex(p - nrm * hw + Vector3(0, 0.02, 0), Vector3.UP, Color.WHITE, Vector2(1, k * 0.1))
		for k in pts.size() - 1:
			var i0 := k * 2
			rb.add_tri_idx(i0, i0 + 1, i0 + 2)
			rb.add_tri_idx(i0 + 1, i0 + 3, i0 + 2)
		var river := MeshInstance3D.new()
		river.name = "River"
		river.mesh = rb.commit()
		var rm := ShaderLib.material("water")
		var first: Vector3 = pts[0]
		var last: Vector3 = pts[pts.size() - 1]
		rm.set_shader_parameter("flow_speed", 0.6)
		rm.set_shader_parameter("flow_dir", Vector2(last.x - first.x, last.z - first.z).normalized())
		rm.render_priority = 1
		river.material_override = rm
		river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(river)


# ----------------------------------------------------------------- backdrop
func _build_backdrop() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = terrain.seed_value + 909
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.frequency = 0.0022
	noise.fractal_octaves = 4
	var spacing := 32.0
	var extent := 1440.0
	var n := int(extent * 2.0 / spacing)
	var H := TerrainData.HALF
	var hts := PackedFloat32Array()
	hts.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := -extent + i * spacing
			var z := -extent + j * spacing
			var e := maxf(absf(x), absf(z))
			var edge_h := terrain.sample_height(clampf(x, -H, H), clampf(z, -H, H))
			if e <= H + 0.01:
				hts[j * (n + 1) + i] = edge_h - 3.0
				continue
			var d := e - H
			var ridge := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var mount := pow(ridge, 1.5) * 160.0 * smoothstep(30.0, 450.0, d)
			# Higher ranges behind the highlands in the north.
			mount *= 1.0 + smoothstep(0.0, -900.0, z) * 0.6
			hts[j * (n + 1) + i] = edge_h - 3.0 + d * 0.12 + mount + smoothstep(0.0, 120.0, d) * 18.0
	var mb := MeshBuilder.new()
	for j in n + 1:
		for i in n + 1:
			var x := -extent + i * spacing
			var z := -extent + j * spacing
			var h := hts[j * (n + 1) + i]
			var hx := hts[j * (n + 1) + mini(i + 1, n)] - hts[j * (n + 1) + maxi(i - 1, 0)]
			var hz := hts[mini(j + 1, n) * (n + 1) + i] - hts[maxi(j - 1, 0) * (n + 1) + i]
			var nrm := Vector3(-hx / (2.0 * spacing), 1.0, -hz / (2.0 * spacing)).normalized()
			mb.add_vertex(Vector3(x, h, z), nrm, Color.WHITE)
	for j in n:
		for i in n:
			var cx := -extent + (i + 0.5) * spacing
			var cz := -extent + (j + 0.5) * spacing
			if absf(cx) < H and absf(cz) < H:
				continue
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			mb.add_tri_idx(a, b, c)
			mb.add_tri_idx(b, d, c)
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = mb.commit()
	mi.material_override = ShaderLib.material("backdrop")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
