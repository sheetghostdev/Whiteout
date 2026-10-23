extends Node
## Global signal hub. Systems emit here; UI and audio observe.
## Nothing in here holds state.

signal frost_changed(amount: float)
signal coverage_changed(world_fraction: float)
signal region_changed(region_id: int)
signal region_milestone(region_id: int, percent: int, frost_bonus: float, complete: bool)
signal world_milestone(fraction: float)
signal upgrade_purchased(node_id: String, level: int)
signal skill_unlocked(skill_id: String)
signal skill_used(skill_id: String, world_pos: Vector3)
signal skill_failed(skill_id: String, reason: String)
signal notify(title: String, subtitle: String, kind: String)
signal world_completed()
signal game_state_changed(state: String)
signal settings_changed()
signal thaw_sense_pulse(origin: Vector3)
signal save_written()
