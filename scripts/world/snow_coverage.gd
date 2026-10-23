class_name SnowCoverage
extends RefCounted
## Authoritative snow/ice coverage field.
##
## One cell per square metre. Each cell holds 0..1 coverage. Rewards are paid
## only for positive coverage gained, so a cell can never pay out more than its
## base reward over a whole run. Work is organised in 16x16 chunks: chunks that
## are fully frozen are skipped outright, and only dirty chunks are re-encoded
## for the GPU texture.

const N := GameBalance.WORLD_SIZE
const HALF := GameBalance.WORLD_HALF
const CS := GameBalance.CHUNK
const CH := N / CS
const FULL_SNAP := 0.995
const REGION_COUNT := 4

var cov := PackedFloat32Array()
var reward := PackedFloat32Array()
var exposure := PackedFloat32Array()
var region := PackedByteArray()
var water := PackedByteArray()
var water_cells := PackedInt32Array()
var water_rate := PackedFloat32Array()   # per water cell creep multiplier (rivers are fast)

var chunk_incomplete := PackedInt32Array()
var chunk_dirty := PackedByteArray()
var any_dirty := false

var region_sum := PackedFloat64Array()
var region_total := PackedFloat64Array()
var total_sum := 0.0
var total_cells := 0
var total_incomplete := 0
var total_reward := 0.0

# Filled by every apply_* call for callers that want detail.
var last_cov_delta := 0.0
var last_new_full := 0

var tex_bytes := PackedByteArray()
var image: Image
var texture: ImageTexture


func setup(terrain: TerrainData) -> void:
	var count := N * N
	cov.resize(count)
	cov.fill(0.0)
	reward.resize(count)
	exposure.resize(count)
	region = terrain.cell_region.duplicate()
	water = terrain.cell_water.duplicate()
	region_sum.resize(REGION_COUNT)
	region_sum.fill(0.0)
	region_total.resize(REGION_COUNT)
	region_total.fill(0.0)
	total_reward = 0.0
	var wc: Array[int] = []
	var wr: Array[float] = []
	for i in count:
		var r := region[i]
		var is_w := water[i] == 1
		reward[i] = GameBalance.WATER_REWARD if is_w else GameBalance.REGION_REWARD[r]
		exposure[i] = GameBalance.WATER_EXPOSURE if is_w else GameBalance.REGION_EXPOSURE[r]
		region_total[r] += 1.0
		total_reward += reward[i]
		if is_w:
			wc.append(i)
			var ci := i % N
			var cj := i / N
			var vi := cj * TerrainData.V + ci
			wr.append(4.0 if terrain.river_dist[vi] < 8.0 else 1.0)
	water_cells = PackedInt32Array(wc)
	water_rate = PackedFloat32Array(wr)
	total_cells = count
	total_sum = 0.0
	total_incomplete = count
	chunk_incomplete.resize(CH * CH)
	chunk_incomplete.fill(CS * CS)
	chunk_dirty.resize(CH * CH)
	chunk_dirty.fill(1)
	any_dirty = true
	tex_bytes.resize(count)
	tex_bytes.fill(0)


func reset() -> void:
	cov.fill(0.0)
	region_sum.fill(0.0)
	total_sum = 0.0
	total_incomplete = total_cells
	chunk_incomplete.fill(CS * CS)
	chunk_dirty.fill(1)
	any_dirty = true


# ------------------------------------------------------------------ queries
func cell_index(x: float, z: float) -> int:
	var ci := clampi(int(floor(x + HALF)), 0, N - 1)
	var cj := clampi(int(floor(z + HALF)), 0, N - 1)
	return cj * N + ci


func get_coverage(x: float, z: float) -> float:
	return cov[cell_index(x, z)]


