class_name UpgradeWeb
extends Control
## The upgrade web. Everything you can become is one connected graph, but
## only owned nodes and their direct neighbours are drawn, plus faint hints
## of what lies one step further. So the web keeps growing while only a
## handful of choices are ever in front of you. Click a node to buy it.
## Drag to pan, wheel to zoom.

signal closed()

const UNIT := 78.0
const NODE_R := 24.0
const BRANCH_NAMES := {
	"size": "Size", "snow": "Snowfall", "wind": "Wind", "companions": "Cloudlets",
	"storm": "Storm skills", "land": "The land", "polar": "Polar",
}

var _canvas: Control
var _frost: Label
var _tip: PanelContainer
var _tip_title: Label
var _tip_kind: Label
var _tip_desc: Label
var _tip_stat: Label
var _tip_cost: Label
var _buttons := {}           # node id -> WebNode
var _hover := ""
var _offset := Vector2.ZERO
var _scale := 1.0
var _dragging := false
var _drag_moved := 0.0
var _anim := {}              # node id -> reveal animation 0..1
var _time := 0.0


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuScreens.backdrop(self, 0.8)
	_canvas = Control.new()
	UIKit.full_rect(_canvas)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_draw_links)
	_canvas.gui_input.connect(_canvas_input)
	_canvas.clip_contents = true
	add_child(_canvas)
	for id in GameBalance.NODES:
		var b := WebNode.new()
		b.node_id = id
		b.web = self
		b.mouse_entered.connect(func(): _set_hover(id))
		b.mouse_exited.connect(func(): if _hover == id: _set_hover(""))
		b.clicked.connect(_buy)
		_canvas.add_child(b)
		_buttons[id] = b
	# Header.
	var header := HBoxContainer.new()
	UIKit.place(header, 0, 0, 1, 0, 28, 20, -28, 70)
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	header.add_child(ProceduralIcon.make("cloud", 32, UIKit.ACCENT))
	var t := UIKit.title("BECOME THE STORM", 30, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	header.add_child(ProceduralIcon.make("crystal", 28, UIKit.FROST))
	_frost = UIKit.label("0", 26, Color.WHITE)
	_frost.add_theme_font_override("font", UIKit.number_font())
	header.add_child(_frost)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	header.add_child(gap)
	var close := UIKit.button("Back to the sky  (Tab)", 240)
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	# Footer help + legend.
	var foot := UIKit.label("Click a node to buy it  ·  finishing a node reveals what it connects to  ·  drag to look around  ·  wheel to zoom",
		14, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(foot, 0, 1, 1, 1, 20, -40, -20, -14)
	add_child(foot)
	# Tooltip.
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.1, 0.17, 0.95), 12, UIKit.BORDER, 14))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size = Vector2(320, 0)
	_tip.visible = false
	add_child(_tip)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	_tip.add_child(tv)
	_tip_title = UIKit.label("", 20, Color.WHITE)
	tv.add_child(_tip_title)
	_tip_kind = UIKit.label("", 12, UIKit.TEXT_DIM)
	tv.add_child(_tip_kind)
	_tip_desc = UIKit.label("", 15, UIKit.TEXT)
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_desc.custom_minimum_size = Vector2(300, 0)
	tv.add_child(_tip_desc)
	_tip_stat = UIKit.label("", 16, UIKit.GOOD)
	tv.add_child(_tip_stat)
	_tip_cost = UIKit.label("", 16, UIKit.FROST)
	tv.add_child(_tip_cost)
	EventBus.frost_changed.connect(func(_v): if visible: _refresh())


func open() -> void:
	visible = true
	_hover = ""
	_tip.visible = false
	_fit_view()
	_refresh()


## Frames the visible part of the web.
func _fit_view() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in GameBalance.NODES:
		if node_state(id) == "hidden":
			continue
		var p: Vector2 = GameBalance.NODES[id]["pos"]
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		lo = Vector2(-1, -1)
		hi = Vector2(1, 1)
	var view := get_viewport_rect().size
	var span := (hi - lo) * UNIT + Vector2(260, 260)
	_scale = clampf(minf(view.x / span.x, (view.y - 140.0) / span.y), 0.45, 1.25)
	_offset = view * 0.5 + Vector2(0, 10) - (lo + hi) * 0.5 * UNIT * _scale


func to_screen(p: Vector2) -> Vector2:
	return _offset + p * UNIT * _scale


## hidden | hint (one step past the frontier) | locked | open | owned | maxed
func node_state(id: String) -> String:
	var prog := Game.prog
	if prog.is_maxed(id):
		return "maxed"
	if prog.has(id):
		return "owned"
	if prog.is_revealed(id):
		return "open" if prog.requirements_met(id) else "locked"
	for l in GameBalance.NODES[id]["links"]:
		if prog.is_revealed(l) and not prog.is_maxed(l):
			return "hint"
	return "hidden"


