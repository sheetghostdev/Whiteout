class_name HUD
extends Control
## Minimal in-game overlay. Observes EventBus signals rather than scanning
## the world.

var _frost: Label
var _frost_rate: Label
var _cores: Label
var _core_box: Control
var _pct: Label
var _bar: ProgressBar
var _region: Label
var _ability_name: Label
var _ability_hint: Label
var _slots: HBoxContainer
var _slot_nodes := {}
var _status: Label
var _status_t := 0.0
var _toasts: VBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_t := 0.0
var _reticle: Control
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
	EventBus.cores_changed.connect(_on_cores)
	EventBus.coverage_changed.connect(_on_coverage)
	EventBus.region_changed.connect(_on_region)
	EventBus.ability_selected.connect(func(_id): _refresh_slots())
	EventBus.ability_unlocked.connect(func(_id): _refresh_slots())
	EventBus.ability_failed.connect(_on_fail)
	EventBus.notify.connect(toast)
	EventBus.region_milestone.connect(_on_region_milestone)
	EventBus.combo_discovered.connect(func(_id): Audio.play("combo"))
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
	sep.custom_minimum_size = Vector2(12, 0)
	hb.add_child(sep)
	_core_box = HBoxContainer.new()
	(_core_box as HBoxContainer).add_theme_constant_override("separation", 8)
	hb.add_child(_core_box)
	_core_box.add_child(ProceduralIcon.make("core", 28, UIKit.CORE))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -4)
	_core_box.add_child(cv)
	_cores = UIKit.label("0", 26, Color.WHITE)
	_cores.add_theme_font_override("font", UIKit.number_font())
	cv.add_child(_cores)
	cv.add_child(UIKit.label("Winter Cores", 13, UIKit.TEXT_DIM))
	_popups = Control.new()
	UIKit.place(_popups, 0, 0, 0, 0, 40, 100, 40, 100)
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

	# Reticle.
	_reticle = Control.new()
	UIKit.place(_reticle, 0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle)
	add_child(_reticle)

	# Status line under the reticle.
	_status = UIKit.label("", 17, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(_status, 0.5, 0.5, 0.5, 0.5, -300, 36, 300, 66)
	add_child(_status)

	# Ability bar, bottom-centre.
	var bottom := VBoxContainer.new()
	UIKit.place(bottom, 0.5, 1, 0.5, 1, -400, -170, 400, -22)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	_ability_name = UIKit.title("", 20, Color.WHITE)
	bottom.add_child(_ability_name)
	_ability_hint = UIKit.label("", 13, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	bottom.add_child(_ability_hint)
	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 10)
	bottom.add_child(_slots)

	# Toasts, top-right.
	_toasts = VBoxContainer.new()
	UIKit.place(_toasts, 1, 0, 1, 0, -380, 18, -20, 18)
	_toasts.add_theme_constant_override("separation", 8)
	for l in [_pct, _region, _ability_name, _ability_hint, _status, _banner_title, _banner_sub]:
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
	_on_cores(Game.prog.cores)
	_on_coverage(Game.prog.world_fraction)
	_refresh_slots()
	_update_hints()


func _update_hints() -> void:
	var parts: Array[String] = ["TAB  Upgrades"]
	if Game.prog.has("overview_map"):
		parts.append("M  Map")
	if Game.prog.has("flight"):
		parts.append("F  Fly")
	if Game.prog.has("thaw_sense"):
		parts.append("Q  Thaw Sense")
	parts.append("G  Weather Guide")
	_hints.text = "     ".join(parts)


func _refresh_slots() -> void:
	for c in _slots.get_children():
		c.queue_free()
	_slot_nodes.clear()
	var unlocked := Game.prog.unlocked_abilities()
	var sel := ""
	if Game.player != null:
		sel = (Game.player as PlayerController).abilities.selected_id()
	for i in GameBalance.ABILITY_ORDER.size():
		var id: String = GameBalance.ABILITY_ORDER[i]
		var is_unlocked := id in unlocked
		var next_locked := not is_unlocked and i == unlocked.size()
		if not is_unlocked and not next_locked:
			continue
		var slot := AbilitySlot.new()
		slot.ability_id = id
		slot.locked = not is_unlocked
		slot.key_label = str(unlocked.find(id) + 1) if is_unlocked else ""
		slot.selected = id == sel
		_slots.add_child(slot)
		_slot_nodes[id] = slot
	if sel != "":
		var a: Dictionary = GameBalance.ABILITIES[sel]
		_ability_name.text = String(a["name"]).to_upper()
		_ability_hint.text = a["alt"] if String(a["alt"]) != "" else ""
	_update_hints()


func _process(delta: float) -> void:
	if Game.weather == null:
		return
	for id in _slot_nodes:
		var slot: AbilitySlot = _slot_nodes[id]
		var cd := Game.prog.cooldown_for(id)
		slot.cooldown = Game.weather.cooldown_remaining(id) / maxf(cd, 0.01)
		slot.queue_redraw()
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
	_reticle.queue_redraw()


var _last_frost := -1.0


func _on_frost(v: float) -> void:
	if _last_frost >= 0.0 and v > _last_frost:
		_gain_accum += v - _last_frost
	_last_frost = v


func _popup(text: String) -> void:
	var l := UIKit.label(text, 15, UIKit.FROST)
	_outline(l, 4)
	l.position = Vector2(randf_range(0, 30), 0)
	_popups.add_child(l)


func _on_cores(v: int) -> void:
	_cores.text = str(v)
	_core_box.visible = Game.prog.lifetime_cores > 0 or v > 0


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


func _on_region_milestone(r: int, percent: int, bonus: float, core: bool) -> void:
	if core:
		_banner_title.text = "%s  —  100%% FROZEN" % GameBalance.REGION_SHORT[r]
		_banner_sub.text = "WINTER CORE EARNED   ·   +%s FROST" % UIKit.fmt(bonus)
		_banner_t = 5.0
	else:
		toast("%s  %d%%" % [GameBalance.REGION_NAMES[r].to_upper(), percent], "Milestone bonus  +%s Frost" % UIKit.fmt(bonus), "region")


func toast(title: String, subtitle: String, kind: String) -> void:
	var p := PanelContainer.new()
	var accent := UIKit.ACCENT
	match kind:
		"core", "unlock":
			accent = UIKit.CORE
		"combo":
			accent = UIKit.GOOD
		"hint":
			accent = Color(1.0, 0.86, 0.6)
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.13, 0.21, 0.78), 12, Color(accent.r, accent.g, accent.b, 0.55), 12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var icon_id: String = {"core": "core", "unlock": "spark", "combo": "spark", "region": "region", "hint": "eye"}.get(kind, "snowflake")
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


func _draw_reticle() -> void:
	var c := Color(1, 1, 1, 0.85)
	var valid := true
	if Game.player != null:
		var prev: Dictionary = (Game.player as PlayerController).abilities.last_preview
		valid = prev.get("valid", true)
	if not valid:
		c = Color(1.0, 0.65, 0.6, 0.9)
	_reticle.draw_arc(Vector2.ZERO, 7.0, 0, TAU, 24, Color(0, 0, 0, 0.25), 3.0, true)
	_reticle.draw_arc(Vector2.ZERO, 7.0, 0, TAU, 24, c, 1.5, true)
	_reticle.draw_circle(Vector2.ZERO, 1.6, c)
