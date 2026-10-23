class_name Atmosphere
extends Node3D
## Sky, sun, ambient light, fog and post-processing - all configured in code.

var env: Environment
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var sky_material: ShaderMaterial
var _storm_darkness := 0.0


func build() -> void:
	sky_material = ShaderLib.material("sky")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 3.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.78, 0.92)
	env.fog_light_energy = 1.0
	env.fog_density = 0.00055
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.0
	env.fog_height = 120.0
	env.fog_height_density = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.4
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.ssao_light_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.06
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.6
	add_child(sun)


func apply_quality(shadow_quality: int, effects: bool) -> void:
	if sun == null:
		return
	sun.shadow_enabled = shadow_quality > 0
	sun.directional_shadow_max_distance = [0.0, 120.0, 220.0, 320.0][clampi(shadow_quality, 0, 3)]
	env.ssao_enabled = effects
	env.glow_enabled = effects


## Called every frame with 0..1 local storm presence near the camera.
func set_storm_darkness(v: float, delta: float) -> void:
	_storm_darkness = lerpf(_storm_darkness, clampf(v, 0.0, 1.0), 1.0 - exp(-delta * 1.5))
	sun.light_energy = lerpf(1.25, 0.95, _storm_darkness)
	env.ambient_light_energy = lerpf(0.6, 0.52, _storm_darkness)
