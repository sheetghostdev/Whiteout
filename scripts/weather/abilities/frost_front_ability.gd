class_name FrostFrontAbility
extends WeatherAbility
## Fronts launch from the player's feet along the view direction.


func validate(_ctx: Dictionary) -> String:
	return ""


func preview(ctx: Dictionary) -> Dictionary:
	var feet: Vector3 = ctx.get("feet", Vector3.ZERO)
	var d := flat_aim(ctx)
	return {"shape": "strip", "center": feet + Vector3(d.x, 0, d.y) * 2.0, "dir": d,
		"width": prog().stat("front_width"), "length": prog().stat("front_distance") * prog().stat("duration_mult"),
		"count": int(prog().stat("front_count")), "valid": true, "reason": ""}


func cast(ctx: Dictionary) -> bool:
	var feet: Vector3 = ctx.get("feet", Vector3.ZERO)
	var d := flat_aim(ctx)
	var n := int(prog().stat("front_count"))
	var spread := deg_to_rad(11.0)
	var root := -1
	var spawned := 0
	for k in n:
		if not manager.can_spawn("frost_front"):
			break
		var f := FrostFront.new()
		f.init_from_stats(prog())
		var off := (k - (n - 1) * 0.5) * spread
		f.dir = d.rotated(off)
		f.pos = t2(feet) + d * 2.0
		manager.spawn(f, root)
		if root < 0:
			root = f.uid
		spawned += 1
	return spawned > 0