## Bilinear sample, matches what the shaders see.
func sample_coverage(x: float, z: float) -> float:
	var fx := clampf(x + HALF - 0.5, 0.0, N - 1.001)
	var fz := clampf(z + HALF - 0.5, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var idx := j * N + i
	return lerpf(lerpf(cov[idx], cov[idx + 1], tx), lerpf(cov[idx + N], cov[idx + N + 1], tx), tz)


func get_coverage_gradient(x: float, z: float) -> Vector2:
	var gx := sample_coverage(x + 1.5, z) - sample_coverage(x - 1.5, z)
	var gz := sample_coverage(x, z + 1.5) - sample_coverage(x, z - 1.5)
	return Vector2(gx, gz) / 3.0


func world_completion() -> float:
	return total_sum / float(total_cells)


func region_completion(r: int) -> float:
	if region_total[r] <= 0.0:
		return 1.0
	return region_sum[r] / region_total[r]


func get_unfrozen_cells_in_area(rect: Rect2) -> int:
	var x0 := clampi(int(floor(rect.position.x + HALF)), 0, N - 1)
	var z0 := clampi(int(floor(rect.position.y + HALF)), 0, N - 1)
	var x1 := clampi(int(floor(rect.end.x + HALF)), 0, N - 1)
	var z1 := clampi(int(floor(rect.end.y + HALF)), 0, N - 1)
	var n := 0
	for z in range(z0, z1 + 1):
		var row := z * N
		for x in range(x0, x1 + 1):
			if cov[row + x] < 1.0:
				n += 1
	return n


## Finds the centre of the most attractive nearby unfrozen patch.
## `avoid` is an Array of Vector3(x, z, radius) already targeted by other storms.
## Returns Vector2.INF when nothing qualifies.
func find_nearest_unfrozen_area(pos: Vector2, max_dist: float = 1.0e9, min_cells: int = 4, avoid: Array = []) -> Vector2:
	var best := -1
	var best_score := 1.0e12
	for ch in CH * CH:
		var inc := chunk_incomplete[ch]
		if inc < min_cells:
			continue
		var c := Vector2((ch % CH) * CS + CS * 0.5 - HALF, (ch / CH) * CS + CS * 0.5 - HALF)
		var d := c.distance_to(pos)
		if d > max_dist:
			continue
		var frac := float(inc) / float(CS * CS)
		var score := d / (0.25 + frac)
		for a in avoid:
			var av: Vector3 = a
			if c.distance_to(Vector2(av.x, av.y)) < av.z:
				score *= 2.5
		if score < best_score:
			best_score = score
			best = ch
	if best < 0:
		return Vector2.INF
	return chunk_unfrozen_centroid(best)


func chunk_unfrozen_centroid(ch: int) -> Vector2:
	var bx := (ch % CH) * CS
	var bz := (ch / CH) * CS
	var sx := 0.0
	var sz := 0.0
	var sw := 0.0
	for z in range(bz, bz + CS):
		var row := z * N
		for x in range(bx, bx + CS):
			var w := 1.0 - cov[row + x]
			if w > 0.0:
				sx += (x + 0.5) * w
				sz += (z + 0.5) * w
				sw += w
	if sw <= 0.0:
		return Vector2(bx + CS * 0.5 - HALF, bz + CS * 0.5 - HALF)
	# The weighted centre of a ring of green cells can sit on frozen ground;
	# snap to the unfrozen cell closest to it so targets are always useful.
	var cx := sx / sw
	var cz := sz / sw
	var best := Vector2(cx, cz)
	var bd := 1.0e9
	for z in range(bz, bz + CS):
		var row := z * N
		for x in range(bx, bx + CS):
			if cov[row + x] < 1.0:
				var d := (x + 0.5 - cx) * (x + 0.5 - cx) + (z + 0.5 - cz) * (z + 0.5 - cz)
				if d < bd:
					bd = d
					best = Vector2(x + 0.5, z + 0.5)
	return best - Vector2(HALF, HALF)


## Lists centres of chunks that still contain unfrozen ground, biggest first.
func unfrozen_patches(limit: int) -> Array[Vector3]:
	var list: Array = []
	for ch in CH * CH:
		var inc := chunk_incomplete[ch]
		if inc > 0:
			list.append([inc, ch])
	list.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array[Vector3] = []
	for k in mini(limit, list.size()):
		var c := chunk_unfrozen_centroid(list[k][1])
		out.append(Vector3(c.x, float(list[k][0]), c.y))
	return out


# ---------------------------------------------------------------- mutation
func _mark_chunk(ch: int) -> void:
	chunk_dirty[ch] = 1
	any_dirty = true


## Soft-edged disc. `amount` is coverage added at the centre for this call.
## stride/phase let very large storms update interleaved rows each tick.
## `core` is the fraction of the disc's area that receives full strength; cells
## reaching `snap` jump straight to fully frozen.
func apply_disc(cx: float, cz: float, r: float, amount: float, stride: int = 1, phase: int = 0,
		core: float = 0.4, snap: float = FULL_SNAP) -> float:
	last_cov_delta = 0.0
	last_new_full = 0
	if amount <= 0.0 or r <= 0.0:
		return 0.0
	var amt := amount * stride
	var gx := cx + HALF
	var gz := cz + HALF
	var x0 := maxi(0, int(floor(gx - r)))
	var x1 := mini(N - 1, int(floor(gx + r)))
	var z0 := maxi(0, int(floor(gz - r)))
	var z1 := mini(N - 1, int(floor(gz + r)))
	if x0 > x1 or z0 > z1:
		return 0.0
	var r2 := r * r
	var inner2 := r2 * clampf(core, 0.0, 0.95)
	var fall := r2 - inner2
	var gain := 0.0
	var dsum := 0.0
	var newfull := 0
	for chz in range(z0 / CS, z1 / CS + 1):
		for chx in range(x0 / CS, x1 / CS + 1):
			var ch := chz * CH + chx
			if chunk_incomplete[ch] == 0:
				continue
			var zs := maxi(z0, chz * CS)
			var ze := mini(z1, chz * CS + CS - 1)
			var xs := maxi(x0, chx * CS)
			var xe := mini(x1, chx * CS + CS - 1)
			var done := 0
			var touched := false
			for z in range(zs, ze + 1):
				if stride > 1 and (z + phase) % stride != 0:
					continue
				var dz := z + 0.5 - gz
				var dz2 := dz * dz
				if dz2 > r2:
					continue
				var row := z * N
				for x in range(xs, xe + 1):
					var dx := x + 0.5 - gx
					var d2 := dx * dx + dz2
					if d2 > r2:
						continue
					var i := row + x
					var c := cov[i]
					if c >= 1.0:
						continue
					var w := 1.0
					if d2 > inner2:
						w = (r2 - d2) / fall
					var nc := c + amt * w * exposure[i]
					if nc >= snap:
						nc = 1.0
						done += 1
					cov[i] = nc
					var dg := nc - c
					dsum += dg
					gain += dg * reward[i]
					region_sum[region[i]] += dg
					touched = true
			if touched:
				chunk_incomplete[ch] -= done
				newfull += done
				_mark_chunk(ch)
	total_sum += dsum
	total_incomplete -= newfull
	last_cov_delta = dsum
	last_new_full = newfull
	return gain


## Swept rectangle from A to B (half-open along the path) with soft sides.
## Each cell swept once receives `amount` (used by fronts, avalanches, gusts).
func apply_sweep(ax: float, az: float, bx: float, bz: float, hw: float, amount: float) -> float:
	last_cov_delta = 0.0
	last_new_full = 0
	var dx0 := bx - ax
	var dz0 := bz - az
	var length := sqrt(dx0 * dx0 + dz0 * dz0)
	if amount <= 0.0 or length < 0.0001 or hw <= 0.0:
		return 0.0
	var ux := dx0 / length
	var uz := dz0 / length
	var gax := ax + HALF
	var gaz := az + HALF
	var x0 := maxi(0, int(floor(minf(ax, bx) + HALF - hw)))
	var x1 := mini(N - 1, int(floor(maxf(ax, bx) + HALF + hw)))
	var z0 := maxi(0, int(floor(minf(az, bz) + HALF - hw)))
	var z1 := mini(N - 1, int(floor(maxf(az, bz) + HALF + hw)))
	if x0 > x1 or z0 > z1:
		return 0.0
	var soft := hw * 0.7
	var soft_den := hw - soft
	var gain := 0.0
	var dsum := 0.0
	var newfull := 0
	for chz in range(z0 / CS, z1 / CS + 1):
		for chx in range(x0 / CS, x1 / CS + 1):
			var ch := chz * CH + chx
			if chunk_incomplete[ch] == 0:
				continue
			var zs := maxi(z0, chz * CS)
			var ze := mini(z1, chz * CS + CS - 1)
			var xs := maxi(x0, chx * CS)
			var xe := mini(x1, chx * CS + CS - 1)
			var done := 0
			var touched := false
			for z in range(zs, ze + 1):
				var rz := z + 0.5 - gaz
				var row := z * N
				for x in range(xs, xe + 1):
					var rx := x + 0.5 - gax
					var along := rx * ux + rz * uz
					if along < 0.0 or along >= length:
						continue
					var lat := absf(rx * uz - rz * ux)
					if lat > hw:
						continue
					var i := row + x
					var c := cov[i]
					if c >= 1.0:
						continue
					var w := 1.0
					if lat > soft:
						w = (hw - lat) / soft_den
					var nc := c + amount * w * exposure[i]
					if nc >= FULL_SNAP:
						nc = 1.0
						done += 1
					cov[i] = nc
					var dg := nc - c
					dsum += dg
					gain += dg * reward[i]
					region_sum[region[i]] += dg
					touched = true
			if touched:
				chunk_incomplete[ch] -= done
				newfull += done
				_mark_chunk(ch)
	total_sum += dsum
	total_incomplete -= newfull
	last_cov_delta = dsum
	last_new_full = newfull
	return gain


## Annulus between r0 and r1 - an expanding frost pulse calls this with the
## ring it swept this tick, so each cell is hit once per pulse.
func apply_ring(cx: float, cz: float, r0: float, r1: float, amount: float) -> float:
	last_cov_delta = 0.0
	last_new_full = 0
	if amount <= 0.0 or r1 <= r0:
		return 0.0
	var gx := cx + HALF
	var gz := cz + HALF
	var x0 := maxi(0, int(floor(gx - r1)))
	var x1 := mini(N - 1, int(floor(gx + r1)))
	var z0 := maxi(0, int(floor(gz - r1)))
	var z1 := mini(N - 1, int(floor(gz + r1)))
	if x0 > x1 or z0 > z1:
		return 0.0
	var a2 := r0 * r0
	var b2 := r1 * r1
	var gain := 0.0
	var dsum := 0.0
	var newfull := 0
	for chz in range(z0 / CS, z1 / CS + 1):
		for chx in range(x0 / CS, x1 / CS + 1):
			var ch := chz * CH + chx
			if chunk_incomplete[ch] == 0:
				continue
			# Skip chunks entirely inside the inner radius or outside the outer one.
			var ccx := chx * CS + CS * 0.5 - gx
			var ccz := chz * CS + CS * 0.5 - gz
			var cd := sqrt(ccx * ccx + ccz * ccz)
			if cd + CS * 0.75 < r0 or cd - CS * 0.75 > r1:
				continue
			var zs := maxi(z0, chz * CS)
			var ze := mini(z1, chz * CS + CS - 1)
			var xs := maxi(x0, chx * CS)
			var xe := mini(x1, chx * CS + CS - 1)
			var done := 0
			var touched := false
			for z in range(zs, ze + 1):
				var dz := z + 0.5 - gz
				var dz2 := dz * dz
				var row := z * N
				for x in range(xs, xe + 1):
					var dx := x + 0.5 - gx
					var d2 := dx * dx + dz2
					if d2 < a2 or d2 >= b2:
						continue
					var i := row + x
					var c := cov[i]
					if c >= 1.0:
						continue
					var nc := c + amount * exposure[i]
					if nc >= FULL_SNAP:
						nc = 1.0
						done += 1
					cov[i] = nc
					var dg := nc - c
					dsum += dg
					gain += dg * reward[i]
					region_sum[region[i]] += dg
					touched = true
			if touched:
				chunk_incomplete[ch] -= done
				newfull += done
				_mark_chunk(ch)
	total_sum += dsum
	total_incomplete -= newfull
	last_cov_delta = dsum
	last_new_full = newfull
	return gain


## Generic convenience matching the design brief's API.
func apply_snow(world_position: Vector3, radius: float, intensity: float, delta: float) -> float:
	return apply_disc(world_position.x, world_position.z, radius, intensity * delta)


func _set_cell(i: int, nc: float) -> float:
	var c := cov[i]
	if nc <= c:
		return 0.0
	if nc >= FULL_SNAP:
		nc = 1.0
	cov[i] = nc
	var dg := nc - c
	total_sum += dg
	region_sum[region[i]] += dg
	var ch := ((i / N) / CS) * CH + (i % N) / CS
	if nc >= 1.0:
		chunk_incomplete[ch] -= 1
		total_incomplete -= 1
	_mark_chunk(ch)
	return dg * reward[i]


## Ice creeps outward from frozen water across the rest of the water body.
## Rivers creep faster than the lake. Called a few times per second.
func water_spread_tick(dt: float, rate: float) -> float:
	var gain := 0.0
	var n := water_cells.size()
	for k in n:
		var i := water_cells[k]
		var c := cov[i]
		if c >= 1.0:
			continue
		var m := 0.0
		var x := i % N
		if x > 0 and water[i - 1] == 1:
			m = maxf(m, cov[i - 1])
		if x < N - 1 and water[i + 1] == 1:
			m = maxf(m, cov[i + 1])
		if i >= N and water[i - N] == 1:
			m = maxf(m, cov[i - N])
		if i < N * (N - 1) and water[i + N] == 1:
			m = maxf(m, cov[i + N])
		if m < 0.95:
			continue
		gain += _set_cell(i, c + rate * water_rate[k] * dt)
	return gain


## Fills tiny isolated holes that are visually insignificant. Only touches
## cells whose eight neighbours are all essentially frozen.
func cleanup_pass() -> float:
	var gain := 0.0
	for ch in CH * CH:
		var inc := chunk_incomplete[ch]
		if inc == 0 or inc > 24:
			continue
		var bx := (ch % CH) * CS
		var bz := (ch / CH) * CS
		for z in range(bz, bz + CS):
			for x in range(bx, bx + CS):
				var i := z * N + x
				if cov[i] >= 1.0:
					continue
				var frozen_n := 0
				var total_n := 0
				for oz in range(-1, 2):
					for ox in range(-1, 2):
						if ox == 0 and oz == 0:
							continue
						var nx := x + ox
						var nz := z + oz
						if nx < 0 or nz < 0 or nx >= N or nz >= N:
							continue
						total_n += 1
						if cov[nz * N + nx] >= 0.9:
							frozen_n += 1
				if frozen_n == total_n:
					gain += _set_cell(i, 1.0)
	return gain


func largest_patch() -> int:
	var m := 0
	for ch in CH * CH:
		m = maxi(m, chunk_incomplete[ch])
	return m


func is_world_complete() -> bool:
	if total_incomplete > GameBalance.MAX_REMAINING_CELLS:
		return false
	return largest_patch() <= GameBalance.MAX_PATCH_CELLS


func freeze_all() -> float:
	var gain := 0.0
	for i in N * N:
		if cov[i] < 1.0:
			gain += (1.0 - cov[i]) * reward[i]
	cov.fill(1.0)
	for r in REGION_COUNT:
		region_sum[r] = region_total[r]
	total_sum = float(total_cells)
	total_incomplete = 0
	chunk_incomplete.fill(0)
	chunk_dirty.fill(1)
	any_dirty = true
	return gain


# -------------------------------------------------------------- GPU texture
func create_texture() -> ImageTexture:
	image = Image.create_from_data(N, N, false, Image.FORMAT_R8, tex_bytes)
	texture = ImageTexture.create_from_image(image)
	return texture


## Re-encodes dirty chunks and uploads. Returns true if anything changed.
func update_texture() -> bool:
	if not any_dirty or texture == null:
		return false
	for ch in CH * CH:
		if chunk_dirty[ch] == 0:
			continue
		chunk_dirty[ch] = 0
		var bx := (ch % CH) * CS
		var bz := (ch / CH) * CS
		for z in range(bz, bz + CS):
			var row := z * N
			for x in range(bx, bx + CS):
				tex_bytes[row + x] = int(cov[row + x] * 255.0)
	any_dirty = false
	image.set_data(N, N, false, Image.FORMAT_R8, tex_bytes)
	texture.update(image)
	return true


# --------------------------------------------------------------- persistence
## Quantised to 16 bits, rounding UP so reloading can never re-award Frost.
func serialize() -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(N * N * 2)
	for i in N * N:
		raw.encode_u16(i * 2, int(ceil(cov[i] * 65535.0)))
	return raw.compress(FileAccess.COMPRESSION_ZSTD)


func deserialize(data: PackedByteArray) -> bool:
	var raw := data.decompress(N * N * 2, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != N * N * 2:
		return false
	region_sum.fill(0.0)
	total_sum = 0.0
	total_incomplete = 0
	chunk_incomplete.fill(0)
	for i in N * N:
		var c := float(raw.decode_u16(i * 2)) / 65535.0
		if c >= FULL_SNAP:
			c = 1.0
		cov[i] = c
		total_sum += c
		region_sum[region[i]] += c
		if c < 1.0:
			total_incomplete += 1
			var ch := ((i / N) / CS) * CH + (i % N) / CS
			chunk_incomplete[ch] += 1
	chunk_dirty.fill(1)
	any_dirty = true
	return true
