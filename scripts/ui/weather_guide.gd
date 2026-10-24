class_name WeatherGuide
extends Control
## How to play, the skills you own and the keystones you have found.

signal closed()

var _list: VBoxContainer


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuScreens.backdrop(self, 0.55)
	var vb := MenuScreens.centered_panel(self, Vector2(900, 660))
	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(ProceduralIcon.make("spark", 30, UIKit.CORE))
	var t := UIKit.title("FIELD GUIDE", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(t)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	sc.add_child(_list)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var back := UIKit.button("Back", 180)
	back.pressed.connect(func(): closed.emit())
	hb.add_child(back)


func open() -> void:
	visible = true
	for c in _list.get_children():
		c.queue_free()
	var prog := Game.prog
	_list.add_child(UIKit.label("YOU ARE THE SNOW CLOUD", 15, UIKit.ACCENT))
	_list.add_child(_entry("cloud", "Drift and snow",
		"WASD drifts relative to the camera, the mouse looks around and the wheel zooms. Everything along your path freezes " +
		"in one pass, and narrow gaps between passes fill in by themselves. Resting earns nothing; each patch pays Frost only once.", true))
	_list.add_child(_entry("wind", "Ride a gust", "Hold Shift to fly faster. Gusting narrows your trail, unless you find Tailwind.", true))
	_list.add_child(_entry("eye", "Finding the last green", "When no green ground is close by, an arrow points to the nearest patch. Near the end, the last green ground glows softly.", true))
	_list.add_child(_entry("crystal", "Grow", "Press TAB to open the upgrade web. Finishing a node reveals the nodes it connects to; keystones change how you play.", true))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_list.add_child(gap)
	_list.add_child(UIKit.label("SKILLS", 15, UIKit.ACCENT))
	for id in GameBalance.SKILL_ORDER:
		var sk: Dictionary = GameBalance.SKILLS[id]
		var have := prog.has(id)
		_list.add_child(_entry(sk["icon"] if have else "lock", ("%s   ·   %s" % [sk["name"], sk["key"]]) if have else "???",
			String(sk["desc"]) if have else "Somewhere in the upgrade web.", have))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	_list.add_child(gap2)
	var keys: Array = []
	for id in GameBalance.NODES:
		if String(GameBalance.NODES[id].get("kind", "")) == "keystone" and id != "heart":
			keys.append(id)
	var owned := keys.filter(func(k): return prog.has(k))
	_list.add_child(UIKit.label("KEYSTONES FOUND  %d / %d" % [owned.size(), keys.size()], 15, UIKit.ACCENT))
	for id in owned:
		var n: Dictionary = GameBalance.NODES[id]
		_list.add_child(_entry(n["icon"], n["name"], String(n["desc"]).replace("KEYSTONE: ", ""), true))
	if owned.is_empty():
		_list.add_child(_entry("eye", "None yet", "Keystones sit at the end of each branch of the web.", false))


func _entry(icon: String, title: String, body: String, lit: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.14, 0.21, 0.31, 0.7 if lit else 0.4), 10, UIKit.BORDER, 12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	hb.add_child(ProceduralIcon.make(icon, 38, UIKit.TEXT if lit else UIKit.TEXT_DIM))
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	vb.add_child(UIKit.label(title, 17, Color.WHITE if lit else UIKit.TEXT_DIM))
	var l := UIKit.label(body, 14, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	return p


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("guide")):
		get_viewport().set_input_as_handled()
		closed.emit()
