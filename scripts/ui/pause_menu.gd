class_name PauseMenu
extends Control

signal resume()
signal open_settings()
signal open_guide()
signal to_main_menu()
signal quit_game()

var _saved: Label


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuScreens.backdrop(self, 0.5)
	var vb := MenuScreens.centered_panel(self, Vector2(420, 520))
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(UIKit.title("PAUSED", 34))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	vb.add_child(gap)
	for item in [["Resume", resume], ["Weather Guide", open_guide], ["Settings", open_settings]]:
		var b := UIKit.button(item[0], 340)
		var sig: Signal = item[1]
		b.pressed.connect(func(): sig.emit())
		vb.add_child(b)
	var save := UIKit.button("Save Game", 340)
	save.pressed.connect(func():
		_saved.text = "Saved." if Game.save_game() else "Could not save.")
	vb.add_child(save)
	var mm := UIKit.button("Save & Main Menu", 340)
	mm.pressed.connect(func(): to_main_menu.emit())
	vb.add_child(mm)
	var q := UIKit.button("Save & Quit", 340)
	q.pressed.connect(func(): quit_game.emit())
	vb.add_child(q)
	_saved = UIKit.label("", 15, UIKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_saved)


func open() -> void:
	visible = true
	_saved.text = ""


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume.emit()
