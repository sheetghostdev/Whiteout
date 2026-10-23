class_name TestEconomy
extends RefCounted
## Integrity of the upgrade web plus a finite-currency audit: the world holds a
## fixed amount of Frost, so the web must fit inside it.


func run(t, _full: bool) -> void:
	_integrity(t)
	_reachability(t)
	_text_matches_gameplay(t)
	_purchase_rules(t)
	_reveal_rules(t)
	_audit(t)


## Buys everything (ignoring Frost and coverage gates). Shared by other tests.
static func buy_everything(prog: Progression) -> void:
	for id in GameBalance.NODES:
		prog.levels[id] = int(GameBalance.NODES[id]["max"])


func _integrity(t) -> void:
	var stats_driven := {}
	for id in GameBalance.NODES:
		var n: Dictionary = GameBalance.NODES[id]
		t.check(GameBalance.BRANCH_COLORS.has(n["branch"]), "%s has a valid branch" % id)
		t.check(int(n["max"]) >= 1 and int(n["max"]) <= 5, "%s has 1-5 levels, never a long slog (%d)" % [id, int(n["max"])])
		t.check(id == "heart" or (float(n["cost"]) > 0.0 and float(n["growth"]) >= 1.0), "%s has sane pricing" % id)
		for l in n["links"]:
			t.check(GameBalance.NODES.has(l), "%s links to a real node %s" % [id, l])
		var kind := String(n.get("kind", ""))
		t.check(n.has("stat") or kind == "keystone" or kind == "skill", "%s does something" % id)
		if kind == "skill":
			t.check(GameBalance.SKILLS.has(id), "skill node %s is a real skill" % id)
		if n.has("stat"):
			var st: String = n["stat"]
			t.check(GameBalance.STATS.has(st), "%s drives an existing stat" % id)
			stats_driven[st] = true
			# No "+4%" nodes: every level is a step the player can feel.
			var s: Dictionary = GameBalance.STATS.get(st, {"base": 1.0, "mode": "add"})
			var per := float(n["per"])
			var step := absf(per - 1.0) if s["mode"] == "mul" else absf(per) / maxf(absf(float(s["base"])), 1.0)
			t.check(step >= 0.1 or st == "core", "%s changes %s by a noticeable step per level (%.0f%%)" % [id, st, step * 100.0])
	for st in GameBalance.STATS:
		t.check(stats_driven.has(st), "stat %s is driven by some node" % st)
	for sk in GameBalance.SKILLS:
		t.check(GameBalance.NODES.has(sk), "skill %s can be bought in the web" % sk)
	# Nodes never overlap on screen.
	var ids := GameBalance.NODES.keys()
	var min_d := INF
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Vector2 = GameBalance.NODES[ids[i]]["pos"]
			var b: Vector2 = GameBalance.NODES[ids[j]]["pos"]
			min_d = minf(min_d, a.distance_to(b))
	t.check(min_d >= 1.0, "web nodes are spaced apart (closest %.2f)" % min_d)
	for b in GameBalance.BRANCH_COLORS:
		if b == "heart":
			continue
		var has_key := false
		for id in GameBalance.NODES:
			var n: Dictionary = GameBalance.NODES[id]
			if n["branch"] == b and (String(n.get("kind", "")) == "keystone" or String(n.get("kind", "")) == "skill"):
				has_key = true
		t.check(has_key, "branch %s has a keystone or skill that changes play" % b)


func _reachability(t) -> void:
	var p := Progression.new()
	p.world_fraction = 1.0
	var changed := true
	while changed:
		changed = false
		for id in GameBalance.NODES:
			if not p.has(id) and p.is_revealed(id):
				p.levels[id] = int(GameBalance.NODES[id]["max"])
				changed = true
	for id in GameBalance.NODES:
		t.check(p.has(id), "%s is reachable from the heart" % id)


