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
	# Build some state: partial coverage, purchases, milestones.
	prog.add_frost(cov.apply_disc(0, 60, 50.0, 1.0))
	prog.add_frost(cov.apply_disc(0, 60, 50.0, 1.0))
	cov.apply_disc(-150, 0, 60.0, 0.37)
	cov.apply_disc(140, -5, 50.0, 1.0)
	cov.apply_disc(-80, 120, 40.0, 1.0)
	cov.apply_disc(-80, 120, 40.0, 1.0)
	prog.world_fraction = cov.world_completion()
	regions.check(cov, prog)
	prog.add_frost(5000)
	prog.purchase("billow")
	prog.purchase("billow")
	prog.purchase("flurry")
	prog.purchase("squall")
	prog.stats["time"] = 1234.5
	var frost_before := prog.frost
	var claimed_before := prog.claimed_world_milestones.duplicate()
	var region_claims := regions.to_array()
	t.check(not claimed_before.is_empty(), "world milestones claimed before saving (%.1f%% frozen)" % (cov.world_completion() * 100.0))
	var weather := [{"kind": "player_cloud", "pos": [5, 6], "vel": [0, 0], "radius": 3.0, "rate": 0.5, "life": 5.0, "age": 1.0, "gen": 0}]
	var data := SaveManager.build(1337, prog, regions, cov, {"yaw": 0.5, "pitch": -0.6, "zoom": 1.2}, weather)
	t.check(SaveManager.write(data, PATH), "save file written")
	t.check(FileAccess.file_exists(PATH), "save file exists")
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
	var regain := 0
	for i in SnowCoverage.N * SnowCoverage.N:
		max_diff = maxf(max_diff, absf(cov2.cov[i] - cov.cov[i]))
		if cov2.cov[i] < cov.cov[i]:
			regain += 1
	t.check(max_diff < 0.0001, "coverage identical after reload (max diff %f)" % max_diff)
	t.approx(cov2.world_completion(), cov.world_completion(), 0.00001, "completion identical after reload")
	t.check(cov2.chunk_incomplete == cov.chunk_incomplete, "chunk bookkeeping rebuilt on load")
	t.check(regain == 0, "reloaded cells are never less frozen than saved")

	var prog2 := Progression.new()
	prog2.from_dict(d["progression"])
	t.approx(prog2.frost, frost_before, 0.001, "Frost persists")
	t.check(prog2.level("billow") == 2 and prog2.level("flurry") == 1, "purchased nodes persist")
	t.check(prog2.has("squall") and "squall" in prog2.unlocked_skills(), "bought skills persist")
	t.approx(prog2.stat("radius"), prog.stat("radius"), 0.0001, "stats rebuild from levels")
	t.approx(float(prog2.stats["time"]), 1234.5, 0.001, "statistics persist")
	var regions2 := RegionTracker.new()
	regions2.from_array(d["regions"])
	t.check(regions2.to_array() == region_claims, "region milestone claims persist")
	t.check(prog2.claimed_world_milestones == claimed_before, "world milestone claims persist")
	prog2.world_fraction = cov2.world_completion()
	regions2.check(cov2, prog2)
	t.approx(prog2.frost, frost_before, 0.001, "re-checking milestones after load pays nothing")
	t.check((d["weather"] as Array).size() == 1, "the cloud is saved")
	t.check((d["player"] as Dictionary).has("yaw"), "camera state is saved")
	# Unknown or over-max node levels from a tampered save are clamped.
	var bad: Dictionary = d["progression"].duplicate(true)
	bad["levels"]["billow"] = 99
	bad["levels"]["not_a_node"] = 3
	var prog_bad := Progression.new()
	prog_bad.from_dict(bad)
	t.check(prog_bad.level("billow") == int(GameBalance.NODES["billow"]["max"]) and not prog_bad.levels.has("not_a_node"), "bad levels are sanitised")
	# Saves from before the cloud redesign are refused rather than misread.
	var old := data.duplicate(true)
	old["version"] = 1
	SaveManager.write(old, PATH + "_old")
	t.check(SaveManager.read(PATH + "_old").is_empty(), "version 1 saves are not loaded")
	SaveManager.delete_save(PATH + "_old")
	# Completed state persists.
	prog2.completed = true
	SaveManager.write(SaveManager.build(1337, prog2, regions2, cov2, {}, []), PATH)
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
