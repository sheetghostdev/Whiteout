class_name ProceduralIcon
extends Control
## Small consistent vector icon set drawn with lines and polygons.

var icon := "snowflake":
	set(v):
		icon = v
		queue_redraw()
var color := Color(0.92, 0.97, 1.0):
	set(v):
		color = v
		queue_redraw()
var line := 2.0


static func make(id: String, size: float, c: Color = Color(0.92, 0.97, 1.0)) -> ProceduralIcon:
	var i := ProceduralIcon.new()
	i.icon = id
	i.color = c
	i.custom_minimum_size = Vector2(size, size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	draw_set_transform(o, 0.0, Vector2(s / 64.0, s / 64.0))
	var w := line * 64.0 / maxf(s, 1.0) * 1.2
	var c := color
	match icon:
		"snowflake", "frost":
			_snowflake(Vector2(32, 32), 26.0, c, w)
		"cloud":
			_cloud(Vector2(32, 30), 1.0, c, w)
			for k in 3:
				var x := 22.0 + k * 10.0
				draw_line(Vector2(x, 44), Vector2(x - 2, 52), c, w, true)
		"front":
			for k in 3:
				var y := 20.0 + k * 11.0
				var pts := PackedVector2Array()
				for i in 13:
					var x := 8.0 + i * 4.0
					pts.append(Vector2(x, y + sin(i * 0.9 + k) * 3.0))
				draw_polyline(pts, c, w, true)
			draw_line(Vector2(48, 50), Vector2(58, 50), c, w, true)
			draw_line(Vector2(54, 46), Vector2(58, 50), c, w, true)
			draw_line(Vector2(54, 54), Vector2(58, 50), c, w, true)
		"wind":
			_wind_curve(Vector2(8, 22), 40.0, c, w, 1.0)
			_wind_curve(Vector2(8, 34), 48.0, c, w, -1.0)
			_wind_curve(Vector2(14, 46), 30.0, c, w, 1.0)
		"blizzard":
			_cloud(Vector2(32, 24), 1.15, c, w)
			for k in 4:
				var x := 16.0 + k * 10.0
				draw_line(Vector2(x, 40), Vector2(x - 6, 56), c, w, true)
			_snowflake(Vector2(48, 50), 5.0, c, w * 0.7)
		"avalanche":
			var mtn := PackedVector2Array([Vector2(4, 56), Vector2(26, 14), Vector2(36, 28), Vector2(44, 20), Vector2(60, 56)])
			draw_polyline(mtn, c, w, true)
			var wave := PackedVector2Array()
			for i in 12:
				var t := i / 11.0
				wave.append(Vector2(lerpf(28.0, 58.0, t), lerpf(30.0, 54.0, t) + sin(t * 9.0) * 2.5))
			draw_polyline(wave, c, w * 1.4, true)
			draw_circle(Vector2(56, 54), 3.0, c)
		"vortex":
			var pts := PackedVector2Array()
			for i in 60:
				var t := i / 59.0
				var a := t * TAU * 2.4
				var r := 2.0 + t * 24.0
				pts.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts, c, w, true)
		"gear":
			var pts2 := PackedVector2Array()
			for i in 17:
				var a := TAU * i / 16.0
				var r := 24.0 if i % 2 == 0 else 18.0
				pts2.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts2, c, w, true)
			draw_arc(Vector2(32, 32), 8.0, 0, TAU, 24, c, w, true)
		"spark":
			var pts3 := PackedVector2Array()
			for i in 9:
				var a := TAU * i / 8.0 - PI * 0.5
				var r := 26.0 if i % 2 == 0 else 9.0
				pts3.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts3, Color(c.r, c.g, c.b, c.a * 0.35))
			draw_polyline(pts3, c, w, true)
		"core":
			var hexa := PackedVector2Array()
			for i in 7:
				var a := TAU * i / 6.0 + PI / 6.0
				hexa.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * 24.0)
			draw_colored_polygon(hexa, Color(c.r, c.g, c.b, c.a * 0.3))
			draw_polyline(hexa, c, w, true)
			_snowflake(Vector2(32, 32), 11.0, c, w * 0.8)
		"crystal":
			var cr := PackedVector2Array([Vector2(32, 4), Vector2(46, 22), Vector2(32, 60), Vector2(18, 22), Vector2(32, 4)])
			draw_colored_polygon(cr, Color(c.r, c.g, c.b, c.a * 0.3))
			draw_polyline(cr, c, w, true)
			draw_line(Vector2(18, 22), Vector2(46, 22), c, w * 0.7, true)
			draw_line(Vector2(32, 4), Vector2(32, 60), c, w * 0.5, true)
		"lock":
			draw_rect(Rect2(16, 28, 32, 26), c, false, w)
			draw_arc(Vector2(32, 28), 10.0, PI, TAU, 16, c, w, true)
			draw_circle(Vector2(32, 40), 3.0, c)
		"map":
			var m := PackedVector2Array([Vector2(8, 14), Vector2(24, 8), Vector2(40, 14), Vector2(56, 8), Vector2(56, 50), Vector2(40, 56), Vector2(24, 50), Vector2(8, 56), Vector2(8, 14)])
			draw_polyline(m, c, w, true)
			draw_line(Vector2(24, 8), Vector2(24, 50), c, w * 0.7, true)
			draw_line(Vector2(40, 14), Vector2(40, 56), c, w * 0.7, true)
		"eye":
			var e1 := PackedVector2Array()
			for i in 21:
				var t := i / 20.0
				e1.append(Vector2(lerpf(6, 58, t), 32 - sin(t * PI) * 16.0))
			for i in 21:
				var t := 1.0 - i / 20.0
				e1.append(Vector2(lerpf(6, 58, t), 32 + sin(t * PI) * 16.0))
			draw_polyline(e1, c, w, true)
			draw_circle(Vector2(32, 32), 7.0, c)
		"flight":
			draw_arc(Vector2(32, 40), 22.0, PI * 1.1, PI * 1.9, 20, c, w, true)
			draw_line(Vector2(32, 52), Vector2(32, 14), c, w, true)
			draw_line(Vector2(24, 22), Vector2(32, 14), c, w, true)
			draw_line(Vector2(40, 22), Vector2(32, 14), c, w, true)
		"region":
			var mt := PackedVector2Array([Vector2(4, 52), Vector2(22, 22), Vector2(32, 34), Vector2(42, 16), Vector2(60, 52), Vector2(4, 52)])
			draw_polyline(mt, c, w, true)
		_:
			_snowflake(Vector2(32, 32), 24.0, c, w)


