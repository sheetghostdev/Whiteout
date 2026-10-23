class_name TestNoAssets
extends RefCounted
## Verifies the project contains no imported media: every visual (and sound)
## must be generated in code.

const FORBIDDEN := [
	"png", "jpg", "jpeg", "webp", "bmp", "tga", "svg", "exr", "hdr", "ktx", "dds",
	"gltf", "glb", "fbx", "obj", "dae", "blend", "mesh", "res",
	"ttf", "otf", "woff", "woff2", "fnt", "font",
	"wav", "ogg", "mp3", "opus",
]


func run(t, _full: bool) -> void:
	var files := _scan("res://")
	var bad: Array[String] = []
	for f in files:
		if f.get_extension().to_lower() in FORBIDDEN:
			bad.append(f)
	t.check(bad.is_empty(), "no imported media files in the project: %s" % ", ".join(bad))
	# Scenes must not reference external resources other than scripts.
	for f in files:
		if f.ends_with(".tscn") or f.ends_with(".tres"):
			var txt := FileAccess.get_file_as_string(f)
			for line in txt.split("\n"):
				if line.begins_with("[ext_resource"):
					t.check(line.contains("type=\"Script\""), "%s only references scripts (%s)" % [f, line])
	print("    scanned %d project files" % files.size())


func _scan(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(_scan(dir.path_join(sub)))
	return out
