class_name WeatherAbility
extends RefCounted
## Common ability contract. The cast context dictionary holds:
##   target: Vector3  (aimed ground point)     hit: bool
##   origin: Vector3  (camera position)         aim: Vector3 (view direction)
##   feet: Vector3    (player ground position)
## Subclasses read their numbers from Progression at cast time, so upgrades
## apply immediately.

var id := ""
var manager: WeatherManager


func prog() -> Progression:
	return manager.prog


func cast_range() -> float:
	return manager.prog.cast_range_for(id)


func flat_aim(ctx: Dictionary) -> Vector2:
	var a: Vector3 = ctx.get("aim", Vector3.FORWARD)
	var f := Vector2(a.x, a.z)
	return f.normalized() if f.length() > 0.01 else Vector2(0, -1)


func in_range(ctx: Dictionary) -> bool:
	if not ctx.get("hit", false):
		return false
	var o: Vector3 = ctx["origin"]
	var t: Vector3 = ctx["target"]
	return o.distance_to(t) <= cast_range()


func validate(ctx: Dictionary) -> String:
	if not ctx.get("hit", false):
		return "No ground in sight"
	if not in_range(ctx):
		return "Out of range"
	return ""


## Shape description for the targeting preview.
func preview(ctx: Dictionary) -> Dictionary:
	return {"shape": "circle", "center": ctx.get("target", Vector3.ZERO), "radius": 2.0, "valid": validate(ctx) == "", "reason": validate(ctx)}


func cast(_ctx: Dictionary) -> bool:
	return false


func alt_cast(_ctx: Dictionary) -> String:
	return "No alternate action"


func guide(ctx: Dictionary, kind_id: String, label: String) -> String:
	if not ctx.get("hit", false):
		return "No ground in sight"
	var t: Vector3 = ctx["target"]
	var n := manager.guide_kind(kind_id, Vector2(t.x, t.z), 6.0 * manager.prog.stat("guide_strength"))
	if n == 0:
		return "No active %s" % label
	return ""


func t2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
