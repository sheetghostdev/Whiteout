extends Node
## Development helper: loads every script so parse/compile errors surface at once.
## Usage: godot --headless --path . res://scenes/load_all.tscn


func _ready() -> void:
	var bad := 0
	for f in _list("res://scripts"):
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			print("FAILED: ", f)
			bad += 1
	print("load_all: %d failures" % bad)
	get_tree().quit(1 if bad > 0 else 0)


func _list(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_list(dir + "/" + sub))
	return out
