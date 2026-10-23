class_name WeatherGuide
extends Control
## Ability reference and the collection of discovered weather combinations.

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
	var t := UIKit.title("WEATHER GUIDE", 30)
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
	_list.add_child(UIKit.label("WEATHER POWERS", 15, UIKit.ACCENT))
	for id in GameBalance.ABILITY_ORDER:
		var a: Dictionary = GameBalance.ABILITIES[id]
		var unlocked := prog.is_ability_unlocked(id)
		var body := String(a["desc"]) if unlocked else "Not yet unlocked."
		if unlocked and String(a["alt"]) != "":
			body += "\n" + String(a["alt"])
		_list.add_child(_entry(a["icon"] if unlocked else "lock", String(a["name"]) if unlocked else "???", body, unlocked))
	var found := prog.discovered_combos.size()
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_list.add_child(gap)
	_list.add_child(UIKit.label("COMBINATIONS DISCOVERED  %d / %d" % [found, WeatherInteractions.COMBOS.size()], 15, UIKit.ACCENT))
	for id in WeatherInteractions.COMBOS:
		var c: Dictionary = WeatherInteractions.COMBOS[id]
		var known: bool = id in prog.discovered_combos
		var title := "%s   ·   %s" % [c["name"], c["pair"]] if known else "???   ·   %s" % c["pair"]
		var desc := String(c["desc"]) if known else "Try combining these weather systems."
		_list.add_child(_entry("spark" if known else "eye", title, desc, known))
	var tip := UIKit.label("Controls: hold Left Mouse to cast · Right Mouse for the alternate action · 1-6 or wheel to switch · Tab upgrades", 14, UIKit.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(tip)


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
