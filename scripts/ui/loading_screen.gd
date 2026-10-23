class_name LoadingScreen
extends Control

var _bar: ProgressBar
var _label: Label


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.11, 0.19)
	UIKit.full_rect(bg)
	add_child(bg)
	MenuScreens.snow_layer(self, 80)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-260, -90)
	vb.custom_minimum_size = Vector2(520, 0)
	vb.add_theme_constant_override("separation", 14)
	add_child(vb)
	var crest := HBoxContainer.new()
	crest.alignment = BoxContainer.ALIGNMENT_CENTER
	crest.add_child(ProceduralIcon.make("snowflake", 54))
	vb.add_child(crest)
	vb.add_child(UIKit.title("WHITEOUT", 56))
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(520, 8)
	vb.add_child(_bar)
	_label = UIKit.label("", 16, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_label)


func set_progress(f: float, text: String) -> void:
	_bar.value = f
	_label.text = text
