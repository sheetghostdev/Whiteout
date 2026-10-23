class_name BalanceBot
extends RefCounted
## Plays WHITEOUT headlessly using the real simulation (coverage, weather,
## economy, milestones) so balance can be measured instead of guessed.
## It walks at the player's speed, thinks four times per second and shops
## every few seconds according to a strategy.

const STRATEGIES := ["standard", "clouds", "fronts", "wind_combo", "multipliers", "scatter", "combine", "expensive_early", "saver", "regions"]

var strategy := "standard"
var terrain: TerrainData
var cov: SnowCoverage
var prog: Progression
var regions: RegionTracker
var w: WeatherManager
var pos := TerrainData.SPAWN
var t := 0.0
var goal := Vector2.INF
var rng := RandomNumberGenerator.new()
var unlock_times := {}
var unlock_levels := {}   # ability -> upgrade levels at the moment it unlocked
var milestone_times := {}
var first_purchase := -1.0
var last_purchase := 0.0
var longest_gap := 0.0
var completed := false
var purchases := 0
var _think := 0.0
var _shop := 0.0
var _check := 0.0
var _goal_timer := 0.0


func setup(host: Node, p_terrain: TerrainData, p_strategy: String, seed_value: int) -> void:
	strategy = p_strategy
	terrain = p_terrain
	rng.seed = seed_value
	cov = SnowCoverage.new()
	cov.setup(terrain)
	prog = Progression.new()
	regions = RegionTracker.new()
	w = WeatherManager.new()
	host.add_child(w)
	w.setup(terrain, cov, prog, false, seed_value)
	prog.ability_unlocked.connect(func(id):
		unlock_times[id] = t
		unlock_levels[id] = prog.levels.duplicate()
		_windows[id] = {"start": t, "area0": w.area_by_source.duplicate(), "casts0": (prog.stats["casts"] as Dictionary).duplicate()})


func dispose() -> void:
	w.queue_free()


func run(max_time: float) -> Dictionary:
	var dt := 0.1
	while t < max_time and not completed:
		w.advance(dt)
		t += dt
		prog.stats["time"] = t
		_move(dt)
		_think -= dt
		if _think <= 0.0:
			_think = 0.5
			_act()
		_shop -= dt
		if _shop <= 0.0:
			_shop = 6.0 if strategy == "saver" else 3.0
			_do_shop()
		_check -= dt
		if _check <= 0.0:
			_check = 0.5
			_checks()
			_close_windows()
	return summary()


## For each newly unlocked ability: m² frozen per cast and per second over
## the next WINDOW seconds, next to the Snow Cloud over the same stretch.
const WINDOW := 150.0
var _windows := {}
var power_report := {}


func _close_windows() -> void:
	for id in _windows.keys():
		var win: Dictionary = _windows[id]
		if t - float(win["start"]) < WINDOW and not completed:
			continue
		var dt := t - float(win["start"])
		var row := {}
		for k in [id, "snow_cloud"]:
			var area := float(w.area_by_source.get(k, 0.0)) - float(win["area0"].get(k, 0.0))
			var casts := int(prog.stats["casts"].get(k, 0)) - int(win["casts0"].get(k, 0))
			row[k] = {"per_s": area / maxf(dt, 1.0), "per_cast": area / maxf(casts, 1), "casts": casts}
		power_report[id] = row
		_windows.erase(id)


func summary() -> Dictionary:
	return {"strategy": strategy, "completed": completed, "time": t, "fraction": cov.world_completion(),
		"lifetime_frost": prog.lifetime_frost, "unlocks": unlock_times, "milestones": milestone_times,
		"first_purchase": first_purchase, "longest_gap": longest_gap, "purchases": purchases, "power": power_report}


func _checks() -> void:
	var wf := cov.world_completion()
	prog.world_fraction = wf
	regions.check(cov, prog)
	for m in [0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99]:
		if wf >= m and not milestone_times.has(m):
			milestone_times[m] = t
	if wf >= 0.985:
		var g := cov.cleanup_pass()
		prog.add_frost(g)
		if cov.is_world_complete():
			cov.freeze_all()
			completed = true
			milestone_times[1.0] = t


# ----------------------------------------------------------------- movement
func _range(id: String) -> float:
	return prog.cast_range_for(id)


