class_name MeshFactory
extends RefCounted
## Procedural art. Every model in the game is assembled here from vertex
## arrays - no imported meshes. Vertex colour alpha is used as a material
## channel: 1.0 = foliage, 0.0 = bark/wood, 0.5 = rock.

const BARK := Color(0.36, 0.25, 0.17, 0.0)
const BARK_DARK := Color(0.25, 0.17, 0.11, 0.0)


static func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


static func _c(r: float, g: float, b: float, a: float = 1.0) -> Color:
	return Color(r, g, b, a)


# ---------------------------------------------------------------- trees
static func broadleaf_tree(variant: int, lod: int = 0) -> ArrayMesh:
	var rng := _rng(1000 + variant * 77)
	var mb := MeshBuilder.new()
	var h_trunk := rng.randf_range(2.6, 3.6)
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
	var top := Vector3(0, h_trunk, 0) + lean
	var segs := 7 if lod == 0 else 5
	mb.add_tube(Vector3(0, -0.4, 0), top, rng.randf_range(0.30, 0.38), 0.18, segs, BARK_DARK, BARK)
	# Root flare.
	mb.add_tube(Vector3(0, -0.4, 0), Vector3(0, 0.5, 0), 0.55, 0.3, segs, BARK_DARK, BARK_DARK)
	var leaf_dark := _c(0.17, 0.38, 0.14)
	var leaf_light := _c(0.42, 0.66, 0.24)
	var hue := rng.randf_range(-0.04, 0.04)
	leaf_dark = leaf_dark.from_hsv(leaf_dark.h + hue, leaf_dark.s, leaf_dark.v, 1.0)
	leaf_light = leaf_light.from_hsv(leaf_light.h + hue, leaf_light.s, leaf_light.v, 1.0)
	var sub := 1 if lod == 0 else 0
	var crown_c := top + Vector3(0, rng.randf_range(1.6, 2.1), 0)
	var branches := rng.randi_range(3, 4)
	var ang0 := rng.randf() * TAU
	for b in branches:
		var a := ang0 + TAU * b / branches + rng.randf_range(-0.3, 0.3)
		var start := Vector3(0, h_trunk * rng.randf_range(0.65, 0.9), 0) + lean * 0.8
		var dir := Vector3(cos(a), rng.randf_range(0.7, 1.1), sin(a)).normalized()
		var length := rng.randf_range(1.5, 2.3)
		var end := start + dir * length
		if lod == 0:
			mb.add_tube(start, end, 0.13, 0.06, 5, BARK, BARK)
		var br := rng.randf_range(1.3, 1.8)
		mb.add_blob(end + Vector3(0, br * 0.35, 0), Vector3(br, br * 0.82, br), sub, 0.14, rng, leaf_light, leaf_dark, -0.55)
	var cr := rng.randf_range(1.9, 2.4)
	mb.add_blob(crown_c, Vector3(cr, cr * 0.85, cr), sub, 0.12, rng, leaf_light, leaf_dark, -0.6)
	if lod == 0:
		for f in 3:
			var a2 := rng.randf() * TAU
			var off := Vector3(cos(a2), rng.randf_range(-0.2, 0.7), sin(a2)) * rng.randf_range(1.2, 1.9)
			var fr := rng.randf_range(1.0, 1.4)
			mb.add_blob(crown_c + off, Vector3(fr, fr * 0.8, fr), 1, 0.15, rng, leaf_light, leaf_dark, -0.5)
	return mb.commit()


