class_name CloudController
extends Node3D
## Third-person rig for the player's cloud. WASD drifts relative to where the
## camera faces, the mouse orbits the camera, the wheel
## zooms. Skills fire from here. The node follows the cloud so anything that
## asks for the "player position" gets the cloud.

const MIN_PITCH := deg_to_rad(-80.0)
const MAX_PITCH := deg_to_rad(-12.0)

var terrain: TerrainData
var weather: WeatherManager
var camera: Camera3D
var yaw := 0.0
var pitch := deg_to_rad(-38.0)
var zoom := 1.0
var input_enabled := false
var autopilot := false     # scripted flights (tour, tests) steer the cloud directly
var _dist := 22.0


func setup(t: TerrainData, w: WeatherManager) -> void:
	terrain = t
	weather = w
	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 3200.0
	camera.fov = Settings.fov
	camera.top_level = true
	add_child(camera)
	EventBus.settings_changed.connect(func(): camera.fov = Settings.fov)


func cloud() -> PlayerCloud:
	return weather.cloud if weather != null else null


func spawn_at(p: Vector2, facing: float) -> void:
	weather.spawn_player_cloud(p)
	yaw = facing
	pitch = deg_to_rad(-38.0)
	zoom = 1.0
	global_position = Vector3(p.x, terrain.surface_height(p.x, p.y) + GameBalance.CLOUD_ALTITUDE, p.y)
	_dist = _target_dist()
	_place_camera(1.0, true)


## Flat world-space direction the camera is looking.
func aim_flat() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func eye_position() -> Vector3:
	return camera.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var s := Settings.mouse_sensitivity * 0.01
		yaw -= m.relative.x * s
		pitch -= m.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	elif event.is_action_pressed("zoom_in"):
		zoom = clampf(zoom * 0.88, 0.45, 2.6)
	elif event.is_action_pressed("zoom_out"):
		zoom = clampf(zoom / 0.88, 0.45, 2.6)
	elif event.is_action_pressed("thaw_sense"):
		if not Game.use_thaw_sense(global_position):
			var why := "Recharging" if Game.prog.has("thaw_sense") else "Not unlocked"
			EventBus.skill_failed.emit("thaw_sense", why)
	else:
		for id in GameBalance.SKILL_ORDER:
			if event.is_action_pressed(GameBalance.SKILLS[id]["action"]):
				cast(id)


func cast(id: String) -> void:
	var c := cloud()
	if c == null:
		return
	if not Game.prog.has(id):
		return
	var reason := weather.use_skill(id, aim_flat())
	if reason != "":
		EventBus.skill_failed.emit(id, reason)


func _physics_process(_delta: float) -> void:
	var c := cloud()
	if c == null or autopilot:
		return
	if input_enabled:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		c.move_input = Vector2(input.x, input.y).rotated(-yaw)
	else:
		c.move_input = Vector2.ZERO


func _target_dist() -> float:
	var c := cloud()
	var r := c.radius if c != null else 3.0
	return (14.0 + r * 2.6) * zoom


func _process(delta: float) -> void:
	_place_camera(delta, false)


func _place_camera(delta: float, snap: bool) -> void:
	var c := cloud()
	if c == null or camera == null:
		return
	var anchor := c.global_position if c.is_inside_tree() else Vector3(c.pos.x, 0, c.pos.y)
	global_position = anchor
	var k := 1.0 if snap else 1.0 - exp(-delta * 3.0)
	_dist = lerpf(_dist, _target_dist(), k)
	var back := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, _dist)
	var p := anchor + back
	# Never let the camera sink into a hillside.
	var floor_y := terrain.obstacle_height(p.x, p.z) + 2.5
	if p.y < floor_y:
		p.y = floor_y
	camera.global_position = p if snap else camera.global_position.lerp(p, 1.0 - exp(-delta * 10.0))
	camera.look_at(anchor + Vector3(0, -c.radius * 0.3, 0))


func save_state() -> Dictionary:
	return {"yaw": yaw, "pitch": pitch, "zoom": zoom}


func restore_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	yaw = float(d.get("yaw", 0.0))
	pitch = clampf(float(d.get("pitch", -0.6)), MIN_PITCH, MAX_PITCH)
	zoom = clampf(float(d.get("zoom", 1.0)), 0.45, 2.6)
	_dist = _target_dist()
	_place_camera(1.0, true)
