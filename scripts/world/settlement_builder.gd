class_name SettlementBuilder
extends Node3D
## Builds the island's towns from the SettlementPlan: houses, cottages and
## cabins, the church, tavern, barn, windmill, lighthouse, boathouses and
## sawmill, with their props, fences, fields, piers, boats and the bridge.
## Buildings use the shared tree shader's "rock" material, so snow settles on
## roofs from the coverage texture.
##
## Window panes and lanterns are a separate mesh whose glow comes from a
## small "warmth" texture: one texel per building, one per town. In summer
## nobody lights a fire; once a town has sat under snow for a while its
## people light their stoves one house at a time, chimneys start to smoke and
## windows glow, and the lamplighter does the street lamps.

const WALLS: Array[Color] = [Color(0.93, 0.88, 0.76), Color(0.95, 0.91, 0.72), Color(0.92, 0.93, 0.92),
	Color(0.76, 0.85, 0.90), Color(0.86, 0.66, 0.52), Color(0.80, 0.84, 0.74)]
const STONE_WALLS: Array[Color] = [Color(0.62, 0.60, 0.57), Color(0.70, 0.66, 0.60), Color(0.56, 0.55, 0.56)]
const ROOFS: Array[Color] = [Color(0.66, 0.30, 0.20), Color(0.30, 0.32, 0.38), Color(0.48, 0.30, 0.22), Color(0.36, 0.44, 0.30),
	Color(0.58, 0.36, 0.26)]
const SHUTTERS: Array[Color] = [Color(0.22, 0.40, 0.30), Color(0.25, 0.32, 0.52), Color(0.56, 0.20, 0.18), Color(0.30, 0.26, 0.22)]
const THATCH := Color(0.70, 0.58, 0.36)
const TIMBER := Color(0.30, 0.22, 0.16)
const WOOD := Color(0.48, 0.34, 0.22)
const DARK_WOOD := Color(0.34, 0.25, 0.18)
const STONE := Color(0.56, 0.54, 0.51)

var terrain: TerrainData
var plan: SettlementPlan
var villagers: Villagers
var coverage: SnowCoverage
var homes: Array = []          # {building, town, chimney: Vector3, smoke, delay, fire}
var _mat: ShaderMaterial
var _glass_mat: ShaderMaterial
var _crop_mat: ShaderMaterial
var _gb: MeshBuilder            # glass panes, built alongside the walls
var _warm_img: Image
var _warm_tex: ImageTexture
var _warm := PackedFloat32Array()
var _warm_count := 0
var _warm_timer := 0.0
var _sails: Array[Node3D] = []
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _campfires: Array = []     # {pos, town, flames, delay, fire}
var _rng := RandomNumberGenerator.new()
# Crop withering: each field cell ages once it is frozen, over WITHER_TIME.
const WITHER_TIME := 150.0
var _wither_origin := Vector2i.ZERO
var _wither_size := Vector2i.ONE
var _wither := PackedFloat32Array()
var _wither_cells := PackedInt32Array()   # coverage index per wither texel (-1 if not a field)
var _wither_img: Image
var _wither_tex: ImageTexture
var _wither_timer := 0.0


func build(t: TerrainData, p_coverage: SnowCoverage) -> void:
	terrain = t
	coverage = p_coverage
	plan = t.settlements
	_rng.seed = t.seed_value * 13 + 3
	_mat = ShaderLib.material("tree")
	_mat.set_shader_parameter("per_vertex_snow", true)
	_mat.set_shader_parameter("per_pixel_snow", true)
	_mat.set_shader_parameter("sway_amount", 0.0)
	_warm_count = plan.buildings.size() + SettlementPlan.TOWNS.size()
	_warm.resize(_warm_count)
	_warm.fill(0.0)
	_warm_img = Image.create(_warm_count, 1, false, Image.FORMAT_R8)
	_warm_tex = ImageTexture.create_from_image(_warm_img)
	_glass_mat = ShaderLib.material("windows")
	_glass_mat.set_shader_parameter("warmth", _warm_tex)
	var mb := MeshBuilder.new()
	_gb = MeshBuilder.new()
	for i in plan.buildings.size():
		_building(mb, plan.buildings[i], i)
	for p in plan.props:
		_prop(mb, p)
	for f in plan.fences:
		_fence(mb, f[0], f[1])
	for br in plan.bridges:
		_bridge(mb, br)
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = mb.commit()
	mi.material_override = _mat
	add_child(mi)
	var gi := MeshInstance3D.new()
	gi.name = "Windows"
	gi.mesh = _gb.commit()
	gi.material_override = _glass_mat
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	var crops := MeshBuilder.new()
	for f in plan.fields:
		_field(crops, f)
	if crops.vertex_count() > 0:
		var cm := MeshInstance3D.new()
		cm.name = "Crops"
		cm.mesh = crops.commit()
		_crop_mat = ShaderLib.material("crops")
		_setup_wither()
		cm.material_override = _crop_mat
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cm.extra_cull_margin = 2.0
		add_child(cm)
	villagers = Villagers.new()
	villagers.name = "Villagers"
	add_child(villagers)
	villagers.setup(t, p_coverage, plan)


# ------------------------------------------------------------ withering
func _setup_wither() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for f in plan.fields:
		var c: Vector2 = f["center"]
		var r: float = (f["size"] as Vector2).length() * 0.5 + 2.0
		lo = lo.min(c - Vector2(r, r))
		hi = hi.max(c + Vector2(r, r))
	_wither_origin = Vector2i(int(floor(lo.x + TerrainData.HALF)), int(floor(lo.y + TerrainData.HALF)))
	_wither_size = Vector2i(int(ceil(hi.x - lo.x)), int(ceil(hi.y - lo.y)))
	var n := _wither_size.x * _wither_size.y
	_wither.resize(n)
	_wither.fill(0.0)
	_wither_cells.resize(n)
	for j in _wither_size.y:
		for i in _wither_size.x:
			var ci := _wither_origin.x + i
			var cj := _wither_origin.y + j
			var idx := -1
			if ci >= 0 and cj >= 0 and ci < TerrainData.N and cj < TerrainData.N and terrain.cell_built[cj * TerrainData.N + ci] == 2:
				idx = cj * TerrainData.N + ci
			_wither_cells[j * _wither_size.x + i] = idx
	_wither_img = Image.create(_wither_size.x, _wither_size.y, false, Image.FORMAT_R8)
	_wither_tex = ImageTexture.create_from_image(_wither_img)
	_crop_mat.set_shader_parameter("wither_tex", _wither_tex)
	_crop_mat.set_shader_parameter("wither_rect", Vector4(_wither_origin.x - TerrainData.HALF, _wither_origin.y - TerrainData.HALF,
		_wither_size.x, _wither_size.y))


## New winter: fresh crops, cold hearths. Loaded game: crops already under
## snow are dead, and towns that are already snowed in have their fires lit.
func reset_crops(already_frozen_dead: bool) -> void:
	for k in _wither.size():
		var idx := _wither_cells[k]
		_wither[k] = 1.0 if already_frozen_dead and idx >= 0 and coverage.cov[idx] >= 1.0 else 0.0
	_upload_wither()


func _process(delta: float) -> void:
	if coverage == null:
		return
	_update_fires(delta)
	for s in _sails:
		s.rotate_object_local(Vector3(0, 0, 1), -delta * 0.55)
	if _beam != null:
		_beam.rotation.y += delta * 0.9
	if _crop_mat == null:
		return
	_wither_timer += delta
	if _wither_timer < 0.5:
		return
	var step := _wither_timer / WITHER_TIME
	_wither_timer = 0.0
	var changed := false
	for k in _wither.size():
		var idx := _wither_cells[k]
		if idx < 0 or _wither[k] >= 1.0:
			continue
		if coverage.cov[idx] >= 1.0:
			_wither[k] = minf(_wither[k] + step, 1.0)
			changed = true
	if changed:
		_upload_wither()


func _upload_wither() -> void:
	var bytes := PackedByteArray()
	bytes.resize(_wither.size())
	for k in _wither.size():
		bytes[k] = int(_wither[k] * 255.0)
	_wither_img.set_data(_wither_size.x, _wither_size.y, false, Image.FORMAT_R8, bytes)
	_wither_tex.update(_wither_img)


