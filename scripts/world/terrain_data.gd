class_name TerrainData
extends RefCounted
## Seeded, deterministic description of the world's shape.
##
## Heights live on a (N+1)x(N+1) vertex grid with 1 m spacing that spans
## [-256, 256] on X and Z. Coverage cells are the N x N squares between
## vertices, so terrain, collision, coverage and shaders all share one
## coordinate system.

const N := GameBalance.WORLD_SIZE
const V := N + 1
const HALF := GameBalance.WORLD_HALF
const LAKE_LEVEL := 5.0
const LAKE_CENTER := Vector2(135.0, -5.0)
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
var cell_water := PackedByteArray()      # N*N, 1 = water surface cell
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


func lake_distance(x: float, z: float) -> float:
	var dx := (x - LAKE_CENTER.x)
	var dz := (z - LAKE_CENTER.y) / 0.82
	return sqrt(dx * dx + dz * dz) + _n_warp.get_noise_2d(x * 2.0 + 300.0, z * 2.0) * 12.0


func _raw_height(x: float, z: float) -> float:
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
		mount += _smooth(-150.0, -256.0, wz) * 30.0
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
		var floor_h := LAKE_LEVEL - 1.2 - 5.5 * _smooth(52.0, 5.0, ld)
		h = lerpf(h, minf(h, floor_h), basin)

	# Gentle rim at the world edge frames the playable area.
	var e := maxf(absf(x), absf(z))
	var rim := _smooth(200.0, 256.0, e)
	h += rim * rim * (20.0 + broad * 8.0)

	# Flatten the starting meadow a little so the first minutes are comfortable.
	var sd := Vector2(x, z).distance_to(SPAWN)
	var flat := _smooth(40.0, 10.0, sd)
	h = lerpf(h, 10.5 + detail * 0.25 + roll * 0.6, flat * 0.7)
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
	for j in V:
		var z := -HALF + j
		var row := j * V
		for i in V:
			heights[row + i] = _raw_height(-HALF + i, z)
	_build_rivers()
	_build_paths()
	_build_lake_water()
	_classify_cells()
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
	var defs := [
		{"pts": [Vector2(-8, -150), Vector2(18, -128), Vector2(50, -112), Vector2(74, -86),
			Vector2(96, -64), Vector2(114, -42), Vector2(126, -24)], "w0": 3.2, "w1": 5.0, "start": -1.0, "end": LAKE_LEVEL},
		{"pts": [Vector2(158, 30), Vector2(170, 74), Vector2(160, 118), Vector2(140, 160),
			Vector2(156, 200), Vector2(182, 236), Vector2(196, 276)], "w0": 5.5, "w1": 4.6, "start": LAKE_LEVEL, "end": LAKE_LEVEL - 2.6},
	]
	rivers.clear()
	for d in defs:
		var line := _resample(_catmull(d["pts"], 14), 2.0)
		var n := line.size()
		var wl := PackedFloat32Array()
		wl.resize(n)
		var widths := PackedFloat32Array()
		widths.resize(n)
		var prev := 1.0e9
		for k in n:
			var raw := sample_height(line[k].x, line[k].y)
			var t := float(k) / (n - 1)
			var w: float
			if d["start"] < 0.0:
				# Mountain stream: follow the land downhill, never rising.
				w = minf(prev - 0.02, raw - 1.1)
			else:
				w = minf(prev - 0.004, lerpf(d["start"], d["end"], t))
				w = minf(w, raw - 1.0)
			w = maxf(w, d["end"])
			prev = w
			wl[k] = w
			widths[k] = lerpf(d["w0"], d["w1"], t)
		# Smooth the profile so the surface has no steps, keeping it monotonic.
		for _pass in 6:
			for k in range(1, n - 1):
				wl[k] = minf(wl[k - 1], (wl[k - 1] + wl[k] + wl[k + 1]) / 3.0)
		var pts3 := PackedVector3Array()
		pts3.resize(n)
		for k in n:
			pts3[k] = Vector3(line[k].x, wl[k], line[k].y)
		rivers.append({"points": pts3, "widths": widths})
		_carve_river(pts3, widths)


func _carve_river(pts: PackedVector3Array, widths: PackedFloat32Array) -> void:
	# Nearest-sample search restricted to each sample's neighbourhood.
	var reach := 20
	var near_w := PackedFloat32Array()
	near_w.resize(V * V)
	near_w.fill(0.0)
	var near_hw := PackedFloat32Array()
	near_hw.resize(V * V)
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
		if dd < hw:
			var q := dd / hw
			target = w - 1.7 * (1.0 - q * q)
			h = minf(h, target)
			water_level[idx] = maxf(water_level[idx], w)
		else:
			var bank_t := _smooth(hw, hw * 3.6, dd)
			target = lerpf(w + 0.25, h, bank_t)
			h = minf(h, target)
			if dd < hw + 1.5:
				water_level[idx] = maxf(water_level[idx], w)
		heights[idx] = h


# ------------------------------------------------------------------- paths
func _build_paths() -> void:
	var defs := [
		[TRAILHEAD, Vector2(-22, 96), Vector2(-46, 122)],
		[TRAILHEAD, Vector2(30, 52), Vector2(66, 36), Vector2(92, 40)],
		[TRAILHEAD, Vector2(-40, 50), Vector2(-90, 34), Vector2(-138, 18)],
		[TRAILHEAD, Vector2(6, 20), Vector2(14, -30), Vector2(30, -78)],
	]
	for d in defs:
		var line := _resample(_catmull(d, 12), 1.5)
		for p in line:
			var ci := int(round(p.x + HALF))
			var cj := int(round(p.y + HALF))
			for j in range(maxi(cj - 4, 0), mini(cj + 4, V - 1) + 1):
				for i in range(maxi(ci - 4, 0), mini(ci + 4, V - 1) + 1):
					var idx := j * V + i
					var dd := Vector2(-HALF + i, -HALF + j).distance_to(p)
					if dd < path_dist[idx]:
						path_dist[idx] = dd


func _build_lake_water() -> void:
	for j in V:
		var z := -HALF + j
		for i in V:
			var x := -HALF + i
			var idx := j * V + i
			if heights[idx] < LAKE_LEVEL + 0.6 and lake_distance(x, z) < 90.0:
				water_level[idx] = maxf(water_level[idx], LAKE_LEVEL)


# ----------------------------------------------------------------- regions
func _classify_cells() -> void:
	cell_region.resize(N * N)
	cell_water.resize(N * N)
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
			cell_water[idx] = 1 if wl > -100.0 and h < wl - 0.05 else 0


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
