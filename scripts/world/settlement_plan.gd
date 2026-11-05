class_name SettlementPlan
extends RefCounted
## Seeded layout of the island's people. Pure data, built before the terrain
## is finalised so building pads can be levelled into the heights.
##
##   Hearthwick   market village in the central meadows: a square with a well,
##                church, tavern and stalls, a pond and a sledding hill.
##   Mere End     fishing hamlet on the lake shore, with a pier and boathouse.
##   Saltmouth    harbour town at the river mouth, its lighthouse out on the
##                headland across the bridge.
##   Brookfield   farm in the southern meadows, its windmill on the hill.
##   Fernhollow   woodcutters' camp in a forest clearing.
##   High Fold    a shepherd's hut where the mountain path ends.
##
## Besides buildings and props the plan lists "spots" - places villagers go
## to work, gather and, once winter has come, play - and the roads that join
## them all, which villagers use to get around.

const TOWNS := [
	{"name": "Hearthwick", "center": Vector2(60, 160), "radius": 95.0},
	{"name": "Mere End", "center": Vector2(94, -36), "radius": 45.0},
	{"name": "Saltmouth", "center": Vector2(216, 228), "radius": 70.0},
	{"name": "Brookfield", "center": Vector2(-122, 196), "radius": 85.0},
	{"name": "Fernhollow", "center": Vector2(-224, 32), "radius": 38.0},
	{"name": "High Fold", "center": Vector2(-156, -150), "radius": 24.0},
]
const HEARTHWICK := 0
const MERE_END := 1
const SALTMOUTH := 2
const BROOKFIELD := 3
const FERNHOLLOW := 4
const HIGH_FOLD := 5

const SQUARE := Vector2(60, 162)
const MAIN_STREET: Array[Vector2] = [Vector2(-22, 148), Vector2(18, 156), Vector2(60, 162), Vector2(102, 167), Vector2(142, 176)]
const CROSS_STREET: Array[Vector2] = [Vector2(56, 108), Vector2(58, 136), Vector2(60, 162), Vector2(62, 190), Vector2(56, 214)]
const HAMLET_LANE: Array[Vector2] = [Vector2(82, -22), Vector2(92, -38), Vector2(102, -52)]
const QUAY: Array[Vector2] = [Vector2(196, 214), Vector2(212, 228), Vector2(228, 240)]
const FARM_LANE: Array[Vector2] = [Vector2(-112, 190), Vector2(-140, 196), Vector2(-166, 204)]
const CAMP_LANE: Array[Vector2] = [Vector2(-210, 42), Vector2(-226, 34), Vector2(-242, 22)]
const ROADS := [
	[Vector2(-22, 148), Vector2(-60, 166), Vector2(-92, 182), Vector2(-112, 190)],
	[Vector2(-22, 148), Vector2(-70, 126), Vector2(-122, 98), Vector2(-172, 66), Vector2(-210, 42)],
	[Vector2(56, 108), Vector2(60, 70), Vector2(70, 24), Vector2(82, -22)],
	[Vector2(142, 176), Vector2(168, 194), Vector2(186, 206), Vector2(196, 214)],
	[Vector2(56, 214), Vector2(24, 234), Vector2(-10, 242)],
	[Vector2(82, -22), Vector2(66, -78), Vector2(32, -124), Vector2(-30, -148), Vector2(-100, -156), Vector2(-150, -150)],
	[Vector2(56, 108), Vector2(30, 104), Vector2(8, 102)],
]

var buildings: Array = []   # {pos, size: Vector3 (w, h, d), rot, kind, seed, town, home}
var fields: Array = []      # {center: Vector2, size: Vector2, rot, crop}
var fences: Array = []      # Array of [Vector2, Vector2] segments
var props: Array = []       # {pos: Vector2, kind, rot, town}
var roads: Array = []       # Array of PackedVector2Array
var routes: Array = []      # walkable polylines (every road)
var spots: Array = []       # {pos: Vector2, kind, town, radius?, to?}
var bridges: Array = []     # {a: Vector2, b: Vector2, width}
var clearings: Array = []   # [centre, radius] where no trees grow
var lighthouse := Vector2.INF