# ------------------------------------------------------------- hearths
## Fires are lit house by house once a town has been under snow for a while
## (each home has its own delay); when the snow is gone they go out again.
func _update_fires(delta: float) -> void:
	_warm_timer += delta
	if _warm_timer < 0.25 or villagers == null:
		return
	var dt := _warm_timer
	_warm_timer = 0.0
	var changed := false
	for h in homes:
		var lit := villagers.winter_time(int(h["town"])) > float(h["delay"])
		var f: float = h["fire"]
		var nf := move_toward(f, 1.0 if lit else 0.0, dt * (0.35 if lit else 0.15))
		if nf != f:
			h["fire"] = nf
			_warm[int(h["building"])] = nf
			changed = true
		var smoke: GPUParticles3D = h["smoke"]
		if smoke != null:
			smoke.emitting = nf > 0.4
	for c in _campfires:
		var lit := villagers.winter_time(int(c["town"])) > float(c["delay"])
		c["fire"] = move_toward(float(c["fire"]), 1.0 if lit else 0.0, dt * 0.3)
		(c["flames"] as GPUParticles3D).emitting = float(c["fire"]) > 0.3
		(c["smoke"] as GPUParticles3D).emitting = float(c["fire"]) > 0.3
	# The church fills for a winter service, the lamplighter does his round
	# and the lighthouse keeper lights the lamp.
	for i in plan.buildings.size():
		var b: Dictionary = plan.buildings[i]
		if b["home"]:
			continue
		var target := 0.0
		match String(b["kind"]):
			"church":
				target = 1.0 if villagers.winter_time(int(b["town"])) > 25.0 else 0.0
			"lighthouse":
				target = 0.35 + 0.65 * minf(villagers.winter_time(int(b["town"])) / 20.0, 1.0)
		var nw := move_toward(_warm[i], target, dt * 0.4)
		if nw != _warm[i]:
			_warm[i] = nw
			changed = true
	for t in SettlementPlan.TOWNS.size():
		var k := plan.buildings.size() + t
		var nw := move_toward(_warm[k], 1.0 if villagers.winter_time(t) > 15.0 else 0.0, dt * 0.5)
		if nw != _warm[k]:
			_warm[k] = nw
			changed = true
	if _beam != null:
		_beam_mat.albedo_color.a = 0.12 * clampf((_warm[_lighthouse_index()] - 0.35) / 0.65, 0.0, 1.0)
		_beam.visible = _beam_mat.albedo_color.a > 0.002
	if changed:
		var bytes := PackedByteArray()
		bytes.resize(_warm_count)
		for k in _warm_count:
			bytes[k] = int(clampf(_warm[k], 0.0, 1.0) * 255.0)
		_warm_img.set_data(_warm_count, 1, false, Image.FORMAT_R8, bytes)
		_warm_tex.update(_warm_img)


func _lighthouse_index() -> int:
	for i in plan.buildings.size():
		if plan.buildings[i]["kind"] == "lighthouse":
			return i
	return 0


## Fraction of homes with a fire burning (0..1), for tests and the guide.
func fires_lit() -> float:
	if homes.is_empty():
		return 0.0
	var n := 0.0
	for h in homes:
		if float(h["fire"]) > 0.5:
			n += 1.0
	return n / homes.size()


# ---------------------------------------------------------------- helpers
## Flat triangle that always faces `outward` (winding fixed automatically).
func _tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, col: Color, outward: Vector3) -> void:
	if (c - a).cross(b - a).dot(outward) < 0.0:
		mb.add_flat_tri(a, c, b, col, col, col)
	else:
		mb.add_flat_tri(a, b, c, col, col, col)


func _quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward: Vector3) -> void:
	_tri(mb, a, b, c, col, outward)
	_tri(mb, a, c, d, col, outward)


## Oriented box: centre, half-size, rotation about Y.
func _box(mb: MeshBuilder, c: Vector3, h: Vector3, rot: float, col: Color, skip_bottom: bool = true) -> void:
	var bs := Basis(Vector3.UP, rot)
	var ax := bs * Vector3(h.x, 0, 0)
	var ay := Vector3(0, h.y, 0)
	var az := bs * Vector3(0, 0, h.z)
	var faces := [[ay, ax, az], [-ax, az, ay], [ax, az, ay], [az, ax, ay], [-az, ax, ay]]
	if not skip_bottom:
		faces.append([-ay, ax, az])
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o: Vector3 = c + n
		_quad(mb, o - u - v, o + u - v, o + u + v, o - u + v, col, n.normalized())


## A pane of glass (or a lantern face) in the window mesh. `idx` selects the
## warmth texel that lights it.
func _pane(c: Vector3, normal: Vector3, half_w: float, half_h: float, idx: int) -> void:
	var n := normal.normalized()
	var u := Vector3.UP.cross(n).normalized() * half_w
	var v := Vector3.UP * half_h
	if absf(n.y) > 0.9:
		u = Vector3.RIGHT * half_w
		v = Vector3.FORWARD * half_h
	var uv := Vector2((idx + 0.5) / float(_warm_count), _rng.randf())
	var a := c - u - v
	var b := c + u - v
	var cc := c + u + v
	var d := c - u + v
	var i := _gb.vertex_count()
	for p in [a, b, cc, d]:
		_gb.add_vertex(p, n, Color.WHITE, uv)
	if (cc - a).cross(b - a).dot(n) < 0.0:
		_gb.add_tri_idx(i, i + 2, i + 1)
		_gb.add_tri_idx(i, i + 3, i + 2)
	else:
		_gb.add_tri_idx(i, i + 1, i + 2)
		_gb.add_tri_idx(i, i + 2, i + 3)


func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 0.5)


func _rock(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.5)


func _ground(p: Vector2) -> float:
	return terrain.sample_height(p.x, p.y)


## Local-to-world helper for a building frame.
class Frame:
	var origin: Vector3
	var bs: Basis
	var rot: float
	func _init(o: Vector3, r: float) -> void:
		origin = o
		rot = r
		bs = Basis(Vector3.UP, r)
	func at(x: float, y: float, z: float) -> Vector3:
		return origin + bs * Vector3(x, y, z)
	func dir(x: float, y: float, z: float) -> Vector3:
		return bs * Vector3(x, y, z)


# -------------------------------------------------------------- buildings
func _building(mb: MeshBuilder, b: Dictionary, index: int) -> void:
	var pos: Vector2 = b["pos"]
	var kind: String = b["kind"]
	var r := RandomNumberGenerator.new()
	r.seed = int(b["seed"])
	var f := Frame.new(Vector3(pos.x, _ground(pos) - 0.15, pos.y), float(b["rot"]))
	match kind:
		"windmill":
			_windmill(mb, f, b, index)
		"lighthouse":
			_lighthouse(mb, f, b, index)
		"sawmill":
			_sawmill(mb, f, b)
		"hut":
			_hut(mb, f, b, r, index)
		_:
			_house(mb, f, b, r, index)