func _move(dt: float) -> void:
	_goal_timer -= dt
	if _goal_timer <= 0.0 or goal == Vector2.INF or cov.get_coverage(goal.x, goal.y) >= 1.0:
		_goal_timer = 2.0
		goal = _pick_goal()
	if goal == Vector2.INF:
		return
	var speed := prog.stat("move_speed") * prog.stat("sprint_mult") * 0.85
	if prog.has("flight"):
		speed = maxf(speed, prog.stat("flight_speed"))
	# Casting range is measured in 3D, so climbing slopes means walking closer.
	var keep := _range("snow_cloud") * 0.6
	var to := goal - pos
	if to.length() > 1.0 and not _reachable(goal, keep):
		pos += to.normalized() * minf(speed * dt, to.length() - 1.0)
		pos.x = clampf(pos.x, -248.0, 248.0)
		pos.y = clampf(pos.y, -248.0, 248.0)


func _pick_goal() -> Vector2:
	if strategy == "regions":
		# Finish the most complete unfinished region first.
		var best := -1
		var bf := -1.0
		for r in SnowCoverage.REGION_COUNT:
			var f := cov.region_completion(r)
			if f < 0.999 and f > bf:
				bf = f
				best = r
		if best >= 0:
			var g := _nearest_in_region(best)
			if g != Vector2.INF:
				return g
	return cov.find_nearest_unfrozen_area(pos, 1.0e9, 1)


func _nearest_in_region(r: int) -> Vector2:
	var best := Vector2.INF
	var bd := 1.0e9
	for ch in SnowCoverage.CH * SnowCoverage.CH:
		if cov.chunk_incomplete[ch] < 3:
			continue
		var c := Vector2((ch % SnowCoverage.CH) * 16 + 8 - 256, (ch / SnowCoverage.CH) * 16 + 8 - 256)
		if terrain.region_at(c.x, c.y) != r:
			continue
		var d := c.distance_to(pos)
		if d < bd:
			bd = d
			best = cov.chunk_unfrozen_centroid(ch)
	return best


# ----------------------------------------------------------------- casting
func _ctx(target: Vector2) -> Dictionary:
	var h := terrain.surface_height(pos.x, pos.y)
	var feet := Vector3(pos.x, h, pos.y)
	var tp := Vector3(target.x, terrain.surface_height(target.x, target.y), target.y)
	var origin := feet + Vector3(0, 1.6, 0)
	if prog.has("flight"):
		origin.y += 20.0
	return {"origin": origin, "aim": (tp - origin).normalized(), "target": tp, "hit": true, "feet": feet}


func _toward(target: Vector2, r: float) -> Vector2:
	var to := target - pos
	if to.length() <= r * 0.9:
		return target
	return pos + to.normalized() * r * 0.9


func _act() -> void:
	if goal == Vector2.INF:
		return
	var order := ["polar_vortex", "avalanche", "blizzard", "frost_front", "snow_cloud", "arctic_wind"]
	for id in order:
		if not prog.is_ability_unlocked(id) or w.cooldown_remaining(id) > 0.0:
			continue
		var target := _choose_target(id)
		if target == Vector2.INF:
			continue
		var r := w.try_cast(id, _ctx(target))
		if r == "":
			return


func _choose_target(id: String) -> Vector2:
	var r := _range(id)
	match id:
		"snow_cloud":
			if strategy == "scatter" and rng.randf() < 0.5:
				var a := rng.randf() * TAU
				return pos + Vector2.from_angle(a) * rng.randf() * r * 0.8
			return _best_point_in_range(r * 0.9, prog.stat("cloud_radius"))
		"frost_front":
			if goal.distance_to(pos) < prog.stat("front_distance") * 1.3:
				return goal
			return Vector2.INF
		"arctic_wind":
			# Push nearby clouds toward the goal (Cloud + Wind).
			var clouds := 0
			for e in w.effects_of("snow_cloud"):
				if e.pos.distance_to(pos) < 30.0:
					clouds += 1
			# The gust's own frost trail is worth casting toward green ground;
			# combo strategies wait for clouds to carry.
			if strategy in ["combine", "wind_combo"] and clouds < 1:
				return Vector2.INF
			return goal
		"blizzard", "polar_vortex":
			if strategy == "combine" and id == "blizzard":
				for e in w.effects_of("blizzard"):
					if e.pos.distance_to(pos) < r:
						return e.pos + Vector2(3, 0)
			var rad := prog.stat("bz_radius") if id == "blizzard" else prog.stat("pv_radius")
			return _best_point_in_range(r * 0.95, rad)
		"avalanche":
			var best := Vector2.INF
			var best_score := 0.0
			for k in 30:
				var a := rng.randf() * TAU
				var p := pos + Vector2.from_angle(a) * rng.randf() * r * 0.9
				if Avalanche.release_check(terrain, cov, p) != "":
					continue
				var score := Avalanche.downhill_green(terrain, cov, p)
				if score > best_score:
					best_score = score
					best = p
			return best if best_score > 0.6 else Vector2.INF
	return Vector2.INF


