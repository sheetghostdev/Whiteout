class_name PowerBench
extends RefCounted
## Controlled measurement of how strong an ability feels: with a given set of
## upgrade levels, cast it whenever it is ready onto fresh ground for a minute
## and report m² frozen per second. Snow Cloud is measured the same way, so a
## newly unlocked power can be compared with the cloud the player already has.

const DURATION := 120.0
const MEADOW := Vector2(-10.0, 40.0)


static func measure(host: Node, terrain: TerrainData, levels: Dictionary, id: String) -> float:
	var cov := SnowCoverage.new()
	cov.setup(terrain)
	var prog := Progression.new()
	prog.levels = levels.duplicate()
	prog.add_frost(1.0e12)
	var w := WeatherManager.new()
	host.add_child(w)
	w.setup(terrain, cov, prog, false, 17)
	var pos := MEADOW
	if id == "avalanche":
		# Snowy upper slopes above green valleys, as when a player first uses it.
		for z in range(-250, -60, 8):
			for x in range(-240, 240, 8):
				if terrain.sample_height(x, z) > 45.0:
					cov.apply_disc(x, z, 6.0, 1.0)
		pos = _snowline_spot(terrain, cov, prog.cast_range_for("avalanche") * 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var angle := 0.0
	var t := 0.0
	while t < DURATION:
		if w.cooldown_remaining(id) <= 0.0:
			var target := _target(w, terrain, cov, prog, id, pos, rng, angle)
			angle += 0.9
			if target != Vector2.INF:
				var h := terrain.surface_height(pos.x, pos.y)
				var tp := Vector3(target.x, terrain.surface_height(target.x, target.y), target.y)
				var origin := Vector3(pos.x, h + 1.6, pos.y)
				w.try_cast(id, {"origin": origin, "aim": (tp - origin).normalized(), "target": tp, "hit": true,
					"feet": Vector3(pos.x, h, pos.y)})
		# Walk on toward green ground like a player would (avalanche stays at the snowline).
		if id != "avalanche":
			var goal := cov.find_nearest_unfrozen_area(pos, 1.0e9, 8)
			if goal != Vector2.INF and goal.distance_to(pos) > prog.cast_range_for("snow_cloud") * 0.5:
				var speed := prog.stat("move_speed") * prog.stat("sprint_mult") * 0.85
				pos += (goal - pos).normalized() * minf(speed * 0.1, goal.distance_to(pos))
		w.advance(0.1)
		t += 0.1
	# Let effects already in flight finish so long-lived storms count fully.
	for i in 300:
		w.advance(0.1)
	var area := float(w.area_by_source.get(id, 0.0))
	w.queue_free()
	return area / DURATION


static func _target(w: WeatherManager, terrain: TerrainData, cov: SnowCoverage, prog: Progression, id: String,
		pos: Vector2, rng: RandomNumberGenerator, angle: float) -> Vector2:
	var r := prog.cast_range_for(id) * 0.85
	match id:
		"frost_front", "arctic_wind":
			var g := cov.find_nearest_unfrozen_area(pos + Vector2.from_angle(angle) * 25.0, 1.0e9, 8)
			return g if g != Vector2.INF else pos + Vector2.from_angle(angle) * 20.0
		"avalanche":
			# Like a player reading the preview: pick a release that runs into green.
			var best := Vector2.INF
			var best_s := 0.5
			for k in 200:
				var p := pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * r
				if Avalanche.release_check(terrain, cov, p) == "":
					var s := Avalanche.downhill_green(terrain, cov, p)
					if s > best_s:
						best_s = s
						best = p
			return best
	var t := cov.find_nearest_unfrozen_area(pos, r, 8)
	if t == Vector2.INF or t.distance_to(pos) > r:
		return pos + Vector2.from_angle(angle) * r * 0.7
	return t


## A standing spot with plenty of releasable snowy slope within reach.
static func _snowline_spot(terrain: TerrainData, cov: SnowCoverage, reach: float) -> Vector2:
	var best := Vector2(-41, -150)
	var best_n := -1
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for z in range(-200, -90, 10):
		for x in range(-200, 201, 10):
			var c := Vector2(x, z)
			var n := 0
			for k in 40:
				var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * reach
				if Avalanche.release_check(terrain, cov, p) == "" and Avalanche.downhill_green(terrain, cov, p) > 1.5:
					n += 1
			if n > best_n:
				best_n = n
				best = c
	return best
