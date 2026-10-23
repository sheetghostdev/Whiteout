class_name UpgradeShop
extends Control
## Category list + upgrade cards. Only available or nearly-available upgrades
## are shown; locked ones state their requirement.

signal closed()

var _cat_box: VBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _frost: Label
var _cores: Label
var _cat := "snow_cloud"
var _cards := {}
var _cat_buttons := {}
var _dirty := false


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.08, 0.45)
	UIKit.full_rect(dim)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1120, 700)
	panel.position = Vector2(-560, -350)
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.13, 0.21, 0.86), 18, UIKit.BORDER, 22))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	header.add_child(ProceduralIcon.make("snowflake", 30, UIKit.ACCENT))
	var t := UIKit.title("UPGRADES", 30, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(ProceduralIcon.make("crystal", 26, UIKit.FROST))
	_frost = UIKit.label("0", 24, Color.WHITE)
	header.add_child(_frost)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	header.add_child(gap)
	header.add_child(ProceduralIcon.make("core", 26, UIKit.CORE))
	_cores = UIKit.label("0", 24, Color.WHITE)
	header.add_child(_cores)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(20, 0)
	header.add_child(gap2)
	var close := UIKit.button("Close  (Tab)", 150)
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_cat_box = VBoxContainer.new()
	_cat_box.custom_minimum_size = Vector2(250, 0)
	_cat_box.add_theme_constant_override("separation", 8)
	body.add_child(_cat_box)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	EventBus.frost_changed.connect(func(_v): _dirty = true)
	EventBus.cores_changed.connect(func(_v): _dirty = true)


func open() -> void:
	visible = true
	_rebuild_categories()
	_select(_cat if _category_visible(_cat) else "snow_cloud")


func _process(_delta: float) -> void:
	if visible and _dirty:
		_dirty = false
		_update_affordability()


func _visible_upgrades(cat: String) -> Array:
	var prog := Game.prog
	var out: Array = []
	for id in GameBalance.UPGRADES:
		var u: Dictionary = GameBalance.UPGRADES[id]
		if u["cat"] != cat:
			continue
		if prog.requirements_met(id) or prog.is_forthcoming(id) or prog.has(id):
			# Hide one-off purchases that are done, except ability unlocks (as a record).
			out.append(id)
	out.sort_custom(func(a, b):
		var ma := prog.is_maxed(a)
		var mb := prog.is_maxed(b)
		if ma != mb:
			return mb
		return false)
	return out


func _category_visible(cat: String) -> bool:
	return not _visible_upgrades(cat).is_empty()


func _affordable_count(cat: String) -> int:
	var n := 0
	for id in _visible_upgrades(cat):
		if Game.prog.can_purchase(id):
			n += 1
	return n


func _rebuild_categories() -> void:
	for c in _cat_box.get_children():
		c.queue_free()
	_cat_buttons.clear()
	for cat in GameBalance.CATEGORIES:
		if not _category_visible(cat):
			continue
		var b := UIKit.button("", 250)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 52)
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 10)
		hb.position = Vector2(12, 8)
		b.add_child(hb)
		hb.add_child(ProceduralIcon.make(GameBalance.CATEGORY_ICONS[cat], 34))
		var l := UIKit.label(GameBalance.CATEGORY_NAMES[cat], 17, UIKit.TEXT)
		l.custom_minimum_size = Vector2(150, 34)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(l)
		var badge := UIKit.label("", 14, UIKit.GOOD)
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(0, 34)
		hb.add_child(badge)
		b.set_meta("badge", badge)
		b.pressed.connect(_select.bind(cat))
		_cat_box.add_child(b)
		_cat_buttons[cat] = b
	_update_badges()


func _update_badges() -> void:
	for cat in _cat_buttons:
		var b: Button = _cat_buttons[cat]
		var n := _affordable_count(cat)
		(b.get_meta("badge") as Label).text = ("● %d" % n) if n > 0 else ""
		var st := UIKit.panel_style(Color(0.30, 0.46, 0.64, 0.92), 10, Color(0.9, 0.97, 1.0, 0.8), 12) if cat == _cat else null
		if st:
			b.add_theme_stylebox_override("normal", st)
		else:
			b.remove_theme_stylebox_override("normal")


func _select(cat: String) -> void:
	_cat = cat
	for c in _list.get_children():
		c.queue_free()
	_cards.clear()
	for id in _visible_upgrades(cat):
		var card := _make_card(id)
		_list.add_child(card)
		_cards[id] = card
	_update_affordability()
	_scroll.scroll_vertical = 0


func _effect_text(id: String) -> String:
	var u: Dictionary = GameBalance.UPGRADES[id]
	var prog := Game.prog
	var lv := prog.level(id)
	if u.has("stat"):
		var stat: String = u["stat"]
		var cur := GameBalance.format_stat(stat, GameBalance.stat_value(stat, lv))
		if prog.is_maxed(id):
			return "%s   (maxed)" % cur
		var nxt := GameBalance.format_stat(stat, GameBalance.stat_value(stat, lv + 1))
		return "%s   →   %s" % [cur, nxt]
	if u.has("unlocks"):
		return "Unlocked" if prog.has(id) else "New weather power"
	return "Active" if prog.has(id) else "Changes how your weather behaves"


