class_name TestPerformance
extends RefCounted
## Measures simulation cost with an extreme late-game load (no rendering).
## The budget leaves ample frame time at 60 FPS: storms step on one of every
## three 30 Hz ticks and very large discs update interleaved rows.


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

	# A worst-case late game: maxed cloud in Vortex Form with every skill and
	# keystone firing, a full flock of wandering cloudlets and a long wake.
	var prog := Progression.new()
	prog.add_frost(1.0e12)
	prog.world_fraction = 1.0
	TestEconomy.buy_everything(prog)
	var w := WeatherManager.new()
	(t as Node).add_child(w)
	w.setup(terrain, cov, prog, false, 5)
	var c := w.spawn_player_cloud(Vector2(0, 40))
	w.use_skill("vortex_form", Vector2.UP)
	var worst := 0
	var total := 0
	var steps := 0
	var frames := int(20.0 * 60.0)
	var peak := 0
	for i in frames:
		c.move_input = Vector2.from_angle(i * 0.004)
		if i % 30 == 0:
			w.cooldowns["squall"] = 0.0
			w.cooldowns["frost_wave"] = 0.0
			w.use_skill("squall", Vector2.UP)
			w.use_skill("frost_wave", c.move_input)
		var s := Time.get_ticks_usec()
		w.advance(1.0 / 60.0)
		var d := Time.get_ticks_usec() - s
		worst = maxi(worst, d)
		total += d
		steps += 1
		peak = maxi(peak, w.effects.size())
	var avg_ms := total / float(steps) / 1000.0
	print("    extreme late game (peak %d effects, r=%.0f m): avg %.2f ms/frame, worst %.2f ms" % [peak, c.radius, avg_ms, worst / 1000.0])
	t.check(avg_ms < 6.0, "average simulation cost per frame stays within budget (%.2f ms)" % avg_ms)
	t.check(worst / 1000.0 < 25.0, "no single frame spikes badly (%.2f ms)" % (worst / 1000.0))
	t.check(peak < GameBalance.MAX_CLOUDS + GameBalance.MAX_FRONTS + GameBalance.MAX_PULSES + 10, "effect count stays bounded (%d)" % peak)
	# Particle density is purely visual.
	var results: Array[float] = []
	for density in [0.2, 1.5]:
		WeatherFX.particle_density = density
		var cv := SnowCoverage.new()
		cv.setup(terrain)
		var p2 := Progression.new()
		var w2 := WeatherManager.new()
		(t as Node).add_child(w2)
		w2.setup(terrain, cv, p2, false, 11)
		w2.spawn_player_cloud(Vector2(10, 10)).move_input = Vector2(0.6, 0.2)
		for i in 60:
			w2.advance(0.1)
		results.append(cv.total_sum)
		w2.queue_free()
	WeatherFX.particle_density = 1.0
	t.check(results[0] == results[1], "particle density does not change snowfall")
	w.queue_free()