## Houses, cottages, the tavern, church, barn, shed and boathouses: walls on
## a stone footing under a thick gable roof, with framed windows, shutters,
## a door with a step and lantern, and a chimney on homes.
func _house(mb: MeshBuilder, f: Frame, b: Dictionary, r: RandomNumberGenerator, index: int) -> void:
	var kind: String = b["kind"]
	var s: Vector3 = b["size"]
	var hw := s.x * 0.5
	var hd := s.z * 0.5
	var h := s.y
	var wall := WALLS[r.randi() % WALLS.size()]
	var roof := ROOFS[r.randi() % ROOFS.size()]
	var shutter := SHUTTERS[r.randi() % SHUTTERS.size()]
	var timbered := kind == "house" and r.randf() < 0.45
	var stone_walls := false
	match kind:
		"barn":
			wall = Color(0.62, 0.20, 0.15)
			roof = Color(0.32, 0.30, 0.30)
		"church":
			wall = Color(0.90, 0.89, 0.86)
			roof = Color(0.30, 0.32, 0.38)
			stone_walls = true
		"tavern":
			wall = Color(0.90, 0.84, 0.68)
			roof = Color(0.40, 0.26, 0.20)
			timbered = true
		"shed", "boathouse":
			wall = Color(0.50, 0.38, 0.26)
		"cottage":
			roof = THATCH
			if r.randf() < 0.4:
				wall = STONE_WALLS[r.randi() % STONE_WALLS.size()]
				stone_walls = true
	if kind == "house" and r.randf() < 0.25:
		wall = STONE_WALLS[r.randi() % STONE_WALLS.size()]
		stone_walls = true
		timbered = false
	wall = _rock(wall)
	roof = _rock(roof)
	# Stone footing so the house sits into the slope.
	_box(mb, f.at(0, 0.25, 0), Vector3(hw + 0.15, 0.4, hd + 0.15), f.rot, _rock(STONE))
	_box(mb, f.at(0, 0.65 + h * 0.5, 0), Vector3(hw, h * 0.5, hd), f.rot, wall)
	var top := 0.65 + h
	if kind == "tavern":
		# A jettied upper floor: a beam band and a slightly wider storey.
		_box(mb, f.at(0, 0.65 + h * 0.5, 0), Vector3(hw + 0.12, 0.12, hd + 0.12), f.rot, _rock(TIMBER))
	if kind == "shed":
		_shed_roof(mb, f, hw, hd, top, roof, wall)
		return
	if timbered:
		_timbers(mb, f, hw, hd, h)
	var rise := SettlementPlan.roof_rise(b)
	var over := 0.5 if kind != "cottage" else 0.7
	var thick := 0.22 if roof != _rock(THATCH) else 0.45
	_gable_roof(mb, f, hw, hd, top, rise, over, thick, roof, wall)
	# Door and windows.
	var door := _rock(Color(0.36, 0.24, 0.16) if kind != "church" else Color(0.40, 0.22, 0.14))
	var frame := _rock(Color(0.95, 0.95, 0.92) if not stone_walls else Color(0.80, 0.78, 0.74))
	var dx := r.randf_range(-hw * 0.35, hw * 0.35) if kind in ["house", "cottage"] else 0.0
	var dw := 0.55
	var dh := 1.1
	if kind == "barn":
		dw = hw * 0.55
		dh = h * 0.42
	elif kind in ["church", "tavern"]:
		dw = 0.8
		dh = 1.35
	elif kind == "boathouse":
		dw = hw * 0.7
		dh = h * 0.4
	_box(mb, f.at(dx, 0.65 + dh, hd + 0.04), Vector3(dw + 0.12, dh + 0.1, 0.05), f.rot, frame)
	_box(mb, f.at(dx, 0.65 + dh, hd + 0.08), Vector3(dw, dh, 0.05), f.rot, door)
	_box(mb, f.at(dx, 0.5, hd + 0.45), Vector3(dw + 0.2, 0.12, 0.35), f.rot, _rock(STONE))
	if kind == "barn":
		# White cross braces on the big doors and a hayloft hatch.
		for y in [0.65 + 0.1, 0.65 + dh, 0.65 + dh * 2.0 - 0.1]:
			_box(mb, f.at(dx, y, hd + 0.13), Vector3(dw, 0.08, 0.04), f.rot, frame)
		_box(mb, f.at(0, 0.65 + h * 0.86 + 0.6, hd + 0.05), Vector3(0.7, 0.6, 0.05), f.rot, door)
		return
	if kind == "boathouse":
		return
	# A lantern beside the door.
	var lamp_x := dx + dw + 0.45
	_box(mb, f.at(lamp_x, 0.65 + dh * 1.6, hd + 0.18), Vector3(0.12, 0.16, 0.12), f.rot, _rock(Color(0.15, 0.15, 0.16)))
	_pane(f.at(lamp_x, 0.65 + dh * 1.6, hd + 0.31), f.dir(0, 0, 1), 0.08, 0.11, index)
	var wy := 0.65 + h * 0.62 if kind != "cottage" else 0.65 + h * 0.55
	var wh := 0.5 if kind != "church" else 1.2
	var ww := 0.45 if kind != "church" else 0.42
	# Front windows (skipping the door), upper floor for tall houses.
	var fronts: Array = []
	for wx in [-hw * 0.6, hw * 0.6, 0.0]:
		if absf(wx - dx) < dw + ww + 0.3:
			continue
		fronts.append([wx, wy])
	if (kind == "house" and h > 4.3) or kind == "tavern":
		for wx in [-hw * 0.55, 0.0, hw * 0.55]:
			fronts.append([wx, 0.65 + h * 0.84])
		for e in fronts:
			if float(e[1]) < 0.65 + h * 0.7:
				e[1] = 0.65 + h * 0.36
	for e in fronts:
		_window(mb, f, Vector3(float(e[0]), float(e[1]), hd), Vector3(0, 0, 1), ww, wh, frame, shutter, index, r, kind)
	for wz in [-hd * 0.45, hd * 0.45]:
		for side in [-1.0, 1.0]:
			_window(mb, f, Vector3(side * hw, wy, wz), Vector3(side, 0, 0), ww, wh, frame, shutter, index, r, kind)
	if kind == "church":
		_steeple(mb, f, hd, top, wall, roof, index)
		return
	if kind == "tavern":
		# The inn sign hangs from a bracket by the door.
		_box(mb, f.at(dx - dw - 1.1, 0.65 + h * 0.5 + 0.3, hd + 0.6), Vector3(0.05, 0.05, 0.6), f.rot, _rock(TIMBER))
		_box(mb, f.at(dx - dw - 1.1, 0.65 + h * 0.5 - 0.25, hd + 0.95), Vector3(0.04, 0.42, 0.34).rotated(Vector3.UP, 0.0),
			f.rot + PI * 0.5, _rock(Color(0.62, 0.42, 0.18)))
	if b["home"]:
		var cx := hw * 0.5 * (1.0 if r.randf() < 0.5 else -1.0)
		var cz := r.randf_range(-hd * 0.4, hd * 0.4)
		var ch_top := top + rise * (1.0 - absf(cx) / hw) + 1.0
		_box(mb, f.at(cx, ch_top - 1.0, cz), Vector3(0.34, 1.0, 0.34), f.rot, _rock(Color(0.52, 0.47, 0.44)))
		_box(mb, f.at(cx, ch_top + 0.05, cz), Vector3(0.42, 0.07, 0.42), f.rot, _rock(Color(0.44, 0.40, 0.38)))
		_add_home(index, int(b["town"]), f.at(cx, ch_top + 0.2, cz))


func _add_home(index: int, town: int, chimney: Vector3) -> void:
	var smoke := _smoke(chimney)
	smoke.emitting = false
	homes.append({"building": index, "town": town, "chimney": chimney, "smoke": smoke,
		"delay": _rng.randf_range(6.0, 40.0), "fire": 0.0})


## A window: frame, sill, glass pane and (on homes) shutters and window boxes.
func _window(mb: MeshBuilder, f: Frame, at: Vector3, out: Vector3, ww: float, wh: float, frame: Color, shutter: Color,
		index: int, r: RandomNumberGenerator, kind: String) -> void:
	var rot := f.rot + (PI * 0.5 if absf(out.x) > 0.5 else 0.0)
	var c := f.at(at.x + out.x * 0.04, at.y, at.z + out.z * 0.04)
	var n := f.dir(out.x, 0, out.z)
	_box(mb, c, Vector3(ww + 0.08, wh + 0.08, 0.05), rot, frame)
	_pane(c + n * 0.06, n, ww, wh, index)
	# Mullions.
	_box(mb, c + n * 0.07, Vector3(0.03, wh, 0.02), rot, frame)
	_box(mb, c + n * 0.07, Vector3(ww, 0.03, 0.02), rot, frame)
	_box(mb, c + n * 0.12 + Vector3(0, -wh - 0.06, 0), Vector3(ww + 0.14, 0.05, 0.12), rot, frame)
	if kind in ["church", "barn", "boathouse"]:
		return
	var side := Vector3.UP.cross(n).normalized()
	for sgn in [-1.0, 1.0]:
		_box(mb, c + side * sgn * (ww + 0.26) + n * 0.03, Vector3(0.22, wh, 0.04), rot, _rock(shutter))
	if r.randf() < 0.45:
		# A window box of flowers.
		_box(mb, c + n * 0.22 + Vector3(0, -wh - 0.2, 0), Vector3(ww, 0.12, 0.14), rot, _rock(WOOD))
		var petal: Color = [Color(0.92, 0.30, 0.32), Color(0.98, 0.82, 0.30), Color(0.86, 0.50, 0.80), Color(0.95, 0.95, 0.95)][r.randi() % 4]
		for k in 4:
			var px := lerpf(-ww * 0.75, ww * 0.75, k / 3.0)
			_box(mb, c + n * 0.22 + side * px + Vector3(0, -wh - 0.02, 0), Vector3(0.1, 0.09, 0.08), rot + k, _rock(petal))


## Dark timber framing over light plaster.
func _timbers(mb: MeshBuilder, f: Frame, hw: float, hd: float, h: float) -> void:
	var t := _rock(TIMBER)
	for side in [-1.0, 1.0]:
		for x in [-hw, -hw * 0.33, hw * 0.33, hw]:
			_box(mb, f.at(x, 0.65 + h * 0.5, side * (hd + 0.04)), Vector3(0.1, h * 0.5, 0.04), f.rot, t)
		for y in [0.75, 0.65 + h * 0.5, 0.65 + h - 0.08]:
			_box(mb, f.at(0, y, side * (hd + 0.05)), Vector3(hw, 0.08, 0.04), f.rot, t)
		for z in [-hd, 0.0, hd]:
			_box(mb, f.at(side * (hw + 0.04), 0.65 + h * 0.5, z), Vector3(0.04, h * 0.5, 0.1), f.rot, t)
		for y in [0.75, 0.65 + h * 0.5, 0.65 + h - 0.08]:
			_box(mb, f.at(side * (hw + 0.05), y, 0), Vector3(0.04, 0.08, hd), f.rot, t)


