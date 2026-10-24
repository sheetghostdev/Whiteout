class_name OverviewMap
extends Control
## Live map: shaded relief tinted by the coverage texture, with the player,
## active storms and per-region completion.

signal closed()

var _map: TextureRect
var _overlay: Control
var _regions: VBoxContainer
var _relief: ImageTexture
const MAP_SIZE := 560.0


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	MenuScreens.backdrop(self, 0.5)
	var vb := MenuScreens.centered_panel(self, Vector2(980, 680))
	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(ProceduralIcon.make("map", 30, UIKit.ACCENT))
	var t := UIKit.title("OVERVIEW", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(t)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	vb.add_child(body)
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	body.add_child(frame)
	_map = TextureRect.new()
	_map.size = Vector2(MAP_SIZE, MAP_SIZE)
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = ShaderLib.shader("map")
	_map.material = mat
	frame.add_child(_map)
	_overlay = Control.new()
	_overlay.size = Vector2(MAP_SIZE, MAP_SIZE)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	frame.add_child(_overlay)
	_regions = VBoxContainer.new()
	_regions.add_theme_constant_override("separation", 10)
	_regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_regions)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var back := UIKit.button("Close  (M)", 180)
	back.pressed.connect(func(): closed.emit())
	hb.add_child(back)


func build_relief(terrain: TerrainData, colors: PackedColorArray) -> void:
	var n := TerrainData.N
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var V := TerrainData.V
	var light := Vector3(-0.5, 0.75, -0.45).normalized()
	for j in n:
		for i in n:
			var idx := j * V + i
			var hx := terrain.heights[idx + 1] - terrain.heights[idx]
			var hz := terrain.heights[idx + V] - terrain.heights[idx]
			var nrm := Vector3(-hx, 1.0, -hz).normalized()
			var shade := clampf(nrm.dot(light) * 0.6 + 0.55, 0.35, 1.15)
			var c := colors[idx]
			if terrain.cell_water[j * n + i] == 1:
				c = Color(0.30, 0.62, 0.78)
				shade = 1.0
			elif terrain.cell_ocean[j * n + i] == 1:
				var depth := clampf(-terrain.heights[idx] / 12.0, 0.0, 1.0)
				c = Color(0.36, 0.68, 0.80).lerp(Color(0.16, 0.38, 0.62), depth)
				shade = 1.0
			elif terrain.cell_built[j * n + i] == 1 and terrain.settlements.building_at(Vector2(i - 256.0 + 0.5, j - 256.0 + 0.5), 0.0):
				c = Color(0.55, 0.30, 0.24)
				shade = 1.0
			img.set_pixel(i, j, Color(c.r * shade, c.g * shade, c.b * shade, clampf(shade - 0.2, 0.0, 1.0)))
	_relief = ImageTexture.create_from_image(img)
	_map.texture = _relief
	(_map.material as ShaderMaterial).set_shader_parameter("relief", _relief)


func open() -> void:
	visible = true
	for c in _regions.get_children():
		c.queue_free()
	var cov := Game.coverage()
	_regions.add_child(UIKit.label("REGIONS", 15, UIKit.ACCENT))
	for r in SnowCoverage.REGION_COUNT:
		var f := cov.region_completion(r)
		var box := VBoxContainer.new()
		box.add_child(UIKit.label("%s   %d%%" % [GameBalance.REGION_NAMES[r], int(floor(f * 100.0))], 18, Color.WHITE))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.value = f
		bar.custom_minimum_size = Vector2(300, 8)
		box.add_child(bar)
		_regions.add_child(box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	_regions.add_child(gap)
	_regions.add_child(UIKit.label("World  %.1f%% frozen" % (cov.world_completion() * 100.0), 20, Color.WHITE))
	var remaining := cov.total_incomplete
	_regions.add_child(UIKit.label("%s m² still unfrozen" % UIKit.fmt(remaining), 15, UIKit.TEXT_DIM))
	var legend := UIKit.label("White = frozen   ·   Green = still to freeze\nTriangle = you, facing the camera   ·   Rings = your cloud and storms", 14, UIKit.TEXT_DIM)
	_regions.add_child(legend)


func _process(_delta: float) -> void:
	if visible:
		_overlay.queue_redraw()


func _w2m(p: Vector2) -> Vector2:
	return (p + Vector2(256, 256)) / 512.0 * MAP_SIZE


func _draw_overlay() -> void:
	if Game.weather == null:
		return
	for e in Game.weather.effects:
		if not e.alive or e.kind == "frost_pulse":
			continue
		var r := maxf(e.radius / 512.0 * MAP_SIZE, 3.0)
		_overlay.draw_arc(_w2m(e.pos), r, 0, TAU, 24, Color(0.5, 0.75, 1.0, 0.9), 2.0, true)
	# Late game: point out the largest unfrozen patches.
	var cov := Game.coverage()
	if cov.world_completion() > 0.9:
		for p in cov.unfrozen_patches(10):
			var c := _w2m(Vector2(p.x, p.z))
			_overlay.draw_arc(c, 7.0, 0, TAU, 16, Color(1.0, 0.6, 0.25, 0.95), 2.0, true)
	if Game.player != null:
		var pl: CloudController = Game.player
		var pos := _w2m(Vector2(pl.global_position.x, pl.global_position.z))
		var f := Vector2(-sin(pl.yaw), -cos(pl.yaw))
		var s := f.orthogonal()
		var tri := PackedVector2Array([pos + f * 11.0, pos - f * 6.0 + s * 6.0, pos - f * 6.0 - s * 6.0])
		_overlay.draw_colored_polygon(tri, Color(1.0, 0.45, 0.35))
		_overlay.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color.WHITE, 1.5, true)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("map") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		closed.emit()