var _rng := RandomNumberGenerator.new()
var _terrain: TerrainData


func plan(seed_value: int, terrain: TerrainData = null) -> void:
	_rng.seed = seed_value * 977 + 5
	_terrain = terrain
	buildings.clear()
	fields.clear()
	fences.clear()
	props.clear()
	roads.clear()
	routes.clear()
	spots.clear()
	bridges.clear()
	clearings.clear()
	for r in ROADS:
		_road(r)
	for r in [MAIN_STREET, CROSS_STREET, HAMLET_LANE, QUAY, FARM_LANE, CAMP_LANE]:
		_road(r)
	_hearthwick()
	_mere_end()
	_saltmouth()
	_brookfield()
	_fernhollow()
	_high_fold()
	for t in TOWNS:
		clearings.append([t["center"], float(t["radius"]) * 0.55])


func _road(pts: Array) -> void:
	var line := PackedVector2Array()
	for p in pts:
		line.append(p)
	roads.append(line)
	routes.append(line)


func _road_angle(line: Array[Vector2], k: int) -> float:
	var a: Vector2 = line[maxi(k - 1, 0)]
	var b: Vector2 = line[mini(k, line.size() - 1)]
	var d := b - a
	return atan2(d.x, d.y)


func _coast(p: Vector2) -> float:
	return _terrain.coast_distance(p.x, p.y) if _terrain != null else 100.0


## Rotation that turns a building's front (local +z) to face `target`.
static func facing(from: Vector2, target: Vector2) -> float:
	var d := target - from
	return atan2(d.x, d.y)


func _add(pos: Vector2, size: Vector3, rot: float, kind: String, town: int, home: bool) -> Dictionary:
	var b := {"pos": pos, "size": size, "rot": rot, "kind": kind, "seed": _rng.randi(), "town": town, "home": home}
	buildings.append(b)
	return b


func _prop(pos: Vector2, kind: String, rot: float, town: int) -> void:
	props.append({"pos": pos, "kind": kind, "rot": rot, "town": town})


func _spot(pos: Vector2, kind: String, town: int, extra: Dictionary = {}) -> void:
	var s := {"pos": pos, "kind": kind, "town": town}
	s.merge(extra)
	spots.append(s)


## Houses on alternating sides of a street, facing it. Stretches closer than
## `keep_clear` to any of `avoid` stay open (squares, junctions).
func _street_houses(line: Array[Vector2], count: int, spacing: float, town: int, avoid: Array = [], keep_clear := 0.0,
		start := 6.0) -> void:
	var dense := PackedVector2Array()
	for k in range(line.size() - 1):
		var a: Vector2 = line[k]
		var b: Vector2 = line[k + 1]
		var n := int(a.distance_to(b))
		for s in n:
			dense.append(a.lerp(b, float(s) / n))
	var placed := 0
	var t := start
	var side := 1.0
	while placed < count and t < dense.size() - 4:
		var i := int(t)
		var p := dense[i]
		var blocked := false
		for q in avoid:
			if p.distance_to(q) < keep_clear:
				blocked = true
		if blocked:
			t += 3.0
			continue
		var dir := (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x) * side
		var kind := "house" if _rng.randf() < 0.6 else "cottage"
		var w := _rng.randf_range(5.5, 7.5) if kind == "house" else _rng.randf_range(6.5, 8.0)
		var d := _rng.randf_range(6.0, 8.0) if kind == "house" else _rng.randf_range(5.0, 6.0)
		var h := _rng.randf_range(3.8, 5.0) if kind == "house" else _rng.randf_range(2.7, 3.2)
		var pos := p + nrm * (d * 0.5 + 4.8)
		# Front of the house (local +z) faces the street.
		var rot := atan2(-nrm.x, -nrm.y)
		if _crowded(pos, Vector2(w, d).length() * 0.5 + 2.5):
			t += 3.0
			continue
		var b := _add(pos, Vector3(w, h, d), rot, kind, town, true)
		# Some homes keep a little garden with a picket fence behind them.
		if _rng.randf() < 0.45:
			_garden(b)
		placed += 1
		side = -side
		t += spacing * (0.5 if side < 0.0 else 1.0)


