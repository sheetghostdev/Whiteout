class_name BalanceBot
extends RefCounted
## Plays WHITEOUT headlessly using the real simulation (coverage, the player
## cloud, skills, economy, milestones) so balance can be measured instead of
## guessed. It steers the cloud exactly as a player would, through
## PlayerCloud.move_input, and shops according to a strategy.

const STRATEGIES := ["standard", "branchy", "random", "saver", "skills_last"]

var strategy := "standard"
var terrain: TerrainData
var cov: SnowCoverage
var prog: Progression
var regions: RegionTracker
var w: WeatherManager
var cloud: PlayerCloud
var t := 0.0
var goal := Vector2.INF
var rng := RandomNumberGenerator.new()
var skill_times := {}
var milestone_times := {}
var first_purchase := -1.0
var last_purchase := 0.0
var longest_gap := 0.0
var completed := false
var purchases := 0
var choice_samples := 0
var choice_sum := 0.0
var choice_max := 0
var choice_peak: Array = []
var choice_peak_t := 0.0
var purchase_log: Array = []
var _think := 0.0
var _shop := 0.0
var _check := 0.0
var _goal_timer := 0.0
var _heading := Vector2.ZERO


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
	cloud = w.spawn_player_cloud(TerrainData.SPAWN)
	prog.skill_unlocked.connect(func(id): skill_times[id] = t)


func dispose() -> void:
	w.queue_free()


func run(max_time: float) -> Dictionary:
	var dt := 0.1
	while t < max_time and not completed:
		w.advance(dt)
		t += dt
		prog.stats["time"] = t
		_steer()
		_think -= dt
		if _think <= 0.0:
			_think = 0.5
			_use_skills()
		_shop -= dt
		if _shop <= 0.0:
			_shop = 20.0 if strategy == "saver" else 2.0
			_do_shop()
		_check -= dt
		if _check <= 0.0:
			_check = 0.5
			_checks()
	return summary()


func summary() -> Dictionary:
	return {"strategy": strategy, "completed": completed, "time": t, "fraction": cov.world_completion(),
		"lifetime_frost": prog.lifetime_frost, "skills": skill_times, "milestones": milestone_times,
		"first_purchase": first_purchase, "longest_gap": longest_gap, "purchases": purchases,
		"choices_avg": choice_sum / maxf(choice_samples, 1), "choices_max": choice_max,
		"spent_fraction": spent_fraction(), "radius": prog.stat("radius"), "sources": w.area_by_source.duplicate(), "land": float(cov.total_cells)}


## Share of the whole web's price that was bought.
func spent_fraction() -> float:
	var all := 0.0
	var got := 0.0
	for id in GameBalance.NODES:
		for lv in int(GameBalance.NODES[id]["max"]):
			var c := GameBalance.node_cost(id, lv)
			all += c
			if lv < prog.level(id):
				got += c
	return got / maxf(all, 1.0)


func _src_line() -> String:
	var parts: Array[String] = []
	for k in w.area_by_source:
		parts.append("%s=%s" % [k.substr(0, 6), UIKit.fmt(w.area_by_source[k])])
	return " ".join(parts)


func _checks() -> void:
	var wf := cov.world_completion()
	prog.world_fraction = wf
	regions.check(cov, prog)
	for m in [0.01, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99]:
		if wf >= m and not milestone_times.has(m):
			milestone_times[m] = t
			if "log" in OS.get_cmdline_user_args():
				print("        @%d%% t=%s r=%.1f rate=%.2f speed=%.1f frost=%s cloudlets=%d spent=%d%% %s" % [int(m * 100), UIKit.fmt_time(t),
					prog.stat("radius"), prog.stat("rate"), prog.stat("speed"), UIKit.fmt(prog.lifetime_frost), int(prog.stat("companions")), int(spent_fraction() * 100), _src_line()])
	# Choices in front of the player: revealed nodes they could buy now or soon.
	var open := 0
	for id in prog.frontier():
		if prog.requirements_met(id):
			open += 1
	choice_samples += 1
	choice_sum += open
	if open > choice_max:
		choice_peak = []
		for id in prog.frontier():
			if prog.requirements_met(id):
				choice_peak.append(id)
		choice_peak_t = t
	choice_max = maxi(choice_max, open)
	if wf >= 0.985:
		var g := cov.cleanup_pass()
		prog.add_frost(g)
		if cov.is_world_complete():
			cov.freeze_all()
			completed = true
			milestone_times[1.0] = t


