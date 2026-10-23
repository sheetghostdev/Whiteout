class_name HUD
extends Control
## Minimal in-game overlay. Observes EventBus signals rather than scanning
## the world.

var _frost: Label
var _frost_rate: Label
var _ready_pill: PanelContainer
var _ready_label: Label
var _goal: Label
var _pct: Label
var _bar: ProgressBar
var _region: Label
var _slots: HBoxContainer
var _slot_nodes := {}
var _status: Label
var _status_t := 0.0
var _toasts: VBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_t := 0.0
var _hints: Label
var _fps: Label
var _gain_accum := 0.0
var _gain_timer := 0.0
var _popups: Control
var _shown_frost := 0.0


func _ready() -> void:
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	_build()
	EventBus.frost_changed.connect(_on_frost)
	EventBus.coverage_changed.connect(_on_coverage)
	EventBus.region_changed.connect(_on_region)
	EventBus.skill_unlocked.connect(func(_id): _refresh_slots())
	EventBus.upgrade_purchased.connect(func(_id, _lv): _refresh_ready())
	EventBus.skill_failed.connect(_on_fail)
	EventBus.notify.connect(toast)
	EventBus.region_milestone.connect(_on_region_milestone)
	EventBus.save_written.connect(func(): _flash_status("Game saved", UIKit.TEXT_DIM))


func _build() -> void:
	# Currency, top-left.
	var cur := PanelContainer.new()
	UIKit.place(cur, 0, 0, 0, 0, 20, 18, 20, 18)
	add_child(cur)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	cur.add_child(hb)
	hb.add_child(ProceduralIcon.make("crystal", 28, UIKit.FROST))
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", -4)
	hb.add_child(fv)
	_frost = UIKit.label("0", 26, Color.WHITE)
	_frost.add_theme_font_override("font", UIKit.number_font())
	fv.add_child(_frost)
	_frost_rate = UIKit.label("Frost", 13, UIKit.TEXT_DIM)
	fv.add_child(_frost_rate)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(14, 0)
	hb.add_child(sep)
	# "Upgrades ready" pill: the one nudge toward the web, never a wall of choices.
	_ready_pill = PanelContainer.new()
	_ready_pill.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.2, 0.36, 0.55, 0.85), 10, Color(0.85, 0.96, 1.0, 0.8), 8))
	_ready_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_ready_pill)
	_ready_label = UIKit.label("", 14, Color.WHITE)
	_ready_pill.add_child(_ready_label)
	_ready_pill.visible = false
	_goal = UIKit.label("", 13, UIKit.TEXT_DIM)
	UIKit.place(_goal, 0, 0, 0, 0, 24, 96, 520, 116)
	add_child(_goal)
	_popups = Control.new()
	UIKit.place(_popups, 0, 0, 0, 0, 40, 124, 40, 124)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)

	# Completion, top-centre.
	var top := VBoxContainer.new()
	UIKit.place(top, 0.5, 0, 0.5, 0, -170, 12, 170, 100)
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_pct = UIKit.label("0.0%", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_pct.add_theme_font_override("font", UIKit.number_font())
	top.add_child(_pct)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(320, 8)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0001
	top.add_child(_bar)
	_region = UIKit.label("", 15, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_region)

	# Region banner.
	_banner = VBoxContainer.new()
	UIKit.place(_banner, 0.5, 0, 0.5, 0, -450, 130, 450, 230)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_banner_title = UIKit.title("", 34, Color.WHITE)
	_banner.add_child(_banner_title)
	_banner_sub = UIKit.label("", 18, UIKit.CORE, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_child(_banner_sub)
	_banner.modulate.a = 0.0

	# Status line under the reticle.
	_status = UIKit.label("", 17, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(_status, 0.5, 1, 0.5, 1, -300, -130, 300, -100)
	add_child(_status)

	# Ability bar, bottom-centre.
	var bottom := VBoxContainer.new()
	UIKit.place(bottom, 0.5, 1, 0.5, 1, -400, -100, 400, -22)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 10)
	bottom.add_child(_slots)

	# Toasts, top-right.
	_toasts = VBoxContainer.new()
	UIKit.place(_toasts, 1, 0, 1, 0, -380, 18, -20, 18)
	_toasts.add_theme_constant_override("separation", 8)
	for l in [_pct, _region, _goal, _status, _banner_title, _banner_sub]:
		_outline(l)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	_hints = UIKit.label("", 14, Color(0.85, 0.92, 1.0, 0.75))
	UIKit.place(_hints, 0, 1, 0, 1, 20, -34, 900, -10)
	add_child(_hints)
	_outline(_hints, 4)
	_fps = UIKit.label("", 13, UIKit.TEXT_DIM)
	UIKit.place(_fps, 1, 1, 1, 1, -110, -30, -20, -8)
	add_child(_fps)


func _outline(l: Label, size: int = 5) -> void:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.14, 0.55))


func refresh_all() -> void:
	_shown_frost = Game.prog.frost
	_on_frost(Game.prog.frost)
	_refresh_ready()
	_on_coverage(Game.prog.world_fraction)
	_refresh_slots()
	_update_hints()


func _update_hints() -> void:
	var parts: Array[String] = ["WASD  Drift", "SHIFT  Gust", "TAB  Upgrades"]
	if Game.prog.has("overview_map"):
		parts.append("M  Map")
	if Game.prog.has("thaw_sense"):
		parts.append("Q  Thaw Sense")
	parts.append("G  Guide")
	_hints.text = "     ".join(parts)


