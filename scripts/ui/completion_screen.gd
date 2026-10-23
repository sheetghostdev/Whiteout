class_name CompletionScreen
extends Control
## Shown after the ending cinematic: statistics and what to do next.

signal keep_exploring()
signal new_winter_plus(modifiers: Array)
signal to_main_menu()

const MODIFIERS := [
	["extra_cloud", "Little Friend", "A cloudlet follows you from the very start."],
	["strong_wind", "Strong Winds", "You drift 20% faster."],
	["swift_fronts", "Long Waves", "Frost Waves reach 30% farther."],
	["frost_head_start", "Head Start", "Begin the run with a gift of Frost."],
]

var _stats: VBoxContainer
var _mods := {}
var _content: Control


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	MenuScreens.backdrop(self, 0.35)
	MenuScreens.snow_layer(self, 90)
	_content = Control.new()
	UIKit.full_rect(_content)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	var vb := MenuScreens.centered_panel(_content, Vector2(860, 690))
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(UIKit.title("WHITEOUT COMPLETE", 46, Color.WHITE))
	vb.add_child(UIKit.label("THE WORLD HAS ENTERED AN ICE AGE", 20, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	vb.add_child(gap)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 4)
	vb.add_child(_stats)
	var mods_title := UIKit.label("New Winter+ modifiers (optional):", 15, UIKit.TEXT_DIM)
	vb.add_child(mods_title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	vb.add_child(grid)
	for m in MODIFIERS:
		var c := CheckBox.new()
		c.text = m[1]
		c.tooltip_text = m[2]
		grid.add_child(c)
		_mods[m[0]] = c
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var ke := UIKit.button("Keep Exploring", 230)
	ke.pressed.connect(func(): keep_exploring.emit())
	hb.add_child(ke)
	var plus := UIKit.button("New Winter+", 230)
	plus.pressed.connect(func():
		var chosen: Array = []
		for k in _mods:
			if (_mods[k] as CheckBox).button_pressed:
				chosen.append(k)
		new_winter_plus.emit(chosen))
	hb.add_child(plus)
	var mm := UIKit.button("Main Menu", 230)
	mm.pressed.connect(func(): to_main_menu.emit())
	hb.add_child(mm)


func open() -> void:
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 1.2)
	for c in _stats.get_children():
		c.queue_free()
	var p := Game.prog
	var st := p.stats
	var most := p.most_used_skill()
	var most_name := "-"
	if GameBalance.SKILLS.has(most):
		most_name = GameBalance.SKILLS[most]["name"]
	elif most == "avalanche":
		most_name = "Avalanche Rider"
	var rows := [
		["Total time", UIKit.fmt_time(float(st.get("time", 0.0)))],
		["Area frozen", "%s m²" % UIKit.fmt(float(SnowCoverage.N * SnowCoverage.N))],
		["Frost earned", UIKit.fmt(p.lifetime_frost)],
		["Distance drifted", "%s km" % ("%.1f" % (float(st.get("distance", 0.0)) / 1000.0))],
		["Largest you grew", "%d m across" % int(float(st.get("largest_storm", 0.0)) * 2.0)],
		["Skills used", UIKit.fmt(float(st.get("skills_used", 0)))],
		["Favourite skill", most_name],
		["Upgrades bought", "%d" % p.upgrades_owned()],
		["Regions completed", "%d / %d" % [SnowCoverage.REGION_COUNT, SnowCoverage.REGION_COUNT]],
	]
	for r in rows:
		var hb := HBoxContainer.new()
		var a := UIKit.label(r[0], 18, UIKit.TEXT_DIM)
		a.custom_minimum_size = Vector2(360, 0)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(a)
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(24, 0)
		hb.add_child(sp)
		hb.add_child(UIKit.label(r[1], 18, Color.WHITE))
		_stats.add_child(hb)
