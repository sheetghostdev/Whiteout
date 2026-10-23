class_name PolarVortexAbility
extends WeatherAbility


func preview(ctx: Dictionary) -> Dictionary:
	var r := validate(ctx)
	return {"shape": "circle", "center": ctx.get("target", Vector3.ZERO), "radius": prog().stat("pv_radius"),
		"valid": r == "", "reason": r, "big": true}


func cast(ctx: Dictionary) -> bool:
	var cap := 2 if prog().is_maxed("pv_radius") else 1
	var mine := manager.effects_of("polar_vortex")
	if mine.size() >= cap:
		var oldest: PolarVortex = mine[0]
		oldest.life = minf(oldest.life, oldest.age + 2.0)
	if not manager.can_spawn("polar_vortex"):
		return false
	var v := PolarVortex.new()
	v.init_from_stats(prog())
	v.pos = t2(ctx["target"])
	v.wander = manager.rng.randf() * TAU
	manager.spawn(v)
	return true


func alt_cast(ctx: Dictionary) -> String:
	return guide(ctx, "polar_vortex", "vortex")
