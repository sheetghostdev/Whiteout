class_name CompletionCinematic
extends Node3D
## Ending camera flight over the frozen regions, with a final sparkling
## snowfall. Emits `finished` when done.

signal finished()

const DURATION := 20.0

var cam: Camera3D
var _t := 0.0
var _points: Array[Vector3] = []
var _looks: Array[Vector3] = []
var _snow: GPUParticles3D
var _running := false


func start(from: Transform3D, terrain: TerrainData) -> void:
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 3200.0
	add_child(cam)
	var f := from.origin
	var fwd := -from.basis.z
	var raw := [
		[f, f + fwd * 20.0],
		[f + Vector3(0, 28, 0) - fwd * 10.0, f + fwd * 40.0],
		[Vector3(-30, 60, 120), Vector3(0, 10, 40)],
		[Vector3(-130, 55, 90), Vector3(-160, 15, 10)],
		[Vector3(-170, 80, -60), Vector3(-40, 40, -170)],
		[Vector3(20, 120, -120), Vector3(120, 5, -10)],
		[Vector3(170, 70, -30), Vector3(140, 5, 30)],
		[Vector3(150, 90, 150), Vector3(0, 10, 0)],
		[Vector3(0, 240, 300), Vector3(0, 0, -40)],
	]
	for r in raw:
		var p: Vector3 = r[0]
		if p != f:
			p.y = maxf(p.y, terrain.surface_height(p.x, p.z) + 25.0)
		_points.append(p)
		_looks.append(r[1])
	cam.global_position = _points[0]
	cam.look_at(_looks[0])
	cam.current = true
	_snow = WeatherFX.streaks(Vector3(60, 25, 60), 900, Vector3(0, -2.0, 0), 9.0)
	var m := _snow.process_material as ParticleProcessMaterial
	m.scale_min = 1.0
	m.scale_max = 2.4
	m.spread = 25.0
	_snow.local_coords = false
	add_child(_snow)
	_running = true


func _catmull(pts: Array[Vector3], u: float) -> Vector3:
	var n := pts.size() - 1
	var x := clampf(u, 0.0, 1.0) * n
	var i := mini(int(x), n - 1)
	var t := x - i
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, n)]
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	var u := _t / DURATION
	# Ease in and out of the whole flight.
	var e := u * u * (3.0 - 2.0 * u)
	var p := _catmull(_points, e)
	var look := _catmull(_looks, clampf(e + 0.02, 0.0, 1.0))
	cam.global_position = p
	if p.distance_to(look) > 0.5:
		cam.look_at(look)
	_snow.global_position = p + Vector3(0, 10, 0)
	if _t >= DURATION:
		_running = false
		finished.emit()
