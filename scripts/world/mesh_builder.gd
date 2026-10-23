class_name MeshBuilder
extends RefCounted
## Accumulates triangles with per-vertex colour and normal, then commits an
## ArrayMesh. Godot treats clockwise triangles (seen from the front) as front
## faces; every helper here emits triangles in that order.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var indices := PackedInt32Array()


func vertex_count() -> int:
	return verts.size()


func add_vertex(p: Vector3, n: Vector3, c: Color, uv: Vector2 = Vector2.ZERO) -> int:
	verts.append(p)
	normals.append(n)
	colors.append(c)
	uvs.append(uv)
	return verts.size() - 1


func add_tri_idx(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


## Flat-shaded triangle. Order a, b, c is clockwise seen from outside.
func add_flat_tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	var i := verts.size()
	add_vertex(a, n, ca)
	add_vertex(b, n, cb)
	add_vertex(c, n, cc)
	add_tri_idx(i, i + 1, i + 2)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if uv2s.size() == verts.size() and uv2s.size() > 0:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ------------------------------------------------------------- icospheres
static var _ico_cache := {}


## Unit icosphere: {"v": PackedVector3Array, "t": PackedInt32Array}, clockwise from outside.
static func icosphere(subdiv: int) -> Dictionary:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for k in v.size():
		v[k] = v[k].normalized()
	# Counter-clockwise list from the classic construction; flipped below.
	var f: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	for _s in subdiv:
		var mid := {}
		var nf: Array = []
		for tri in f:
			var m := []
			for e in 3:
				var a: int = tri[e]
				var b: int = tri[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					v.append(((v[a] + v[b]) * 0.5).normalized())
					mid[key] = v.size() - 1
				m.append(mid[key])
			nf.append([tri[0], m[0], m[2]])
			nf.append([tri[1], m[1], m[0]])
			nf.append([tri[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f = nf
	var pv := PackedVector3Array(v)
	var pt := PackedInt32Array()
	for tri in f:
		# Flip to clockwise for Godot front faces.
		pt.append(tri[0])
		pt.append(tri[2])
		pt.append(tri[1])
	var res := {"v": pv, "t": pt}
	_ico_cache[subdiv] = res
	return res


## Smooth-shaded noisy blob. `shade` is called with (local_unit_dir, world_pos) -> Color.
func add_blob(center: Vector3, scale: Vector3, subdiv: int, noise_amp: float, rng: RandomNumberGenerator,
		col_top: Color, col_bottom: Color, flat_bottom: float = -2.0, basis: Basis = Basis()) -> void:
	var ico := icosphere(subdiv)
	var src: PackedVector3Array = ico["v"]
	var tris: PackedInt32Array = ico["t"]
	var base := verts.size()
	var ph := Vector3(rng.randf() * 10.0, rng.randf() * 10.0, rng.randf() * 10.0)
	var pos_list := PackedVector3Array()
	pos_list.resize(src.size())
	for k in src.size():
		var d := src[k]
		var n := sin(d.x * 3.1 + ph.x) * sin(d.y * 2.7 + ph.y) * sin(d.z * 3.3 + ph.z)
		n += 0.5 * sin(d.x * 6.3 + ph.z) * sin(d.z * 5.9 + ph.x)
		var r := 1.0 + n * noise_amp
		var lp := d * r
		if lp.y < flat_bottom:
			lp.y = flat_bottom + (lp.y - flat_bottom) * 0.15
		pos_list[k] = center + basis * (lp * scale)
	# Smooth normals from the displaced surface.
	var acc := PackedVector3Array()
	acc.resize(src.size())
	for k in range(0, tris.size(), 3):
		var a := pos_list[tris[k]]
		var b := pos_list[tris[k + 1]]
		var c := pos_list[tris[k + 2]]
		var fn := (c - a).cross(b - a)
		acc[tris[k]] += fn
		acc[tris[k + 1]] += fn
		acc[tris[k + 2]] += fn
	for k in src.size():
		var t := clampf(src[k].y * 0.5 + 0.5, 0.0, 1.0)
		var col := col_bottom.lerp(col_top, t)
		add_vertex(pos_list[k], acc[k].normalized(), col)
	for k in range(0, tris.size(), 3):
		add_tri_idx(base + tris[k], base + tris[k + 1], base + tris[k + 2])


## Flat-shaded faceted blob (rocks).
func add_faceted_blob(center: Vector3, scale: Vector3, subdiv: int, noise_amp: float, rng: RandomNumberGenerator,
		col_a: Color, col_b: Color, flat_bottom: float, basis: Basis = Basis()) -> void:
	var ico := icosphere(subdiv)
	var src: PackedVector3Array = ico["v"]
	var tris: PackedInt32Array = ico["t"]
	var pos_list := PackedVector3Array()
	pos_list.resize(src.size())
	var ph := Vector3(rng.randf() * 10.0, rng.randf() * 10.0, rng.randf() * 10.0)
	for k in src.size():
		var d := src[k]
		var n := sin(d.x * 2.3 + ph.x) * sin(d.y * 2.1 + ph.y) * sin(d.z * 2.6 + ph.z)
		n += rng.randf_range(-0.5, 0.5) * 0.6
		var lp := d * (1.0 + n * noise_amp)
		if lp.y < flat_bottom:
			lp.y = flat_bottom
		pos_list[k] = center + basis * (lp * scale)
	for k in range(0, tris.size(), 3):
		var a := pos_list[tris[k]]
		var b := pos_list[tris[k + 1]]
		var c := pos_list[tris[k + 2]]
		var h := clampf((a.y + b.y + c.y) / 3.0 - center.y + 0.5, 0.0, 1.0)
		var col := col_b.lerp(col_a, h * 0.7 + rng.randf() * 0.3)
		add_flat_tri(a, b, c, col, col, col)


## Tapered cylinder between two points (open ends unless cap).
func add_tube(p0: Vector3, p1: Vector3, r0: float, r1: float, segments: int, c0: Color, c1: Color, cap_top: bool = false) -> void:
	var axis := (p1 - p0).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	var base := verts.size()
	for s in segments + 1:
		var a := TAU * float(s) / segments
		var dir := u * cos(a) + w * sin(a)
		add_vertex(p0 + dir * r0, dir, c0)
		add_vertex(p1 + dir * r1, dir, c1)
	for s in segments:
		var i0 := base + s * 2
		var i1 := i0 + 1
		var i2 := i0 + 2
		var i3 := i0 + 3
		# Winding chosen so faces point outward.
		add_tri_idx(i0, i1, i2)
		add_tri_idx(i1, i3, i2)
	if cap_top:
		var ci := add_vertex(p1, axis, c1)
		for s in segments:
			add_tri_idx(ci, base + s * 2 + 3, base + s * 2 + 1)