## True when a building of radius `r` at `p` would touch another building or
## sit on a road.
func _crowded(p: Vector2, r: float) -> bool:
	for o in buildings:
		var s: Vector3 = o["size"]
		if p.distance_to(o["pos"]) < r + Vector2(s.x, s.z).length() * 0.5:
			return true
	for road in roads:
		var line: PackedVector2Array = road
		for k in range(line.size() - 1):
			var a := line[k]
			var ab := line[k + 1] - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if p.distance_to(a + ab * t) < r - 1.0:
				return true
	return false


func _garden(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var s: Vector3 = b["size"]
	var rot: float = b["rot"]
	var tr := Transform2D(-rot, pos)
	var hw := s.x * 0.5 + 1.2
	var back := -s.z * 0.5 - 0.6
	var deep := back - _rng.randf_range(4.0, 6.0)
	var c := [Vector2(-hw, back), Vector2(-hw, deep), Vector2(hw, deep), Vector2(hw, back)]
	for k in 3:
		fences.append([tr * (c[k] as Vector2), tr * (c[k + 1] as Vector2)])
	_prop(tr * Vector2(_rng.randf_range(-hw * 0.5, hw * 0.5), (back + deep) * 0.5), "laundry" if _rng.randf() < 0.5 else "veg_patch",
		rot, int(b["town"]))


# ------------------------------------------------------------------ towns
func _hearthwick() -> void:
	var t := HEARTHWICK
	_street_houses(MAIN_STREET, 12, 12.0, t, [SQUARE, MAIN_STREET[0]], 18.0)
	_street_houses(CROSS_STREET, 7, 13.0, t, [SQUARE, CROSS_STREET[0]], 18.0, 4.0)
	# The square: church to the north-east, tavern to the south-west.
	var church := Vector2(80, 140)
	_add(church, Vector3(7.5, 7.5, 13.0), facing(church, SQUARE), "church", t, false)
	var tavern := Vector2(40, 180)
	_add(tavern, Vector3(9.0, 5.2, 11.0), facing(tavern, SQUARE), "tavern", t, true)
	_prop(SQUARE + Vector2(6, -8), "well", 0.0, t)
	_prop(SQUARE + Vector2(-12, -9), "stall", 0.3, t)
	_prop(SQUARE + Vector2(14, 8), "stall", -2.6, t)
	_prop(SQUARE + Vector2(-9, 9), "stall", 2.9, t)
	_prop(SQUARE + Vector2(-4, -12), "bench", 0.2, t)
	_prop(SQUARE + Vector2(12, -4), "bench", -1.5, t)
	_prop(SQUARE + Vector2(-14, 2), "cart", 1.2, t)
	_prop(SQUARE + Vector2(1, 14), "tree_planter", 0.0, t)
	for line in [MAIN_STREET, CROSS_STREET]:
		_lamps(line, 22.0, t)
	_prop(Vector2(-18, 152), "signpost", 0.9, t)
	# The pond, with a bench and reeds.
	var pond := TerrainData.POND_CENTER
	_prop(pond + Vector2(-13, 6), "bench", 2.0, t)
	_prop(pond + Vector2(9, 10), "reeds", 0.0, t)
	_prop(pond + Vector2(-6, -11), "reeds", 1.0, t)
	_road([CROSS_STREET[1], Vector2(80, 124), pond + Vector2(-13, 2)])
	_spot(SQUARE, "square", t, {"radius": 13.0})
	_spot(SQUARE + Vector2(6, -6), "well", t)
	_spot(SQUARE + Vector2(-12, -7), "stall", t)
	_spot(SQUARE + Vector2(14, 6), "stall", t)
	_spot(SQUARE + Vector2(-4, -10), "bench", t)
	_spot(tavern + Vector2(0, 8.5).rotated(-facing(tavern, SQUARE)), "tavern", t)
	_spot(church + Vector2(0, 9).rotated(-facing(church, SQUARE)), "church", t)
	_spot(pond, "pond", t, {"radius": TerrainData.POND_RADIUS - 2.5})
	_spot(pond + Vector2(-13, 3), "bench", t)
	# Snowball fights on the green between the pond and the main street.
	_spot(Vector2(96, 146), "green", t, {"radius": 11.0})
	_spot(Vector2(22, 128), "green", t, {"radius": 11.0})
	# The sledding hill rises south-east of the village.
	var top: Vector2 = TerrainData.HILLS[0][0]
	_spot(top, "sled_top", t, {"to": top + Vector2(-26, -20)})
	_road([MAIN_STREET[4], Vector2(140, 196), top + Vector2(-4, -2)])
	# Meadow flowers and a picnic bench out by the windmill track.
	_prop(Vector2(30, 228), "bench", 1.0, t)


func _lamps(line: Array[Vector2], every: float, town: int) -> void:
	var acc := every * 0.5
	for k in range(line.size() - 1):
		var a: Vector2 = line[k]
		var b: Vector2 = line[k + 1]
		var seg := a.distance_to(b)
		var dir := (b - a) / seg
		var d := acc
		while d < seg:
			var p := a + dir * d + Vector2(-dir.y, dir.x) * 2.8
			if p.distance_to(SQUARE) > 10.0:
				_prop(p, "lamp", 0.0, town)
			d += every
		acc = d - seg


func _mere_end() -> void:
	var t := MERE_END
	_street_houses(HAMLET_LANE, 3, 11.0, t, [], 0.0, 4.0)
	_add(Vector2(70, -40), Vector3(6.0, 4.5, 7.0), 1.1, "house", t, true)
	var shore := Vector2(112, -52)
	_add(shore + Vector2(-4, 8), Vector3(6.0, 3.6, 9.0), facing(shore + Vector2(-4, 8), TerrainData.LAKE_CENTER), "boathouse", t, false)
	var pier_dir := (TerrainData.LAKE_CENTER - shore).normalized()
	var pier_rot := atan2(pier_dir.x, pier_dir.y)
	_prop(shore, "pier", pier_rot, t)
	_prop(shore + pier_dir * 6.0 + Vector2(-pier_dir.y, pier_dir.x) * 3.6, "boat", pier_rot + 0.2, t)
	_prop(shore + pier_dir * 11.0 - Vector2(-pier_dir.y, pier_dir.x) * 3.6, "boat", pier_rot - 0.15, t)
	_prop(shore + Vector2(-10, -4), "nets", 0.4, t)
	_prop(shore + Vector2(-8, 3), "barrels", 0.0, t)
	_spot(shore + pier_dir * 13.0, "pier_end", t, {"look": pier_dir})
	_spot(shore + Vector2(-9, -2), "chat", t)
	# Out on the lake beyond the pier is where the skaters will go.
	_spot(shore + pier_dir * 30.0, "rink", t, {"radius": 13.0, "water": true})
	_spot(Vector2(84, -54), "green", t, {"radius": 8.0})


func _saltmouth() -> void:
	var t := SALTMOUTH
	_street_houses(QUAY, 5, 10.0, t, [], 0.0, 3.0)
	var inn := Vector2(184, 228)
	_add(inn, Vector3(9.0, 5.0, 10.0), facing(inn, QUAY[0]), "tavern", t, true)
	_add(Vector2(204, 196), Vector3(6.0, 4.2, 7.0), facing(Vector2(204, 196), QUAY[1]), "house", t, true)
	_add(Vector2(176, 210), Vector3(6.5, 3.0, 5.5), facing(Vector2(176, 210), QUAY[0]), "cottage", t, true)
	# The harbour pier runs out into the sea from the end of the quay.
	var dir := Vector2(0.6, 0.8).normalized()
	var start := QUAY[2] + dir * 4.0
	for k in 60:
		if _coast(start) < 1.5:
			break
		start += dir * 1.0
	var rot := atan2(dir.x, dir.y)
	_prop(start, "harbor_pier", rot, t)
	_road([QUAY[2], start])
	var side := Vector2(-dir.y, dir.x)
	_prop(start + dir * 9.0 + side * 4.2, "boat", rot + 0.3, t)
	_prop(start + dir * 17.0 - side * 4.2, "boat", rot - 0.2, t)
	_prop(start + dir * 24.0 + side * 4.6, "boat", rot + 0.1, t)
	_prop(QUAY[1] + Vector2(6, 6), "crates", 0.5, t)
	_prop(QUAY[2] + Vector2(-5, 7), "barrels", 0.0, t)
	_prop(QUAY[2] + Vector2(4, 3), "nets", -0.4, t)
	_add(start + Vector2(-10, -2), Vector3(6.0, 3.4, 8.0), rot, "boathouse", t, false)
	_spot(start + dir * 20.0, "pier_end", t, {"look": dir})
	_spot(QUAY[1] + Vector2(3, 4), "chat", t)
	_spot(inn + Vector2(8, 0), "tavern", t)
	_spot(Vector2(178, 194), "green", t, {"radius": 9.0})
	_lamps(QUAY, 14.0, t)
	# Lighthouse on the headland, reached over a bridge across the river.
	var cdir := Vector2.from_angle(TerrainData.CAPE_ANGLE)
	var p := cdir * 240.0
	for k in 160:
		if _coast(p + cdir) < 11.0:
			break
		p += cdir
	lighthouse = p
	_add(p, Vector3(5.2, 15.0, 5.2), 0.0, "lighthouse", t, false)
	var keeper := p - cdir * 14.0 + Vector2(-cdir.y, cdir.x) * 6.0
	_add(keeper, Vector3(6.0, 3.0, 5.0), facing(keeper, p), "cottage", t, true)
	var mid := Vector2(255, 214)
	_road([QUAY[2], Vector2(240, 230), mid, keeper.lerp(p, 0.4)])
	# Where that road meets the river, a little bridge carries it across.
	bridges.append({"a": Vector2(234, 233), "b": Vector2(262, 210), "width": 3.2})
	_spot(p - cdir * 6.0, "lookout", t, {"look": cdir})


func _brookfield() -> void:
	var t := BROOKFIELD
	_add(Vector2(-112, 178), Vector3(7.0, 4.6, 8.0), 0.3, "house", t, true)
	_add(Vector2(-136, 176), Vector3(10.0, 7.0, 14.0), 0.25, "barn", t, false)
	_add(Vector2(-100, 200), Vector3(4.0, 3.0, 4.5), -0.2, "shed", t, false)
	_add(Vector2(-160, 214), Vector3(6.5, 3.0, 5.5), -0.1, "cottage", t, true)
	_prop(Vector2(-124, 190), "cart", 0.7, t)
	_prop(Vector2(-118, 168), "woodpile", 0.3, t)
	_prop(Vector2(-106, 186), "laundry", 0.3, t)
	var crops := ["wheat", "corn", "greens", "wheat", "sprouts", "pasture"]
	var origin := Vector2(-200, 228)
	var k := 0
	for j in 2:
		for i in 3:
			var size := Vector2(_rng.randf_range(24.0, 30.0), _rng.randf_range(20.0, 26.0))
			var c := origin + Vector2(i * 32.0, j * 28.0) + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))
			fields.append({"center": c, "size": size, "rot": 0.12, "crop": crops[k % crops.size()]})
			if crops[k % crops.size()] != "pasture":
				_spot(c, "field", t, {"radius": 9.0})
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
		_prop(p, "hay", _rng.randf() * TAU, t)
	_prop(origin + Vector2(30, 14), "scarecrow", 0.4, t)
	_road([FARM_LANE[1], origin + Vector2(30, -18)])
	# The windmill on its hill, with a sack cart at the door.
	var mill: Vector2 = TerrainData.HILLS[1][0]
	_add(mill, Vector3(6.0, 10.0, 6.0), facing(mill, Vector2(24, 234)), "windmill", t, false)
	_prop(mill + Vector2(5, 5), "sacks", 0.4, t)
	_spot(Vector2(-112, 190), "chat", t)
	_spot(Vector2(-150, 196), "green", t, {"radius": 9.0})


