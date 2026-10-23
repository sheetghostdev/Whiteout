class_name RegionTracker
extends RefCounted
## Tracks regional and world-wide milestones. Claimed milestones are stored,
## so reloading a save can never pay a reward twice.

signal region_milestone(region_id: int, percent: int, frost_bonus: float, complete: bool)
signal world_milestone(fraction: float)

var claimed: Array = []   # per region: Array of claimed percents


func _init() -> void:
	reset()


func reset() -> void:
	claimed = []
	for r in SnowCoverage.REGION_COUNT:
		claimed.append([])


## Region milestone percent counts as reached slightly early at 100% so that a
## couple of microscopic leftover cells cannot block a region's completion.
static func region_reached(fraction: float, percent: int) -> bool:
	if percent == 100:
		return fraction >= 0.999
	return fraction >= percent / 100.0


func check(cov: SnowCoverage, prog: Progression) -> void:
	for r in SnowCoverage.REGION_COUNT:
		var f := cov.region_completion(r)
		for p in GameBalance.REGION_MILESTONES:
			if p in claimed[r]:
				continue
			if not region_reached(f, p):
				continue
			claimed[r].append(p)
			var bonus := region_bonus(cov, r, p) * prog.stat("region_bonus")
			prog.add_frost(bonus)
			region_milestone.emit(r, p, bonus, p == 100)
	var wf := cov.world_completion()
	for k in GameBalance.WORLD_MILESTONES.size():
		if k in prog.claimed_world_milestones:
			continue
		if wf >= GameBalance.WORLD_MILESTONES[k]:
			prog.claimed_world_milestones.append(k)
			world_milestone.emit(GameBalance.WORLD_MILESTONES[k])


static func region_bonus(cov: SnowCoverage, r: int, percent: int) -> float:
	return round(cov.region_total[r] * GameBalance.REGION_REWARD[r] * float(GameBalance.REGION_MILESTONE_FRACTION[percent]))


func to_array() -> Array:
	return claimed.duplicate(true)


func from_array(a: Array) -> void:
	reset()
	for r in mini(a.size(), SnowCoverage.REGION_COUNT):
		for p in a[r]:
			claimed[r].append(int(p))
