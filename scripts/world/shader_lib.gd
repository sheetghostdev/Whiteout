class_name ShaderLib
extends RefCounted
## Loads shader source files and registers the global shader parameters that
## tie every material to the authoritative simulation textures.

static var _shaders := {}
static var _registered := false
static var _materials := {}


static func shader(name: String) -> Shader:
	if not _shaders.has(name):
		_shaders[name] = load("res://shaders/%s.gdshader" % name)
	return _shaders[name]


static func material(name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(name)
	return m


## Shared material cached by key (for many identical meshes).
static func shared(key: String, shader_name: String, params: Dictionary = {}) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var m := material(shader_name)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_materials[key] = m
	return m


## The globals are declared in project.godot ([shader_globals]) so every
## shader can compile before the world exists; here we only bind values.
static func _ensure(param: String, value: Variant) -> void:
	RenderingServer.global_shader_parameter_set(param, value)


static func register_globals(height_tex: Texture2D, water_tex: Texture2D, coverage_tex: Texture2D) -> void:
	_ensure("wo_height", height_tex)
	_ensure("wo_water", water_tex)
	_ensure("wo_coverage", coverage_tex)
	_ensure("wo_completion", 0.0)
	_ensure("wo_thaw", Vector4.ZERO)
	_ensure("wo_wind", Vector2.ZERO)
	_registered = true


static func set_global(param: String, value: Variant) -> void:
	if _registered:
		RenderingServer.global_shader_parameter_set(param, value)
