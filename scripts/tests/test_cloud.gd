class_name TestCloud
extends RefCounted
## The player cloud: steering, snowfall, keystones and skills, run headlessly
## on the real simulation.


func _world(t, prog: Progression) -> WeatherManager:
	var cov := SnowCoverage.new()
	cov.setup(t.shared_terrain())
	var w := WeatherManager.new()
	(t as Node).add_child(w)
	w.setup(t.shared_terrain(), cov, prog, false, 7)
	return w


func _run(w: WeatherManager, seconds: float) -> void:
	for i in int(seconds * 10.0):
		w.advance(0.1)


func run(t, _full: bool) -> void:
	_movement(t)
	_snowfall(t)
	_keystones(t)
	_skills(t)
	_companions(t)


func _movement(t) -> void:
	var prog := Progression.new()
	var w := _world(t, prog)
	var c := w.spawn_player_cloud(Vector2(0, 80))
	c.move_input = Vector2(1, 0)
	_run(w, 3.0)
	t.check(c.pos.x > prog.stat("speed") * 2.0 and absf(c.pos.y - 80.0) < 0.5, "cloud drifts where it is steered (%.1f m)" % c.pos.x)
	var slow := c.pos.x
	c.pos = Vector2(0, 80)
	c.vel = Vector2.ZERO
	prog.levels["breeze"] = 5
	_run(w, 3.0)
	t.check(c.pos.x > slow * 1.3, "speed upgrades make you fly faster")
	prog.levels.erase("breeze")
	c.move_input = Vector2.ZERO
	_run(w, 2.0)
	var still := c.pos
	_run(w, 1.0)
	t.check(c.pos.distance_to(still) < 0.2, "cloud stops when you let go")
	c.pos = Vector2(250, 250)
	c.move_input = Vector2(1, 1)
	_run(w, 2.0)
	t.check(absf(c.pos.x) < GameBalance.WORLD_HALF and absf(c.pos.y) < GameBalance.WORLD_HALF, "cloud stays inside the world")
	t.check(float(prog.stats["distance"]) > 0.0, "distance drifted is recorded")
	w.queue_free()


func _snowfall(t) -> void:
	var prog := Progression.new()
	var w := _world(t, prog)
	var c := w.spawn_player_cloud(Vector2(0, 80))
	var cov := w.cov
	_run(w, 5.0)
	t.check(cov.total_sum == 0.0 and prog.frost == 0.0, "hovering in place lays no snow and earns nothing")
	c.move_input = Vector2(1, 0)
	_run(w, 3.0)
	c.move_input = Vector2.ZERO
	_run(w, 3.0)
	var mid := Vector2(5.0, 80.0)
	t.check(cov.get_coverage(mid.x, mid.y) == 1.0, "one pass freezes the ground solid")
	var partial := 0
	for z in range(70, 91):
		var v := cov.get_coverage(mid.x, z + 0.5)
		if v > 0.0 and v < 1.0:
			partial += 1
	t.check(partial == 0, "a pass never leaves half-frozen ground")
	t.check(cov.get_coverage(mid.x, mid.y + c.snow_width() + 2.0) == 0.0, "snow only falls along the cloud's path")
	t.check(prog.frost > 0.0, "freezing earns Frost")
	var f0 := prog.frost
	_run(w, 4.0)
	t.check(prog.frost - f0 < 0.5, "resting earns nothing more")
	# Flying over ground that is already frozen pays nothing.
	c.move_input = Vector2.ZERO
	_run(w, 1.0)
	cov.apply_disc(-40, 80, 20.0, 1.0)
	cov.apply_disc(-40, 80, 20.0, 1.0)
	c.pos = Vector2(-50, 80)
	# Let drifting snow settle the edge of the painted patch first.
	for k in 20:
		cov.drift_fill(1024)
	_run(w, 0.5)
	var f1 := prog.frost
	c.move_input = Vector2(1, 0)
	_run(w, 2.0)
	t.check(prog.frost - f1 < 0.5, "frozen ground pays only once (%.2f)" % (prog.frost - f1))
	# Bigger and snowier clouds freeze more per pass.
	var prog2 := Progression.new()
	prog2.levels["billow"] = 5
	prog2.levels["flurry"] = 3
	var w2 := _world(t, prog2)
	var c2 := w2.spawn_player_cloud(Vector2(0, 80))
	c2.move_input = Vector2(1, 0)
	_run(w2, 3.0)
	var prog3 := Progression.new()
	var w3 := _world(t, prog3)
	var c3 := w3.spawn_player_cloud(Vector2(0, 80))
	c3.move_input = Vector2(1, 0)
	_run(w3, 3.0)
	t.check(w2.cov.total_sum > w3.cov.total_sum * 1.8, "upgrades make a clear difference (%.0f vs %.0f m²)" % [w2.cov.total_sum, w3.cov.total_sum])
	w.queue_free()
	w2.queue_free()
	w3.queue_free()