static func pine_tree(variant: int, lod: int = 0) -> ArrayMesh:
	var rng := _rng(2000 + variant * 131)
	var mb := MeshBuilder.new()
	var height := rng.randf_range(8.5, 11.5)
	mb.add_tube(Vector3(0, -0.4, 0), Vector3(0, height * 0.75, 0), 0.32, 0.08, 6 if lod == 0 else 4, BARK_DARK, BARK)
	var layers := rng.randi_range(5, 7) if lod == 0 else 4
	var dark := _c(0.10, 0.30, 0.22)
	var light := _c(0.20, 0.45, 0.30)
	var y := rng.randf_range(1.4, 2.0)
	var span := height - y
	var spikes := 11 if lod == 0 else 7
	for l in layers:
		var t := float(l) / layers
		var r := lerpf(2.6, 0.7, t) * rng.randf_range(0.9, 1.1)
		var lh := span / layers * 1.75
		var apex := Vector3(rng.randf_range(-0.05, 0.05), y + lh, rng.randf_range(-0.05, 0.05))
		var rim: Array[Vector3] = []
		var rot := rng.randf() * TAU
		for k in spikes * 2:
			var a := rot + TAU * k / (spikes * 2)
			var rr := r if k % 2 == 0 else r * 0.68
			var droop := -0.35 if k % 2 == 0 else 0.0
			rim.append(Vector3(cos(a) * rr, y + droop + rng.randf_range(-0.08, 0.08), sin(a) * rr))
		var under := Vector3(0, y + 0.35, 0)
		var c_layer_top := light.lerp(_c(0.26, 0.52, 0.34), t)
		for k in rim.size():
			var p0 := rim[k]
			var p1 := rim[(k + 1) % rim.size()]
			var cl := c_layer_top if k % 2 == 0 else c_layer_top.darkened(0.08)
			mb.add_flat_tri(apex, p0, p1, cl.lightened(0.08), dark, dark)
			mb.add_flat_tri(under, p1, p0, dark.darkened(0.25), dark.darkened(0.2), dark.darkened(0.2))
		y += span / layers
	# Tip.
	var tip_base := Vector3(0, y - 0.2, 0)
	var tip := Vector3(0, y + 1.0, 0)
	for k in 5:
		var a0 := TAU * k / 5.0
		var a1 := TAU * (k + 1) / 5.0
		mb.add_flat_tri(tip, tip_base + Vector3(cos(a0), 0, sin(a0)) * 0.35, tip_base + Vector3(cos(a1), 0, sin(a1)) * 0.35, light, dark, dark)
	return mb.commit()


## Slender birch-like tree with pale bark and light airy foliage.
static func small_tree(variant: int, lod: int = 0) -> ArrayMesh:
	var rng := _rng(3000 + variant * 97)
	var mb := MeshBuilder.new()
	var h := rng.randf_range(3.2, 4.4)
	var bark := Color(0.86, 0.84, 0.78, 0.0)
	var bark_d := Color(0.55, 0.53, 0.5, 0.0)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	mb.add_tube(Vector3(0, -0.3, 0), Vector3(0, h, 0) + lean, 0.15, 0.07, 6 if lod == 0 else 4, bark_d, bark)
	var lt := _c(0.58, 0.74, 0.30)
	var dk := _c(0.30, 0.50, 0.18)
	var sub := 1 if lod == 0 else 0
	var blobs := rng.randi_range(3, 4)
	for b in blobs:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a) * 0.6, rng.randf_range(-0.6, 0.8), sin(a) * 0.6)
		var r := rng.randf_range(0.9, 1.25)
		mb.add_blob(Vector3(0, h, 0) + lean + off, Vector3(r, r * 1.15, r), sub, 0.18, rng, lt, dk, -0.5)
	return mb.commit()


static func bush(variant: int) -> ArrayMesh:
	var rng := _rng(4000 + variant * 53)
	var mb := MeshBuilder.new()
	var lt := _c(0.36, 0.58, 0.22)
	var dk := _c(0.16, 0.34, 0.12)
	var n := rng.randi_range(3, 5)
	for b in n:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.7)
		var r := rng.randf_range(0.55, 0.85)
		mb.add_blob(off + Vector3(0, r * 0.45, 0), Vector3(r, r * 0.75, r), 1, 0.2, rng, lt, dk, -0.4)
	# A few berries/blossoms for colour.
	if variant % 2 == 0:
		var bc := _c(0.95, 0.85, 0.9) if variant == 0 else _c(0.92, 0.35, 0.35)
		for k in 7:
			var a3 := rng.randf() * TAU
			var p := Vector3(cos(a3) * 0.75, rng.randf_range(0.5, 0.9), sin(a3) * 0.75)
			mb.add_blob(p, Vector3.ONE * 0.08, 0, 0.0, rng, bc, bc, -2.0)
	return mb.commit()


