class_name TestEconomy
extends RefCounted
## Data integrity of the balance tables plus a finite-currency audit: the world
## holds a fixed amount of Frost, so required purchases must fit inside it.


func run(t, _full: bool) -> void:
	_integrity(t)
	_text_matches_gameplay(t)
	_purchase_rules(t)
	_audit(t)


func _integrity(t) -> void:
	for id in GameBalance.UPGRADES:
		var u: Dictionary = GameBalance.UPGRADES[id]
		t.check(u["cat"] in GameBalance.CATEGORIES, "%s has a valid category" % id)
		t.check(int(u["max"]) >= 1, "%s has a max level" % id)
		t.check(float(u["cost"]) > 0.0 and float(u["growth"]) >= 1.0, "%s has sane pricing" % id)
		if u.has("stat"):
			t.check(GameBalance.STATS.has(u["stat"]), "%s drives an existing stat" % id)
			t.check(u["stat"] == id, "%s stat id matches upgrade id (Progression.stat relies on it)" % id)
		var req: Dictionary = u.get("req", {})
		if req.has("ability"):
			t.check(GameBalance.ABILITIES.has(req["ability"]), "%s requires a real ability" % id)
		for k in req.get("upgrades", {}):
			t.check(GameBalance.UPGRADES.has(k), "%s requires a real upgrade %s" % [id, k])
			t.check(int(req["upgrades"][k]) <= int(GameBalance.UPGRADES[k]["max"]), "%s requirement level is reachable" % id)
		if u.has("unlocks"):
			t.check(GameBalance.ABILITIES.has(u["unlocks"]), "%s unlocks a real ability" % id)
	for a in GameBalance.ABILITY_ORDER:
		var unlock: String = GameBalance.ABILITIES[a]["unlock"]
		if unlock != "":
			t.check(GameBalance.UPGRADES.has(unlock) and GameBalance.UPGRADES[unlock].get("unlocks", "") == a, "%s has an unlock upgrade" % a)
	for s in GameBalance.STATS:
		t.check(GameBalance.UPGRADES.has(s), "stat %s is purchasable" % s)
	for cat in GameBalance.CATEGORIES:
		var n := 0
		for id in GameBalance.UPGRADES:
			if GameBalance.UPGRADES[id]["cat"] == cat:
				n += 1
		t.check(n >= 2, "category %s offers upgrades" % cat)
	# Every ability has meaningful upgrades.
	for a in GameBalance.ABILITY_ORDER:
		var n2 := 0
		for id in GameBalance.UPGRADES:
			if GameBalance.UPGRADES[id]["cat"] == a and GameBalance.UPGRADES[id].has("stat"):
				n2 += 1
		t.check(n2 >= 4, "%s has at least four repeatable upgrades (%d)" % [a, n2])


func _text_matches_gameplay(t) -> void:
	# The shop shows format_stat(stat_value(level)); gameplay reads Progression.stat.
	var p := Progression.new()
	for id in GameBalance.UPGRADES:
		var u: Dictionary = GameBalance.UPGRADES[id]
		if not u.has("stat"):
			continue
		for lv in [0, 1, int(u["max"])]:
			p.levels[id] = lv
			var shown := GameBalance.format_stat(u["stat"], GameBalance.stat_value(u["stat"], lv))
			var actual := GameBalance.format_stat(u["stat"], p.stat(u["stat"]))
			t.check(shown == actual, "%s level %d: shop text '%s' matches gameplay '%s'" % [id, lv, shown, actual])


