class_name InputSetup
extends RefCounted
## Defines every input action in code (so bindings are data we can save and
## rebind) and converts events to/from plain dictionaries.

const ACTIONS := [
	["move_forward", "Drift Forward", {"key": KEY_W}],
	["move_back", "Drift Back", {"key": KEY_S}],
	["move_left", "Drift Left", {"key": KEY_A}],
	["move_right", "Drift Right", {"key": KEY_D}],
	["dash", "Ride a Gust", {"key": KEY_SHIFT}],
	["skill_squall", "Squall", {"mouse": MOUSE_BUTTON_LEFT}],
	["skill_wave", "Frost Wave", {"mouse": MOUSE_BUTTON_RIGHT}],
	["skill_vortex", "Vortex Form", {"key": KEY_R}],
	["zoom_in", "Zoom In", {"mouse": MOUSE_BUTTON_WHEEL_UP}],
	["zoom_out", "Zoom Out", {"mouse": MOUSE_BUTTON_WHEEL_DOWN}],
	["upgrades", "Upgrade Web", {"key": KEY_TAB}],
	["pause", "Pause", {"key": KEY_ESCAPE}],
	["map", "Overview Map", {"key": KEY_M}],
	["thaw_sense", "Thaw Sense", {"key": KEY_Q}],
	["guide", "Field Guide", {"key": KEY_G}],
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