# ----------------------------------------------------------------- flying
## Flies like a tidy player mowing a lawn: head for the nearest green
## ground and keep moving through it, turning back across the patch for the
## next pass. The cloud never needs to stop, and stopping earns nothing.
func _steer() -> void:
	var pos := cloud.pos
	_goal_timer -= 0.1
	if _goal_timer <= 0.0 or goal == Vector2.INF or cov.get_coverage(goal.x, goal.y) >= 1.0:
		_goal_timer = 0.8
		goal = cov.find_nearest_unfrozen_area(pos, 1.0e9, 2)
	if goal == Vector2.INF:
		cloud.move_input = Vector2.ZERO
		return
	var to := goal - pos
	var d := to.length()
	var r := cloud.radius
	if d > r * 0.6 or _heading == Vector2.ZERO:
		_heading = to.normalized()
	# Within the patch, keep the current heading: the cloud overshoots,
	# then the next goal turns it back for a parallel pass.
	cloud.move_input = _heading


func _green_around(c: Vector2, rr: float) -> float:
	var g := 0.0
	for k in 8:
		var p := c + Vector2.from_angle(TAU * k / 8.0) * rr
		g += 1.0 - cov.sample_coverage(p.x, p.y)
	return g / 8.0


func _use_skills() -> void:
	if strategy == "skills_last" and t < 60.0:
		return
	var pos := cloud.pos
	if prog.has("squall") and w.cooldown_remaining("squall") <= 0.0:
		if _green_around(pos, prog.stat("squall_radius") * 0.6 + cloud.radius) > 0.35:
			w.use_skill("squall", Vector2.UP)
	if prog.has("frost_wave") and w.cooldown_remaining("frost_wave") <= 0.0:
		var best := Vector2.ZERO
		var best_g := 0.3
		var reach := prog.stat("wave_length")
		for k in 12:
			var dir := Vector2.from_angle(TAU * k / 12.0)
			var g := 0.0
			for s in [0.3, 0.6, 0.9]:
				var p: Vector2 = pos + dir * reach * s
				if terrain.in_bounds(p.x, p.y, 4.0):
					g += 1.0 - cov.sample_coverage(p.x, p.y)
			if g / 3.0 > best_g:
				best_g = g / 3.0
				best = dir
		if best != Vector2.ZERO:
			w.use_skill("frost_wave", best)
	if prog.has("vortex_form") and w.cooldown_remaining("vortex_form") <= 0.0:
		if _green_around(pos, cloud.radius * prog.stat("vortex_mult") * 0.8) > 0.4:
			w.use_skill("vortex_form", Vector2.UP)


# ---------------------------------------------------------------- shopping
func _do_shop() -> void:
	var bought := true
	var guard := 0
	while bought and guard < 30:
		guard += 1
		bought = false
		var options: Array[String] = []
		for id in prog.frontier():
			if prog.can_purchase(id):
				options.append(id)
		if options.is_empty():
			break
		var pick := _choose(options)
		if pick != "" and prog.purchase(pick):
			bought = true
			purchases += 1
			purchase_log.append([t, pick, prog.level(pick)])
			if first_purchase < 0.0:
				first_purchase = t
			longest_gap = maxf(longest_gap, t - last_purchase)
			last_purchase = t
	# Waiting with nothing affordable counts as a gap as it grows.
	if prog.affordable_count() == 0:
		longest_gap = maxf(longest_gap, t - last_purchase)


func _choose(options: Array[String]) -> String:
	match strategy:
		"random":
			return options[rng.randi() % options.size()]
		"branchy":
			# Spread purchases across branches, cheapest within the least-owned one.
			var owned := {}
			for id in prog.levels:
				var b: String = GameBalance.NODES[id]["branch"]
				owned[b] = int(owned.get(b, 0)) + int(prog.levels[id])
			options.sort_custom(func(a, b):
				var oa := int(owned.get(GameBalance.NODES[a]["branch"], 0))
				var ob := int(owned.get(GameBalance.NODES[b]["branch"], 0))
				return oa < ob if oa != ob else prog.cost_of(a) < prog.cost_of(b))
			return options[0]
		"skills_last":
			var non := options.filter(func(id): return not GameBalance.SKILLS.has(id))
			if not non.is_empty():
				options.assign(non)
	options.sort_custom(func(a, b): return prog.cost_of(a) < prog.cost_of(b))
	return options[0]
