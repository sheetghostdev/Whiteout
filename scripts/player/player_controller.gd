class_name PlayerController
extends CharacterBody3D
## First-person weather controller: grounded walking with gentle
## acceleration, optional flight (Skyward Drift), and no visible body.

const EYE := 1.62
const GRAVITY := 18.0
const JUMP := 6.2
const MAX_FLIGHT_ALT := 170.0

var terrain: TerrainData
var head: Node3D
var camera: Camera3D
var abilities: AbilityController
var targeting: TargetingSystem
var yaw := 0.0
var pitch := 0.0
var flying := false
var input_enabled := false
var _bob := 0.0
var _land_dip := 0.0


func setup(t: TerrainData) -> void:
	terrain = t
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	head = Node3D.new()
	head.position = Vector3(0, EYE, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 3200.0
	camera.fov = Settings.fov
	head.add_child(camera)
	targeting = TargetingSystem.new()
	targeting.name = "Targeting"
	targeting.top_level = true
	add_child(targeting)
	abilities = AbilityController.new()
	abilities.name = "Abilities"
	abilities.player = self
	add_child(abilities)
	EventBus.settings_changed.connect(func(): camera.fov = Settings.fov)


func spawn_at(p: Vector2, facing: float) -> void:
	global_position = Vector3(p.x, terrain.surface_height(p.x, p.y) + 0.2, p.y)
	yaw = facing
	pitch = -0.08
	velocity = Vector3.ZERO
	flying = false
	_apply_look()


func eye_position() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func _apply_look() -> void:
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3(pitch, 0, 0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var s := Settings.mouse_sensitivity * 0.01
		yaw -= m.relative.x * s
		pitch -= m.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-88.0), deg_to_rad(88.0))
		_apply_look()
	elif event.is_action_pressed("special"):
		toggle_flight()


func toggle_flight() -> void:
	if not Game.prog.has("flight"):
		EventBus.ability_failed.emit("flight", "Unlock Skyward Drift in the General upgrades")
		Audio.play("error", -6.0)
		return
	flying = not flying
	Audio.play("cast_wind", -10.0, 1.4 if flying else 0.9)
	EventBus.notify.emit("SKYWARD DRIFT" if flying else "LANDING", "Space to climb, Ctrl to descend" if flying else "", "info")


func _physics_process(delta: float) -> void:
	if terrain == null:
		return
	var prog: Progression = Game.prog
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_flat := Basis(Vector3.UP, yaw)
	var wish := basis_flat * Vector3(input.x, 0, input.y)
	var sprinting := input_enabled and Input.is_action_pressed("sprint")
	var speed := prog.stat("move_speed") * (prog.stat("sprint_mult") if sprinting else 1.0)
	var surface := terrain.surface_height(global_position.x, global_position.z)
	if flying:
		var fs := prog.stat("flight_speed") * (1.6 if sprinting else 1.0)
		var up := 0.0
		if input_enabled:
			up = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("descend") else 0.0)
		var target := wish * fs + Vector3.UP * up * fs * 0.6
		velocity = velocity.lerp(target, 1.0 - exp(-delta * 3.0))
		var alt := global_position.y - surface
		if alt > MAX_FLIGHT_ALT and velocity.y > 0.0:
			velocity.y *= 0.5
		move_and_slide()
		if global_position.y - surface > MAX_FLIGHT_ALT + 5.0:
			global_position.y = surface + MAX_FLIGHT_ALT + 5.0
	else:
		var target_h := wish * speed
		var accel := 10.0 if is_on_floor() else 3.0
		var hv := Vector3(velocity.x, 0, velocity.z).lerp(target_h, 1.0 - exp(-delta * accel))
		velocity.x = hv.x
		velocity.z = hv.z
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif input_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
		var was_air := not is_on_floor()
		move_and_slide()
		if was_air and is_on_floor() and Settings.motion_effects:
			_land_dip = 0.06
	# Wade through water rather than walking along the bottom.
	var wl := terrain.sample_water_level(global_position.x, global_position.z)
	if wl > -100.0 and global_position.y < wl - 0.55:
		global_position.y = wl - 0.55
		velocity.y = maxf(velocity.y, 0.0)
	# Safety net if anything ever falls through the world.
	var ground := terrain.sample_height(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.3
		velocity.y = 0.0
	_update_bob(delta, Vector2(velocity.x, velocity.z).length())


func _update_bob(delta: float, hspeed: float) -> void:
	var y := EYE
	if Settings.motion_effects and not flying and is_on_floor() and hspeed > 0.5:
		_bob += delta * hspeed * 1.6
		y += sin(_bob) * 0.025
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.4)
	head.position.y = lerpf(head.position.y, y - _land_dip, 1.0 - exp(-delta * 12.0))


func save_state() -> Dictionary:
	var p := global_position
	return {"pos": [p.x, p.y, p.z], "yaw": yaw, "pitch": pitch, "flying": flying, "ability": abilities.selected_id()}


func restore_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	var p: Array = d.get("pos", [TerrainData.SPAWN.x, 12.0, TerrainData.SPAWN.y])
	global_position = Vector3(p[0], p[1], p[2])
	yaw = float(d.get("yaw", 0.0))
	pitch = float(d.get("pitch", 0.0))
	flying = bool(d.get("flying", false)) and Game.prog.has("flight")
	velocity = Vector3.ZERO
	_apply_look()
	abilities.select_id(String(d.get("ability", "snow_cloud")))