func _fernhollow() -> void:
	var t := FERNHOLLOW
	_add(Vector2(-214, 26), Vector3(5.0, 2.8, 6.0), facing(Vector2(-214, 26), CAMP_LANE[1]), "hut", t, true)
	_add(Vector2(-234, 46), Vector3(5.0, 2.8, 6.0), facing(Vector2(-234, 46), CAMP_LANE[1]), "hut", t, true)
	_add(Vector2(-246, 30), Vector3(4.5, 2.6, 5.5), facing(Vector2(-246, 30), CAMP_LANE[2]), "hut", t, true)
	var mill := Vector2(-228, 12)
	_add(mill, Vector3(8.0, 4.0, 12.0), facing(mill, CAMP_LANE[1]), "sawmill", t, false)
	_prop(Vector2(-218, 8), "logs", 0.4, t)
	_prop(Vector2(-240, 6), "logs", -0.3, t)
	_prop(Vector2(-222, 40), "woodpile", 1.2, t)
	_prop(Vector2(-230, 30), "campfire", 0.0, t)
	_spot(Vector2(-218, 10), "chop", t)
	_spot(Vector2(-230, 30), "campfire", t, {"radius": 3.0})
	_spot(Vector2(-210, 54), "green", t, {"radius": 8.0})


func _high_fold() -> void:
	var t := HIGH_FOLD
	var hut := Vector2(-160, -146)
	_add(hut, Vector3(5.0, 2.8, 6.0), facing(hut, Vector2(-150, -150)), "hut", t, true)
	var pen := Vector2(-146, -164)
	var c := [pen + Vector2(-8, -6), pen + Vector2(8, -6), pen + Vector2(8, 6), pen + Vector2(-8, 6)]
	for k in 4:
		fences.append([c[k], c[(k + 1) % 4]])
	_prop(hut + Vector2(5, 2), "woodpile", 0.2, t)
	_spot(hut + Vector2(3, 6), "chat", t)


