class_name TestPerformance
extends RefCounted
## Measures simulation cost with an extreme late-game storm load (no
## rendering). The budget leaves ample frame time at 60 FPS because each
## effect only steps on one of every three 30 Hz ticks.


func run(t, _full: bool) -> void:
	var terrain: TerrainData = t.shared_terrain()
	var cov := SnowCoverage.new()
	cov.setup(terrain)
	# Raw coverage throughput.
	var t0 := Time.get_ticks_usec()
	var cells := 0
	for k in 20:
		cov.apply_disc(-50 + k * 5, 0, 40.0, 0.01)
		cells += int(PI * 1600.0)
	var us := Time.get_ticks_usec() - t0
	var mcells := float(cells) / us
	print("    coverage throughput: %.2f M cells/s" % mcells)
	t.check(mcells > 1.0, "coverage update throughput is sufficient")
	# Fully frozen chunks are skipped.
	var frozen := SnowCoverage.new()
	frozen.setup(terrain)
	frozen.freeze_all()
	t0 = Time.get_ticks_usec()
	for k in 50:
		frozen.apply_disc(0, 0, 90.0, 0.2)
	var frozen_us := (Time.get_ticks_usec() - t0) / 50.0
	print("    huge storm over frozen land: %.3f ms" % (frozen_us / 1000.0))
	t.check(frozen_us < 500.0, "frozen chunks are skipped rather than rescanned")

	# A worst-case storm stack running for a while.
	var prog := Progression.new()
	prog.add_frost(1.0e12)
	prog.add_cores(100)
	TestStormInteractions.buy_everything(prog)
	var w := WeatherManager.new()
	(t as Node).add_child(w)
	w.setup(terrain, cov, prog, false, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 40:
		var c := SnowCloud.new()
		c.init_from_stats(prog)
		c.pos = Vector2(rng.randf_range(-240, 240), rng.randf_range(-240, 240))
		w.spawn(c)
	for k in 4:
		var b := Blizzard.new()
		b.init_from_stats(prog)
		b.pos = Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		w.spawn(b)
	for k in 2:
		var v := PolarVortex.new()
		v.init_from_stats(prog)
		v.pos = Vector2(-120 + k * 240, 0)
		w.spawn(v)
	for k in 6:
		var f := FrostFront.new()
		f.init_from_stats(prog)
		f.pos = Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		f.dir = Vector2.from_angle(rng.randf() * TAU)
		w.spawn(f)
	for k in 3:
		var g := ArcticWind.new()
		g.init_from_stats(prog)
		g.origin = Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		g.dir = Vector2.from_angle(rng.randf() * TAU)
		w.spawn(g)
	var worst := 0
	var total := 0
	var steps := 0
	var sim_seconds := 20.0
	var frames := int(sim_seconds * 60.0)
	for i in frames:
		var s := Time.get_ticks_usec()
		w.advance(1.0 / 60.0)
		var d := Time.get_ticks_usec() - s
		worst = maxi(worst, d)
		total += d
		steps += 1
	var avg_ms := total / float(steps) / 1000.0
	print("    extreme storm load (%d effects): avg %.2f ms/frame, worst %.2f ms" % [w.effects.size(), avg_ms, worst / 1000.0])
	t.check(avg_ms < 6.0, "average simulation cost per frame stays within budget (%.2f ms)" % avg_ms)
	t.check(worst / 1000.0 < 25.0, "no single frame spikes badly (%.2f ms)" % (worst / 1000.0))
	t.check(w.effects.size() < GameBalance.MAX_CLOUDS + 40, "effect count stays bounded")
	# Particle density is purely visual.
	var cov_a := SnowCoverage.new()
	cov_a.setup(terrain)
	var cov_b := SnowCoverage.new()
	cov_b.setup(terrain)
	var results: Array[float] = []
	for density in [0.2, 1.5]:
		WeatherFX.particle_density = density
		var cv := cov_a if density < 1.0 else cov_b
		var p2 := Progression.new()
		var w2 := WeatherManager.new()
		(t as Node).add_child(w2)
		w2.setup(terrain, cv, p2, false, 11)
		var c2 := SnowCloud.new()
		c2.init_from_stats(p2)
		c2.pos = Vector2(10, 10)
		w2.spawn(c2)
		for i in 60:
			w2.advance(0.1)
		results.append(cv.total_sum)
		w2.queue_free()
	WeatherFX.particle_density = 1.0
	t.check(results[0] == results[1], "particle density does not change snowfall")
	w.queue_free()
