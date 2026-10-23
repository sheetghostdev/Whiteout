class_name ArcticWindAbility
extends WeatherAbility
## Gusts start just ahead of the player and blow along the view direction.


func validate(_ctx: Dictionary) -> String:
	return ""


func preview(ctx: Dictionary) -> Dictionary:
	var feet: Vector3 = ctx.get("feet", Vector3.ZERO)
	var d := flat_aim(ctx)
	var jet := prog().has("jet_stream")
	return {"shape": "wind", "center": feet + Vector3(d.x, 0, d.y) * 1.5, "dir": d,
		"width": prog().stat("wind_width") * prog().stat("wind_streams"),
		"length": prog().stat("wind_range") * (1.5 if jet else 1.0), "valid": true, "reason": ""}


func cast(ctx: Dictionary) -> bool:
	var feet: Vector3 = ctx.get("feet", Vector3.ZERO)
	var d := flat_aim(ctx)
	var n := int(prog().stat("wind_streams"))
	var w := prog().stat("wind_width")
	var side := d.orthogonal()
	var root := -1
	var spawned := 0
	for k in n:
		if not manager.can_spawn("arctic_wind"):
			break
		var g := ArcticWind.new()
		g.init_from_stats(prog())
		g.dir = d
		g.origin = t2(feet) + d * 1.5 + side * (k - (n - 1) * 0.5) * w * 0.9
		g.pos = g.origin
		manager.spawn(g, root)
		if root < 0:
			root = g.uid
		spawned += 1
	return spawned > 0


## Cyclonic Flow: a gust circling the aimed point.
func alt_cast(ctx: Dictionary) -> String:
	if not prog().has("cyclonic_flow"):
		return "Requires Cyclonic Flow"
	if manager.cooldown_remaining(id) > 0.0:
		return "Recharging"
	var r := validate_target(ctx)
	if r != "":
		return r
	if not manager.can_spawn("arctic_wind"):
		return "Too much weather"
	var g := ArcticWind.new()
	g.init_from_stats(prog())
	g.cyclonic = true
	g.origin = t2(ctx["target"])
	g.pos = g.origin
	g.ring_r = clampf(g.length * 0.35, 12.0, 70.0)
	manager.spawn(g)
	manager.cooldowns[id] = prog().cooldown_for(id)
	prog().record_cast(id)
	EventBus.ability_cast.emit(id, ctx["target"])
	return ""


func validate_target(ctx: Dictionary) -> String:
	if not ctx.get("hit", false):
		return "No ground in sight"
	if not in_range(ctx):
		return "Out of range"
	return ""
