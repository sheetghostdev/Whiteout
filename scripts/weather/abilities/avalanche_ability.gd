class_name AvalancheAbility
extends WeatherAbility


func validate(ctx: Dictionary) -> String:
	var base := super.validate(ctx)
	if base != "":
		return base
	return Avalanche.release_check(manager.terrain, manager.cov, t2(ctx["target"]))


## Traces the likely downhill path for the preview arrow.
func trace_path(start: Vector2, steps: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p := start
	var v := Vector2.ZERO
	var t := manager.terrain
	for k in steps:
		var g := t.gradient(p.x, p.y)
		v = v * 0.8 - g * 3.0
		if v.length() < 0.05:
			break
		p += v.normalized() * 3.0
		if not t.in_bounds(p.x, p.y, 3.0):
			break
		pts.append(Vector3(p.x, t.surface_height(p.x, p.y), p.y))
	return pts


func preview(ctx: Dictionary) -> Dictionary:
	var r := validate(ctx)
	var target: Vector3 = ctx.get("target", Vector3.ZERO)
	return {"shape": "avalanche", "center": target, "radius": prog().stat("av_width") * 0.7,
		"path": trace_path(t2(target), 24) if ctx.get("hit", false) else PackedVector3Array(),
		"valid": r == "", "reason": r}


func cast(ctx: Dictionary) -> bool:
	if not manager.can_spawn("avalanche"):
		return false
	var a := Avalanche.new()
	a.init_from_stats(prog())
	manager.spawn(a)
	a.start(t2(ctx["target"]), manager.rng.randi())
	return true
