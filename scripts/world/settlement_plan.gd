class_name SettlementPlan
extends RefCounted
## Seeded layout of the island's people: a village street, a lakeside hamlet
## and a farm with fields, joined by roads. Pure data, built before the
## terrain is finalised so building pads can be levelled into the heights.

# Roads are polylines of Vector2 (x, z); villagers walk along them.
const VILLAGE_STREET: Array[Vector2] = [Vector2(30, 124), Vector2(52, 136), Vector2(76, 146), Vector2(100, 152)]
const HAMLET_LANE: Array[Vector2] = [Vector2(70, 38), Vector2(84, 30), Vector2(96, 22)]
const FARM_LANE: Array[Vector2] = [Vector2(-74, 78), Vector2(-100, 92), Vector2(-128, 100)]
const ROADS := [
	[Vector2(0, 66), Vector2(14, 92), Vector2(30, 124)],
	[Vector2(0, 66), Vector2(30, 54), Vector2(56, 42), Vector2(70, 38)],
	[Vector2(0, 66), Vector2(-30, 64), Vector2(-56, 70), Vector2(-74, 78)],
	[Vector2(0, 66), Vector2(6, 24), Vector2(14, -30), Vector2(26, -76)],
]

var buildings: Array = []   # {pos: Vector2, size: Vector3 (w, h, d), rot, kind, seed}
var fields: Array = []      # {center: Vector2, size: Vector2, rot, crop}
var fences: Array = []      # Array of [Vector2, Vector2] segments
var props: Array = []       # {pos: Vector2, kind, rot}
var roads: Array = []       # Array of PackedVector2Array
var routes: Array = []      # walkable polylines for villagers (subset of roads)

var _rng := RandomNumberGenerator.new()


func plan(seed_value: int) -> void:
	_rng.seed = seed_value * 977 + 5
	buildings.clear()
	fields.clear()
	fences.clear()
	props.clear()
	roads.clear()
	routes.clear()
	for r in ROADS:
		roads.append(PackedVector2Array(r))
	roads.append(PackedVector2Array(VILLAGE_STREET))
	roads.append(PackedVector2Array(HAMLET_LANE))
	roads.append(PackedVector2Array(FARM_LANE))
	routes = [PackedVector2Array(VILLAGE_STREET), PackedVector2Array(HAMLET_LANE), PackedVector2Array(FARM_LANE),
		PackedVector2Array(ROADS[0]), PackedVector2Array(ROADS[1]), PackedVector2Array(ROADS[2])]
	_street_houses(VILLAGE_STREET, 9, 13.0)
	# The village church closes the end of the street.
	buildings.append({"pos": Vector2(112, 160), "size": Vector3(7.0, 7.5, 12.0), "rot": _road_angle(VILLAGE_STREET, 3), "kind": "church", "seed": 1})
	props.append({"pos": Vector2(64, 146), "kind": "well", "rot": 0.0})
	_street_houses(HAMLET_LANE, 2, 11.0)
	buildings.append({"pos": Vector2(64, 28), "size": Vector3(6.0, 4.5, 7.0), "rot": 0.6, "kind": "house", "seed": 77})
	props.append({"pos": Vector2(102, 18), "kind": "pier", "rot": -0.35})
	_farm()


func _road_angle(line: Array[Vector2], k: int) -> float:
	var a: Vector2 = line[maxi(k - 1, 0)]
	var b: Vector2 = line[mini(k, line.size() - 1)]
	var d := b - a
	return atan2(d.x, d.y)


## Houses on alternating sides of a street, facing it.
func _street_houses(line: Array[Vector2], count: int, spacing: float) -> void:
	var dense := PackedVector2Array()
	for k in range(line.size() - 1):
		var a: Vector2 = line[k]
		var b: Vector2 = line[k + 1]
		var n := int(a.distance_to(b))
		for s in n:
			dense.append(a.lerp(b, float(s) / n))
	var placed := 0
	var t := 6.0
	var side := 1.0
	while placed < count and t < dense.size() - 4:
		var i := int(t)
		var p := dense[i]
		var dir := (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x) * side
		var w := _rng.randf_range(5.5, 7.5)
		var d := _rng.randf_range(6.0, 8.0)
		var pos := p + nrm * (d * 0.5 + 4.5)
		# Front of the house (local +z) faces the street.
		var rot := atan2(-nrm.x, -nrm.y)
		buildings.append({"pos": pos, "size": Vector3(w, _rng.randf_range(3.6, 4.8), d), "rot": rot,
			"kind": "house", "seed": _rng.randi()})
		placed += 1
		side = -side
		t += spacing * (0.5 if side < 0.0 else 1.0)


func _farm() -> void:
	# Farmhouse and barn by the lane, a shed, then a patchwork of fields.
	buildings.append({"pos": Vector2(-96, 80), "size": Vector3(7.0, 4.6, 8.0), "rot": 0.3, "kind": "house", "seed": 401})
	buildings.append({"pos": Vector2(-114, 82), "size": Vector3(10.0, 7.0, 14.0), "rot": 0.25, "kind": "barn", "seed": 402})
	buildings.append({"pos": Vector2(-84, 102), "size": Vector3(4.0, 3.0, 4.5), "rot": -0.2, "kind": "shed", "seed": 403})
	var crops := ["wheat", "furrow", "greens", "wheat", "furrow", "pasture"]
	var origin := Vector2(-150, 112)
	var k := 0
	for j in 2:
		for i in 3:
			var size := Vector2(_rng.randf_range(24.0, 30.0), _rng.randf_range(20.0, 26.0))
			var c := origin + Vector2(i * 32.0, j * 28.0) + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))
			fields.append({"center": c, "size": size, "rot": 0.12, "crop": crops[k % crops.size()]})
			k += 1
	# Fence around the whole patchwork.
	var lo := origin + Vector2(-18, -16)
	var hi := origin + Vector2(64 + 18, 28 + 16)
	var basis := Transform2D(0.12, origin)
	var corners := [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]
	for c in 4:
		var a: Vector2 = corners[c] - origin
		var b: Vector2 = corners[(c + 1) % 4] - origin
		fences.append([basis * a, basis * b])
	for h in 7:
		var p := origin + Vector2(_rng.randf_range(-10, 70), _rng.randf_range(-8, 36))
		props.append({"pos": p, "kind": "hay", "rot": _rng.randf() * TAU})
	props.append({"pos": origin + Vector2(30, 14), "kind": "scarecrow", "rot": 0.4})


## Rectangle test against a building footprint (with margin).
func building_at(p: Vector2, margin: float) -> bool:
	for b in buildings:
		var local: Vector2 = (p - b["pos"]).rotated(b["rot"])
		var s: Vector3 = b["size"]
		if absf(local.x) <= s.x * 0.5 + margin and absf(local.y) <= s.z * 0.5 + margin:
			return true
	return false


func field_at(p: Vector2, margin: float = 0.0) -> Dictionary:
	for f in fields:
		var local: Vector2 = (p - f["center"]).rotated(f["rot"])
		var s: Vector2 = f["size"]
		if absf(local.x) <= s.x * 0.5 + margin and absf(local.y) <= s.y * 0.5 + margin:
			return f
	return {}
