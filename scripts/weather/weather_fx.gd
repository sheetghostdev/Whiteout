class_name WeatherFX
extends RefCounted
## Procedural visual building blocks shared by weather effects. Particle
## counts scale with the particle-density setting; that setting never touches
## the simulation.

static var particle_density := 1.0
static var visual_complexity := 1.0
static var _cloud_meshes: Array[ArrayMesh] = []
static var _cloud_meshes_lo: Array[ArrayMesh] = []
static var _flake_mesh: ArrayMesh
static var _flake_mat: StandardMaterial3D
static var _streak_mat: StandardMaterial3D
static var _disc: ArrayMesh
static var _strip: ArrayMesh
static var _snow_mass: Array[ArrayMesh] = []


static func cloud_mesh(variant: int, lo: bool = false) -> ArrayMesh:
	if _cloud_meshes.is_empty():
		for k in 6:
			_cloud_meshes.append(MeshFactory.cloud(k, 2))
			_cloud_meshes_lo.append(MeshFactory.cloud(k, 1))
	var i := posmod(variant, 6)
	return _cloud_meshes_lo[i] if lo else _cloud_meshes[i]


static func snow_mass_mesh(variant: int) -> ArrayMesh:
	if _snow_mass.is_empty():
		for k in 3:
			_snow_mass.append(MeshFactory.snow_mass(k))
	return _snow_mass[posmod(variant, 3)]


static func disc_mesh() -> ArrayMesh:
	if _disc == null:
		_disc = MeshFactory.disc_grid(10, 48)
	return _disc


static func strip_mesh() -> ArrayMesh:
	if _strip == null:
		_strip = MeshFactory.strip_grid(6, 40)
	return _strip


static func flake_material() -> StandardMaterial3D:
	if _flake_mat == null:
		_flake_mat = StandardMaterial3D.new()
		_flake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flake_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_flake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flake_mat.vertex_color_use_as_albedo = true
		_flake_mat.albedo_color = Color(1, 1, 1, 0.95)
		_flake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _flake_mat


static func streak_material() -> StandardMaterial3D:
	if _streak_mat == null:
		_streak_mat = StandardMaterial3D.new()
		_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_streak_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_streak_mat.billboard_keep_scale = true
		_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_streak_mat.vertex_color_use_as_albedo = true
		_streak_mat.albedo_color = Color(1, 1, 1, 0.55)
		_streak_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _streak_mat


static func flake_mesh() -> ArrayMesh:
	if _flake_mesh == null:
		_flake_mesh = MeshFactory.snowflake()
		_flake_mesh.surface_set_material(0, flake_material())
	return _flake_mesh


static func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.12, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 0.9))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Snowfall from a disc of the given radius, falling `height` metres.
static func snowfall(radius: float, height: float, base_amount: int, fall_speed: float, flake_size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var amount := maxi(4, int(base_amount * particle_density))
	p.amount = amount
	p.lifetime = height / fall_speed
	p.local_coords = false
	p.draw_pass_1 = flake_mesh()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = radius
	m.emission_ring_inner_radius = 0.0
	m.emission_ring_height = 1.0
	m.direction = Vector3(0, -1, 0)
	m.initial_velocity_min = fall_speed * 0.8
	m.initial_velocity_max = fall_speed * 1.2
	m.gravity = Vector3(0, -0.5, 0)
	m.scale_min = flake_size * 6.0 * 0.6
	m.scale_max = flake_size * 6.0 * 1.3
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = -90.0
	m.angular_velocity_max = 90.0
	# No particle turbulence and no preprocessing: both are heavy GPU compute
	# jobs, and several emitters rebuilt in one frame (buying cloudlets, a
	# vortex swelling) could stall the GPU long enough for the driver to give
	# up (VK_ERROR_DEVICE_LOST). A little sideways drift does the same job.
	m.spread = 10.0
	m.color_ramp = _fade_ramp()
	p.process_material = m
	p.visibility_aabb = AABB(Vector3(-radius - 6.0, -height - 6.0, -radius - 6.0), Vector3(radius * 2.0 + 12.0, height + 12.0, radius * 2.0 + 12.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Fast-moving streaks (wind, blowing snow).
static func streaks(box: Vector3, base_amount: int, velocity: Vector3, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(base_amount * particle_density))
	p.lifetime = life
	p.local_coords = true
	p.draw_pass_1 = flake_mesh()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = box
	m.direction = velocity.normalized()
	m.spread = 4.0
	m.initial_velocity_min = velocity.length() * 0.8
	m.initial_velocity_max = velocity.length() * 1.2
	m.gravity = Vector3(0, -0.6, 0)
	m.scale_min = 0.8
	m.scale_max = 1.6
	m.color_ramp = _fade_ramp()
	p.process_material = m
	var ext := box + Vector3.ONE * (velocity.length() * life + 4.0)
	p.visibility_aabb = AABB(-ext, ext * 2.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## One-shot glittering burst used for weather combinations and milestones.
static func burst(color: Color, amount: int, speed: float, radius: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(6, int(amount * particle_density))
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.draw_pass_1 = flake_mesh()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.direction = Vector3(0, 1, 0)
	m.spread = 180.0
	m.initial_velocity_min = speed * 0.5
	m.initial_velocity_max = speed
	m.gravity = Vector3(0, -2.0, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 1.5
	m.scale_max = 3.0
	m.color = color
	m.color_ramp = _fade_ramp()
	p.process_material = m
	p.visibility_aabb = AABB(Vector3.ONE * -(radius + speed * 2.0), Vector3.ONE * (radius + speed * 2.0) * 2.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func decal(mode: int, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = strip_mesh() if mode == 2 or mode == 4 else disc_mesh()
	var mat := ShaderLib.material("decal")
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("color", color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	return mi


static func cloud_material(tint: Color = Color.WHITE) -> ShaderMaterial:
	var m := ShaderLib.material("cloud")
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m


static func effect_material(mode: int, color: Color) -> ShaderMaterial:
	var m := ShaderLib.material("effect")
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("color", color)
	return m
