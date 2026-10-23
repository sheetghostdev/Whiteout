class_name InputSetup
extends RefCounted
## Defines every input action in code (so bindings are data we can save and
## rebind) and converts events to/from plain dictionaries.

const ACTIONS := [
	["move_forward", "Move Forward", {"key": KEY_W}],
	["move_back", "Move Back", {"key": KEY_S}],
	["move_left", "Move Left", {"key": KEY_A}],
	["move_right", "Move Right", {"key": KEY_D}],
	["sprint", "Sprint", {"key": KEY_SHIFT}],
	["jump", "Jump / Climb", {"key": KEY_SPACE}],
	["descend", "Descend (flight)", {"key": KEY_CTRL}],
	["cast", "Cast Ability", {"mouse": MOUSE_BUTTON_LEFT}],
	["alt_cast", "Alternate Action", {"mouse": MOUSE_BUTTON_RIGHT}],
	["next_ability", "Next Ability", {"mouse": MOUSE_BUTTON_WHEEL_DOWN}],
	["prev_ability", "Previous Ability", {"mouse": MOUSE_BUTTON_WHEEL_UP}],
	["ability_1", "Ability 1", {"key": KEY_1}],
	["ability_2", "Ability 2", {"key": KEY_2}],
	["ability_3", "Ability 3", {"key": KEY_3}],
	["ability_4", "Ability 4", {"key": KEY_4}],
	["ability_5", "Ability 5", {"key": KEY_5}],
	["ability_6", "Ability 6", {"key": KEY_6}],
	["upgrades", "Upgrade Menu", {"key": KEY_TAB}],
	["pause", "Pause", {"key": KEY_ESCAPE}],
	["map", "Overview Map", {"key": KEY_M}],
	["special", "Skyward Drift (fly)", {"key": KEY_F}],
	["thaw_sense", "Thaw Sense", {"key": KEY_Q}],
	["guide", "Weather Guide", {"key": KEY_G}],
]

## Actions the player may not rebind (menus must always be reachable).
const FIXED := ["pause"]


static func defaults() -> Dictionary:
	var d := {}
	for a in ACTIONS:
		d[a[0]] = [a[2]]
	return d


static func label_for(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


static func event_from_dict(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var e := InputEventKey.new()
		e.physical_keycode = int(d["key"])
		return e
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(d["mouse"])
		return m
	return null


static func event_to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return {"key": int(code)}
	if e is InputEventMouseButton:
		return {"mouse": int((e as InputEventMouseButton).button_index)}
	return {}


static func describe(d: Dictionary) -> String:
	if d.has("key"):
		return OS.get_keycode_string(int(d["key"]))
	if d.has("mouse"):
		match int(d["mouse"]):
			MOUSE_BUTTON_LEFT:
				return "Left Mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right Mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel Down"
		return "Mouse %d" % int(d["mouse"])
	return "-"


static func apply(bindings: Dictionary) -> void:
	for a in ACTIONS:
		var name: String = a[0]
		if not InputMap.has_action(name):
			InputMap.add_action(name, 0.2)
		InputMap.action_erase_events(name)
		var list: Array = bindings.get(name, [a[2]])
		for d in list:
			var e := event_from_dict(d)
			if e != null:
				InputMap.action_add_event(name, e)
