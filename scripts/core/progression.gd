class_name Progression
extends RefCounted
## Owns Frost, the upgrade web state and run statistics.
## Pure data + rules: no scene access, so the balancing harness can drive it.

signal frost_changed(amount: float)
signal purchased(node_id: String, level: int)
signal skill_unlocked(skill_id: String)

var frost: float = 0.0
var lifetime_frost: float = 0.0
var levels: Dictionary = {"heart": 1}   # node_id -> level
var world_fraction: float = 0.0        # mirrored from SnowCoverage for requirement checks
var claimed_world_milestones: Array = []
var completed: bool = false
var plus_level: int = 0                # New Winter+ count
var modifiers: Array = []              # New Winter+ modifier ids
var stats: Dictionary = {
	"time": 0.0,
	"skills_used": 0,
	"casts": {},
	"largest_storm": 0.0,
	"longest_chain": 0,
	"area_frozen": 0.0,
	"distance": 0.0,
}


func level(node_id: String) -> int:
	return int(levels.get(node_id, 0))


func has(node_id: String) -> bool:
	return level(node_id) > 0


func stat(stat_id: String) -> float:
	var s: Dictionary = GameBalance.STATS[stat_id]
	var v := float(s["base"])
	for id in GameBalance.stat_nodes(stat_id):
		var lv := level(id)
		if lv <= 0:
			continue
		var per := float(GameBalance.NODES[id]["per"])
		if s["mode"] == "mul":
			v *= pow(per, lv)
		else:
			v += per * lv
	return _modified(stat_id, v)


## The stat value if `node_id` had one more level (for "current -> next" text).
func stat_with_next(stat_id: String, node_id: String) -> float:
	levels[node_id] = level(node_id) + 1
	var v := stat(stat_id)
	levels[node_id] = level(node_id) - 1
	if levels[node_id] == 0:
		levels.erase(node_id)
	return v


func _modified(stat_id: String, v: float) -> float:
	if stat_id == "companions" and "extra_cloud" in modifiers:
		v += 1.0
	if stat_id == "speed" and "strong_wind" in modifiers:
		v *= 1.2
	if stat_id == "wave_length" and "swift_fronts" in modifiers:
		v *= 1.3
	return v


func cost_of(node_id: String) -> float:
	return GameBalance.node_cost(node_id, level(node_id))


func is_maxed(node_id: String) -> bool:
	return level(node_id) >= int(GameBalance.NODES[node_id]["max"])


## Revealed nodes are drawn in the web; everything else stays hidden. A node
## appears once a node linked to it is fully levelled, so only a handful of
## choices are ever open and each one is finished before the next opens.
func is_revealed(node_id: String) -> bool:
	if has(node_id):
		return true
	var n: Dictionary = GameBalance.NODES[node_id]
	if n.has("coverage") and world_fraction < float(n["coverage"]) - 0.2:
		return false
	for l in n["links"]:
		if is_maxed(l):
			return true
	return (n["links"] as Array).is_empty()


## "" when the node can be bought (Frost aside), otherwise why not.
func requirement_text(node_id: String) -> String:
	if not is_revealed(node_id):
		return "Hidden"
	var n: Dictionary = GameBalance.NODES[node_id]
	if n.has("coverage") and world_fraction < float(n["coverage"]):
		return "Freeze %d%% of the world" % int(round(float(n["coverage"]) * 100.0))
	return ""


func requirements_met(node_id: String) -> bool:
	return requirement_text(node_id) == ""


func can_purchase(node_id: String) -> bool:
	if is_maxed(node_id) or not requirements_met(node_id):
		return false
	return frost >= cost_of(node_id)


func purchase(node_id: String) -> bool:
	if not can_purchase(node_id):
		return false
	frost -= cost_of(node_id)
	levels[node_id] = level(node_id) + 1
	frost_changed.emit(frost)
	purchased.emit(node_id, level(node_id))
	if GameBalance.SKILLS.has(node_id):
		skill_unlocked.emit(node_id)
	return true


## Nodes on the frontier: revealed and not yet maxed.
func frontier() -> Array[String]:
	var out: Array[String] = []
	for id in GameBalance.NODES:
		if is_revealed(id) and not is_maxed(id):
			out.append(id)
	return out


func affordable_count() -> int:
	var n := 0
	for id in frontier():
		if can_purchase(id):
			n += 1
	return n


func unlocked_skills() -> Array[String]:
	var out: Array[String] = []
	for s in GameBalance.SKILL_ORDER:
		if has(s):
			out.append(s)
	return out


func skill_cooldown(skill_id: String) -> float:
	return stat(GameBalance.SKILLS[skill_id]["cd_stat"])


func add_frost(amount: float) -> void:
	if amount <= 0.0:
		return
	frost += amount
	lifetime_frost += amount
	frost_changed.emit(frost)


func record_cast(skill_id: String) -> void:
	var casts: Dictionary = stats["casts"]
	casts[skill_id] = int(casts.get(skill_id, 0)) + 1
	stats["skills_used"] = int(stats.get("skills_used", 0)) + 1


func most_used_skill() -> String:
	var best := ""
	var best_n := -1
	var casts: Dictionary = stats["casts"]
	for k in casts:
		if int(casts[k]) > best_n:
			best_n = int(casts[k])
			best = k
	return best


func upgrades_owned() -> int:
	var n := 0
	for id in levels:
		if id != "heart":
			n += int(levels[id])
	return n


func to_dict() -> Dictionary:
	return {
		"frost": frost, "lifetime_frost": lifetime_frost, "levels": levels.duplicate(),
		"claimed_world_milestones": claimed_world_milestones.duplicate(), "completed": completed,
		"plus_level": plus_level, "modifiers": modifiers.duplicate(), "stats": stats.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	frost = float(d.get("frost", 0.0))
	lifetime_frost = float(d.get("lifetime_frost", 0.0))
	levels = {"heart": 1}
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		if GameBalance.NODES.has(k):
			levels[k] = mini(int(lv[k]), int(GameBalance.NODES[k]["max"]))
		else:
			# Upgrades that no longer exist: hand back what was spent on them.
			frost += GameBalance.retired_refund(String(k), int(lv[k]))
	claimed_world_milestones = []
	for v in d.get("claimed_world_milestones", []):
		claimed_world_milestones.append(int(v))
	completed = bool(d.get("completed", false))
	plus_level = int(d.get("plus_level", 0))
	modifiers = []
	for v in d.get("modifiers", []):
		modifiers.append(String(v))
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
	if typeof(stats.get("casts")) != TYPE_DICTIONARY:
		stats["casts"] = {}
	frost_changed.emit(frost)