func _freeze_rate(t, levels: Dictionary, seconds: float = 8.0, throttle: float = 1.0, there_and_back: bool = false) -> float:
	var prog := Progression.new()
	for k in levels:
		prog.levels[k] = levels[k]
	var w := _world(t, prog)
	var c := w.spawn_player_cloud(Vector2(-60, 120))
	c.move_input = Vector2(throttle, 0)
	_run(w, seconds)
	if there_and_back:
		c.move_input = Vector2(-throttle, 0)
		_run(w, seconds)
	var v := w.cov.total_sum
	w.queue_free()
	return v


func _keystones(t) -> void:
	var base := {"billow": 5, "swell": 3, "flurry": 5, "heavy_snow": 3}
	# Deep Freeze lets drifting snow seal much wider gaps between passes.
	var pdf := Progression.new()
	var wdf := _world(t, pdf)
	wdf.spawn_player_cloud(Vector2(0, 0))
	pdf.levels["deep_freeze"] = 1
	_run(wdf, 0.6)
	t.check(wdf.cov.gap_reach > 2, "Deep Freeze widens the gaps drifting snow can seal")
	wdf.queue_free()
	# Tailwind: fast over frozen ground, normal speed over green.
	var pt := Progression.new()
	pt.levels["tailwind"] = 1
	var wt := _world(t, pt)
	var ct := wt.spawn_player_cloud(Vector2(0, 80))
	var v_green := ct.max_speed()
	wt.cov.apply_disc(0, 80, 6.0, 1.0)
	t.check(ct.max_speed() > v_green * 1.4 and v_green == pt.stat("speed"), "Tailwind speeds you over frozen ground only")
	wt.queue_free()
	var wake := base.duplicate()
	wake["snow_wake"] = 1
	var w_on := _freeze_rate(t, wake, 10.0)
	var w_off := _freeze_rate(t, base, 10.0)
	t.check(w_on > w_off * 1.1, "Snow Wake leaves snowing flurries behind (%.0f vs %.0f)" % [w_on, w_off])
	# Thunderhead is a big jump.
	var p := Progression.new()
	var r0 := p.stat("radius")
	p.levels["thunderhead"] = 1
	t.check(p.stat("radius") >= r0 + 2.5, "Thunderhead makes you vastly bigger")
	# Avalanche Rider releases on snowy slopes only.
	var prog := Progression.new()
	prog.levels["avalanche"] = 1
	var w := _world(t, prog)
	var terrain: TerrainData = t.shared_terrain()
	var slope := Vector2.INF
	for k in 4000:
		var q := Vector2(-200 + (k % 80) * 5.0, -230 + (k / 80) * 5.0)
		if terrain.gradient(q.x, q.y, 4.0).length() > 0.55 and terrain.sample_height(q.x, q.y) > 30.0 \
				and terrain.highland_mask(q.x, q.y) > 0.5 and not terrain.is_water(q.x, q.y) and terrain.coast_at(q.x, q.y) > 40.0:
			slope = q
			break
	t.check(slope != Vector2.INF, "test world has a mountainside")
	# Small hills in the meadows never set anything off.
	var hill := Vector2(-48, 128)
	w.cov.apply_disc(hill.x, hill.y, 20.0, 1.0)
	t.check(Avalanche.release_check(terrain, w.cov, hill) != "" and not w.try_ride_avalanche(hill), "no avalanches from small hills")
	w.cov.apply_disc(slope.x, slope.y, 6.0, 1.0)
	t.check(w.try_ride_avalanche(slope), "Avalanche Rider releases on a snowy slope")
	t.check(not w.try_ride_avalanche(slope), "Avalanche Rider then recharges")
	t.check(w.count_kind("avalanche") == 1, "an avalanche is running")
	_run(w, 6.0)
	t.check(float(w.area_by_source.get("avalanche", 0.0)) > 100.0, "the avalanche freezes ground downhill")
	var w2 := _world(t, Progression.new())
	t.check(not w2.try_ride_avalanche(slope), "no avalanches without the keystone")
	w.queue_free()
	w2.queue_free()