func _snowflake(center: Vector2, r: float, c: Color, w: float) -> void:
	for k in 6:
		var a := TAU * k / 6.0 - PI * 0.5
		var d := Vector2(cos(a), sin(a))
		draw_line(center, center + d * r, c, w, true)
		var b := center + d * r * 0.55
		var p1 := Vector2(cos(a + 0.7), sin(a + 0.7)) * r * 0.28
		var p2 := Vector2(cos(a - 0.7), sin(a - 0.7)) * r * 0.28
		draw_line(b, b + p1, c, w * 0.8, true)
		draw_line(b, b + p2, c, w * 0.8, true)


func _cloud(center: Vector2, sc: float, c: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var lobes := [[-14.0, 4.0, 9.0], [-4.0, -4.0, 12.0], [10.0, -1.0, 10.0], [18.0, 5.0, 7.0]]
	for i in 48:
		var a := TAU * i / 47.0
		var dir := Vector2(cos(a), sin(a))
		var best := 0.0
		for l in lobes:
			var lc := Vector2(l[0], l[1])
			var r: float = l[2]
			var proj := lc.dot(dir)
			var disc := proj * proj - lc.length_squared() + r * r
			if disc > 0.0:
				best = maxf(best, proj + sqrt(disc))
		best = minf(best, 13.0 / maxf(dir.y, 0.01)) if dir.y > 0.0 else best
		pts.append(center + dir * best * sc)
	draw_polyline(pts, c, w, true)


func _wind_curve(start: Vector2, length: float, c: Color, w: float, curl: float) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var t := i / 15.0
		pts.append(start + Vector2(t * length, sin(t * PI * 1.2) * -3.0 * curl))
	var end := pts[pts.size() - 1]
	for i in 12:
		var a := -PI * 0.5 + i / 11.0 * PI * 1.4 * curl
		pts.append(end + Vector2(cos(a) * 5.0, (sin(a) + 1.0) * 5.0 * curl * -1.0 + 0.0))
	draw_polyline(pts, c, w, true)