static func stump() -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.add_tube(Vector3(0, -0.3, 0), Vector3(0, 0.55, 0), 0.5, 0.42, 9, BARK_DARK, BARK, true)
	# Ring top in pale wood.
	var ring_c := Color(0.78, 0.64, 0.45, 0.0)
	var c0 := mb.add_vertex(Vector3(0, 0.56, 0), Vector3.UP, ring_c.lightened(0.1))
	var base := mb.vertex_count()
	for k in 10:
		var a := TAU * k / 9.0
		mb.add_vertex(Vector3(cos(a) * 0.4, 0.56, sin(a) * 0.4), Vector3.UP, ring_c)
	for k in 9:
		mb.add_tri_idx(c0, base + k, base + k + 1)
	return mb.commit()


static func rock(variant: int) -> ArrayMesh:
	var rng := _rng(5000 + variant * 211)
	var mb := MeshBuilder.new()
	var warm := _c(0.58, 0.55, 0.50, 0.5)
	var dark := _c(0.36, 0.35, 0.34, 0.5)
	if variant % 3 == 1:
		warm = _c(0.63, 0.58, 0.48, 0.5)
	var sc := Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.55, 0.9), rng.randf_range(0.8, 1.2))
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
	mb.add_faceted_blob(Vector3(0, 0.15, 0), sc, 1, 0.28, rng, warm, dark, -0.35, basis)
	if variant >= 3:
		# Secondary lump for a more interesting silhouette.
		var off := Vector3(rng.randf_range(0.5, 0.9), 0.0, rng.randf_range(-0.4, 0.4))
		mb.add_faceted_blob(off, sc * 0.6, 1, 0.3, rng, warm, dark, -0.35, basis)
	return mb.commit()


# ---------------------------------------------------------------- ground
static func grass_clump(variant: int) -> ArrayMesh:
	var rng := _rng(6000 + variant * 17)
	var mb := MeshBuilder.new()
	var blades := 9
	for b in blades:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.22)
		var h := rng.randf_range(0.32, 0.62)
		var w := rng.randf_range(0.035, 0.055)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face)) * w
		var bend := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.2) * h
		var mid := root + Vector3(0, h * 0.55, 0) + bend * 0.4
		var tip := root + Vector3(0, h, 0) + bend
		var cb := _c(0.20, 0.42, 0.13, 0.0)
		var cm := _c(0.36, 0.60, 0.20, 0.55)
		var ct := _c(0.62, 0.78, 0.34, 1.0)
		var up := Vector3.UP
		var i0 := mb.add_vertex(root - side, up, cb)
		var i1 := mb.add_vertex(root + side, up, cb)
		var i2 := mb.add_vertex(mid - side * 0.7, up, cm)
		var i3 := mb.add_vertex(mid + side * 0.7, up, cm)
		var i4 := mb.add_vertex(tip, up, ct)
		mb.add_tri_idx(i0, i2, i1)
		mb.add_tri_idx(i1, i2, i3)
		mb.add_tri_idx(i2, i4, i3)
	return mb.commit()