## Picks a cast point within reach: fresh green ground if there is any,
## otherwise the unfrozen fringe the bot is currently working on.
func _best_point_in_range(reach: float, radius: float) -> Vector2:
	var aim := _toward(goal, reach)
	var best := aim
	var best_c := _area_cov(aim, radius) if _reachable(aim, reach) else 2.0
	if best_c < 0.4:
		return best
	for k in 16:
		var a := TAU * k / 16.0
		for f in [0.25, 0.5, 0.75, 1.0]:
			var p: Vector2 = pos + Vector2.from_angle(a) * reach * f
			if not _reachable(p, reach):
				continue
			var c := _area_cov(p, radius)
			if c < best_c:
				best_c = c
				best = p
	if best_c < 0.85:
		return best
	# Finish partially frozen fringes at the goal.
	if _reachable(goal, reach) and cov.sample_coverage(goal.x, goal.y) < 0.995:
		return goal
	var local := cov.find_nearest_unfrozen_area(pos, reach + 12.0, 1)
	if local != Vector2.INF and _reachable(local, reach):
		return local
	return Vector2.INF


func _reachable(p: Vector2, reach: float) -> bool:
	var ctx := _ctx(p)
	return (ctx["origin"] as Vector3).distance_to(ctx["target"]) <= reach


func _area_cov(p: Vector2, radius: float) -> float:
	var s := cov.sample_coverage(p.x, p.y)
	var r := radius * 0.6
	s += cov.sample_coverage(p.x + r, p.y) + cov.sample_coverage(p.x - r, p.y)
	s += cov.sample_coverage(p.x, p.y + r) + cov.sample_coverage(p.x, p.y - r)
	return s / 5.0


# ----------------------------------------------------------------- shopping
func _weight(id: String) -> float:
	var u: Dictionary = GameBalance.UPGRADES[id]
	var cat: String = u["cat"]
	if u.has("unlocks") or id == "flight":
		return 1000.0
	var w2 := 1.0
	match strategy:
		"clouds":
			w2 = 3.0 if cat == "snow_cloud" else 0.5
		"fronts":
			w2 = 3.0 if cat == "frost_front" else 0.6
		"wind_combo", "combine":
			w2 = 2.0 if cat in ["arctic_wind", "snow_cloud"] else 0.9
		"multipliers":
			w2 = 6.0 if id in ["frost_mult", "region_bonus"] else 0.7
	if id in ["cast_range", "cooldown_mult", "frost_mult"]:
		w2 *= 1.4
	if id in ["overview_map", "guide_strength", "cyclonic_flow", "wind_steering", "flight_speed", "thaw_sense"]:
		w2 *= 0.2
	return w2


## An unlock whose requirements and cores are ready but whose Frost is not -
## players save up for these rather than spending on small upgrades.
func _saving_for() -> float:
	for id in GameBalance.UPGRADES:
		var u: Dictionary = GameBalance.UPGRADES[id]
		if not (u.has("unlocks") or id == "flight") or prog.has(id):
			continue
		if prog.requirements_met(id) and prog.cores >= prog.core_cost_of(id) and prog.frost < prog.cost_of(id):
			return prog.cost_of(id)
	return 0.0


func _do_shop() -> void:
	var saving := _saving_for()
	for k in 12:
		var best := ""
		var best_score := -1.0
		for id in GameBalance.UPGRADES:
			if not prog.can_purchase(id):
				continue
			var cost := prog.cost_of(id)
			var weight := _weight(id)
			if saving > 0.0 and weight < 1000.0 and cost > (saving - prog.frost) * 0.08:
				continue
			if strategy == "saver" and weight < 1000.0 and prog.frost < cost * 3.0:
				continue
			var score := weight / maxf(cost, 1.0)
			if strategy == "expensive_early" and weight < 1000.0:
				score = cost * weight
			if score > best_score:
				best_score = score
				best = id
		if best == "":
			break
		prog.purchase(best)
		purchases += 1
		if first_purchase < 0.0:
			first_purchase = t
		longest_gap = maxf(longest_gap, t - last_purchase)
		last_purchase = t
