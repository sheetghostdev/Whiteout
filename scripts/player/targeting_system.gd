class_name TargetingSystem
extends Node3D
## World-space ability previews, drawn with terrain-hugging procedural
## meshes: circles, frost-front strips, wind arrows and avalanche paths.

const VALID := Color(0.78, 0.94, 1.0, 0.7)
const INVALID := Color(1.0, 0.56, 0.5, 0.7)

var _disc: MeshInstance3D
var _strips: Array[MeshInstance3D] = []
var _ghost: MeshInstance3D
var _ghost_mat: ShaderMaterial
var _path: MeshInstance3D
var _path_mesh: ImmediateMesh
var _path_mat: ShaderMaterial
var _flash := 0.0
var _radius_anim := 0.0


func _ready() -> void:
	_disc = WeatherFX.decal(0, VALID)
	add_child(_disc)
	for k in 5:
		var s := WeatherFX.decal(2, VALID)
		add_child(s)
		_strips.append(s)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = WeatherFX.cloud_mesh(3, true)
	_ghost_mat = WeatherFX.cloud_material()
	_ghost_mat.set_shader_parameter("fade", 0.3)
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_path_mesh = ImmediateMesh.new()
	_path = MeshInstance3D.new()
	_path.mesh = _path_mesh
	_path_mat = ShaderLib.material("decal")
	_path_mat.set_shader_parameter("mode", 4)
	_path_mat.set_shader_parameter("color", VALID)
	_path_mat.set_shader_parameter("scroll_speed", 1.5)
	_path.material_override = _path_mat
	_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_path.extra_cull_margin = 500.0
	add_child(_path)
	hide_all()


func hide_all() -> void:
	_disc.visible = false
	for s in _strips:
		s.visible = false
	_ghost.visible = false
	_path.visible = false


func flash() -> void:
	_flash = 1.0


func _set_color(mi: MeshInstance3D, c: Color, intensity: float) -> void:
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("intensity", intensity)


func show_preview(p: Dictionary, _ability_id: String) -> void:
	hide_all()
	var valid: bool = p.get("valid", false)
	var ready: bool = p.get("ready", true)
	var col := VALID if valid else INVALID
	var intensity := (1.0 if ready else 0.55) + _flash * 0.8
	var center: Vector3 = p.get("center", Vector3.ZERO)
	_flash = maxf(_flash - get_process_delta_time() * 3.0, 0.0)
	match String(p.get("shape", "circle")):
		"circle":
			var r: float = p.get("radius", 2.0)
			# Animate radius changes so purchased upgrades are visible at once.
			_radius_anim = r if _radius_anim <= 0.0 else lerpf(_radius_anim, r, 1.0 - exp(-get_process_delta_time() * 6.0))
			_disc.visible = true
			_disc.global_position = Vector3(center.x, 0, center.z)
			_disc.scale = Vector3(_radius_anim, 1, _radius_anim)
			var mat := _disc.material_override as ShaderMaterial
			mat.set_shader_parameter("ring_width", clampf(0.6 / maxf(_radius_anim, 0.5), 0.012, 0.25))
			_set_color(_disc, col, intensity)
			if p.get("cloud", false):
				_ghost.visible = true
				var alt := 3.2 + r * 0.45
				_ghost.global_position = center + Vector3(0, alt, 0)
				_ghost.scale = Vector3(r * 1.05, r * 0.75, r * 1.05)
				_ghost_mat.set_shader_parameter("fade", 0.28 if valid else 0.12)
		"strip", "wind":
			var d: Vector2 = p.get("dir", Vector2(0, -1))
			var w: float = p.get("width", 4.0)
			var length: float = p.get("length", 30.0)
			var n: int = p.get("count", 1)
			var mode := 2 if p["shape"] == "strip" else 4
			for k in mini(n, _strips.size()):
				var s := _strips[k]
				var dd := d.rotated((k - (n - 1) * 0.5) * deg_to_rad(11.0)) if mode == 2 else d
				s.visible = true
				(s.material_override as ShaderMaterial).set_shader_parameter("mode", mode)
				s.global_position = Vector3(center.x, 0, center.z)
				s.rotation = Vector3(0, atan2(dd.x, dd.y), 0)
				s.scale = Vector3(w, 1, length)
				_set_color(s, col, intensity * 0.8)
		"avalanche":
			var r2: float = p.get("radius", 4.0)
			_disc.visible = true
			_disc.global_position = Vector3(center.x, 0, center.z)
			_disc.scale = Vector3(r2, 1, r2)
			_set_color(_disc, col, intensity)
			var path: PackedVector3Array = p.get("path", PackedVector3Array())
			if path.size() >= 2 and valid:
				_build_path(center, path, r2 * 1.2)
				_path.visible = true
				_path_mat.set_shader_parameter("color", col)
				_path_mat.set_shader_parameter("intensity", intensity)


func _build_path(start: Vector3, pts: PackedVector3Array, width: float) -> void:
	_path_mesh.clear_surfaces()
	var all := PackedVector3Array([start])
	all.append_array(pts)
	var total := 0.0
	for k in range(1, all.size()):
		total += all[k].distance_to(all[k - 1])
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var acc := 0.0
	for k in all.size():
		var a := all[maxi(k - 1, 0)]
		var b := all[mini(k + 1, all.size() - 1)]
		var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := Vector3(-t.z, 0, t.x) * width * 0.5
		if k > 0:
			acc += all[k].distance_to(all[k - 1])
		var v := acc / maxf(total, 0.001)
		_path_mesh.surface_set_uv(Vector2(0, v))
		_path_mesh.surface_add_vertex(all[k] - side)
		_path_mesh.surface_set_uv(Vector2(1, v))
		_path_mesh.surface_add_vertex(all[k] + side)
	_path_mesh.surface_end()
