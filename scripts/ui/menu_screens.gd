class_name MenuScreens
extends RefCounted
## Shared construction helpers for full-screen menus.


static func backdrop(parent: Control, alpha: float = 0.5) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.08, alpha)
	UIKit.full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)


static func centered_panel(parent: Control, size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = size
	panel.position = -size * 0.5
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.13, 0.21, 0.86), 18, UIKit.BORDER, 24))
	parent.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	return vb


## Draws a field of gently falling procedural snowflakes behind menus.
static func snow_layer(parent: Control, count: int) -> Control:
	var layer := SnowLayer.new()
	layer.count = count
	UIKit.full_rect(layer)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	return layer