## Flower: green stem, white petals (tinted per instance in the shader via
## vertex alpha 1.0) and a golden centre.
static func flower() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var stem := _c(0.25, 0.48, 0.16, 0.0)
	var h := 0.42
	var up := Vector3.UP
	var w := 0.018
	for k in 2:
		var side := Vector3(w, 0, 0) if k == 0 else Vector3(0, 0, w)
		var i0 := mb.add_vertex(-side, up, stem)
		var i1 := mb.add_vertex(side, up, stem)
		var i2 := mb.add_vertex(Vector3(0, h, 0) - side, up, stem)
		var i3 := mb.add_vertex(Vector3(0, h, 0) + side, up, stem)
		mb.add_tri_idx(i0, i2, i1)
		mb.add_tri_idx(i1, i2, i3)
	var petal := Color(1, 1, 1, 1.0)
	var centre := _c(0.98, 0.82, 0.25, 0.5)
	var c := Vector3(0, h, 0)
	var petals := 5
	for p in petals:
		var a := TAU * p / petals
		var d := Vector3(cos(a), 0.25, sin(a))
		var t := Vector3(-sin(a), 0, cos(a))
		var tip := c + d * 0.11
		var i0 := mb.add_vertex(c, up, petal)
		var i1 := mb.add_vertex(c + d * 0.07 + t * 0.045, up, petal)
		var i2 := mb.add_vertex(tip, up, petal)
		var i3 := mb.add_vertex(c + d * 0.07 - t * 0.045, up, petal)
		mb.add_tri_idx(i0, i1, i2)
		mb.add_tri_idx(i0, i2, i3)
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var i0 := mb.add_vertex(c + Vector3(0, 0.02, 0), up, centre)
		var i1 := mb.add_vertex(c + Vector3(cos(a0) * 0.028, 0.012, sin(a0) * 0.028), up, centre)
		var i2 := mb.add_vertex(c + Vector3(cos(a1) * 0.028, 0.012, sin(a1) * 0.028), up, centre)
		mb.add_tri_idx(i0, i2, i1)
	return mb.commit()


# ---------------------------------------------------------------- weather
## Puffy cloud roughly spanning x/z in [-1.1, 1.1], y in [-0.3, 0.8].
static func cloud(variant: int, detail: int = 2) -> ArrayMesh:
	var rng := _rng(7000 + variant * 389)
	var mb := MeshBuilder.new()
	var top := Color(1.0, 1.0, 1.0)
	var bottom := Color(0.74, 0.80, 0.90)
	var n := rng.randi_range(7, 10)
	var stretch := rng.randf_range(1.0, 1.35)
	for b in n:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 0.75
		var p := Vector3(cos(a) * rr * stretch, 0.0, sin(a) * rr)
		var size := lerpf(0.55, 0.32, rr / 0.75) * rng.randf_range(0.85, 1.15)
		p.y = size * 0.3 + (0.75 - rr) * 0.25
		mb.add_blob(p, Vector3(size, size * 0.85, size), detail, 0.06, rng, top, bottom, -0.35)
	return mb.commit()


static func snowflake(size: float = 0.07) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var c := Color(1, 1, 1, 1)
	var n := Vector3(0, 0, 1)
	var arms := 6
	var center := mb.add_vertex(Vector3.ZERO, n, c)
	var base := mb.vertex_count()
	for k in arms * 2:
		var a := TAU * k / (arms * 2)
		var r := size if k % 2 == 0 else size * 0.4
		mb.add_vertex(Vector3(cos(a) * r, sin(a) * r, 0), n, c)
	for k in arms * 2:
		mb.add_tri_idx(center, base + (k + 1) % (arms * 2), base + k)
	return mb.commit()