## Roof rise used by the builder, so the cloud can clear rooftops.
static func roof_rise(b: Dictionary) -> float:
	var hw: float = (b["size"] as Vector3).x * 0.5
	match String(b["kind"]):
		"church":
			return hw * 1.1
		"barn":
			return hw * 0.85
		"shed", "sawmill":
			return 1.0
		"cottage", "hut":
			return hw * 0.6
		"windmill":
			return 4.0
		"lighthouse":
			return 4.5
	return hw * 0.7


## Footprints with absolute top heights: [centre, half-size, rot, top].
func obstacles(ground: Callable) -> Array:
	var out: Array = []
	for b in buildings:
		var pos: Vector2 = b["pos"]
		var s: Vector3 = b["size"]
		var base: float = ground.call(pos) - 0.15
		var top: float = base + 0.65 + s.y + roof_rise(b) + 1.0
		var half := Vector2(s.x * 0.5 + 0.6, s.z * 0.5 + 0.6)
		if b["kind"] == "windmill":
			# The sails sweep a wide disc in front of the tower.
			half = Vector2(8.6, 4.0)
			top += 5.0
		out.append([pos, half, float(b["rot"]), top])
		if b["kind"] == "church":
			var tower: Vector2 = pos + Vector2(0, s.z * 0.5 + 1.6).rotated(-float(b["rot"]))
			out.append([tower, Vector2(2.4, 2.4), float(b["rot"]), base + 0.65 + s.y + 12.5])
	return out


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


## Which town a point belongs to (-1 when out in the country).
static func town_at(p: Vector2) -> int:
	for k in TOWNS.size():
		if p.distance_to(TOWNS[k]["center"]) < float(TOWNS[k]["radius"]):
			return k
	return -1


## The deck height of a bridge under `p`, or -INF when there is none.
func bridge_height(p: Vector2, water: float) -> float:
	for br in bridges:
		var a: Vector2 = br["a"]
		var b: Vector2 = br["b"]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) <= float(br["width"]) * 0.5 + 0.3:
			# A gentle arch, a little above the water at its middle.
			return water + 1.1 + 0.6 * sin(t * PI)
	return -INF
