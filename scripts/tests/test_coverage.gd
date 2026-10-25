class_name TestCoverage
extends RefCounted
## The coverage field is the authoritative progress state: these tests check
## accumulation, one-time rewards, bookkeeping consistency and searches.


func run(t, _full: bool) -> void:
	var terrain: TerrainData = t.shared_terrain()
	var cov := SnowCoverage.new()
	cov.setup(terrain)
	t.check(cov.world_completion() == 0.0, "fresh world starts unfrozen")
	t.check(cov.total_incomplete == cov.total_cells, "all land cells start incomplete")
	var sea := 0
	for i in SnowCoverage.N * SnowCoverage.N:
		if cov.is_void(i):
			sea += 1
	t.check(sea > 20000 and cov.total_cells + sea == SnowCoverage.N * SnowCoverage.N, "the sea around the island is not part of the land (%d sea cells)" % sea)
	t.check(terrain.is_ocean(250, 250) and terrain.is_ocean(-250, 0) and not terrain.is_ocean(0, 60), "the world edge is open sea, the middle is land")
	var sea_gain := cov.apply_disc(0, 250, 6.0, 1.0)
	t.check(sea_gain == 0.0 and cov.last_cov_delta == 0.0, "snow on the open sea pays nothing")

	# Gradual accumulation, never instant.
	var p := Vector2(0, 60)
	var g1 := cov.apply_disc(p.x, p.y, 4.0, 0.3)
	var c1 := cov.get_coverage(p.x, p.y)
	t.approx(c1, 0.3, 0.001, "centre gains exactly the applied amount")
	t.check(g1 > 0.0, "freezing new ground earns Frost")
	for k in 10:
		cov.apply_disc(p.x, p.y, 4.0, 0.3)
	t.check(cov.get_coverage(p.x, p.y) == 1.0, "coverage saturates at 1.0")

	# No double-counted rewards.
	var before := cov.total_sum
	var g2 := cov.apply_disc(p.x, p.y, 2.0, 1.0)
	t.check(g2 == 0.0, "snow on fully frozen ground pays nothing (got %f)" % g2)
	t.check(cov.total_sum == before, "frozen ground does not change totals")

	# Lifetime reward per cell never exceeds its base reward.
	var cov2 := SnowCoverage.new()
	cov2.setup(terrain)
	var total_gain := 0.0
	for k in 40:
		total_gain += cov2.apply_disc(30, 30, 10.0, 0.13)
		total_gain += cov2.apply_sweep(0, 30, 60, 30, 6.0, 0.2)
		total_gain += cov2.apply_ring(30, 30, 0.0, 15.0, 0.25)
	var max_possible := 0.0
	for z in range(0, SnowCoverage.N):
		for x in range(0, SnowCoverage.N):
			var i := z * SnowCoverage.N + x
			max_possible += cov2.cov[i] * cov2.reward[i]
	t.approx(total_gain, max_possible, 0.5, "total reward equals sum of coverage x reward")

	# Bookkeeping: region sums, totals and chunk counters agree with a brute-force recount.
	_consistency(t, cov2, "after mixed operations")

	# Sweeps apply exactly once along their path.
	var cov3 := SnowCoverage.new()
	cov3.setup(terrain)
	var a := Vector2(-100, 100)
	for k in 20:
		var b := a + Vector2(1.5, 0.0)
		cov3.apply_sweep(a.x, a.y, b.x, b.y, 3.0, 0.4)
		a = b
	var mid := cov3.get_coverage(-85.0, 100.0)
	var expected := 0.4 * cov3.exposure[cov3.cell_index(-85.0, 100.0)]
	t.approx(mid, expected, 0.001, "consecutive sweep segments do not double-apply")
	# Rings likewise.
	var r := 0.0
	while r < 20.0:
		cov3.apply_ring(100, 100, r, r + 1.7, 0.5)
		r += 1.7
	var at := cov3.get_coverage(110.0, 100.0)
	t.approx(at, 0.5 * cov3.exposure[cov3.cell_index(110.0, 100.0)], 0.001, "expanding ring hits each cell once")

	# Large-storm row interleaving deposits the same total as a single pass.
	var c4 := SnowCoverage.new()
	c4.setup(terrain)
	var c5 := SnowCoverage.new()
	c5.setup(terrain)
	# Four ticks of a full update vs four ticks of 1/4-row updates at 4x strength.
	for ph in 4:
		c4.apply_disc(-60, -20, 30.0, 0.05)
		c5.apply_disc(-60, -20, 30.0, 0.05, 4, ph)
	t.approx(c4.total_sum, c5.total_sum, 0.5, "interleaved large-storm updates match full updates")

	# Searches.
	# Drifting snow seals narrow gaps between passes but never eats open ground.
	var dr := SnowCoverage.new()
	dr.setup(terrain)
	# Two passes leaving a 2 m gap (rows 64-65) and, further on, a 5 m gap.
	dr.apply_sweep(-40, 60, 40, 60, 4.0, 1.0, 1.0)
	dr.apply_sweep(-40, 70, 40, 70, 4.0, 1.0, 1.0)
	dr.apply_sweep(-40, 83, 40, 83, 4.0, 1.0, 1.0)
	var narrow := dr.get_coverage(0, 64.5)
	var wide := dr.get_coverage(0, 76.5)
	for k in 8:
		dr.drift_fill(256)
	t.check(narrow == 0.0 and dr.get_coverage(0, 64.5) == 1.0 and dr.get_coverage(0, 65.5) == 1.0,
		"a 2 m gap between two passes seals itself")
	t.check(wide == 0.0 and dr.get_coverage(0, 76.5) == 0.0, "a 5 m gap is left for you to fly over")
	t.check(dr.get_coverage(0, 90.0) == 0.0 and dr.get_coverage(0, 54.0) == 0.0, "open green ground beside a pass stays green")
	_consistency(t, dr, "after drift fill")
	# Deep Freeze bridges wider gaps.
	dr.gap_reach = 4
	dr.fill_dirty.fill(1)
	for k in 12:
		dr.drift_fill(256)
	t.check(dr.get_coverage(0, 76.5) == 1.0, "Deep Freeze seals a 5 m gap too")
	t.check(dr.get_coverage(0, 92.0) == 0.0, "even Deep Freeze leaves open ground alone")
	# Spreading Frost creeps from frozen land, never in from the sea.
	var sp := SnowCoverage.new()
	sp.setup(terrain)
	var left0 := sp.total_incomplete
	sp.spread_tick(200)
	t.check(sp.total_incomplete == left0, "spreading frost never starts from the open sea")
	sp.apply_disc(0, 60, 6.0, 1.0)
	var left1 := sp.total_incomplete
	sp.spread_tick(30)
	t.check(left1 - sp.total_incomplete == 30, "spreading frost freezes exactly as many cells as asked (%d)" % (left1 - sp.total_incomplete))
	t.check(sp.get_coverage(0, 75.0) == 0.0, "spreading frost only touches ground next to frozen ground")
	_consistency(t, sp, "after spreading")
	# A pass at full strength leaves no half-frozen ground at its edges.
	var edge := SnowCoverage.new()
	edge.setup(terrain)
	edge.apply_sweep(-40, 60, 40, 60, 4.0, 1.0, 1.0)
	var partial := 0
	for z in range(50, 71):
		var v := edge.get_coverage(0, z + 0.5)
		if v > 0.0 and v < 1.0:
			partial += 1
	t.check(partial == 0, "a pass leaves either frozen or untouched ground, nothing in between")

	var cov6 := SnowCoverage.new()
	cov6.setup(terrain)
	for k in 3:
		cov6.apply_disc(0, 0, 400.0, 1.0)   # freeze (almost) everything
	t.check(cov6.world_completion() > 0.98, "huge disc freezes most of the world")
	var hole := Vector2(-150, 40)
	t.check(cov6.world_completion() <= 1.0, "completion never exceeds 100%")
	var nearest := cov6.find_nearest_unfrozen_area(hole + Vector2(5, 5), 1.0e9, 1)
	if cov6.total_incomplete > 0:
		t.check(nearest != Vector2.INF, "unfrozen search finds remaining corners")
		t.check(cov6.get_unfrozen_cells_in_area(Rect2(nearest - Vector2(16, 16), Vector2(32, 32))) > 0, "search result lies on unfrozen ground")
	var all := SnowCoverage.new()
	all.setup(terrain)
	all.freeze_all()
	t.check(all.find_nearest_unfrozen_area(Vector2.ZERO) == Vector2.INF, "no target when everything is frozen")
	t.check(all.is_world_complete(), "fully frozen world is complete")
	_consistency(t, all, "after freeze_all")

	# Completion tolerance: a visible patch blocks completion, specks do not.
	var almost := SnowCoverage.new()
	almost.setup(terrain)
	almost.freeze_all()
	for i in [130000, 140000, 150000]:
		almost.cov[i] = 0.0
	almost.deserialize(almost.serialize())
	t.check(almost.is_world_complete(), "three isolated specks do not block completion")
	almost.cov.fill(1.0)
	for z in 6:
		for x in 6:
			almost.cov[(200 + z) * SnowCoverage.N + 200 + x] = 0.0
	almost.deserialize(almost.serialize())
	t.check(not almost.is_world_complete(), "a 6x6 m green patch still blocks completion")
	# Cleanup only removes isolated holes.
	almost.cov.fill(1.0)
	almost.cov[300 * SnowCoverage.N + 300] = 0.2
	almost.deserialize(almost.serialize())
	almost.cleanup_pass()
	t.check(almost.cov[300 * SnowCoverage.N + 300] == 1.0, "cleanup fills a single isolated hole")

	# Water: ice creeps from frozen water to neighbouring water only.
	var w := SnowCoverage.new()
	w.setup(terrain)
	var lake_idx := -1
	for k in w.water_cells:
		var x := k % SnowCoverage.N
		var z := k / SnowCoverage.N
		if w.water[k - 1] == 1 and w.water[k + 1] == 1 and absf(x - 256 - TerrainData.LAKE_CENTER.x) < 10 and absf(z - 256 - TerrainData.LAKE_CENTER.y) < 10:
			lake_idx = k
			break
	t.check(lake_idx >= 0, "found a lake cell")
	if lake_idx >= 0:
		w.cov[lake_idx] = 1.0
		w.deserialize(w.serialize())
		var g := 0.0
		for k in 20:
			g += w.water_spread_tick(0.5, 0.5)
		t.check(w.cov[lake_idx + 1] > 0.5, "ice creeps into neighbouring water")
		t.check(g > 0.0, "ice creep earns Frost")
		var land_frozen := 0
		for i in SnowCoverage.N * SnowCoverage.N:
			if w.water[i] == 0 and w.cov[i] > 0.0 and not w.is_void(i):
				land_frozen += 1
		t.check(land_frozen == 0, "ice creep never touches land")

	# Texture encoding covers dirty chunks.
	var tx := SnowCoverage.new()
	tx.setup(terrain)
	tx.create_texture()
	tx.update_texture()
	tx.apply_disc(10, 10, 3.0, 1.0)
	t.check(tx.any_dirty, "edits mark chunks dirty")
	tx.update_texture()
	t.check(tx.tex_bytes[tx.cell_index(10, 10)] == 255, "texture byte matches frozen cell")
	t.check(not tx.any_dirty, "upload clears dirty flags")
	# Sea texels follow the land beside them: no snow at a green waterline,
	# snow right to the water once the beach is frozen.
	var shore := Vector2.INF
	for k in 256:
		if tx.is_void(tx.cell_index(-40.0, 0.5 + k)):
			shore = Vector2(-40.0, 0.5 + k + 1.0)
			break
	t.check(shore != Vector2.INF, "test world has a shore south of the meadows")
	t.check(tx.tex_bytes[tx.cell_index(shore.x, shore.y)] == 0, "a green beach shows no snow at the waterline")
	tx.apply_disc(shore.x, shore.y - 4.0, 6.0, 1.0)
	tx.update_texture()
	t.check(tx.tex_bytes[tx.cell_index(shore.x, shore.y)] > 200, "a frozen beach is snowy right to the waterline")
	t.check(tx.tex_bytes[tx.cell_index(250, 250)] == 0, "the open sea itself reads as no snow")


func _consistency(t, cov: SnowCoverage, label: String) -> void:
	var rs := PackedFloat64Array()
	rs.resize(SnowCoverage.REGION_COUNT)
	var total := 0.0
	var inc := 0
	var chunk := PackedInt32Array()
	chunk.resize(SnowCoverage.CH * SnowCoverage.CH)
	for i in SnowCoverage.N * SnowCoverage.N:
		if cov.is_void(i):
			continue
		var c := cov.cov[i]
		rs[cov.region[i]] += c
		total += c
		if c < 1.0:
			inc += 1
			chunk[((i / SnowCoverage.N) / SnowCoverage.CS) * SnowCoverage.CH + (i % SnowCoverage.N) / SnowCoverage.CS] += 1
	t.approx(cov.total_sum, total, 0.05, "total sum matches recount " + label)
	for r in SnowCoverage.REGION_COUNT:
		t.approx(cov.region_sum[r], rs[r], 0.05, "region %d sum matches recount %s" % [r, label])
	t.check(cov.total_incomplete == inc, "incomplete count matches recount %s (%d vs %d)" % [label, cov.total_incomplete, inc])
	t.check(cov.chunk_incomplete == chunk, "chunk counters match recount " + label)