## Flat polar grid of unit radius in XZ, uv = xz * 0.5 + 0.5.
static func disc_grid(rings: int, segments: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var up := Vector3.UP
	var c := Color.WHITE
	var center := mb.add_vertex(Vector3.ZERO, up, c, Vector2(0.5, 0.5))
	for r in range(1, rings + 1):
		var rad := float(r) / rings
		for s in segments:
			var a := TAU * s / segments
			var p := Vector3(cos(a) * rad, 0, sin(a) * rad)
			mb.add_vertex(p, up, c, Vector2(p.x * 0.5 + 0.5, p.z * 0.5 + 0.5))
	for s in segments:
		mb.add_tri_idx(center, 1 + s, 1 + (s + 1) % segments)
	for r in range(1, rings):
		var b0 := 1 + (r - 1) * segments
		var b1 := 1 + r * segments
		for s in segments:
			var s1 := (s + 1) % segments
			mb.add_tri_idx(b0 + s, b1 + s, b0 + s1)
			mb.add_tri_idx(b0 + s1, b1 + s, b1 + s1)
	return mb.commit()


## Plane grid spanning x in [-0.5, 0.5], z in [0, 1]; uv = (x + 0.5, z).
static func strip_grid(nx: int, nz: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for j in nz + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / nz
			mb.add_vertex(Vector3(u - 0.5, 0, v), Vector3.UP, Color.WHITE, Vector2(u, v))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			mb.add_tri_idx(a, b, c)
			mb.add_tri_idx(b, d, c)
	return mb.commit()


## Vertical curved curtain: x in [-0.5, 0.5], y in [0, 1], bowed forward on +z.
static func curtain(nx: int, ny: int, bow: float) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for j in ny + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / ny
			var x := u - 0.5
			var z := bow * (1.0 - 4.0 * x * x)
			mb.add_vertex(Vector3(x, v, z), Vector3(0, 0, 1), Color.WHITE, Vector2(u, v))
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			mb.add_tri_idx(a, c, b)
			mb.add_tri_idx(b, c, d)
	return mb.commit()


## Spiral arms for the polar vortex. Unit radius, uv.x = along arm, uv.y = across.
static func spiral(arms: int, turns: float, steps: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for a in arms:
		var off := TAU * a / arms
		var base := mb.vertex_count()
		for s in steps + 1:
			var t := float(s) / steps
			var ang := off + t * turns * TAU
			var r := 0.06 + t * 0.94
			var w := 0.05 + t * 0.22
			var y := 0.25 * (1.0 - t)
			var dir := Vector3(cos(ang), 0, sin(ang))
			mb.add_vertex(dir * (r - w * 0.5) + Vector3(0, y, 0), Vector3.UP, Color.WHITE, Vector2(t, 0))
			mb.add_vertex(dir * (r + w * 0.5) + Vector3(0, y, 0), Vector3.UP, Color.WHITE, Vector2(t, 1))
		for s in steps:
			var i0 := base + s * 2
			mb.add_tri_idx(i0, i0 + 1, i0 + 2)
			mb.add_tri_idx(i0 + 1, i0 + 3, i0 + 2)
	return mb.commit()


## Open cylinder (beacon / funnel), radius r0 at y=0 to r1 at y=1, uv.y = height.
static func open_cylinder(r0: float, r1: float, segments: int, rows: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for j in rows + 1:
		var v := float(j) / rows
		var r := lerpf(r0, r1, v)
		for s in segments + 1:
			var a := TAU * s / segments
			var d := Vector3(cos(a), 0, sin(a))
			mb.add_vertex(d * r + Vector3(0, v, 0), d, Color.WHITE, Vector2(float(s) / segments, v))
	for j in rows:
		for s in segments:
			var a := j * (segments + 1) + s
			var b := a + 1
			var c := a + segments + 1
			var d := c + 1
			mb.add_tri_idx(a, b, c)
			mb.add_tri_idx(b, d, c)
	return mb.commit()


## Rolling snow mass for avalanches: a lumpy, flattened dome.
static func snow_mass(variant: int) -> ArrayMesh:
	var rng := _rng(8000 + variant * 13)
	var mb := MeshBuilder.new()
	var top := Color(1, 1, 1)
	var bottom := Color(0.80, 0.86, 0.95)
	mb.add_blob(Vector3(0, 0.2, 0), Vector3(0.9, 0.55, 0.7), 2, 0.12, rng, top, bottom, -0.3)
	for k in 6:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 0.55, rng.randf_range(0.1, 0.45), sin(a) * 0.45 + 0.15)
		var r := rng.randf_range(0.25, 0.42)
		mb.add_blob(p, Vector3(r, r * 0.8, r), 1, 0.15, rng, top, bottom, -0.5)
	return mb.commit()