## Gable roof with real thickness: sloped tops, fascia boards along the
## edges, darker undersides, a ridge cap and gable-end walls.
func _gable_roof(mb: MeshBuilder, f: Frame, hw: float, hd: float, top: float, rise: float, over: float, thick: float,
		roof: Color, wall: Color) -> void:
	var y0 := top - 0.25
	var e0 := f.at(-hw - over, y0, -hd - over)
	var e1 := f.at(-hw - over, y0, hd + over)
	var r0 := f.at(0.0, top + rise, -hd - over)
	var r1 := f.at(0.0, top + rise, hd + over)
	var g0 := f.at(hw + over, y0, -hd - over)
	var g1 := f.at(hw + over, y0, hd + over)
	var up := Vector3(0, thick, 0)
	var left_n := f.dir(-rise, hw + over, 0).normalized()
	var right_n := f.dir(rise, hw + over, 0).normalized()
	_quad(mb, e0 + up, e1 + up, r1 + up, r0 + up, roof, left_n)
	_quad(mb, g0 + up, r0 + up, r1 + up, g1 + up, roof, right_n)
	var under := _shade(roof, 0.5)
	_quad(mb, e0, r0, r1, e1, under, -left_n)
	_quad(mb, g0, g1, r1, r0, under, -right_n)
	var edge := _shade(roof, 0.75)
	# Eave fascias and the sloped gable edges.
	_quad(mb, e0, e1, e1 + up, e0 + up, edge, f.dir(-1, 0, 0))
	_quad(mb, g0, g1, g1 + up, g0 + up, edge, f.dir(1, 0, 0))
	for z in [-1.0, 1.0]:
		var a := e0 if z < 0.0 else e1
		var rr := r0 if z < 0.0 else r1
		var g := g0 if z < 0.0 else g1
		var out := f.dir(0, 0, z)
		_quad(mb, a, rr, rr + up, a + up, edge, out)
		_quad(mb, rr, g, g + up, rr + up, edge, out)
	# Ridge cap.
	var ridge := (r0 + r1) * 0.5 + up + Vector3(0, 0.06, 0)
	_box(mb, ridge, Vector3(0.14, 0.08, hd + over + 0.05), f.rot, _shade(roof, 0.8))
	# Gable ends.
	for side in [-1.0, 1.0]:
		var zz: float = side * hd
		var out: Vector3 = f.dir(0, 0, side)
		_tri(mb, f.at(-hw, top, zz), f.at(hw, top, zz), f.at(0.0, top + rise - 0.2, zz), wall, out)


func _shed_roof(mb: MeshBuilder, f: Frame, hw: float, hd: float, top: float, roof: Color, wall: Color) -> void:
	var a := f.at(-hw - 0.3, top + 0.9, -hd - 0.3)
	var b := f.at(hw + 0.3, top - 0.1, -hd - 0.3)
	var c := f.at(hw + 0.3, top - 0.1, hd + 0.3)
	var d := f.at(-hw - 0.3, top + 0.9, hd + 0.3)
	_quad(mb, a, b, c, d, roof, f.dir(0.4, 1, 0).normalized())
	_quad(mb, a, d, c, b, _shade(roof, 0.55), f.dir(-0.4, -1, 0).normalized())
	for side in [-1.0, 1.0]:
		var zz: float = side * hd
		_tri(mb, f.at(-hw, top, zz), f.at(hw, top, zz), f.at(-hw, top + 0.85, zz), wall, f.dir(0, 0, side))
	_box(mb, f.at(0, 0.65 + 1.0, hd + 0.05), Vector3(0.6, 1.0, 0.05), f.rot, _rock(DARK_WOOD))


## The church tower over the door: belfry, clock faces and a slate spire.
func _steeple(mb: MeshBuilder, f: Frame, hd: float, top: float, wall: Color, roof: Color, index: int) -> void:
	var tower_c := f.at(0, 0, hd + 1.6)
	var th := top + 6.0
	_box(mb, tower_c + Vector3(0, th * 0.5, 0), Vector3(1.6, th * 0.5, 1.6), f.rot, wall)
	# The church door is in the foot of the tower.
	var front := f.dir(0, 0, 1)
	_box(mb, tower_c + front * 1.62 + Vector3(0, 1.45, 0), Vector3(0.75, 1.45, 0.05), f.rot, _rock(Color(0.80, 0.78, 0.74)))
	_box(mb, tower_c + front * 1.66 + Vector3(0, 1.35, 0), Vector3(0.62, 1.32, 0.05), f.rot, _rock(Color(0.40, 0.22, 0.14)))
	_box(mb, tower_c + Vector3(0, th - 0.1, 0), Vector3(1.75, 0.18, 1.75), f.rot, _rock(Color(0.76, 0.74, 0.70)))
	var tip := tower_c + Vector3(0, th + 6.0, 0)
	for k in 8:
		var a := f.rot + PI * 0.125 + k * PI * 0.25
		var b := a + PI * 0.25
		var pa := tower_c + Vector3(sin(a) * 1.95, th, cos(a) * 1.95)
		var pb := tower_c + Vector3(sin(b) * 1.95, th, cos(b) * 1.95)
		var mid := (pa + pb) * 0.5 - tower_c
		_tri(mb, pa, pb, tip, roof, Vector3(mid.x, 0.4, mid.z).normalized())
	var gold := _rock(Color(0.85, 0.70, 0.30))
	_box(mb, tip + Vector3(0, 0.6, 0), Vector3(0.06, 0.6, 0.06), f.rot, gold)
	_box(mb, tip + Vector3(0, 0.8, 0), Vector3(0.3, 0.06, 0.06), f.rot, gold)
	for k in 4:
		var d := Basis(Vector3.UP, f.rot + k * PI * 0.5)
		var face := d * Vector3(0, 0, 1)
		# Belfry opening and a clock face below it.
		_box(mb, tower_c + Vector3(0, th - 1.4, 0) + face * 1.62, Vector3(0.5, 0.8, 0.04), f.rot + k * PI * 0.5, _rock(Color(0.16, 0.16, 0.2)))
		var clock := tower_c + Vector3(0, th - 3.4, 0) + face * 1.63
		_box(mb, clock, Vector3(0.62, 0.62, 0.03), f.rot + k * PI * 0.5, _rock(Color(0.95, 0.94, 0.88)))
		_box(mb, clock + face * 0.04 + Vector3(0, 0.2, 0), Vector3(0.04, 0.24, 0.02), f.rot + k * PI * 0.5, _rock(Color(0.1, 0.1, 0.1)))
		_box(mb, clock + face * 0.04 + d * Vector3(0.14, 0, 0), Vector3(0.16, 0.04, 0.02), f.rot + k * PI * 0.5, _rock(Color(0.1, 0.1, 0.1)))
	# Tall arched windows down the nave glow in a winter service.
	_pane(tower_c + Vector3(0, top * 0.55, 0) + f.dir(0, 0, 1) * 1.66, f.dir(0, 0, 1), 0.35, 0.9, index)


func _hut(mb: MeshBuilder, f: Frame, b: Dictionary, r: RandomNumberGenerator, index: int) -> void:
	var s: Vector3 = b["size"]
	var hw := s.x * 0.5
	var hd := s.z * 0.5
	var h := s.y
	_box(mb, f.at(0, 0.2, 0), Vector3(hw + 0.1, 0.3, hd + 0.1), f.rot, _rock(STONE))
	# Log walls: alternating courses, ends poking out at the corners.
	var logs := int(h / 0.32)
	for k in logs:
		var y := 0.5 + k * 0.32 + 0.16
		var col := _rock(WOOD if k % 2 == 0 else Color(0.42, 0.30, 0.20))
		_box(mb, f.at(0, y, hd), Vector3(hw + 0.25, 0.16, 0.16), f.rot, col)
		_box(mb, f.at(0, y, -hd), Vector3(hw + 0.25, 0.16, 0.16), f.rot, col)
		_box(mb, f.at(hw, y, 0), Vector3(0.16, 0.16, hd + 0.25), f.rot, col)
		_box(mb, f.at(-hw, y, 0), Vector3(0.16, 0.16, hd + 0.25), f.rot, col)
	_box(mb, f.at(0, 0.5 + h * 0.5, 0), Vector3(hw - 0.05, h * 0.5, hd - 0.05), f.rot, _rock(Color(0.38, 0.28, 0.19)))
	var top := 0.5 + logs * 0.32
	var roof := _rock(Color(0.30, 0.26, 0.22))
	_gable_roof(mb, f, hw, hd, top + 0.25, hw * 0.6, 0.6, 0.25, roof, _rock(WOOD))
	_box(mb, f.at(0, 0.5 + 0.95, hd + 0.2), Vector3(0.5, 0.95, 0.05), f.rot, _rock(DARK_WOOD))
	_window(mb, f, Vector3(hw * 0.55, 0.5 + h * 0.6, hd + 0.16), Vector3(0, 0, 1), 0.35, 0.35, _rock(WOOD), Color(0.3, 0.26, 0.22), index, r, "hut")
	var cx := -hw * 0.5
	var ch_top := top + 0.25 + hw * 0.6 * 0.5 + 0.9
	_box(mb, f.at(cx, ch_top - 1.0, -hd * 0.3), Vector3(0.3, 1.0, 0.3), f.rot, _rock(Color(0.50, 0.46, 0.43)))
	_add_home(index, int(b["town"]), f.at(cx, ch_top + 0.1, -hd * 0.3))