func _text_matches_gameplay(t) -> void:
	# The web shows stat_with_next before buying; gameplay reads stat() after.
	var p := Progression.new()
	p.add_frost(1.0e12)
	p.world_fraction = 1.0
	buy_everything(p)
	for id in GameBalance.NODES:
		p.levels.erase(id)
	p.levels["heart"] = 1
	var guard := 0
	while guard < 500:
		guard += 1
		var front := p.frontier()
		if front.is_empty():
			break
		var id: String = front[0]
		var n: Dictionary = GameBalance.NODES[id]
		var predicted := 0.0
		if n.has("stat"):
			predicted = p.stat_with_next(n["stat"], id)
		t.check(p.purchase(id), "%s can be bought with Frost and coverage" % id)
		if n.has("stat"):
			var shown := GameBalance.format_stat(n["stat"], predicted)
			var actual := GameBalance.format_stat(n["stat"], p.stat(n["stat"]))
			t.check(shown == actual, "%s: web preview '%s' matches gameplay '%s'" % [id, shown, actual])
	t.check(p.frontier().is_empty(), "the whole web can be bought")


func _purchase_rules(t) -> void:
	var p := Progression.new()
	t.check(not p.can_purchase("billow"), "cannot buy without Frost")
	p.add_frost(p.cost_of("billow"))
	var r0 := p.stat("radius")
	t.check(p.purchase("billow"), "can buy the first upgrade once affordable")
	t.check(p.frost == 0.0, "purchase deducts the exact cost")
	t.check(p.stat("radius") > r0, "purchase changes the stat immediately")
	t.check(p.cost_of("billow") > GameBalance.node_cost("billow", 0), "next level costs more")
	var cheapest := INF
	for id in GameBalance.NODES:
		if "heart" in GameBalance.NODES[id]["links"]:
			cheapest = minf(cheapest, GameBalance.node_cost(id, 0))
	t.check(cheapest <= 15.0, "an opening upgrade is cheap enough for the first seconds (%d)" % cheapest)
	p.add_frost(1.0e9)
	t.check(not p.can_purchase("swell"), "only revealed nodes are buyable")
	t.check(not p.purchase("vortex_form"), "coverage-gated nodes wait for the world to freeze")
	t.check(p.requirement_text("vortex_form") != "", "coverage gates state their requirement")
	p.world_fraction = 0.3
	t.check(p.purchase("vortex_form"), "coverage gate opens at the stated fraction")
	t.check("vortex_form" in p.unlocked_skills(), "skills become usable once bought")
	t.check(not p.purchase("vortex_form"), "one-off nodes cannot be bought twice")


func _reveal_rules(t) -> void:
	var p := Progression.new()
	var start := 0
	for id in GameBalance.NODES:
		if p.is_revealed(id) and not p.has(id):
			start += 1
	t.check(start >= 4 and start <= 8, "a new game shows only a handful of choices (%d)" % start)
	t.check(not p.is_revealed("swell"), "nodes deeper in the web start hidden")
	p.levels["billow"] = 1
	t.check(not p.is_revealed("swell"), "a half-levelled node keeps its neighbours hidden")
	p.levels["billow"] = int(GameBalance.NODES["billow"]["max"])
	t.check(p.is_revealed("swell"), "finishing a node reveals its neighbours")


## Frost available from the finite world versus the web's total price.
func _audit(t) -> void:
	var terrain: TerrainData = t.shared_terrain()
	var cov := SnowCoverage.new()
	cov.setup(terrain)
	var base := cov.total_reward
	var milestone := 0.0
	for r in SnowCoverage.REGION_COUNT:
		for pct in GameBalance.REGION_MILESTONES:
			milestone += RegionTracker.region_bonus(cov, r, pct)
	var maxed := Progression.new()
	buy_everything(maxed)
	var ceiling := base * maxed.stat("frost_mult") + milestone * maxed.stat("region_bonus")
	var all_costs := 0.0
	for id in GameBalance.NODES:
		for lv in int(GameBalance.NODES[id]["max"]):
			all_costs += GameBalance.node_cost(id, lv)
	print("    Frost in world: base %s, milestones %s, ceiling with multipliers %s" % [UIKit.fmt(base), UIKit.fmt(milestone), UIKit.fmt(ceiling)])
	print("    Whole web: %s Frost over %d nodes" % [UIKit.fmt(all_costs), GameBalance.NODES.size()])
	# Deep enough that Frost always has a use, shallow enough that most of it
	# is bought in a run (the progression bot measures the actual share).
	t.check(all_costs < ceiling * 1.3, "the web is not out of reach of the world's Frost")
	t.check(all_costs > (base + milestone) * 0.8, "the web is deep enough that spending stays meaningful to the end")
