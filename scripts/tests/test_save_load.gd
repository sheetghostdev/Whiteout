class_name TestSaveLoad
extends RefCounted
## Round-trips a save file and checks nothing is lost or re-awarded.

const PATH := "user://test_whiteout_save.json"


func run(t, _full: bool) -> void:
	var terrain: TerrainData = t.shared_terrain()
	var cov := SnowCoverage.new()
	cov.setup(terrain)
	var prog := Progression.new()
	var regions := RegionTracker.new()
	# Build some state: partial coverage, purchases, milestones, discoveries.
	prog.add_frost(cov.apply_disc(0, 60, 30.0, 1.0))
	cov.apply_disc(-150, 0, 60.0, 0.37)
	cov.apply_disc(140, -5, 50.0, 1.0)
	regions.check(cov, prog)
	prog.add_frost(5000)
	prog.purchase("cloud_radius")
	prog.purchase("cloud_radius")
	prog.purchase("cloud_rate")
	prog.discovered_combos.append("drifting_snow")
	prog.stats["time"] = 1234.5
	var frost_before := prog.frost
	var cores_before := prog.cores
	var claimed_before := prog.claimed_world_milestones.duplicate()
	var region_claims := regions.to_array()
	t.check(cores_before > 0, "milestones awarded cores before saving")
	var data := SaveManager.build(1337, prog, regions, cov, {"pos": [1, 2, 3], "yaw": 0.5, "pitch": 0.1}, [
		{"kind": "snow_cloud", "pos": [5, 6], "vel": [0, 0], "radius": 3.0, "rate": 0.5, "life": 5.0, "age": 1.0, "gen": 0}])
	t.check(SaveManager.write(data, PATH), "save file written")
	t.check(FileAccess.file_exists(PATH), "save file exists")
	# Second write keeps a backup and replaces atomically.
	t.check(SaveManager.write(data, PATH), "second save written")
	t.check(FileAccess.file_exists(PATH + ".bak"), "previous save kept as backup")
	t.check(not FileAccess.file_exists(PATH + ".tmp"), "no temp file left behind")

	var d := SaveManager.read(PATH)
	t.check(not d.is_empty(), "save file reads back")
	t.check(int(d["version"]) == SaveManager.VERSION, "save is versioned")
	var cov2 := SnowCoverage.new()
	cov2.setup(terrain)
	t.check(SaveManager.restore_coverage(d, cov2), "coverage restores")
	var max_diff := 0.0
	for i in SnowCoverage.N * SnowCoverage.N:
		max_diff = maxf(max_diff, absf(cov2.cov[i] - cov.cov[i]))
	t.check(max_diff < 0.0001, "coverage identical after reload (max diff %f)" % max_diff)
	t.approx(cov2.world_completion(), cov.world_completion(), 0.00001, "completion identical after reload")
	t.check(cov2.chunk_incomplete == cov.chunk_incomplete, "chunk bookkeeping rebuilt on load")
	# Reloaded coverage never pays out again: quantisation rounds up.
	var regain := 0.0
	for i in SnowCoverage.N * SnowCoverage.N:
		if cov2.cov[i] < cov.cov[i]:
			regain += 1.0
	t.check(regain == 0.0, "reloaded cells are never less frozen than saved")

	var prog2 := Progression.new()
	prog2.from_dict(d["progression"])
	t.approx(prog2.frost, frost_before, 0.001, "Frost persists")
	t.check(prog2.cores == cores_before, "Winter Cores persist")
	t.check(prog2.level("cloud_radius") == 2 and prog2.level("cloud_rate") == 1, "purchased upgrades persist")
	t.check("drifting_snow" in prog2.discovered_combos, "discoveries persist")
	t.approx(float(prog2.stats["time"]), 1234.5, 0.001, "statistics persist")
	var regions2 := RegionTracker.new()
	regions2.from_array(d["regions"])
	t.check(regions2.to_array() == region_claims, "region milestone claims persist")
	t.check(prog2.claimed_world_milestones == claimed_before, "world milestone claims persist")
	# No duplicate rewards when milestones are re-checked after loading.
	regions2.check(cov2, prog2)
	t.approx(prog2.frost, frost_before, 0.001, "re-checking milestones after load pays nothing")
	t.check(prog2.cores == cores_before, "re-checking milestones after load grants no cores")
	t.check((d["weather"] as Array).size() == 1, "active weather is saved")
	t.check((d["player"] as Dictionary).has("yaw"), "player state is saved")
	# Completed state persists.
	prog2.completed = true
	var d2 := SaveManager.build(1337, prog2, regions2, cov2, {}, [])
	SaveManager.write(d2, PATH)
	var prog3 := Progression.new()
	prog3.from_dict(SaveManager.read(PATH)["progression"])
	t.check(prog3.completed, "world completion state persists")
	# Corrupt main file falls back to the backup.
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	t.check(not SaveManager.read(PATH).is_empty(), "corrupt save falls back to backup")
	SaveManager.delete_save(PATH)
	t.check(not FileAccess.file_exists(PATH), "save deleted")