func _make_card(id: String) -> PanelContainer:
	var u: Dictionary = GameBalance.UPGRADES[id]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.14, 0.21, 0.31, 0.78), 12, UIKit.BORDER, 14))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	card.add_child(hb)
	var icon_id: String = u.get("icon", GameBalance.CATEGORY_ICONS[u["cat"]])
	if u.has("unlocks"):
		icon_id = GameBalance.ABILITIES[u["unlocks"]]["icon"]
	hb.add_child(ProceduralIcon.make(icon_id, 46, UIKit.ACCENT if not u.get("evo", false) else UIKit.CORE))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	hb.add_child(mid)
	var top := HBoxContainer.new()
	mid.add_child(top)
	var name_l := UIKit.label(String(u["name"]), 19, Color.WHITE)
	top.add_child(name_l)
	var lvl := UIKit.label("", 14, UIKit.TEXT_DIM)
	lvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(lvl)
	if u.get("evo", false):
		var tag := UIKit.label("  EVOLUTION", 12, UIKit.CORE)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(tag)
	var desc := UIKit.label(String(u["desc"]), 15, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(480, 0)
	mid.add_child(desc)
	var eff := UIKit.label("", 15, UIKit.ACCENT)
	mid.add_child(eff)
	var req := UIKit.label("", 14, Color(1.0, 0.82, 0.62))
	mid.add_child(req)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(170, 0)
	hb.add_child(right)
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_END
	cost_row.add_theme_constant_override("separation", 6)
	right.add_child(cost_row)
	var frost_icon := ProceduralIcon.make("crystal", 18, UIKit.FROST)
	cost_row.add_child(frost_icon)
	var cost := UIKit.label("", 17, Color.WHITE)
	cost_row.add_child(cost)
	var core_icon := ProceduralIcon.make("core", 18, UIKit.CORE)
	cost_row.add_child(core_icon)
	var core_cost := UIKit.label("", 17, Color.WHITE)
	cost_row.add_child(core_cost)
	var buy := UIKit.button("Buy", 170)
	buy.custom_minimum_size = Vector2(170, 42)
	buy.pressed.connect(_buy.bind(id))
	right.add_child(buy)
	card.set_meta("ui", {"lvl": lvl, "eff": eff, "req": req, "cost": cost, "core_cost": core_cost,
		"core_icon": core_icon, "frost_icon": frost_icon, "buy": buy})
	return card


func _update_affordability() -> void:
	var prog := Game.prog
	_frost.text = UIKit.fmt(prog.frost)
	_cores.text = str(prog.cores)
	for id in _cards:
		var card: PanelContainer = _cards[id]
		var ui: Dictionary = card.get_meta("ui")
		var u: Dictionary = GameBalance.UPGRADES[id]
		var maxl := int(u["max"])
		var lv := prog.level(id)
		(ui["lvl"] as Label).text = ("   Lv %d / %d" % [lv, maxl]) if maxl > 1 else ""
		(ui["eff"] as Label).text = _effect_text(id)
		var req_text := prog.requirement_text(id)
		(ui["req"] as Label).text = ("Requires: " + req_text) if req_text != "" else ""
		(ui["req"] as Label).visible = req_text != ""
		var buy: FrostButton = ui["buy"]
		var maxed := prog.is_maxed(id)
		var ccost := prog.core_cost_of(id)
		(ui["cost"] as Label).text = "" if maxed else UIKit.fmt(prog.cost_of(id))
		(ui["frost_icon"] as Control).visible = not maxed
		(ui["core_cost"] as Label).text = str(ccost) if ccost > 0 and not maxed else ""
		(ui["core_icon"] as Control).visible = ccost > 0 and not maxed
		if maxed:
			buy.text = "Owned" if maxl == 1 else "Maxed"
			buy.disabled = true
		else:
			buy.text = "Buy"
			buy.disabled = not prog.can_purchase(id)
			var short_frost := prog.frost < prog.cost_of(id)
			var short_core := prog.cores < ccost
			(ui["cost"] as Label).add_theme_color_override("font_color", UIKit.BAD if short_frost else Color.WHITE)
			(ui["core_cost"] as Label).add_theme_color_override("font_color", UIKit.BAD if short_core else Color.WHITE)
		card.modulate = Color(1, 1, 1, 0.6) if req_text != "" else Color.WHITE
	_update_badges()


func _buy(id: String) -> void:
	if not Game.prog.purchase(id):
		Audio.play("error", -6.0)
		return
	Audio.play("purchase")
	var card: PanelContainer = _cards.get(id)
	if card:
		var tw := card.create_tween()
		card.modulate = Color(1.5, 1.7, 2.0)
		tw.tween_property(card, "modulate", Color.WHITE, 0.45)
	# New entries may have become visible.
	var before := _cards.keys()
	var now := _visible_upgrades(_cat)
	if before.size() != now.size():
		_select(_cat)
	_rebuild_categories()
	_update_affordability()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("upgrades") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		closed.emit()
