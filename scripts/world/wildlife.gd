class_name Wildlife
extends Node3D
## Birds. Flocks of songbirds wheel over the meadows, the woods and the lake
## all summer; once the snow covers the ground beneath them they gather and
## fly off south over the sea. Gulls stay at the harbour whatever the weather.
## Purely decorative.

const FLOCKS := [
	{"anchor": Vector2(10, 60), "radius": 40.0, "height": 26.0, "count": 9, "kind": "songbird"},
	{"anchor": Vector2(-180, -40), "radius": 50.0, "height": 34.0, "count": 8, "kind": "songbird"},
	{"anchor": Vector2(-120, 240), "radius": 45.0, "height": 22.0, "count": 7, "kind": "songbird"},
	{"anchor": Vector2(190, -45), "radius": 60.0, "height": 20.0, "count": 8, "kind": "songbird"},
	{"anchor": Vector2(232, 262), "radius": 30.0, "height": 16.0, "count": 6, "kind": "gull"},
]

var terrain: TerrainData
var coverage: SnowCoverage
var flocks: Array = []        # {spec, center: Vector3, ang, state, birds: Array}
var _mat: StandardMaterial3D
var _t := 0.0
var _check := 0.0


func setup(t: TerrainData, cov: SnowCoverage) -> void:
	terrain = t
	coverage = cov
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = t.seed_value * 31 + 4
	for spec in FLOCKS:
		var f := {"spec": spec, "ang": rng.randf() * TAU, "state": "circle", "birds": [], "leave": Vector3.ZERO}
		var a: Vector2 = spec["anchor"]
		f["center"] = Vector3(a.x, terrain.sample_height(a.x, a.y) + float(spec["height"]), a.y)
		for k in int(spec["count"]):
			f["birds"].append(_bird(String(spec["kind"]), rng))
		flocks.append(f)


func _bird(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var gull := kind == "gull"
	var body_col: Color = Color(0.95, 0.95, 0.95) if gull else [Color(0.36, 0.26, 0.20), Color(0.24, 0.24, 0.28), Color(0.50, 0.36, 0.22)][rng.randi() % 3]
	var wing_col: Color = Color(0.62, 0.66, 0.70) if gull else body_col.darkened(0.15)
	var s := 1.8 if gull else 1.0
	var root := Node3D.new()
	add_child(root)
	var mb := MeshBuilder.new()
	mb.add_blob(Vector3.ZERO, Vector3(0.09, 0.08, 0.2) * s, 1, 0.0, rng, body_col, body_col.darkened(0.2), 0.0)
	mb.add_flat_tri(Vector3(0, 0.02, -0.18) * s, Vector3(-0.08, 0.02, -0.3) * s, Vector3(0.08, 0.02, -0.3) * s, body_col, body_col, body_col)
	var body := MeshInstance3D.new()
	body.mesh = mb.commit()
	body.material_override = _mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var wings: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		root.add_child(pivot)
		var wb := MeshBuilder.new()
		var tip := Vector3(side * 0.42, 0, -0.04) * s
		wb.add_flat_tri(Vector3(0, 0, 0.08) * s, tip, Vector3(0, 0, -0.1) * s, wing_col, wing_col, wing_col)
		var wi := MeshInstance3D.new()
		wi.mesh = wb.commit()
		wi.material_override = _mat
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(wi)
		wings.append(pivot)
	return {"root": root, "wings": wings, "off": Vector3(rng.randf_range(-6, 6), rng.randf_range(-2, 2), rng.randf_range(-6, 6)),
		"phase": rng.randf() * TAU, "rate": rng.randf_range(9.0, 12.0) * (0.6 if gull else 1.0), "glide": rng.randf()}


## True while the ground under a flock's home is mostly snowed over.
func _snowed(a: Vector2, r: float) -> bool:
	var frozen := 0
	for k in 9:
		var p := a + Vector2.from_angle(k * 2.4) * r * 0.6 * sqrt((k + 0.5) / 9.0)
		var i := coverage.cell_index(p.x, p.y)
		if coverage.cov[i] >= 1.0 and not coverage.is_void(i):
			frozen += 1
	return frozen >= 6


## Number of songbird flocks still on the island (for tests).
func flocks_home() -> int:
	var n := 0
	for f in flocks:
		if String(f["spec"]["kind"]) == "songbird" and f["state"] == "circle":
			n += 1
	return n


func _process(delta: float) -> void:
	if coverage == null:
		return
	_t += delta
	_check -= delta
	var check := _check <= 0.0
	if check:
		_check = 1.0
	for f in flocks:
		var spec: Dictionary = f["spec"]
		var a: Vector2 = spec["anchor"]
		var center: Vector3 = f["center"]
		var heading: Vector3
		if f["state"] == "circle":
			if check and spec["kind"] == "songbird" and _snowed(a, float(spec["radius"])):
				# Winter has come: off they go, south over the sea.
				f["state"] = "leaving"
				f["leave"] = Vector3(randf_range(-0.3, 0.3), 0.35, 1.0).normalized()
			f["ang"] = float(f["ang"]) + delta * 0.25
			var r: float = spec["radius"]
			var ang: float = f["ang"]
			var target := Vector3(a.x + cos(ang) * r, 0, a.y + sin(ang * 1.3) * r * 0.7)
			target.y = terrain.sample_height(target.x, target.z) + float(spec["height"]) + sin(_t * 0.4 + ang) * 4.0
			heading = target - center
			center = center.lerp(target, 1.0 - exp(-delta * 0.8))
		elif f["state"] == "leaving":
			heading = f["leave"]
			center += heading * delta * 14.0
			if center.distance_to(Vector3(a.x, center.y, a.y)) > 700.0:
				f["state"] = "gone"
		f["center"] = center
		var gone: bool = f["state"] == "gone"
		var flat := Vector2(heading.x, heading.z)
		var yaw := atan2(flat.x, flat.y) if flat.length() > 0.01 else 0.0
		for b in f["birds"]:
			var root: Node3D = b["root"]
			root.visible = not gone
			if gone:
				continue
			var ph: float = b["phase"]
			var off: Vector3 = b["off"]
			var sway := Vector3(sin(_t * 0.7 + ph) * 2.0, sin(_t * 1.1 + ph) * 1.0, cos(_t * 0.6 + ph) * 2.0)
			root.position = center + off + sway
			root.rotation = Vector3(0, yaw, sin(_t * 0.9 + ph) * 0.2)
			# Flap, then glide a little, like real small birds.
			var flapping: bool = fmod(_t * 0.5 + float(b["glide"]) * 2.0, 2.0) < 1.3 or f["state"] == "leaving"
			var w := sin(_t * float(b["rate"]) + ph) * 0.7 if flapping else 0.1
			(b["wings"][0] as Node3D).rotation.z = -w
			(b["wings"][1] as Node3D).rotation.z = w