func _refresh() -> void:
	_frost.text = UIKit.fmt(Game.prog.frost)
	for id in _buttons:
		var b: WebNode = _buttons[id]
		var st := node_state(id)
		b.state = st
		b.visible = st != "hidden"
		var r := NODE_R * _scale * (1.25 if _is_big(id) else 1.0) * (0.45 if st == "hint" else 1.0)
		b.radius = r
		b.size = Vector2(r, r) * 2.0
		b.position = to_screen(GameBalance.NODES[id]["pos"]) - Vector2(r, r)
		b.affordable = Game.prog.can_purchase(id)
		b.queue_redraw()
	_canvas.queue_redraw()
	if _hover != "":
		_update_tip()


static func _is_big(id: String) -> bool:
	var k := String(GameBalance.NODES[id].get("kind", ""))
	return k == "keystone" or k == "skill"


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	for id in _anim.keys():
		_anim[id] = minf(float(_anim[id]) + delta * 2.5, 1.0)
		var b: WebNode = _buttons[id]
		b.pop = _anim[id]
		b.queue_redraw()
		if _anim[id] >= 1.0:
			_anim.erase(id)
	for id in _buttons:
		var b: WebNode = _buttons[id]
		if b.affordable and b.visible:
			b.pulse = 0.5 + 0.5 * sin(_time * 4.0 + b.position.x * 0.01)
			b.queue_redraw()
	if _tip.visible:
		var m := get_local_mouse_position() + Vector2(22, 18)
		var view := get_viewport_rect().size
		m.x = minf(m.x, view.x - _tip.size.x - 10)
		m.y = minf(m.y, view.y - _tip.size.y - 10)
		_tip.position = m


func _draw_links() -> void:
	var prog := Game.prog
	for id in GameBalance.NODES:
		var a_state := node_state(id)
		if a_state == "hidden":
			continue
		var n: Dictionary = GameBalance.NODES[id]
		var col: Color = GameBalance.BRANCH_COLORS[n["branch"]]
		for l in n["links"]:
			var b_state := node_state(l)
			if b_state == "hidden":
				continue
			var a := to_screen(n["pos"])
			var b := to_screen(GameBalance.NODES[l]["pos"])
			var both := prog.has(id) and prog.has(l)
			var c := col if both else Color(col.r, col.g, col.b, 0.35)
			if a_state == "hint" or b_state == "hint":
				_dashed(a, b, Color(col.r, col.g, col.b, 0.18), 1.5 * _scale)
			else:
				_canvas.draw_line(a, b, c, (4.0 if both else 2.0) * _scale, true)


