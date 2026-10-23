class_name SaveManager
extends RefCounted
## Versioned JSON save files with atomic replace and a backup copy.
## Nothing here depends on scene node paths.

const VERSION := 1
const PATH := "user://whiteout_save.json"
const TMP_PATH := "user://whiteout_save.json.tmp"
const BAK_PATH := "user://whiteout_save.json.bak"


static func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func build(seed_value: int, prog: Progression, regions: RegionTracker, cov: SnowCoverage,
		player: Dictionary, weather: Array) -> Dictionary:
	return {
		"version": VERSION,
		"seed": seed_value,
		"saved_at": Time.get_datetime_string_from_system(),
		"progression": prog.to_dict(),
		"regions": regions.to_array(),
		"coverage": Marshalls.raw_to_base64(cov.serialize()),
		"world_fraction": cov.world_completion(),
		"player": player,
		"weather": weather,
	}


## Writes to a temp file, verifies it parses, then swaps it into place.
static func write(data: Dictionary, path: String = PATH) -> bool:
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var text := JSON.stringify(data)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	var check := FileAccess.get_file_as_string(tmp)
	if JSON.parse_string(check) == null:
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			dir.remove(bak.get_file())
		dir.rename(path.get_file(), bak.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


static func read(path: String = PATH) -> Dictionary:
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary and int(parsed.get("version", 0)) >= 1:
			return migrate(parsed)
	return {}


static func migrate(d: Dictionary) -> Dictionary:
	# Future versions upgrade older dictionaries here.
	return d


static func delete_save(path: String = PATH) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			dir.remove(p.get_file())


static func restore_coverage(d: Dictionary, cov: SnowCoverage) -> bool:
	var b64: String = d.get("coverage", "")
	if b64 == "":
		return false
	return cov.deserialize(Marshalls.base64_to_raw(b64))
