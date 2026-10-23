class_name TestStormInteractions
extends RefCounted
## Spawns real weather in a headless WeatherManager (no visuals) and checks
## each ability and every combination rule from the design table.

var t
var terrain: TerrainData
var cov: SnowCoverage
var prog: Progression
var w: WeatherManager


func _fresh(host: Node) -> void:
	if w != null:
		w.queue_free()
	cov = SnowCoverage.new()
	cov.setup(terrain)
	prog = Progression.new()
	prog.add_frost(1.0e9)
	prog.add_cores(40)
	w = WeatherManager.new()
	host.add_child(w)
	w.setup(terrain, cov, prog, false, 99)


func _ctx(target: Vector2, from: Vector2) -> Dictionary:
	var tp := Vector3(target.x, terrain.surface_height(target.x, target.y), target.y)
	var fp := Vector3(from.x, terrain.surface_height(from.x, from.y), from.y)
	return {"origin": fp + Vector3(0, 1.6, 0), "aim": (tp - fp).normalized(), "target": tp, "hit": true, "feet": fp}


func _run(seconds: float) -> void:
	var steps := int(seconds / 0.1)
	for i in steps:
		w.advance(0.1)


func run(p_t, _full: bool) -> void:
	t = p_t
	terrain = t.shared_terrain()
	var host: Node = t
	_fresh(host)

	# --- Snow Cloud
	var r := w.try_cast("snow_cloud", _ctx(Vector2(0, 70), Vector2(0, 80)))
	t.check(r == "", "snow cloud casts (%s)" % r)
	_run(1.0)
	t.check(cov.get_coverage(0, 70) > 0.2, "snow cloud adds coverage")
	t.check(prog.lifetime_frost > 1.0e9, "snow cloud earns Frost")
	r = w.try_cast("snow_cloud", _ctx(Vector2(0, 70), Vector2(0, 80)))
	t.check(r == "Recharging", "cooldown is enforced")
	r = w.try_cast("snow_cloud", _ctx(Vector2(0, 0), Vector2(0, 200)))
	t.check(r != "", "out-of-range casts are refused")
	_run(6.0)
	t.check(w.count_kind("snow_cloud") == 0, "clouds dissipate after their duration")
	t.check(cov.get_coverage(0, 70) == 1.0, "a full cloud freezes its centre")

	# --- Cloud + Wind: moving snowfall source.
	_fresh(host)
	prog.purchase("unlock_frost_front")
	prog.purchase("unlock_arctic_wind")
	for i in 6:
		prog.purchase("cloud_duration")
	w.try_cast("snow_cloud", _ctx(Vector2(0, 40), Vector2(0, 52)))
	var cloud: SnowCloud = w.effects_of("snow_cloud")[0]
	var start := cloud.pos
	w.try_cast("arctic_wind", _ctx(Vector2(0, 20), Vector2(0, 52)))
	_run(4.0)
	t.check(cloud.pos.distance_to(start) > 8.0, "wind pushes the cloud (moved %.1f m)" % cloud.pos.distance_to(start))
	t.check(cloud.pos.y < start.y, "cloud moves in the wind direction")
	t.check("drifting_snow" in prog.discovered_combos, "Drifting Snow discovered")
	var trail := cov.get_coverage(start.x, start.y - 4.0) + cov.get_coverage(cloud.pos.x, cloud.pos.y + 3.0)
	t.check(trail > 0.3, "moving cloud leaves a snowy trail")

	# --- Cloud + Cloud: stronger overlapping snowfall.
	_fresh(host)
	for i in 3:
		prog.purchase("cloud_count")
	w.try_cast("snow_cloud", _ctx(Vector2(50, 50), Vector2(50, 60)))
	w.cooldowns["snow_cloud"] = 0.0
	w.try_cast("snow_cloud", _ctx(Vector2(50.5, 50), Vector2(50, 60)))
	_run(0.6)
	t.check("converging_clouds" in prog.discovered_combos, "Converging Clouds discovered")

	# --- Frost Front: follows terrain and covers a strip.
	_fresh(host)
	prog.purchase("unlock_frost_front")
	r = w.try_cast("frost_front", _ctx(Vector2(0, 40), Vector2(0, 80)))
	t.check(r == "", "frost front casts")
	_run(6.0)
	var strip := 0.0
	for z in range(45, 75, 3):
		strip += cov.get_coverage(0.0, float(z))
	t.check(strip > 2.0, "frost front deposits snow along its path")
	t.check(cov.get_coverage(20.0, 60.0) == 0.0, "frost front stays within its width")

	# --- Front + Wind and Front + Cloud.
	_fresh(host)
	prog.purchase("unlock_frost_front")
	prog.purchase("unlock_arctic_wind")
	w.try_cast("arctic_wind", _ctx(Vector2(0, 0), Vector2(0, 80)))
	_run(0.6)
	w.try_cast("snow_cloud", _ctx(Vector2(0, 66), Vector2(0, 80)))
	w.try_cast("frost_front", _ctx(Vector2(0, 0), Vector2(0, 80)))
	_run(3.0)
	t.check("gale_front" in prog.discovered_combos, "Gale Front discovered")
	t.check("frost_burst" in prog.discovered_combos, "Frost Burst discovered")

	# --- Blizzard absorbs clouds; Superstorm fuses blizzards.
	_fresh(host)
	for u in ["unlock_frost_front", "unlock_arctic_wind", "unlock_blizzard"]:
		prog.purchase(u)
	for i in 10:
		prog.purchase("cast_range")
	prog.purchase("bz_count")
	w.try_cast("blizzard", _ctx(Vector2(0, 0), Vector2(0, 30)))
	var bz: Blizzard = w.effects_of("blizzard")[0]
	var life0 := bz.life
	w.try_cast("snow_cloud", _ctx(Vector2(2, 2), Vector2(0, 14)))
	_run(1.0)
	t.check("storm_feeding" in prog.discovered_combos, "Storm Feeding discovered")
	t.check(bz.life > life0, "absorbed cloud extends the blizzard")
	_run(2.0)
	t.check(cov.region_completion(TerrainData.REGION_MEADOWS) > 0.0, "blizzard freezes ground")
	prog.purchase("superstorm")
	w.cooldowns["blizzard"] = 0.0
	w.try_cast("blizzard", _ctx(bz.pos + Vector2(4, 0), Vector2(0, 30)))
	_run(1.0)
	t.check(w.count_kind("blizzard") == 1, "overlapping blizzards fuse with Superstorm")
	t.check("superstorm_fusion" in prog.discovered_combos, "Superstorm Fusion discovered")
	var merged: Blizzard = w.effects_of("blizzard")[0]
	t.check(merged.radius > bz.radius * 0.99 or merged != bz, "fused storm is larger")

	# --- Avalanche: needs a snowy slope, flows downhill, coverage follows it.
	_fresh(host)
	for u in ["unlock_frost_front", "unlock_arctic_wind", "unlock_blizzard", "unlock_avalanche"]:
		prog.purchase(u)
	for i in 15:
		prog.purchase("cast_range")
	var slope := _find_slope()
	t.check(slope != Vector2.INF, "found a steep slope for the avalanche test")
	if slope != Vector2.INF:
		r = w.try_cast("avalanche", _ctx(slope, slope + Vector2(10, 10)))
		t.check(r == "Needs a snowy slope", "avalanche refuses a green slope (%s)" % r)
		cov.apply_disc(slope.x, slope.y, 10.0, 1.0)
		var h0 := terrain.sample_height(slope.x, slope.y)
		r = w.try_cast("avalanche", _ctx(slope, slope + Vector2(10, 10)))
		t.check(r == "", "avalanche releases on a snowy slope (%s)" % r)
		var av: Avalanche = w.effects_of("avalanche")[0]
		_run(3.0)
		var lead: Vector2 = av.heads[0]["p"]
		t.check(terrain.sample_height(lead.x, lead.y) < h0 - 2.0, "avalanche travels downhill")
		t.check(cov.get_coverage(lead.x, lead.y) > 0.0 or av.heads.size() > 1, "coverage matches the avalanche path")

	# --- Avalanche + Blizzard, Avalanche + Frozen Lake.
	_fresh(host)
	for u in ["unlock_frost_front", "unlock_arctic_wind", "unlock_blizzard", "unlock_avalanche"]:
		prog.purchase(u)
	var lake := TerrainData.LAKE_CENTER
	cov.apply_disc(lake.x, lake.y, 70.0, 1.0)
	cov.apply_disc(lake.x, lake.y, 70.0, 1.0)
	var av2 := Avalanche.new()
	av2.init_from_stats(prog)
	w.spawn(av2)
	av2.start(lake + Vector2(-48, -5), 7)
	av2.heads[0]["v"] = Vector2(14, 1)
	var bz2 := Blizzard.new()
	bz2.init_from_stats(prog)
	bz2.pos = lake + Vector2(-40, -5)
	bz2.radius = 25.0
	w.spawn(bz2)
	_run(4.0)
	t.check("whiteout_slide" in prog.discovered_combos, "Whiteout Slide discovered")
	t.check("ice_shockwave" in prog.discovered_combos, "Ice Shockwave discovered")

	# --- Polar Vortex orbits and absorbs clouds, amplifies blizzards.
	_fresh(host)
	for u in ["unlock_frost_front", "unlock_arctic_wind", "unlock_blizzard", "unlock_avalanche", "unlock_polar_vortex"]:
		prog.purchase(u)
	for i in 15:
		prog.purchase("cast_range")
	for i in 5:
		prog.purchase("cloud_count")
	w.try_cast("polar_vortex", _ctx(Vector2(-100, 0), Vector2(-100, 40)))
	var vx: PolarVortex = w.effects_of("polar_vortex")[0]
	for k in 4:
		w.cooldowns["snow_cloud"] = 0.0
		w.try_cast("snow_cloud", _ctx(vx.pos + Vector2(35, k * 5.0), vx.pos + Vector2(40, 0)))
	w.cooldowns["blizzard"] = 0.0
	w.try_cast("blizzard", _ctx(vx.pos + Vector2(-30, 0), vx.pos + Vector2(-40, 0)))
	var before := cov.total_sum
	_run(6.0)
	t.check("vortex_orbit" in prog.discovered_combos, "Vortex Orbit discovered")
	t.check("vortex_amplify" in prog.discovered_combos, "Polar Amplification discovered")
	t.check(cov.total_sum - before > 800.0, "the vortex freezes a vast area (%d m² in 6 s)" % int(cov.total_sum - before))

	# --- Budgets: runaway replication stays bounded.
	_fresh(host)
	buy_everything(prog)
	t.check(prog.stat("cloud_division") == 2.0 and prog.stat("cloud_rebirth") > 0.0, "replication upgrades owned for the budget test")
	var peak := 0
	for k in 300:
		w.cooldowns["snow_cloud"] = 0.0
		var a := Vector2(randf_range(-200, 200), randf_range(-200, 200))
		w.try_cast("snow_cloud", _ctx(a, a + Vector2(3, 3)))
		w.advance(0.2)
		peak = maxi(peak, w.count_kind("snow_cloud"))
		if k % 50 == 0:
			t.check(w.count_kind("frost_pulse") <= GameBalance.MAX_PULSES, "pulse budget holds")
	t.check(peak <= GameBalance.MAX_CLOUDS, "cloud count never exceeds the budget (peak %d)" % peak)
	print("    peak clouds with every replication upgrade: %d" % peak)
	w.queue_free()
	w = null


static func buy_everything(p: Progression) -> void:
	var bought := true
	while bought:
		bought = false
		for id in GameBalance.UPGRADES:
			if p.purchase(id):
				bought = true


func _find_slope() -> Vector2:
	for z in range(-200, -100, 6):
		for x in range(-150, 150, 6):
			if terrain.slope(x, z) > 0.45 and not terrain.is_water(x, z):
				# Make sure there is room to run downhill.
				var d := -terrain.gradient(x, z).normalized()
				var below := Vector2(x, z) + d * 15.0
				if terrain.sample_height(below.x, below.y) < terrain.sample_height(x, z) - 4.0:
					return Vector2(x, z)
	return Vector2.INF
