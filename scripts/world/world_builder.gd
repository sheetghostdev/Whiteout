class_name WorldBuilder
extends Node3D
## Generates the whole procedural world once per run, spread across frames
## so the loading screen stays responsive.

signal progress(fraction: float, label: String)
signal finished()

var terrain: TerrainData
var coverage: SnowCoverage
var renderer: TerrainRenderer
var foliage: FoliageBuilder
var settlements: SettlementBuilder
var atmosphere: Atmosphere
var height_texture: ImageTexture
var water_texture: ImageTexture
var built := false


func generate(seed_value: int, vegetation_density: float) -> void:
	built = false
	progress.emit(0.02, "Shaping the land")
	await get_tree().process_frame
	terrain = TerrainData.new()
	terrain.generate(seed_value)

	progress.emit(0.25, "Preparing the snow")
	await get_tree().process_frame
	coverage = SnowCoverage.new()
	coverage.setup(terrain)
	var cov_tex := coverage.create_texture()
	height_texture = ImageTexture.create_from_image(terrain.height_image())
	water_texture = ImageTexture.create_from_image(terrain.water_image())
	ShaderLib.register_globals(height_texture, water_texture, cov_tex)

	progress.emit(0.32, "Lighting the sky")
	await get_tree().process_frame
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.build()

	progress.emit(0.36, "Raising hills and valleys")
	await get_tree().process_frame
	renderer = TerrainRenderer.new()
	renderer.name = "Terrain"
	add_child(renderer)
	renderer.build(terrain)

	progress.emit(0.5, "Building the village")
	await get_tree().process_frame
	settlements = SettlementBuilder.new()
	settlements.name = "Settlements"
	add_child(settlements)
	settlements.build(terrain, coverage)

	progress.emit(0.55, "Planting forests")
	await get_tree().process_frame
	foliage = FoliageBuilder.new()
	foliage.name = "Foliage"
	add_child(foliage)
	foliage.setup(terrain, vegetation_density)
	foliage.place_all()
	foliage.build_trees()

	progress.emit(0.72, "Scattering stones")
	await get_tree().process_frame
	foliage.build_rocks_and_stumps()
	foliage.build_collision()

	progress.emit(0.80, "Growing meadows")
	await get_tree().process_frame
	foliage.build_grass()
	progress.emit(0.92, "Opening the flowers")
	await get_tree().process_frame
	foliage.build_flowers()

	progress.emit(1.0, "Ready")
	built = true
	finished.emit()
