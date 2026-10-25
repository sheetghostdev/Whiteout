class_name TerrainData
extends RefCounted
## Seeded, deterministic description of the world's shape: an island in a
## wide sea, with mountains in the north, a lake and woods, and the roads,
## village, hamlet and farm of the people who live there.
##
## Heights live on a (N+1)x(N+1) vertex grid with 1 m spacing that spans
## [-256, 256] on X and Z. Coverage cells are the N x N squares between
## vertices, so terrain, collision, coverage and shaders all share one
## coordinate system.

const N := GameBalance.WORLD_SIZE
const V := N + 1
const HALF := GameBalance.WORLD_HALF
const SEA_LEVEL := 0.0
const LAKE_LEVEL := 5.0
const LAKE_CENTER := Vector2(135.0, -5.0)
const MOUTH_END := -6.0                  # coast distance where the river gives way to the sea
const LAKE_REACH := 64.0                 # lake_distance where the basin rim stands
const SPAWN := Vector2(3.0, 84.0)
const TRAILHEAD := Vector2(0.0, 66.0)

const REGION_MEADOWS := 0
const REGION_WOODLAND := 1
const REGION_LAKE := 2
const REGION_HIGHLANDS := 3

var seed_value: int = 1337
var heights := PackedFloat32Array()      # V*V vertex heights
var water_level := PackedFloat32Array()  # V*V, -1000 where no water body
var river_dist := PackedFloat32Array()   # V*V distance to nearest river centre
var path_dist := PackedFloat32Array()    # V*V distance to nearest footpath
var cell_region := PackedByteArray()     # N*N
var cell_water := PackedByteArray()      # N*N, 1 = inland water surface cell
var cell_ocean := PackedByteArray()      # N*N, 1 = open sea (not part of the playable land)
var flow := PackedVector2Array()         # V*V river flow direction * speed (zero on still water)
var coast := PackedFloat32Array()        # V*V distance inland from the coast (negative at sea)
var cell_built := PackedByteArray()      # N*N, 1 = building or yard, 2 = farm field
var cell_roof := PackedFloat32Array()    # N*N, absolute height of rooftops (-1000 where open)
var settlements := SettlementPlan.new()
var rivers: Array = []                   # Array of {"points": PackedVector3Array (x, water_y, z), "widths": PackedFloat32Array}
var min_height := 0.0
var max_height := 0.0

var _n_broad := FastNoiseLite.new()
var _n_roll := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_warp := FastNoiseLite.new()
var _n_region := FastNoiseLite.new()


func _setup_noise() -> void:
	var s := seed_value
	_n_broad.seed = s
	_n_broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_broad.frequency = 0.0045
	_n_broad.fractal_octaves = 3
	_n_roll.seed = s + 11
	_n_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_roll.frequency = 0.014
	_n_roll.fractal_octaves = 3
	_n_detail.seed = s + 23
	_n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_detail.frequency = 0.06
	_n_detail.fractal_octaves = 2
	_n_ridge.seed = s + 37
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.frequency = 0.0075
	_n_ridge.fractal_octaves = 5
	_n_ridge.fractal_gain = 0.45
	_n_warp.seed = s + 51
	_n_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_warp.frequency = 0.006
	_n_warp.fractal_octaves = 2
	_n_region.seed = s + 67
	_n_region.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_region.frequency = 0.012
	_n_region.fractal_octaves = 2


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func highland_mask(x: float, z: float) -> float:
	var r := _n_roll.get_noise_2d(x, z)
	return _smooth(-70.0, -185.0, z + r * 16.0 + _n_warp.get_noise_2d(x * 0.7, 40.0) * 22.0)


## Distance inland from the coast (negative out at sea). The island is a
## rounded square, warped by noise into bays and headlands.
func coast_distance(x: float, z: float) -> float:
	var wx := x + _n_warp.get_noise_2d(x * 1.3 + 900.0, z * 1.3) * 16.0
	var wz := z + _n_warp.get_noise_2d(x * 1.3, z * 1.3 - 700.0) * 16.0
	var r := pow(pow(absf(wx), 4.0) + pow(absf(wz), 4.0), 0.25)
	var reach := 212.0 + _n_broad.get_noise_2d(x * 0.7 + 400.0, z * 0.7) * 12.0 + _n_detail.get_noise_2d(x * 0.3, z * 0.3) * 3.0
	return reach - r