## An open-sided sawmill: posts, a long roof, the saw bench and a log.
func _sawmill(mb: MeshBuilder, f: Frame, b: Dictionary) -> void:
	var s: Vector3 = b["size"]
	var hw := s.x * 0.5
	var hd := s.z * 0.5
	var h := s.y
	for x in [-hw, hw]:
		for z in [-hd, 0.0, hd]:
			_box(mb, f.at(x, h * 0.5 + 0.3, z), Vector3(0.15, h * 0.5 + 0.3, 0.15), f.rot, _rock(DARK_WOOD))
	_gable_roof(mb, f, hw, hd, h + 0.6, hw * 0.45, 0.6, 0.2, _rock(Color(0.32, 0.30, 0.28)), _rock(WOOD))
	_box(mb, f.at(0, 0.6, 0), Vector3(0.7, 0.45, hd * 0.8), f.rot, _rock(WOOD))
	mb.add_tube(f.at(0, 1.35, -hd * 0.7), f.at(0, 1.35, hd * 0.5), 0.4, 0.4, 8, _rock(Color(0.55, 0.40, 0.26)), _rock(Color(0.55, 0.40, 0.26)), true)
	_box(mb, f.at(0, 1.3, hd * 0.65), Vector3(0.02, 0.5, 0.5), f.rot, _rock(Color(0.7, 0.72, 0.75)))


## A white tower windmill with a dark cap; the sails turn on their own node.
func _windmill(mb: MeshBuilder, f: Frame, b: Dictionary, index: int) -> void:
	var s: Vector3 = b["size"]
	var h := s.y
	var white := _rock(Color(0.93, 0.92, 0.88))
	_box(mb, f.at(0, 0.3, 0), Vector3(3.4, 0.5, 3.4), f.rot, _rock(STONE))
	mb.add_tube(f.at(0, 0.6, 0), f.at(0, h, 0), 3.0, 2.1, 8, white, white)
	var cap := _rock(Color(0.30, 0.24, 0.20))
	mb.add_tube(f.at(0, h, 0), f.at(0, h + 1.2, 0), 2.5, 2.4, 8, cap, cap)
	mb.add_tube(f.at(0, h + 1.2, 0), f.at(0, h + 3.4, 0), 2.4, 0.2, 8, cap, cap)
	_box(mb, f.at(0, h - 0.2, 0), Vector3(2.4, 0.15, 2.4), f.rot, _rock(Color(0.36, 0.28, 0.22)))
	# Door, little windows and a railing balcony.
	_box(mb, f.at(0, 1.6, 2.92), Vector3(0.6, 1.0, 0.1), f.rot, _rock(DARK_WOOD))
	for y in [h * 0.45, h * 0.72]:
		_pane(f.at(0, y, 3.0 - (y / h) * 0.9 + 0.08), f.dir(0, 0, 1), 0.3, 0.38, index)
	# Sails: four lattice blades on a hub, facing the front.
	var hub := f.at(0, h + 1.0, 2.9)
	mb.add_tube(f.at(0, h + 1.0, 1.6), hub, 0.25, 0.25, 8, cap, cap, true)
	var sm := MeshBuilder.new()
	var wood := _rock(Color(0.42, 0.32, 0.24))
	var cloth := _rock(Color(0.92, 0.88, 0.80))
	for k in 4:
		var a := k * PI * 0.5
		var dir := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		_spar(sm, dir * 0.3, dir * 8.4, 0.1, wood)
		for j in 6:
			var p := dir * (2.0 + j * 1.25)
			_spar(sm, p, p + side * 1.4, 0.05, wood)
		var p0 := dir * 1.9 + Vector3(0, 0, 0.04)
		var p1 := dir * 8.3 + Vector3(0, 0, 0.04)
		_quad(sm, p0, p1, p1 + side * 1.35, p0 + side * 1.35, cloth, Vector3(0, 0, 1))
		_quad(sm, p0, p1, p1 + side * 1.35, p0 + side * 1.35, _shade(cloth, 0.85), Vector3(0, 0, -1))
	var sails := MeshInstance3D.new()
	sails.mesh = sm.commit()
	sails.material_override = _mat
	add_child(sails)
	sails.global_transform = Transform3D(f.bs, hub + f.dir(0, 0, 0.2))
	_sails.append(sails)


## A thin square spar between two points (any direction).
func _spar(mb: MeshBuilder, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	mb.add_tube(a, b, r, r, 4, col, col, true)


## A striped lighthouse on its rock, with a gallery and a glowing lantern
## whose beam sweeps the sea once the winter nights draw in.
func _lighthouse(mb: MeshBuilder, f: Frame, b: Dictionary, index: int) -> void:
	var h: float = (b["size"] as Vector3).y
	_box(mb, f.at(0, 0.4, 0), Vector3(3.6, 0.7, 3.6), f.rot, _rock(STONE))
	var bands := 6
	for k in bands:
		var y0 := 1.0 + h * k / bands
		var y1 := 1.0 + h * (k + 1) / bands
		var r0 := lerpf(2.7, 1.9, float(k) / bands)
		var r1 := lerpf(2.7, 1.9, float(k + 1) / bands)
		var col := _rock(Color(0.94, 0.94, 0.92) if k % 2 == 0 else Color(0.74, 0.16, 0.14))
		mb.add_tube(f.at(0, y0, 0), f.at(0, y1, 0), r0, r1, 12, col, col)
	var top := 1.0 + h
	var dark := _rock(Color(0.20, 0.22, 0.24))
	mb.add_tube(f.at(0, top, 0), f.at(0, top + 0.25, 0), 2.7, 2.7, 12, dark, dark, true)
	for k in 12:
		var a := TAU * k / 12.0
		_box(mb, f.at(cos(a) * 2.55, top + 0.75, sin(a) * 2.55), Vector3(0.05, 0.5, 0.05), 0.0, dark)
	mb.add_tube(f.at(0, top + 1.2, 0), f.at(0, top + 1.28, 0), 2.6, 2.6, 12, dark, dark, true)
	# The lantern room: glass all round, a red dome and a vane.
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var n := Vector3(cos(a), 0, sin(a))
		_pane(f.at(0, top + 1.25, 0) + n * 1.3, n, 0.5, 0.95, index)
		_box(mb, f.at(cos(TAU * k / 8.0) * 1.38, top + 1.25, sin(TAU * k / 8.0) * 1.38), Vector3(0.06, 1.0, 0.06), 0.0, dark)
	var red := _rock(Color(0.70, 0.14, 0.12))
	mb.add_tube(f.at(0, top + 2.25, 0), f.at(0, top + 3.6, 0), 1.6, 0.1, 12, red, red)
	_box(mb, f.at(0, top + 3.9, 0), Vector3(0.05, 0.4, 0.05), 0.0, dark)
	_box(mb, f.at(0, 1.6, 2.6), Vector3(0.55, 0.95, 0.12), f.rot, _rock(DARK_WOOD))
	# The beam: a long, faint wedge of light that turns slowly.
	var bm := MeshBuilder.new()
	var w := Color(1.0, 0.95, 0.75)
	for sgn in [-1.0, 1.0]:
		bm.add_flat_tri(Vector3.ZERO, Vector3(sgn * 70.0, -6.0, 8.0), Vector3(sgn * 70.0, -6.0, -8.0), w, w, w)
		bm.add_flat_tri(Vector3.ZERO, Vector3(sgn * 70.0, -6.0, -8.0), Vector3(sgn * 70.0, -6.0, 8.0), w, w, w)
	_beam = MeshInstance3D.new()
	_beam.mesh = bm.commit()
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(1.0, 0.92, 0.7, 0.0)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_beam.global_position = f.at(0, top + 1.25, 0)
	_beam.visible = false


func _smoke(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(10 * WeatherFX.particle_density))
	p.lifetime = 5.0
	p.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	p.draw_pass_1 = sm
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.0
	m.gravity = Vector3(0.3, 0.06, 0.12)
	m.scale_min = 0.6
	m.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 2.8))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(0.80, 0.80, 0.82, 0.6))
	g.set_color(1, Color(0.9, 0.92, 0.95, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 16, 10))
	add_child(p)
	p.position = at
	return p