func _refresh_slots() -> void:
	for c in _slots.get_children():
		c.queue_free()
	_slot_nodes.clear()
	for id in Game.prog.unlocked_skills():
		var slot := AbilitySlot.new()
		slot.skill_id = id
		slot.key_label = _short_key(String(GameBalance.SKILLS[id]["key"]))
		_slots.add_child(slot)
		_slot_nodes[id] = slot
	_update_hints()
	_refresh_ready()


static func _short_key(k: String) -> String:
	return {"Left Mouse": "LMB", "Right Mouse": "RMB"}.get(k, k)


## Shows how many upgrades can be bought right now, and the next goal.
func _refresh_ready() -> void:
	var prog := Game.prog
	var n := prog.affordable_count()
	_ready_pill.visible = n > 0
	_ready_label.text = "%d upgrade%s ready  ·  TAB" % [n, "" if n == 1 else "s"]
	var best := ""
	var best_cost := INF
	for id in prog.frontier():
		if prog.requirements_met(id) and prog.cost_of(id) < best_cost:
			best_cost = prog.cost_of(id)
			best = id
	if n == 0 and best != "":
		_goal.text = "Next: %s  ·  %s Frost" % [GameBalance.NODES[best]["name"], UIKit.fmt(best_cost)]
	else:
		_goal.text = ""


func _process(delta: float) -> void:
	if Game.weather == null:
		return
	for id in _slot_nodes:
		var slot: AbilitySlot = _slot_nodes[id]
		var cd := Game.prog.skill_cooldown(id)
		slot.set_cooldown(Game.weather.cooldown_remaining(id) / maxf(cd, 0.01))
	# Count the Frost display up smoothly.
	var target := Game.prog.frost
	_shown_frost = target if absf(target - _shown_frost) < 1.0 else lerpf(_shown_frost, target, 1.0 - exp(-delta * 10.0))
	_frost.text = UIKit.fmt(_shown_frost)
	_frost_rate.text = "Frost  +%s/s" % UIKit.fmt(Game.weather.frost_rate) if Game.weather.frost_rate >= 1.0 else "Frost"
	_status_t -= delta
	_status.modulate.a = clampf(_status_t, 0.0, 1.0)
	_banner_t -= delta
	_banner.modulate.a = clampf(_banner_t, 0.0, 1.0) if _banner_t < 1.0 else minf(_banner.modulate.a + delta * 3.0, 1.0)
	_gain_timer += delta
	if _gain_timer >= 0.6:
		_gain_timer = 0.0
		if _gain_accum >= 1.0:
			_popup("+" + UIKit.fmt(_gain_accum))
		_gain_accum = 0.0
	for p in _popups.get_children():
		p.position.y -= delta * 26.0
		p.modulate.a -= delta * 0.9
		if p.modulate.a <= 0.0:
			p.queue_free()
	_fps.visible = Settings.show_fps
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	_ready_timer -= delta
	if _ready_timer <= 0.0:
		_ready_timer = 0.5
		_refresh_ready()
	if _ready_pill.visible:
		_ready_pill.modulate.a = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.005)


var _last_frost := -1.0
var _ready_timer := 0.0


func _on_frost(v: float) -> void:
	if _last_frost >= 0.0 and v > _last_frost:
		_gain_accum += v - _last_frost
	_last_frost = v


func _popup(text: String) -> void:
	var l := UIKit.label(text, 15, UIKit.FROST)
	_outline(l, 4)
	l.position = Vector2(randf_range(0, 30), 0)
	_popups.add_child(l)


func _on_coverage(f: float) -> void:
	_pct.text = ("%.1f%%" % (f * 100.0)) if f < 0.9995 or Game.prog.completed else "99.9%"
	if Game.prog.completed:
		_pct.text = "100%"
	_bar.value = f
	_on_region(Game.current_region)


func _on_region(r: int) -> void:
	if r < 0 or Game.world == null:
		_region.text = ""
		return
	var f := Game.world.coverage.region_completion(r)
	_region.text = "%s  ·  %d%%" % [GameBalance.REGION_NAMES[r], int(floor(f * 100.0))]


func _on_fail(_id: String, reason: String) -> void:
	_flash_status(reason, UIKit.BAD)


func _flash_status(text: String, c: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", c)
	_status_t = 1.6


func _on_region_milestone(r: int, percent: int, bonus: float, complete: bool) -> void:
	if complete:
		_banner_title.text = "%s  —  100%% FROZEN" % GameBalance.REGION_SHORT[r]
		_banner_sub.text = "+%s FROST" % UIKit.fmt(bonus)
		_banner_t = 5.0
	else:
		toast("%s  %d%%" % [GameBalance.REGION_NAMES[r].to_upper(), percent], "Milestone bonus  +%s Frost" % UIKit.fmt(bonus), "region")


func toast(title: String, subtitle: String, kind: String) -> void:
	var p := PanelContainer.new()
	var accent := UIKit.ACCENT
	match kind:
		"core", "unlock":
			accent = UIKit.CORE
		"milestone":
			accent = UIKit.GOOD
		"hint":
			accent = Color(1.0, 0.86, 0.6)
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.13, 0.21, 0.78), 12, Color(accent.r, accent.g, accent.b, 0.55), 12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var icon_id: String = {"core": "core", "unlock": "spark", "milestone": "spark", "region": "region", "hint": "eye"}.get(kind, "snowflake")
	hb.add_child(ProceduralIcon.make(icon_id, 30, accent))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	hb.add_child(vb)
	var t := UIKit.label(title, 16, Color.WHITE)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(290, 0)
	vb.add_child(t)
	if subtitle != "":
		var s := UIKit.label(subtitle, 13, UIKit.TEXT_DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(290, 0)
		vb.add_child(s)
	p.modulate.a = 0.0
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