func lake_distance(x: float, z: float) -> float:
	var dx := (x - LAKE_CENTER.x)
	var dz := (z - LAKE_CENTER.y) / 0.82
	return sqrt(dx * dx + dz * dz) + _n_warp.get_noise_2d(x * 2.0 + 300.0, z * 2.0) * 12.0


func _raw_height(x: float, z: float, cd: float) -> float:
	var wx := x + _n_warp.get_noise_2d(x, z) * 18.0
	var wz := z + _n_warp.get_noise_2d(x + 517.0, z - 291.0) * 18.0
	var broad := _n_broad.get_noise_2d(wx, wz)
	var roll := _n_roll.get_noise_2d(wx, wz)
	var detail := _n_detail.get_noise_2d(x, z)
	var h := 10.0 + broad * 4.5 + roll * 2.0 + detail * 0.3

	# Woodland: hillier, undulating forest floor in the west.
	var wood := _smooth(-40.0, -140.0, wx)
	h += wood * (roll * 3.2 + 2.5 + maxf(0.0, broad) * 6.0)

	# Highlands: ridged mountains rising toward the north edge.
	var hl := highland_mask(x, z)
	if hl > 0.0:
		var ridge := clampf(_n_ridge.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
		var mount := 10.0 + pow(ridge, 1.7) * 62.0 + broad * 10.0 + roll * 4.0
		mount += _smooth(-120.0, -175.0, wz) * 24.0
		# Mountains run down to the sea rather than off the edge of the world.
		mount *= _smooth(0.0, 50.0, cd)
		h += pow(hl, 1.25) * mount

	# Observation hills.
	h += 15.0 * exp(-((x + 48.0) * (x + 48.0) + (z - 128.0) * (z - 128.0)) / (2.0 * 26.0 * 26.0))
	h += 9.0 * exp(-((x - 92.0) * (x - 92.0) + (z - 92.0) * (z - 92.0)) / (2.0 * 20.0 * 20.0))
	h += 7.0 * exp(-((x + 150.0) * (x + 150.0) + (z + 60.0) * (z + 60.0)) / (2.0 * 24.0 * 24.0))

	# Keep low ground from dipping into accidental puddles outside the lake.
	if h < 7.0:
		h = 7.0 - (7.0 - h) * 0.3

	# Lake basin.
	var ld := lake_distance(x, z)
	var basin := _smooth(80.0, 38.0, ld)
	if basin > 0.0:
		var floor_h := maxf(LAKE_LEVEL - 1.2 - 5.5 * _smooth(52.0, 5.0, ld), 0.6)
		h = lerpf(h, minf(h, floor_h), basin)

	# Flatten the starting meadow a little so the first minutes are comfortable.
	var sd := Vector2(x, z).distance_to(SPAWN)
	var flat := _smooth(40.0, 10.0, sd)
	h = lerpf(h, 10.5 + detail * 0.25 + roll * 0.6, flat * 0.7)

	# Coast: land eases down to sandy beaches, then shelves away under the sea.
	if cd > 0.0:
		var beach := 0.9 + detail * 0.3 + maxf(roll, 0.0) * 0.5
		h = lerpf(beach, h, _smooth(1.0, lerpf(28.0, 12.0, hl), cd))
	else:
		h = lerpf(0.5, -12.0, _smooth(0.0, -34.0, cd))
	return h


func generate(p_seed: int) -> void:
	seed_value = p_seed
	_setup_noise()
	heights.resize(V * V)
	water_level.resize(V * V)
	river_dist.resize(V * V)
	path_dist.resize(V * V)
	water_level.fill(-1000.0)
	river_dist.fill(1.0e6)
	path_dist.fill(1.0e6)
	flow.resize(V * V)
	flow.fill(Vector2.ZERO)
	coast.resize(V * V)
	for j in V:
		var z := -HALF + j
		var row := j * V
		for i in V:
			var cd := coast_distance(-HALF + i, z)
			coast[row + i] = cd
			heights[row + i] = _raw_height(-HALF + i, z, cd)
	settlements.plan(p_seed)
	_level_settlements()
	_build_rivers()
	_build_paths()
	_build_lake_water()
	_build_sea()
	_classify_cells()
	_mark_roofs()
	min_height = 1.0e9
	max_height = -1.0e9
	for h in heights:
		min_height = minf(min_height, h)
		max_height = maxf(max_height, h)


# ------------------------------------------------------------------ rivers
func _catmull(points: Array, samples_per_seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(points.size() - 1):
		var p0: Vector2 = points[maxi(k - 1, 0)]
		var p1: Vector2 = points[k]
		var p2: Vector2 = points[k + 1]
		var p3: Vector2 = points[mini(k + 2, points.size() - 1)]
		for s in samples_per_seg:
			var t := float(s) / samples_per_seg
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[points.size() - 1])
	return out


func _resample(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(line[0])
	var carry := 0.0
	for k in range(1, line.size()):
		var a := line[k - 1]
		var b := line[k]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += step
		carry = seg - (d - step)
	return out


func _build_rivers() -> void:
	# A mountain stream flows from a tarn down to the lake; the lake drains
	# to the sea through a wider river in the south-east.
	var defs := [
		{"pts": [Vector2(-34, -150), Vector2(-10, -140), Vector2(18, -126), Vector2(50, -112), Vector2(74, -86),
			Vector2(96, -64), Vector2(114, -42), Vector2(126, -24)], "w0": 2.6, "w1": 5.0, "start": -1.0, "end": LAKE_LEVEL, "tarn": true},
		{"pts": [Vector2(158, 30), Vector2(172, 72), Vector2(164, 112), Vector2(150, 146),
			Vector2(158, 172), Vector2(172, 192), Vector2(188, 212)], "w0": 5.5, "w1": 6.5, "start": LAKE_LEVEL, "end": SEA_LEVEL},
	]
	rivers.clear()
	for d in defs:
		var line := _resample(_catmull(d["pts"], 14), 2.0)
		var n := line.size()
		var wl := PackedFloat32Array()
		wl.resize(n)
		var widths := PackedFloat32Array()
		widths.resize(n)
		# Outlet river: stays level with the lake until it has left the basin,
		# then eases down to reach sea level just before the coast.
		var s0 := 0.0
		var s1 := 1.0
		if d["start"] >= 0.0:
			var acc := 0.0
			var left_lake := -1.0
			var at_coast := -1.0
			for k in n:
				if k > 0:
					acc += line[k].distance_to(line[k - 1])
				if left_lake < 0.0 and lake_distance(line[k].x, line[k].y) > LAKE_REACH + 2.0:
					left_lake = acc
				if at_coast < 0.0 and coast_distance(line[k].x, line[k].y) < 12.0:
					at_coast = acc
			s0 = maxf(left_lake, 0.0)
			s1 = at_coast if at_coast > s0 else acc
		var along := 0.0
		var prev := 1.0e9
		for k in n:
			if k > 0:
				along += line[k].distance_to(line[k - 1])
			var raw := sample_height(line[k].x, line[k].y)
			var t := float(k) / (n - 1)
			var w: float
			if d["start"] < 0.0:
				# Mountain stream: follow the land downhill, never rising.
				w = minf(prev - 0.02, raw - 1.1)
			else:
				# Raised banks (see _carve_river) hold it where the land is low.
				var f := _smooth(s0, s1, along)
				w = minf(prev, lerpf(d["start"], d["end"], f))
			w = maxf(w, d["end"])
			prev = w
			wl[k] = w
			widths[k] = lerpf(d["w0"], d["w1"], t)
		# Smooth the profile so the surface has no steps, keeping it monotonic.
		for _pass in (24 if d["start"] < 0.0 else 6):
			for k in range(1, n - 1):
				wl[k] = minf(wl[k - 1], (wl[k - 1] + wl[k] + wl[k + 1]) / 3.0)
		# Down to the waterline (which lies a few metres outside the island's
		# outline, where the beach shelves under the sea) the river stays a
		# little above the sea and eases down to it, with its bed above the
		# sea surface so the sea never shows through it.
		for k in n:
			var cdk := coast_distance(line[k].x, line[k].y)
			if d["start"] >= 0.0 and cdk > MOUTH_END:
				wl[k] = maxf(wl[k], SEA_LEVEL + lerpf(0.05, 0.25, _smooth(-5.0, -1.0, cdk)))
		var pts3 := PackedVector3Array()
		pts3.resize(n)
		for k in n:
			pts3[k] = Vector3(line[k].x, wl[k], line[k].y)
		rivers.append({"points": pts3, "widths": widths})
		_carve_river(pts3, widths)
		if d.get("tarn", false):
			var head := Vector2(pts3[0].x, pts3[0].z)
			var down := (Vector2(pts3[3].x, pts3[3].z) - head).normalized()
			_carve_tarn(head - down * 9.0, 12.0, pts3[0].y)


func _carve_river(pts: PackedVector3Array, widths: PackedFloat32Array) -> void:
	# Nearest-sample search restricted to each sample's neighbourhood.
	var reach := 20
	var near_w := PackedFloat32Array()
	near_w.resize(V * V)
	near_w.fill(0.0)
	var near_hw := PackedFloat32Array()
	near_hw.resize(V * V)
	var near_dir := PackedVector2Array()
	near_dir.resize(V * V)
	var local_d := PackedFloat32Array()
	local_d.resize(V * V)
	local_d.fill(1.0e6)
	for k in pts.size():
		var p := pts[k]
		var ci := int(round(p.x + HALF))
		var cj := int(round(p.z + HALF))
		for j in range(maxi(cj - reach, 0), mini(cj + reach, V - 1) + 1):
			var dz := (-HALF + j) - p.z
			for i in range(maxi(ci - reach, 0), mini(ci + reach, V - 1) + 1):
				var dx := (-HALF + i) - p.x
				var dd := sqrt(dx * dx + dz * dz)
				var idx := j * V + i
				if dd < local_d[idx]:
					local_d[idx] = dd
					near_w[idx] = p.y
					near_hw[idx] = widths[k]
					var nxt := pts[mini(k + 1, pts.size() - 1)]
					var prv := pts[maxi(k - 1, 0)]
					var drop := maxf(prv.y - nxt.y, 0.0)
					near_dir[idx] = Vector2(nxt.x - prv.x, nxt.z - prv.z).normalized() * (0.35 + minf(drop * 2.0, 1.2))
	for idx in V * V:
		var dd := local_d[idx]
		if dd > reach:
			continue
		if dd < river_dist[idx]:
			river_dist[idx] = dd
		var w := near_w[idx]
		var hw := near_hw[idx]
		var h := heights[idx]
		var target: float
		# Current only in the river itself - none out on the still lake.
		var vx := -HALF + (idx % V)
		var vz := -HALF + (idx / V)
		if dd < hw + 2.0 and lake_distance(vx, vz) > 58.0:
			flow[idx] = near_dir[idx]
		if dd < hw:
			var q := dd / hw
			target = w - 1.7 * (1.0 - q * q)
			# Inland channels stay above the sea floor so no sea shows through.
			if w > 1.0:
				target = maxf(target, 0.15)
			else:
				# Near the waterline the bed rises gently to just above the sea,
				# so the sea never shows through the river and the channel slips
				# under the sea smoothly.
				target = lerpf(target, maxf(target, SEA_LEVEL + 0.02), _smooth(MOUTH_END, -2.0, coast_at(vx, vz)))
			h = minf(h, target)
			water_level[idx] = maxf(water_level[idx], w)
		else:
			var bank_t := _smooth(hw, hw * 3.6, dd)
			target = lerpf(w + 0.25, h, bank_t)
			h = minf(h, target)
			# Where the land is lower than the river, gentle raised banks
			# keep the water in its channel instead of floating over the land.
			if w > SEA_LEVEL + 0.3 and lake_distance(vx, vz) > LAKE_REACH - 6.0:
				h = maxf(h, lerpf(w + 0.7, h, bank_t))
			if dd < hw + 1.5:
				water_level[idx] = maxf(water_level[idx], w)
		heights[idx] = h


## A small mountain lake where the stream is born.
func _carve_tarn(c: Vector2, r: float, level: float) -> void:
	var reach := int(r * 1.6) + 2
	var ci := int(round(c.x + HALF))
	var cj := int(round(c.y + HALF))
	for j in range(maxi(cj - reach, 0), mini(cj + reach, V - 1) + 1):
		for i in range(maxi(ci - reach, 0), mini(ci + reach, V - 1) + 1):
			var p := Vector2(-HALF + i, -HALF + j)
			var wob := _n_detail.get_noise_2d(p.x * 3.0, p.y * 3.0) * 2.0
			var dd := p.distance_to(c) + wob
			var idx := j * V + i
			var h := heights[idx]
			if dd < r:
				var q := dd / r
				h = minf(h, level - 0.4 - 2.6 * (1.0 - q * q))
				water_level[idx] = maxf(water_level[idx], level)
			elif dd < r * 1.6:
				# A raised rim holds the tarn; the outlet stream keeps its own
				# (lower) water so no sheet of tarn water hangs over it.
				var t := _smooth(r, r * 1.6, dd)
				if water_level[idx] < -100.0:
					h = maxf(h, lerpf(level + 0.4, h, t))
					if dd < r + 1.0:
						water_level[idx] = level
			heights[idx] = h


## Level building pads and soften fields into the land.
func _level_settlements() -> void:
	for b in settlements.buildings:
		var pos: Vector2 = b["pos"]
		var s: Vector3 = b["size"]
		var pad := sample_height(pos.x, pos.y)
		var reach := maxf(s.x, s.z) * 0.5 + 6.0
		var ci := int(round(pos.x + HALF))
		var cj := int(round(pos.y + HALF))
		var rr := int(reach) + 1
		for j in range(maxi(cj - rr, 0), mini(cj + rr, V - 1) + 1):
			for i in range(maxi(ci - rr, 0), mini(ci + rr, V - 1) + 1):
				var local := (Vector2(-HALF + i, -HALF + j) - pos).rotated(b["rot"])
				var ex := maxf(absf(local.x) - s.x * 0.5 - 1.5, 0.0)
				var ez := maxf(absf(local.y) - s.z * 0.5 - 1.5, 0.0)
				var t := _smooth(0.0, 4.5, sqrt(ex * ex + ez * ez))
				var idx := j * V + i
				heights[idx] = lerpf(pad, heights[idx], t)


## Open sea: water at sea level over every vertex below it near the coast.
func _build_sea() -> void:
	for j in V:
		var z := -HALF + j
		for i in V:
			var idx := j * V + i
			if heights[idx] < SEA_LEVEL + 0.3 and water_level[idx] < -100.0 and coast[idx] < 30.0:
				water_level[idx] = SEA_LEVEL


# ------------------------------------------------------------------- paths
func _build_paths() -> void:
	for road in settlements.roads:
		var pts: Array = []
		for p in road:
			pts.append(p)
		var line := _resample(_catmull(pts, 12), 1.5)
		for p in line:
			var ci := int(round(p.x + HALF))
			var cj := int(round(p.y + HALF))
			for j in range(maxi(cj - 4, 0), mini(cj + 4, V - 1) + 1):
				for i in range(maxi(ci - 4, 0), mini(ci + 4, V - 1) + 1):
					var idx := j * V + i
					var dd := Vector2(-HALF + i, -HALF + j).distance_to(p)
					if dd < path_dist[idx]:
						path_dist[idx] = dd


## The lake fills its basin from the middle outwards and stops at the rim,
## so it can never spill over low ground beyond it (the beach, the sea, the
## outlet valley) as a sheet of water floating above the land.
func _build_lake_water() -> void:
	var seen := PackedByteArray()
	seen.resize(V * V)
	var start := int(round(LAKE_CENTER.y + HALF)) * V + int(round(LAKE_CENTER.x + HALF))
	var stack: Array[int] = [start]
	seen[start] = 1
	while not stack.is_empty():
		var idx: int = stack.pop_back()
		var i := idx % V
		var j := idx / V
		if heights[idx] >= LAKE_LEVEL + 0.6 or lake_distance(-HALF + i, -HALF + j) > LAKE_REACH:
			continue
		water_level[idx] = maxf(water_level[idx], LAKE_LEVEL)
		for n: Vector2i in [Vector2i(i + 1, j), Vector2i(i - 1, j), Vector2i(i, j + 1), Vector2i(i, j - 1)]:
			if n.x < 0 or n.y < 0 or n.x >= V or n.y >= V:
				continue
			var ni := n.y * V + n.x
			if seen[ni] == 0:
				seen[ni] = 1
				stack.append(ni)


# ----------------------------------------------------------------- regions
func _classify_cells() -> void:
	cell_region.resize(N * N)
	cell_water.resize(N * N)
	cell_ocean.resize(N * N)
	cell_built.resize(N * N)
	for cj in N:
		var z := -HALF + cj + 0.5
		for ci in N:
			var x := -HALF + ci + 0.5
			var idx := cj * N + ci
			var n := _n_region.get_noise_2d(x, z) * 22.0
			var h := sample_height(x, z)
			var r := REGION_MEADOWS
			if z + n < -100.0 or (z + n < -78.0 and h > 22.0):
				r = REGION_HIGHLANDS
			elif x + n < -72.0:
				r = REGION_WOODLAND
			elif x + n > 76.0:
				r = REGION_LAKE
			cell_region[idx] = r
			var wl := sample_water_level(x, z)
			var cd := coast_at(x, z)
			# The river's last stretch, inside the coastline, is river (it
			# freezes like the rest of it), not sea.
			var river_mouth := cd > MOUTH_END and river_dist[cj * V + ci] < 9.0 and wl > -100.0
			var sea := h < SEA_LEVEL + 0.05 and cd < 30.0 and wl <= SEA_LEVEL + 0.01 and not river_mouth
			var built := 0
			if settlements.building_at(Vector2(x, z), 3.0):
				built = 1
			elif not settlements.field_at(Vector2(x, z), 1.0).is_empty():
				built = 2
			cell_built[idx] = built
			cell_ocean[idx] = 1 if sea else 0
			cell_water[idx] = 1 if (wl > -100.0 and h < wl - 0.05 and not sea) or river_mouth else 0


## Rooftops as gentle hills for the cloud: each building's top height falls
## off slowly around its footprint, so the cloud eases up over a house
## rather than jumping when its edge reaches the eaves.
const ROOF_SLOPE := 0.35
func _mark_roofs() -> void:
	cell_roof.resize(N * N)
	cell_roof.fill(-1000.0)
	for o in settlements.obstacles(func(p: Vector2) -> float: return sample_height(p.x, p.y)):
		var c: Vector2 = o[0]
		var hs: Vector2 = o[1]
		var rot: float = o[2]
		var top: float = o[3]
		var ground := sample_height(c.x, c.y)
		var fall := (top - ground) / ROOF_SLOPE
		var reach := int(ceil(hs.length() + fall)) + 1
		for cj in range(maxi(int(c.y + HALF) - reach, 0), mini(int(c.y + HALF) + reach, N - 1) + 1):
			for ci in range(maxi(int(c.x + HALF) - reach, 0), mini(int(c.x + HALF) + reach, N - 1) + 1):
				var local := (Vector2(-HALF + ci + 0.5, -HALF + cj + 0.5) - c).rotated(rot)
				var ex := maxf(absf(local.x) - hs.x, 0.0)
				var ez := maxf(absf(local.y) - hs.y, 0.0)
				var h := top - sqrt(ex * ex + ez * ez) * ROOF_SLOPE
				var idx := cj * N + ci
				cell_roof[idx] = maxf(cell_roof[idx], h)


## Highest thing the cloud must clear at a point: ground, water surface or
## the gentle "hill" around a rooftop (bilinear, so the rise is smooth).
func obstacle_height(x: float, z: float) -> float:
	var h := surface_height(x, z)
	if not in_bounds(x, z):
		return h
	var fx := clampf(x + HALF - 0.5, 0.0, N - 1.001)
	var fz := clampf(z + HALF - 0.5, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var idx := j * N + i
	var r := lerpf(lerpf(cell_roof[idx], cell_roof[idx + 1], tx), lerpf(cell_roof[idx + N], cell_roof[idx + N + 1], tx), tz)
	return maxf(h, r)


# ---------------------------------------------------------------- sampling
func sample_height(x: float, z: float) -> float:
	var fx := clampf(x + HALF, 0.0, N - 0.0001)
	var fz := clampf(z + HALF, 0.0, N - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var idx := j * V + i
	var h00 := heights[idx]
	var h10 := heights[idx + 1]
	var h01 := heights[idx + V]
	var h11 := heights[idx + V + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func sample_water_level(x: float, z: float) -> float:
	var i := clampi(int(round(x + HALF)), 0, N)
	var j := clampi(int(round(z + HALF)), 0, N)
	return water_level[j * V + i]


## Surface height: terrain or water surface, whichever is higher.
func surface_height(x: float, z: float) -> float:
	var h := sample_height(x, z)
	var w := sample_water_level(x, z)
	return maxf(h, w)


func gradient(x: float, z: float, e: float = 1.0) -> Vector2:
	var hx := sample_height(x + e, z) - sample_height(x - e, z)
	var hz := sample_height(x, z + e) - sample_height(x, z - e)
	return Vector2(hx, hz) / (2.0 * e)


func slope(x: float, z: float) -> float:
	return gradient(x, z).length()


func normal_at(x: float, z: float) -> Vector3:
	var g := gradient(x, z)
	return Vector3(-g.x, 1.0, -g.y).normalized()


func region_at(x: float, z: float) -> int:
	var ci := clampi(int(floor(x + HALF)), 0, N - 1)
	var cj := clampi(int(floor(z + HALF)), 0, N - 1)
	return cell_region[cj * N + ci]


func is_water(x: float, z: float) -> bool:
	var ci := clampi(int(floor(x + HALF)), 0, N - 1)
	var cj := clampi(int(floor(z + HALF)), 0, N - 1)
	return cell_water[cj * N + ci] == 1


func coast_at(x: float, z: float) -> float:
	return coast[vertex_index(x, z)]


func built_at(x: float, z: float) -> int:
	var ci := clampi(int(floor(x + HALF)), 0, N - 1)
	var cj := clampi(int(floor(z + HALF)), 0, N - 1)
	return cell_built[cj * N + ci]


func is_ocean(x: float, z: float) -> bool:
	if not in_bounds(x, z):
		return true
	var ci := clampi(int(floor(x + HALF)), 0, N - 1)
	var cj := clampi(int(floor(z + HALF)), 0, N - 1)
	return cell_ocean[cj * N + ci] == 1


func vertex_index(x: float, z: float) -> int:
	var i := clampi(int(round(x + HALF)), 0, N)
	var j := clampi(int(round(z + HALF)), 0, N)
	return j * V + i


func in_bounds(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= HALF - margin and absf(z) <= HALF - margin


## Ray-march against the height field (and water surfaces).
## Returns {"hit": bool, "position": Vector3, "distance": float}.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var step := 0.5
	var t := 0.0
	var prev_t := 0.0
	var prev_above := origin.y - surface_height(origin.x, origin.z)
	if prev_above < 0.0:
		return {"hit": true, "position": Vector3(origin.x, surface_height(origin.x, origin.z), origin.z), "distance": 0.0}
	while t < max_dist:
		t = minf(t + step, max_dist)
		var p := origin + dir * t
		if not in_bounds(p.x, p.z, -40.0):
			break
		var above := p.y - surface_height(p.x, p.z)
		if above <= 0.0:
			# Refine by bisection.
			var a := prev_t
			var b := t
			for _k in 8:
				var m := (a + b) * 0.5
				var pm := origin + dir * m
				if pm.y - surface_height(pm.x, pm.z) > 0.0:
					a = m
				else:
					b = m
			var hp := origin + dir * b
			hp.y = surface_height(hp.x, hp.z)
			return {"hit": true, "position": hp, "distance": b}
		prev_t = t
		prev_above = above
		step = clampf(above * 0.5, 0.4, 4.0)
		if t >= max_dist:
			break
	return {"hit": false, "position": origin + dir * max_dist, "distance": max_dist}


func height_image() -> Image:
	var bytes := heights.to_byte_array()
	return Image.create_from_data(V, V, false, Image.FORMAT_RF, bytes)


func water_image() -> Image:
	var bytes := water_level.to_byte_array()
	return Image.create_from_data(V, V, false, Image.FORMAT_RF, bytes)