func _skills(t) -> void:
	var prog := Progression.new()
	var w := _world(t, prog)
	var c := w.spawn_player_cloud(Vector2(0, 80))
	t.check(w.use_skill("squall", Vector2.UP) != "", "skills need to be bought first")
	for id in GameBalance.SKILLS:
		prog.levels[id] = 1
	t.check(w.use_skill("squall", Vector2.UP) == "", "Squall fires")
	t.check(w.use_skill("squall", Vector2.UP) == "Recharging", "Squall then recharges")
	_run(w, 2.0)
	t.check(float(w.area_by_source.get("squall", 0.0)) > 25.0, "Squall freezes a ring of ground (%.0f m²)" % float(w.area_by_source.get("squall", 0.0)))
	t.check(w.use_skill("frost_wave", Vector2(1, 0)) == "", "Frost Wave fires")
	_run(w, 3.0)
	t.check(float(w.area_by_source.get("frost_wave", 0.0)) > 100.0, "Frost Wave freezes a strip ahead")
	prog.levels["splinter"] = 1
	w.cooldowns["frost_wave"] = 0.0
	w.use_skill("frost_wave", Vector2(-1, 0))
	_run(w, 4.0)
	t.check(int(prog.stats["longest_chain"]) >= 3, "Splintering Frost splits waves")
	var r0 := c.radius
	t.check(w.use_skill("vortex_form", Vector2.UP) == "", "Vortex Form fires")
	_run(w, 2.0)
	t.check(c.radius > r0 * 1.5, "Vortex Form swells the cloud (%.1f -> %.1f)" % [r0, c.radius])
	prog.levels["absolute_zero"] = 1
	_run(w, prog.stat("vortex_time") + 1.0)
	t.check(absf(c.radius - r0) < 0.1, "the vortex ends and the cloud returns to size")
	t.check(float(w.area_by_source.get("absolute_zero", 0.0)) > 0.0 or w.count_kind("frost_pulse") > 0, "Absolute Zero releases a frost ring")
	t.check(int(prog.stats["skills_used"]) >= 4, "skill uses are counted")
	w.queue_free()


func _companions(t) -> void:
	var prog := Progression.new()
	var w := _world(t, prog)
	var c := w.spawn_player_cloud(Vector2(0, 80))
	prog.levels["cloudlet"] = 1
	prog.levels["more_cloudlets"] = 2
	_run(w, 1.0)
	t.check(c.cloudlets.size() == 3, "cloudlets join the cloud (%d)" % c.cloudlets.size())
	c.move_input = Vector2(1, 0)
	_run(w, 5.0)
	var far := 0.0
	for k in c.cloudlets:
		far = maxf(far, k.pos.distance_to(c.pos))
	t.check(far < c.radius * 4.0 + 6.0, "cloudlets keep up with you (%.1f m)" % far)
	prog.levels["wanderers"] = 1
	for k in 8:
		c.move_input = Vector2(0.3 if k % 2 == 0 else -0.3, 0)
		_run(w, 1.0)
	c.move_input = Vector2.ZERO
	var spread := 0.0
	for k in c.cloudlets:
		spread = maxf(spread, k.pos.distance_to(c.pos))
	t.check(spread > c.radius * 1.5 and spread <= prog.stat("comp_leash") + c.radius + 4.0, "Wanderers roam to green ground within reach (%.1f m)" % spread)
	prog.levels.erase("more_cloudlets")
	_run(w, 1.0)
	t.check(c.cloudlets.size() == 1, "cloudlet count follows the stat")
	w.queue_free()
