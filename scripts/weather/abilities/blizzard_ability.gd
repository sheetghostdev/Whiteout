class_name BlizzardAbility
extends WeatherAbility


func preview(ctx: Dictionary) -> Dictionary:
	var r := validate(ctx)
	return {"shape": "circle", "center": ctx.get("target", Vector3.ZERO), "radius": prog().stat("bz_radius"),
		"valid": r == "", "reason": r}


func cast(ctx: Dictionary) -> bool:
	var mine := manager.effects_of("blizzard")
	if mine.size() >= int(prog().stat("bz_count")):
		mine.sort_custom(func(a, b): return a.age / a.life > b.age / b.life)
		var oldest: Blizzard = mine[0]
		oldest.life = minf(oldest.life, oldest.age + 1.0)
	if not manager.can_spawn("blizzard"):
		return false
	var b := Blizzard.new()
	b.init_from_stats(prog())
	b.pos = t2(ctx["target"])
	b.heading = manager.rng.randf() * TAU
	manager.spawn(b)
	return true


func alt_cast(ctx: Dictionary) -> String:
	return guide(ctx, "blizzard", "blizzards")
