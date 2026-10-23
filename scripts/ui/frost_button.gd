class_name FrostButton
extends Button
## Button with a soft hover glow, press bounce and procedural sounds.

var _hover := 0.0
var _target := 0.0
var _press := 0.0


func _ready() -> void:
	mouse_entered.connect(func():
		_target = 1.0
		if not disabled:
			Audio.play("hover", -6.0))
	mouse_exited.connect(func(): _target = 0.0)
	pressed.connect(func():
		_press = 1.0
		Audio.play("click", -3.0))
	focus_mode = Control.FOCUS_NONE
	resized.connect(func(): pivot_offset = size * 0.5)
	pivot_offset = size * 0.5


func _process(delta: float) -> void:
	_hover = move_toward(_hover, _target, delta * 6.0)
	_press = move_toward(_press, 0.0, delta * 5.0)
	var s := 1.0 + _hover * 0.025 - _press * 0.04
	scale = Vector2(s, s)
	modulate = Color(1, 1, 1, 1).lerp(Color(1.08, 1.1, 1.15, 1), _hover)
