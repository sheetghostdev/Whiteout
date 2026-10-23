class_name Progression
extends RefCounted
## Owns currency, purchased upgrades, ability unlocks and run statistics.
## Pure data + rules: no scene access, so the balancing harness can drive it.

signal frost_changed(amount: float)
signal cores_changed(amount: int)
signal purchased(upgrade_id: String, level: int)
signal ability_unlocked(ability_id: String)

var frost: float = 0.0
var lifetime_frost: float = 0.0
var cores: int = 0
var lifetime_cores: int = 0
var levels: Dictionary = {}          # upgrade_id -> level
var world_fraction: float = 0.0      # mirrored from SnowCoverage for requirement checks
var claimed_world_milestones: Array = []   # indices into WORLD_CORE_MILESTONES
var discovered_combos: Array = []
var completed: bool = false
var plus_level: int = 0              # New Winter+ count
var modifiers: Array = []            # New Winter+ modifier ids
var stats: Dictionary = {
	"time": 0.0,
	"storms": 0,
	"casts": {},
	"largest_storm": 0.0,
	"longest_chain": 0,
	"area_frozen": 0.0,
}


func level(upgrade_id: String) -> int:
	return int(levels.get(upgrade_id, 0))


func has(upgrade_id: String) -> bool:
	return level(upgrade_id) > 0


func stat(stat_id: String) -> float:
	# Stats are driven by the upgrade of the same id; modifiers add on top.
	var v := GameBalance.stat_value(stat_id, level(stat_id))
	if stat_id == "cloud_count" and "extra_cloud" in modifiers:
		v += 1.0
	if stat_id == "wind_strength" and "strong_wind" in modifiers:
		v *= 1.25
	if stat_id == "front_speed" and "swift_fronts" in modifiers:
		v *= 1.3
	return v


func is_ability_unlocked(ability_id: String) -> bool:
	var unlock: String = GameBalance.ABILITIES[ability_id]["unlock"]
	return unlock == "" or has(unlock)


func unlocked_abilities() -> Array[String]:
	var out: Array[String] = []
	for a in GameBalance.ABILITY_ORDER:
		if is_ability_unlocked(a):
			out.append(a)
	return out


func cost_of(upgrade_id: String) -> float:
	return GameBalance.upgrade_cost(upgrade_id, level(upgrade_id))


func core_cost_of(upgrade_id: String) -> int:
	return GameBalance.upgrade_core_cost(upgrade_id)


func is_maxed(upgrade_id: String) -> bool:
	return level(upgrade_id) >= int(GameBalance.UPGRADES[upgrade_id]["max"])


## Returns "" when requirements are met, otherwise a human readable reason.
func requirement_text(upgrade_id: String) -> String:
	var u: Dictionary = GameBalance.UPGRADES[upgrade_id]
	var req: Dictionary = u.get("req", {})
	var parts: Array[String] = []
	if req.has("ability") and not is_ability_unlocked(req["ability"]):
		parts.append("Unlock %s" % GameBalance.ABILITIES[req["ability"]]["name"])
	var ups: Dictionary = req.get("upgrades", {})
	for k in ups:
		if level(k) < int(ups[k]):
			var nm: String = GameBalance.UPGRADES[k]["name"]
			if int(GameBalance.UPGRADES[k]["max"]) == 1:
				parts.append("Requires %s" % nm)
			else:
				parts.append("%s level %d" % [nm, int(ups[k])])
	if req.has("coverage") and world_fraction < float(req["coverage"]):
		parts.append("World %d%% frozen" % int(round(float(req["coverage"]) * 100.0)))
	return ", ".join(parts)


func requirements_met(upgrade_id: String) -> bool:
	return requirement_text(upgrade_id) == ""


## True when the upgrade's requirements are almost satisfied - used to decide
## whether the shop shows a locked entry or hides it entirely.
func is_forthcoming(upgrade_id: String) -> bool:
	var u: Dictionary = GameBalance.UPGRADES[upgrade_id]
	var req: Dictionary = u.get("req", {})
	if req.has("ability") and not is_ability_unlocked(req["ability"]):
		return false
	var ups: Dictionary = req.get("upgrades", {})
	for k in ups:
		var need := int(ups[k])
		if level(k) == 0 and need > 0 and GameBalance.UPGRADES[k].has("req") and not requirements_met(k):
			return false
	if req.has("coverage") and world_fraction < float(req["coverage"]) - 0.25:
		return false
	return true


func can_purchase(upgrade_id: String) -> bool:
	if is_maxed(upgrade_id) or not requirements_met(upgrade_id):
		return false
	return frost >= cost_of(upgrade_id) and cores >= core_cost_of(upgrade_id)


func purchase(upgrade_id: String) -> bool:
	if not can_purchase(upgrade_id):
		return false
	var cost := cost_of(upgrade_id)
	var ccost := core_cost_of(upgrade_id)
	frost -= cost
	cores -= ccost
	levels[upgrade_id] = level(upgrade_id) + 1
	frost_changed.emit(frost)
	if ccost > 0:
		cores_changed.emit(cores)
	purchased.emit(upgrade_id, level(upgrade_id))
	var u: Dictionary = GameBalance.UPGRADES[upgrade_id]
	if u.has("unlocks"):
		ability_unlocked.emit(u["unlocks"])
	return true


func add_frost(amount: float) -> void:
	if amount <= 0.0:
		return
	frost += amount
	lifetime_frost += amount
	frost_changed.emit(frost)


func add_cores(n: int) -> void:
	cores += n
	lifetime_cores += n
	cores_changed.emit(cores)


func record_cast(ability_id: String) -> void:
	var casts: Dictionary = stats["casts"]
	casts[ability_id] = int(casts.get(ability_id, 0)) + 1
	stats["storms"] = int(stats["storms"]) + 1


func most_used_ability() -> String:
	var best := ""
	var best_n := -1
	var casts: Dictionary = stats["casts"]
	for k in casts:
		if int(casts[k]) > best_n:
			best_n = int(casts[k])
			best = k
	return best


func cooldown_for(ability_id: String) -> float:
	return float(GameBalance.ABILITIES[ability_id]["cooldown"]) * stat("cooldown_mult")


func cast_range_for(ability_id: String) -> float:
	return stat("cast_range") * float(GameBalance.ABILITIES[ability_id]["range_mult"])


func to_dict() -> Dictionary:
	return {
		"frost": frost, "lifetime_frost": lifetime_frost, "cores": cores, "lifetime_cores": lifetime_cores,
		"levels": levels.duplicate(), "claimed_world_milestones": claimed_world_milestones.duplicate(),
		"discovered_combos": discovered_combos.duplicate(), "completed": completed,
		"plus_level": plus_level, "modifiers": modifiers.duplicate(), "stats": stats.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	frost = float(d.get("frost", 0.0))
	lifetime_frost = float(d.get("lifetime_frost", 0.0))
	cores = int(d.get("cores", 0))
	lifetime_cores = int(d.get("lifetime_cores", 0))
	levels = {}
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		if GameBalance.UPGRADES.has(k):
			levels[k] = int(lv[k])
	claimed_world_milestones = []
	for v in d.get("claimed_world_milestones", []):
		claimed_world_milestones.append(int(v))
	discovered_combos = []
	for v in d.get("discovered_combos", []):
		discovered_combos.append(String(v))
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
	cores_changed.emit(cores)