func _dashed(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	var len := a.distance_to(b)
	var d := (b - a) / maxf(len, 0.01)
	var s := 0.0
	while s < len:
		_canvas.draw_line(a + d * s, a + d * minf(s + 6.0, len), c, w, true)
		s += 12.0


func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var f := 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
				var ns := clampf(_scale * f, 0.35, 1.8)
				_offset = mb.position - (mb.position - _offset) * (ns / _scale)
				_scale = ns
				_refresh()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			_drag_moved = 0.0
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_offset += mm.relative
		_drag_moved += mm.relative.length()
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("upgrades") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _set_hover(id: String) -> void:
	_hover = id
	if id == "" or node_state(id) == "hint":
		_tip.visible = false
		return
	_update_tip()
	_tip.visible = true


func _update_tip() -> void:
	var id := _hover
	var prog := Game.prog
	var n: Dictionary = GameBalance.NODES[id]
	_tip_title.text = n["name"]
	var kind := String(n.get("kind", ""))
	var kind_txt: String = {"keystone": "KEYSTONE", "skill": "ACTIVE SKILL"}.get(kind, "UPGRADE")
	var lv := prog.level(id)
	var mx := int(n["max"])
	_tip_kind.text = "%s  ·  %s%s" % [BRANCH_NAMES.get(n["branch"], "").to_upper(), kind_txt,
		("  ·  LEVEL %d / %d" % [lv, mx]) if mx > 1 else ""]
	_tip_kind.add_theme_color_override("font_color", GameBalance.BRANCH_COLORS[n["branch"]])
	_tip_desc.text = String(n["desc"]).replace("KEYSTONE: ", "").replace("SKILL ", "")
	if n.has("stat") and id != "heart":
		var st: String = n["stat"]
		var cur := prog.stat(st)
		if prog.is_maxed(id):
			_tip_stat.text = "%s  %s" % [GameBalance.STATS[st]["name"], GameBalance.format_stat(st, cur)]
		else:
			_tip_stat.text = "%s  %s  →  %s" % [GameBalance.STATS[st]["name"], GameBalance.format_stat(st, cur),
				GameBalance.format_stat(st, prog.stat_with_next(st, id))]
		_tip_stat.visible = true
	else:
		_tip_stat.visible = false
	if prog.is_maxed(id):
		_tip_cost.text = "Owned" if mx == 1 else "Maxed"
		_tip_cost.add_theme_color_override("font_color", UIKit.GOOD)
	elif not prog.requirements_met(id):
		_tip_cost.text = prog.requirement_text(id) + "  ·  " + UIKit.fmt(prog.cost_of(id)) + " Frost"
		_tip_cost.add_theme_color_override("font_color", UIKit.BAD)
	else:
		var c := prog.cost_of(id)
		_tip_cost.text = "%s Frost%s" % [UIKit.fmt(c), "" if prog.frost >= c else "  ·  need %s more" % UIKit.fmt(c - prog.frost)]
		_tip_cost.add_theme_color_override("font_color", UIKit.FROST if prog.frost >= c else UIKit.BAD)


func _buy(id: String) -> void:
	if _drag_moved > 8.0:
		return
	var prog := Game.prog
	var before := {}
	for k in GameBalance.NODES:
		before[k] = node_state(k)
	if not prog.purchase(id):
		Audio.play("error", -6.0)
		var b: WebNode = _buttons[id]
		b.shake = 1.0
		return
	Audio.play("purchase", -2.0, 1.0 + 0.04 * prog.level(id))
	_anim[id] = 0.0
	for k in GameBalance.NODES:
		var was: String = before[k]
		if (was == "hidden" or was == "hint") and node_state(k) != "hidden" and node_state(k) != "hint":
			_anim[k] = 0.0
	_refresh()
	_set_hover(id)


## One clickable node in the web.
class WebNode extends Control:
	signal clicked(id: String)

	var node_id := ""
	var web: UpgradeWeb
	var state := "hidden"
	var radius := 24.0
	var affordable := false
	var pulse := 0.0
	var pop := 1.0
	var shake := 0.0
	var _icon: ProceduralIcon

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_icon = ProceduralIcon.make(GameBalance.NODES[node_id]["icon"], 24, Color.WHITE)
		add_child(_icon)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			web._drag_moved = 0.0
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if state == "open" or state == "owned" or state == "locked":
				clicked.emit(node_id)

	func _process(delta: float) -> void:
		if shake > 0.0:
			shake = maxf(shake - delta * 4.0, 0.0)
			queue_redraw()

	func _has_point(p: Vector2) -> bool:
		return p.distance_to(size * 0.5) <= radius + 4.0

	func _draw() -> void:
		var n: Dictionary = GameBalance.NODES[node_id]
		var col: Color = GameBalance.BRANCH_COLORS[n["branch"]]
		var c := size * 0.5 + Vector2(sin(shake * 40.0) * 5.0 * shake, 0)
		var r := radius * (0.6 + 0.4 * ease(pop, 0.4)) if pop < 1.0 else radius
		var kind := String(n.get("kind", ""))
		var big := kind == "keystone" or kind == "skill"
		_icon.visible = state != "hint"
		if state == "hint":
			draw_circle(c, r, Color(col.r, col.g, col.b, 0.12))
			draw_arc(c, r, 0, TAU, 20, Color(col.r, col.g, col.b, 0.3), 1.2, true)
			return
		var fill := Color(0.07, 0.11, 0.18, 0.95)
		var ring := Color(col.r, col.g, col.b, 0.45)
		var ring_w := 2.0
		match state:
			"maxed":
				fill = col.darkened(0.35)
				ring = col
				ring_w = 3.0
			"owned":
				fill = col.darkened(0.6)
				ring = col
				ring_w = 2.5
			"locked":
				ring = Color(0.6, 0.65, 0.75, 0.35)
		if affordable:
			draw_circle(c, r + 6.0 + pulse * 3.0, Color(col.r, col.g, col.b, 0.12 + 0.12 * pulse))
			ring = col.lightened(0.3)
			ring_w = 3.0
		if big:
			var pts := PackedVector2Array()
			for k in 6:
				pts.append(c + Vector2.from_angle(TAU * k / 6.0 + PI / 6.0) * r)
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, ring, ring_w, true)
		else:
			draw_circle(c, r, fill)
			draw_arc(c, r, 0, TAU, 32, ring, ring_w, true)
		# Level pips around the bottom.
		var mx := int(n["max"])
		if mx > 1:
			var lv := Game.prog.level(node_id)
			for k in mx:
				var a := PI * 0.5 + (k - (mx - 1) * 0.5) * 0.32
				var pp := c + Vector2.from_angle(a) * (r + 7.0)
				draw_circle(pp, 3.0, col if k < lv else Color(0.3, 0.38, 0.5, 0.8))
		var isz := r * 1.1
		_icon.size = Vector2(isz, isz)
		_icon.position = c - Vector2(isz, isz) * 0.5
		var ic := Color.WHITE if state != "locked" else Color(0.7, 0.75, 0.85, 0.6)
		if state == "open" and not affordable:
			ic = Color(0.85, 0.9, 1.0, 0.6)
		_icon.color = ic
		if state == "locked":
			_icon.icon = "lock"
		else:
			_icon.icon = n["icon"]