func _flames(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.8
	p.local_coords = false
	var qm := QuadMesh.new()
	qm.size = Vector2(0.35, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	qm.material = mat
	p.draw_pass_1 = qm
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.35
	m.direction = Vector3(0, 1, 0)
	m.spread = 10.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 1.4
	m.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	g.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.position = at
	return p


# ------------------------------------------------------------------ props
func _water_at(pos: Vector2) -> float:
	var w := terrain.sample_water_level(pos.x, pos.y)
	return w if w > -100.0 else maxf(_ground(pos), TerrainData.SEA_LEVEL)


func _prop(mb: MeshBuilder, p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var rot: float = p["rot"]
	var y := _ground(pos)
	var at := Vector3(pos.x, y, pos.y)
	var f := Frame.new(at, rot)
	var wood := _rock(WOOD)
	var town: int = p.get("town", 0)
	match String(p["kind"]):
		"well":
			var stone := _rock(Color(0.58, 0.56, 0.53))
			for k in 8:
				var a := k * TAU / 8.0
				_box(mb, at + Vector3(sin(a) * 0.9, 0.4, cos(a) * 0.9), Vector3(0.35, 0.4, 0.2), a, stone)
			_box(mb, at + Vector3(-0.9, 1.3, 0), Vector3(0.08, 0.9, 0.08), rot, wood)
			_box(mb, at + Vector3(0.9, 1.3, 0), Vector3(0.08, 0.9, 0.08), rot, wood)
			_box(mb, at + Vector3(0, 1.75, 0), Vector3(0.9, 0.04, 0.04), rot, wood)
			_box(mb, at + Vector3(0, 1.25, 0), Vector3(0.18, 0.18, 0.18), rot, _rock(DARK_WOOD))
			var tile := _rock(Color(0.55, 0.28, 0.20))
			_quad(mb, at + Vector3(-1.25, 2.0, -0.9), at + Vector3(-1.25, 2.0, 0.9), at + Vector3(0, 2.6, 0.9), at + Vector3(0, 2.6, -0.9), tile, Vector3(-1, 2, 0))
			_quad(mb, at + Vector3(1.25, 2.0, -0.9), at + Vector3(0, 2.6, -0.9), at + Vector3(0, 2.6, 0.9), at + Vector3(1.25, 2.0, 0.9), tile, Vector3(1, 2, 0))
		"pier":
			_pier(mb, pos, rot, TerrainData.LAKE_LEVEL + 0.35, 8)
		"harbor_pier":
			_pier(mb, pos, rot, TerrainData.SEA_LEVEL + 0.9, 14)
		"boat":
			_boat(mb, Vector3(pos.x, _water_at(pos) + 0.1, pos.y), rot)
		"hay":
			var hay := _rock(Color(0.86, 0.74, 0.38))
			var bs := Basis(Vector3.UP, rot)
			mb.add_tube(at + Vector3(0, 0.75, 0) + bs * Vector3(-0.7, 0, 0), at + Vector3(0, 0.75, 0) + bs * Vector3(0.7, 0, 0), 0.75, 0.75, 10, hay, hay, true)
			mb.add_tube(at + Vector3(0, 0.75, 0) + bs * Vector3(0.7, 0, 0), at + Vector3(0, 0.75, 0) + bs * Vector3(-0.7, 0, 0), 0.0, 0.75, 10, hay, hay, false)
		"scarecrow":
			_box(mb, at + Vector3(0, 1.0, 0), Vector3(0.06, 1.0, 0.06), rot, wood)
			_box(mb, at + Vector3(0, 1.5, 0), Vector3(0.8, 0.06, 0.06), rot, wood)
			_box(mb, at + Vector3(0, 1.45, 0), Vector3(0.3, 0.35, 0.18), rot, _rock(Color(0.30, 0.42, 0.62)))
			_box(mb, at + Vector3(0, 2.0, 0), Vector3(0.18, 0.18, 0.18), rot, _rock(Color(0.85, 0.74, 0.40)))
			_box(mb, at + Vector3(0, 2.25, 0), Vector3(0.38, 0.04, 0.38), rot, _rock(Color(0.45, 0.30, 0.18)))
		"stall":
			for x in [-1.3, 1.3]:
				for z in [-0.7, 0.7]:
					_box(mb, f.at(x, 1.1, z), Vector3(0.06, 1.1, 0.06), rot, wood)
			_box(mb, f.at(0, 0.85, 0.2), Vector3(1.35, 0.06, 0.55), rot, wood)
			var stripe: Color = [Color(0.80, 0.24, 0.22), Color(0.22, 0.42, 0.66), Color(0.30, 0.56, 0.32)][posmod(int(pos.x * 7.0 + pos.y), 3)]
			for k in 6:
				var x0 := -1.45 + k * 0.483
				var col := _rock(stripe if k % 2 == 0 else Color(0.95, 0.94, 0.90))
				_quad(mb, f.at(x0, 2.35, -0.9), f.at(x0 + 0.483, 2.35, -0.9), f.at(x0 + 0.483, 2.0, 1.0), f.at(x0, 2.0, 1.0), col, f.dir(0, 1, 0.2))
			for k in 7:
				var goods: Color = [Color(0.92, 0.42, 0.20), Color(0.85, 0.78, 0.30), Color(0.55, 0.75, 0.30), Color(0.75, 0.22, 0.25)][k % 4]
				_box(mb, f.at(-1.1 + k * 0.36, 0.98, 0.2 + sin(k * 2.0) * 0.2), Vector3(0.13, 0.08, 0.13), rot, _rock(goods))
		"bench":
			_box(mb, f.at(0, 0.45, 0), Vector3(0.9, 0.05, 0.22), rot, wood)
			_box(mb, f.at(0, 0.75, -0.22), Vector3(0.9, 0.18, 0.04), rot, wood)
			for x in [-0.75, 0.75]:
				_box(mb, f.at(x, 0.22, 0), Vector3(0.05, 0.22, 0.2), rot, _rock(DARK_WOOD))
		"cart":
			_box(mb, f.at(0, 0.85, 0), Vector3(0.75, 0.3, 1.1), rot, wood)
			for z in [-0.6, 0.6]:
				for x in [-0.85, 0.85]:
					mb.add_tube(f.at(x, 0.5, z), f.at(x * 1.12, 0.5, z), 0.45, 0.45, 10, _rock(DARK_WOOD), _rock(DARK_WOOD), true)
			_spar(mb, f.at(-0.4, 0.7, 1.1), f.at(-0.35, 0.45, 2.6), 0.05, wood)
			_spar(mb, f.at(0.4, 0.7, 1.1), f.at(0.35, 0.45, 2.6), 0.05, wood)
			_box(mb, f.at(0, 1.25, -0.3), Vector3(0.5, 0.15, 0.4), rot, _rock(Color(0.86, 0.74, 0.38)))
		"tree_planter":
			mb.add_tube(at, at + Vector3(0, 0.6, 0), 1.3, 1.3, 10, _rock(STONE), _rock(STONE), true)
			mb.add_tube(at + Vector3(0, 0.6, 0), at + Vector3(0, 2.4, 0), 0.15, 0.12, 6, _rock(DARK_WOOD), _rock(DARK_WOOD))
			var leaf := Color(0.30, 0.52, 0.24, 1.0)
			mb.add_blob(at + Vector3(0, 3.0, 0), Vector3(1.3, 1.1, 1.3), 1, 0.12, _rng, leaf, leaf.darkened(0.2), -0.2)
		"lamp":
			var iron := _rock(Color(0.16, 0.16, 0.18))
			mb.add_tube(at, at + Vector3(0, 2.9, 0), 0.07, 0.05, 6, iron, iron)
			_box(mb, at + Vector3(0, 0.12, 0), Vector3(0.18, 0.12, 0.18), 0.0, iron)
			_box(mb, at + Vector3(0, 3.05, 0), Vector3(0.2, 0.2, 0.2), 0.0, iron)
			_box(mb, at + Vector3(0, 3.35, 0), Vector3(0.26, 0.06, 0.26), 0.0, iron)
			for k in 4:
				var n := Basis(Vector3.UP, k * PI * 0.5) * Vector3(0, 0, 1)
				_pane(at + Vector3(0, 3.05, 0) + n * 0.21, n, 0.13, 0.15, plan.buildings.size() + town)
		"signpost":
			_box(mb, at + Vector3(0, 1.2, 0), Vector3(0.07, 1.2, 0.07), rot, wood)
			_box(mb, f.at(0.5, 2.0, 0), Vector3(0.6, 0.12, 0.03), rot, wood)
			_box(mb, f.at(-0.4, 1.6, 0), Vector3(0.5, 0.12, 0.03), rot + 0.6, wood)
		"reeds":
			for k in 14:
				var o := Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
				var col := Color(0.42, 0.52, 0.28, 1.0)
				var base := at + o
				_tri(mb, base + Vector3(-0.04, -0.2, 0), base + Vector3(0.04, -0.2, 0), base + Vector3(0.05, 1.3, 0.05), col, Vector3(0, 0, 1))
				_tri(mb, base + Vector3(-0.04, -0.2, 0), base + Vector3(0.05, 1.3, 0.05), base + Vector3(0.04, -0.2, 0), col, Vector3(0, 0, -1))
				_box(mb, base + Vector3(0.05, 1.2, 0.05), Vector3(0.04, 0.12, 0.04), 0.0, _rock(Color(0.38, 0.26, 0.16)))
		"nets":
			for x in [-1.2, 1.2]:
				_box(mb, f.at(x, 0.9, 0), Vector3(0.05, 0.9, 0.05), rot, wood)
			_box(mb, f.at(0, 1.75, 0), Vector3(1.25, 0.04, 0.04), rot, wood)
			var net := _rock(Color(0.36, 0.42, 0.40))
			_quad(mb, f.at(-1.15, 1.7, 0.02), f.at(1.15, 1.7, 0.02), f.at(1.0, 0.4, 0.05), f.at(-1.0, 0.4, 0.05), net, f.dir(0, 0, 1))
			_quad(mb, f.at(-1.15, 1.7, 0.0), f.at(-1.0, 0.4, 0.03), f.at(1.0, 0.4, 0.03), f.at(1.15, 1.7, 0.0), _shade(net, 0.8), f.dir(0, 0, -1))
		"barrels":
			for k in 3:
				var o := f.at(-0.7 + k * 0.7, 0, 0.1 * k)
				mb.add_tube(o, o + Vector3(0, 0.9, 0), 0.32, 0.32, 8, _rock(Color(0.52, 0.36, 0.22)), _rock(Color(0.46, 0.32, 0.20)), true)
		"crates":
			_box(mb, f.at(0, 0.4, 0), Vector3(0.45, 0.4, 0.45), rot, wood)
			_box(mb, f.at(0.95, 0.35, 0.1), Vector3(0.38, 0.35, 0.38), rot + 0.3, _rock(Color(0.55, 0.42, 0.26)))
			_box(mb, f.at(0.2, 1.1, 0.05), Vector3(0.32, 0.3, 0.32), rot - 0.2, wood)
		"laundry":
			for x in [-1.8, 1.8]:
				_box(mb, f.at(x, 1.0, 0), Vector3(0.05, 1.0, 0.05), rot, wood)
			_box(mb, f.at(0, 1.95, 0), Vector3(1.8, 0.012, 0.012), rot, _rock(Color(0.85, 0.85, 0.82)))
			var cloths := [Color(0.92, 0.92, 0.88), Color(0.40, 0.55, 0.78), Color(0.85, 0.40, 0.38), Color(0.95, 0.85, 0.50)]
			for k in 4:
				var x0 := -1.4 + k * 0.75
				var col: Color = _rock(cloths[k])
				var hgt := _rng.randf_range(0.5, 0.9)
				_quad(mb, f.at(x0, 1.93, 0.01), f.at(x0 + 0.5, 1.93, 0.01), f.at(x0 + 0.5, 1.93 - hgt, 0.03), f.at(x0, 1.93 - hgt, 0.03), col, f.dir(0, 0, 1))
				_quad(mb, f.at(x0, 1.93, -0.01), f.at(x0, 1.93 - hgt, 0.01), f.at(x0 + 0.5, 1.93 - hgt, 0.01), f.at(x0 + 0.5, 1.93, -0.01), _shade(col, 0.85), f.dir(0, 0, -1))
		"veg_patch":
			_box(mb, f.at(0, 0.08, 0), Vector3(1.6, 0.1, 1.1), rot, _rock(Color(0.36, 0.26, 0.18)))
			for k in 8:
				var o := f.at(-1.2 + (k % 4) * 0.8, 0.25, -0.5 + (k / 4) * 1.0)
				var leaf := Color(0.36, 0.62, 0.28, 1.0)
				mb.add_blob(o, Vector3(0.28, 0.22, 0.28), 1, 0.1, _rng, leaf, leaf.darkened(0.2), -0.2)
		"woodpile":
			for row in 3:
				for k in 5 - row:
					var o := f.at(-0.9 + k * 0.42 + row * 0.21, 0.2 + row * 0.36, 0)
					mb.add_tube(o + f.dir(0, 0, -0.6), o + f.dir(0, 0, 0.6), 0.18, 0.18, 6, _rock(Color(0.55, 0.40, 0.26)), _rock(Color(0.66, 0.52, 0.34)), true)
			_box(mb, f.at(1.6, 0.25, 0.4), Vector3(0.3, 0.25, 0.3), rot, _rock(Color(0.50, 0.36, 0.24)))
		"logs":
			for row in 2:
				for k in 4 - row:
					var o := f.at(-1.3 + k * 0.9 + row * 0.45, 0.4 + row * 0.75, 0)
					mb.add_tube(o + f.dir(0, 0, -3.0), o + f.dir(0, 0, 3.0), 0.42, 0.4, 8, _rock(Color(0.42, 0.30, 0.20)), _rock(Color(0.62, 0.48, 0.30)), true)
		"campfire":
			for k in 8:
				var a := k * TAU / 8.0
				_box(mb, at + Vector3(sin(a) * 0.8, 0.12, cos(a) * 0.8), Vector3(0.2, 0.14, 0.16), a, _rock(STONE))
			for k in 4:
				var a := k * PI * 0.5 + 0.4
				_spar(mb, at + Vector3(sin(a) * 0.55, 0.08, cos(a) * 0.55), at + Vector3(0, 0.55, 0), 0.07, _rock(DARK_WOOD))
			for k in 3:
				var a := k * TAU / 3.0 + 0.3
				_box(mb, at + Vector3(sin(a) * 2.0, 0.25, cos(a) * 2.0), Vector3(0.6, 0.22, 0.25), a, _rock(Color(0.45, 0.33, 0.22)))
			var flames := _flames(at + Vector3(0, 0.3, 0))
			flames.emitting = false
			var smoke := _smoke(at + Vector3(0, 0.9, 0))
			smoke.emitting = false
			_campfires.append({"pos": pos, "town": town, "flames": flames, "smoke": smoke, "delay": 10.0, "fire": 0.0})
		"sacks":
			for k in 3:
				var o := f.at(-0.5 + k * 0.5, 0.35, 0.15 * (k % 2))
				var sack := Color(0.82, 0.74, 0.56, 1.0)
				mb.add_blob(o, Vector3(0.3, 0.38, 0.26), 1, 0.08, _rng, _rock(sack), _rock(sack.darkened(0.15)), -0.2)


## A plank pier on posts, out over the water.
func _pier(mb: MeshBuilder, pos: Vector2, rot: float, deck: float, planks: int) -> void:
	var bs := Basis(Vector3.UP, rot)
	var at := Vector3(pos.x, 0, pos.y)
	var wood := _rock(WOOD)
	var post_col := _rock(Color(0.36, 0.26, 0.18))
	for k in planks:
		var c := at + bs * Vector3(0, 0, k * 2.0)
		c.y = deck
		_box(mb, c, Vector3(1.3, 0.09, 1.0), rot, wood)
		for sx in [-1.2, 1.2]:
			var post := at + bs * Vector3(sx, 0, k * 2.0)
			_box(mb, Vector3(post.x, deck - 1.4, post.z), Vector3(0.11, 1.6, 0.11), rot, post_col)
	var end := at + bs * Vector3(0, 0, planks * 2.0 - 1.0)
	for sx in [-1.2, 1.2]:
		_box(mb, Vector3(end.x, deck + 0.4, end.z) + bs * Vector3(sx, 0, 0), Vector3(0.12, 0.4, 0.12), rot, post_col)


## A small rowing boat (bow towards local +z).
func _boat(mb: MeshBuilder, at: Vector3, rot: float) -> void:
	var f := Frame.new(at, rot)
	var hull := _rock([Color(0.70, 0.30, 0.22), Color(0.25, 0.40, 0.56), Color(0.88, 0.86, 0.80)][posmod(int(at.x * 3.0 + at.z), 3)])
	var inner := _rock(Color(0.50, 0.36, 0.24))
	var hw := 0.65
	var hl := 1.7
	var pts := [f.at(-hw, 0.45, -hl), f.at(hw, 0.45, -hl), f.at(hw, 0.45, hl * 0.55), f.at(0, 0.5, hl), f.at(-hw, 0.45, hl * 0.55)]
	var keel := [f.at(-hw * 0.5, -0.05, -hl * 0.85), f.at(hw * 0.5, -0.05, -hl * 0.85), f.at(hw * 0.5, -0.05, hl * 0.4), f.at(0, 0.1, hl * 0.9), f.at(-hw * 0.5, -0.05, hl * 0.4)]
	var center := f.at(0, 0.2, 0)
	for k in 5:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 5]
		var c: Vector3 = keel[(k + 1) % 5]
		var d: Vector3 = keel[k]
		var out := ((a + b) * 0.5 - center)
		out.y = 0.0
		_quad(mb, a, b, c, d, hull, out.normalized())
		_quad(mb, a, d, c, b, inner, -out.normalized())
	_quad(mb, keel[0], keel[1], keel[2], keel[4], inner, Vector3.UP)
	_tri(mb, keel[2], keel[3], keel[4], inner, Vector3.UP)
	for z in [-0.6, 0.5]:
		_box(mb, f.at(0, 0.3, z), Vector3(hw * 0.9, 0.04, 0.16), rot, inner)


## A wooden bridge with an arched deck and rails, on stone abutments.
func _bridge(mb: MeshBuilder, br: Dictionary) -> void:
	var a: Vector2 = br["a"]
	var b: Vector2 = br["b"]
	var w: float = br["width"]
	var dir := (b - a).normalized()
	var rot := atan2(dir.x, dir.y)
	var side := Vector2(-dir.y, dir.x)
	var n := int(a.distance_to(b) / 1.0)
	var water := maxf(terrain.sample_water_level((a.x + b.x) * 0.5, (a.y + b.y) * 0.5), _ground((a + b) * 0.5))
	var wood := _rock(Color(0.52, 0.38, 0.24))
	for k in n:
		var p := a.lerp(b, (k + 0.5) / n)
		var y := plan.bridge_height(p, water)
		if y == -INF:
			y = maxf(_ground(p), water + 1.0)
		y = maxf(y, _ground(p) + 0.05)
		_box(mb, Vector3(p.x, y - 0.06, p.y), Vector3(w * 0.5, 0.08, 0.46), rot, wood if k % 2 == 0 else _shade(wood, 0.9))
		if k % 2 == 0:
			for s in [-1.0, 1.0]:
				var q: Vector2 = p + side * s * (w * 0.5 - 0.08)
				_box(mb, Vector3(q.x, y + 0.5, q.y), Vector3(0.07, 0.5, 0.07), rot, _rock(DARK_WOOD))
	for s in [-1.0, 1.0]:
		for k in n - 1:
			var p: Vector2 = a.lerp(b, (k + 0.5) / n) + side * s * (w * 0.5 - 0.08)
			var q: Vector2 = a.lerp(b, (k + 1.5) / n) + side * s * (w * 0.5 - 0.08)
			var yp := plan.bridge_height(a.lerp(b, (k + 0.5) / n), water)
			var yq := plan.bridge_height(a.lerp(b, (k + 1.5) / n), water)
			if yp == -INF or yq == -INF:
				continue
			_spar(mb, Vector3(p.x, yp + 0.95, p.y), Vector3(q.x, yq + 0.95, q.y), 0.05, _rock(DARK_WOOD))
	for e in [a, b]:
		_box(mb, Vector3(e.x, _ground(e) + 0.3, e.y), Vector3(w * 0.5 + 0.3, 0.7, 0.6), rot, _rock(STONE))


func _fence(mb: MeshBuilder, a: Vector2, b: Vector2) -> void:
	var wood := _rock(Color(0.52, 0.38, 0.24))
	var len := a.distance_to(b)
	var n := int(len / 2.5)
	var rot := atan2(b.x - a.x, b.y - a.y)
	for k in n + 1:
		var p := a.lerp(b, float(k) / maxf(n, 1))
		if terrain.path_dist[terrain.vertex_index(p.x, p.y)] < 2.5:
			continue
		var y := _ground(p)
		_box(mb, Vector3(p.x, y + 0.55, p.y), Vector3(0.07, 0.6, 0.07), rot, wood)
		if k < n:
			var q := a.lerp(b, float(k + 1) / maxf(n, 1))
			if terrain.path_dist[terrain.vertex_index(q.x, q.y)] < 2.5:
				continue
			var m := (p + q) * 0.5
			var my := (y + _ground(q)) * 0.5
			for rh in [0.45, 0.85]:
				_box(mb, Vector3(m.x, my + rh, m.y), Vector3(0.04, 0.05, p.distance_to(q) * 0.5), rot, wood)


## Crops in rows. Each plant carries its base point so the crop shader can
## grow it, sway it and make it wilt where the snow lands.
const CROPS := {
	"wheat": {"row": 0.75, "step": 0.45, "color": Color(0.88, 0.74, 0.34)},
	"corn": {"row": 1.1, "step": 0.8, "color": Color(0.52, 0.66, 0.26)},
	"greens": {"row": 0.9, "step": 0.7, "color": Color(0.42, 0.66, 0.30)},
	"sprouts": {"row": 0.8, "step": 0.5, "color": Color(0.40, 0.68, 0.28)},
}


func _field(mb: MeshBuilder, f: Dictionary) -> void:
	var crop: String = f["crop"]
	if not CROPS.has(crop):
		return
	var spec: Dictionary = CROPS[crop]
	var c: Vector2 = f["center"]
	var size: Vector2 = f["size"] - Vector2(1.5, 1.5)
	var rot: float = f["rot"]
	var tr := Transform2D(-rot, c)
	var rows := int(size.x / float(spec["row"]))
	var per := int(size.y / float(spec["step"]))
	for k in rows:
		var x := -size.x * 0.5 + (k + 0.5) * float(spec["row"])
		for j in per:
			var z := -size.y * 0.5 + (j + 0.5) * float(spec["step"]) + _rng.randf_range(-0.1, 0.1)
			var p: Vector2 = tr * Vector2(x + _rng.randf_range(-0.08, 0.08), z)
			_plant(mb, crop, p, _ground(p) - 0.03, spec["color"])


func _blade(mb: MeshBuilder, base: Vector3, tip: Vector3, half_w: float, side: Vector3, col: Color,
		p: Vector2, phase: float, t0: float = 0.0, t1: float = 1.0) -> void:
	var a := base - side * half_w
	var b := base + side * half_w
	var c0 := Color(col.r, col.g, col.b, t0)
	var c1 := Color(col.r, col.g, col.b, t1)
	for v in [[a, c0], [b, c0], [tip, c1]]:
		mb.add_vertex(v[0], Vector3.UP, v[1], p)
		mb.uv2s.append(Vector2(phase, base.y if t0 == 0.0 else 0.0))
	var i := mb.vertex_count() - 3
	mb.add_tri_idx(i, i + 1, i + 2)


func _plant(mb: MeshBuilder, crop: String, p: Vector2, y: float, col: Color) -> void:
	var phase := _rng.randf()
	var root := Vector3(p.x, y, p.y)
	var yaw := _rng.randf() * TAU
	var start := mb.vertex_count()
	match crop:
		"wheat":
			for k in 3:
				var a := yaw + k * 2.1
				var lean := Vector3(cos(a), 0, sin(a)) * 0.12
				var h := _rng.randf_range(0.8, 1.05)
				_blade(mb, root, root + lean + Vector3(0, h, 0), 0.035, Vector3(-sin(a), 0, cos(a)), col, p, phase)
				# Ear of grain near the top.
				_blade(mb, root + lean * 0.8 + Vector3(0, h * 0.78, 0), root + lean * 1.1 + Vector3(0, h * 1.02, 0), 0.06,
					Vector3(-sin(a), 0, cos(a)), col.lightened(0.1), p, phase, 0.78, 1.0)
		"corn":
			var h := _rng.randf_range(1.5, 1.9)
			for k in 2:
				var a := yaw + k * PI * 0.5
				_blade(mb, root, root + Vector3(0, h, 0), 0.06, Vector3(cos(a), 0, sin(a)), col, p, phase)
			for k in 3:
				var a := yaw + k * 2.2
				var out := Vector3(cos(a), 0, sin(a))
				_blade(mb, root + Vector3(0, h * (0.3 + k * 0.18), 0), root + out * 0.55 + Vector3(0, h * (0.45 + k * 0.18), 0), 0.07,
					out.cross(Vector3.UP).normalized(), col.darkened(0.1), p, phase, 0.3 + k * 0.18, 0.5 + k * 0.18)
			_blade(mb, root + Vector3(0, h * 0.95, 0), root + Vector3(0, h * 1.15, 0), 0.05, Vector3(cos(yaw), 0, sin(yaw)),
				Color(0.86, 0.76, 0.42), p, phase, 0.95, 1.0)
		"greens":
			# A round head of leaves.
			for k in 5:
				var a := yaw + k * TAU / 5.0
				var out := Vector3(cos(a), 0, sin(a))
				_blade(mb, root + out * 0.05, root + out * 0.3 + Vector3(0, 0.32, 0), 0.16, out.cross(Vector3.UP).normalized(),
					col, p, phase)
			_blade(mb, root, root + Vector3(0, 0.38, 0), 0.14, Vector3(cos(yaw), 0, sin(yaw)), col.lightened(0.15), p, phase)
		"sprouts":
			for k in 2:
				var a := yaw + k * PI
				var out := Vector3(cos(a), 0, sin(a))
				_blade(mb, root, root + out * 0.12 + Vector3(0, 0.28, 0), 0.05, out.cross(Vector3.UP).normalized(), col, p, phase)
	# Every vertex of a plant shares its base height (for the shader's growth).
	for i in range(start, mb.vertex_count()):
		mb.uv2s[i] = Vector2(phase, y)
