class_name SnowCloudAbility
extends WeatherAbility


func max_clouds() -> int:
	return int(prog().stat("cloud_count") + prog().stat("storm_capacity"))


func preview(ctx: Dictionary) -> Dictionary:
	var r := validate(ctx)
	return {"shape": "circle", "center": ctx.get("target", Vector3.ZERO), "radius": prog().stat("cloud_radius"),
		"valid": r == "", "reason": r, "cloud": true}


func cast(ctx: Dictionary) -> bool:
	# At capacity, the oldest player cloud gives way to the new one.
	var mine: Array = []
	for e in manager.effects_of("snow_cloud"):
		if (e as SnowCloud).player_owned:
			mine.append(e)
	if mine.size() >= max_clouds():
		mine.sort_custom(func(a, b): return a.age / a.life > b.age / b.life)
		var oldest: SnowCloud = mine[0]
		oldest.player_owned = false
		oldest.life = minf(oldest.life, oldest.age + 0.5)
	if not manager.can_spawn("snow_cloud"):
		return false
	var c := SnowCloud.new()
	c.init_from_stats(prog())
	c.pos = t2(ctx["target"])
	c.wander = manager.rng.randf() * TAU
	manager.spawn(c)
	return true


func alt_cast(ctx: Dictionary) -> String:
	return guide(ctx, "snow_cloud", "clouds")
