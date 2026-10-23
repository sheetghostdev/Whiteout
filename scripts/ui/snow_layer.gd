class_name SnowLayer
extends Control
## Decorative 2D snowfall drawn with vector snowflakes.

var count := 60
var _flakes: Array = []


func _ready() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in count:
		_flakes.append({"p": Vector2(r.randf(), r.randf()), "s": r.randf_range(2.0, 7.0), "v": r.randf_range(0.015, 0.05),
			"w": r.randf_range(0.5, 2.0), "ph": r.randf() * TAU, "rot": r.randf() * TAU})


func _process(delta: float) -> void:
	for f in _flakes:
		var p: Vector2 = f["p"]
		p.y += float(f["v"]) * delta
		p.x += sin(Time.get_ticks_msec() * 0.0005 * float(f["w"]) + float(f["ph"])) * 0.0004
		if p.y > 1.05:
			p.y = -0.05
		f["p"] = p
		f["rot"] = float(f["rot"]) + delta * 0.3
	queue_redraw()


func _draw() -> void:
	for f in _flakes:
		var p: Vector2 = f["p"] * size
		var s: float = f["s"]
		var c := Color(1, 1, 1, 0.25 + s * 0.06)
		for k in 3:
			var a := float(f["rot"]) + PI * k / 3.0
			var d := Vector2(cos(a), sin(a)) * s
			draw_line(p - d, p + d, c, maxf(1.0, s * 0.18), true)
