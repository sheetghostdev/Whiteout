extends Node
## Global signal hub. Systems emit here; UI and audio observe.
## Nothing in here holds state.

signal frost_changed(amount: float)
signal cores_changed(amount: int)
signal frost_gained(amount: float, world_pos: Vector3)
signal coverage_changed(world_fraction: float)
signal region_changed(region_id: int)
signal region_milestone(region_id: int, percent: int, frost_bonus: float, core: bool)
signal world_milestone(percent: float, cores: int)
signal upgrade_purchased(upgrade_id: String, level: int)
signal ability_unlocked(ability_id: String)
signal ability_selected(ability_id: String)
signal ability_cast(ability_id: String, world_pos: Vector3)
signal ability_failed(ability_id: String, reason: String)
signal combo_discovered(combo_id: String)
signal combo_triggered(combo_id: String, world_pos: Vector3)
signal notify(title: String, subtitle: String, kind: String)
signal world_completed()
signal game_state_changed(state: String)
signal settings_changed()
signal thaw_sense_pulse(origin: Vector3)
signal save_written()