func _purchase_rules(t) -> void:
	var p := Progression.new()
	t.check(not p.can_purchase("cloud_radius"), "cannot buy without Frost")
	p.add_frost(GameBalance.upgrade_cost("cloud_radius", 0))
	t.check(p.purchase("cloud_radius"), "can buy the first upgrade once affordable")
	t.check(p.frost == 0.0, "purchase deducts the exact cost")
	t.check(p.stat("cloud_radius") > GameBalance.stat_value("cloud_radius", 0), "purchase changes the stat immediately")
	p.add_frost(1.0e9)
	t.check(not p.purchase("unlock_frost_front"), "ability unlocks need a Winter Core")
	p.add_cores(1)
	t.check(p.purchase("unlock_frost_front"), "unlock with Frost + core")
	t.check(p.is_ability_unlocked("frost_front"), "ability becomes available")
	t.check(not p.purchase("unlock_frost_front"), "one-off unlocks cannot be bought twice")
	t.check(p.requirement_text("front_width") == "", "unlocked ability opens its upgrades")
	t.check(p.requirement_text("superstorm") != "", "locked evolutions state a requirement")
	var cheap := GameBalance.upgrade_cost("cloud_radius", 0)
	t.check(cheap <= 15.0, "first upgrade is cheap enough for the opening seconds (%d)" % cheap)


## Frost available from the finite world versus what progression requires.
func _audit(t) -> void:
	var terrain: TerrainData = t.shared_terrain()
	var cov := SnowCoverage.new()
	cov.setup(terrain)
	var base := cov.total_reward
	var milestone := 0.0
	for r in SnowCoverage.REGION_COUNT:
		for pct in GameBalance.REGION_MILESTONES:
			milestone += RegionTracker.region_bonus(cov, r, pct)
	var max_mult := GameBalance.stat_value("frost_mult", int(GameBalance.UPGRADES["frost_mult"]["max"]))
	var max_region := GameBalance.stat_value("region_bonus", int(GameBalance.UPGRADES["region_bonus"]["max"]))
	var floor_frost := base + milestone
	var ceiling := base * max_mult + milestone * max_region
	var required_frost := 0.0
	var required_cores := 0
	for a in GameBalance.ABILITY_ORDER:
		var unlock: String = GameBalance.ABILITIES[a]["unlock"]
		if unlock != "":
			required_frost += GameBalance.upgrade_cost(unlock, 0)
			required_cores += GameBalance.upgrade_core_cost(unlock)
	var cores_available := GameBalance.WORLD_CORE_MILESTONES.size() + SnowCoverage.REGION_COUNT
	var all_costs := 0.0
	var all_cores := 0
	for id in GameBalance.UPGRADES:
		var u: Dictionary = GameBalance.UPGRADES[id]
		for lv in int(u["max"]):
			all_costs += GameBalance.upgrade_cost(id, lv)
		all_cores += GameBalance.upgrade_core_cost(id)
	print("    Frost in world: base %s, with milestones %s, ceiling with multipliers %s" % [UIKit.fmt(base), UIKit.fmt(floor_frost), UIKit.fmt(ceiling)])
	print("    Required unlocks: %s Frost, %d cores (of %d obtainable)" % [UIKit.fmt(required_frost), required_cores, cores_available])
	print("    Everything maxed: %s Frost, %d cores" % [UIKit.fmt(all_costs), all_cores])
	t.check(required_frost < floor_frost * 0.3, "required unlocks leave most of the world's Frost for upgrades (%d%%)" % int(required_frost / floor_frost * 100.0))
	t.check(required_cores <= cores_available, "enough Winter Cores exist for every ability")
	t.check(all_cores <= cores_available, "every core purchase is obtainable in one run")
	# Each unlock must be affordable from the Frost the world yields before the
	# core that pays for it arrives (conservatively: no multipliers, no bonuses).
	var cores_needed := 0
	var spent := 0.0
	for a in GameBalance.ABILITY_ORDER:
		var unlock: String = GameBalance.ABILITIES[a]["unlock"]
		if unlock == "":
			continue
		cores_needed += GameBalance.upgrade_core_cost(unlock)
		spent += GameBalance.upgrade_cost(unlock, 0)
		var frac := GameBalance.WORLD_CORE_MILESTONES[mini(cores_needed, GameBalance.WORLD_CORE_MILESTONES.size()) - 1]
		var earned := base * frac
		t.check(spent <= earned, "%s affordable by the time its core arrives (%s needed, %s earned by %d%%)" % [a, UIKit.fmt(spent), UIKit.fmt(earned), int(frac * 100.0)])
	# Mid-game purchasing power must keep pace (no dead economy).
	t.check(all_costs > floor_frost * 0.6, "upgrade catalogue is deep enough to keep spending meaningful")
