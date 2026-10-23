class_name AbilityController
extends Node
## Ability selection and casting input. Holding the cast button re-casts as
## soon as the ability recharges, so early play never feels like clicking
## through a cooldown.

const CAST_SOUNDS := {
	"snow_cloud": "cast_cloud", "frost_front": "cast_front", "arctic_wind": "cast_wind",
	"blizzard": "cast_blizzard", "avalanche": "cast_avalanche", "polar_vortex": "cast_vortex",
}

var player: PlayerController
var selected := "snow_cloud"
var last_ctx := {}
var last_preview := {}


func weather() -> WeatherManager:
	return Game.weather


func unlocked() -> Array[String]:
	return Game.prog.unlocked_abilities()


func selected_id() -> String:
	if Game.prog.is_ability_unlocked(selected):
		return selected
	return "snow_cloud"


func select_id(id: String) -> void:
	if Game.prog.is_ability_unlocked(id):
		selected = id
		EventBus.ability_selected.emit(id)


## Number keys address the unlocked abilities in bar order.
func select_index(i: int) -> void:
	var list := unlocked()
	if i < 0 or i >= list.size():
		Audio.play("error", -10.0)
		return
	if selected != list[i]:
		selected = list[i]
		Audio.play("hover", -2.0, 1.2)
	EventBus.ability_selected.emit(list[i])


func cycle(d: int) -> void:
	var list := unlocked()
	if list.size() <= 1:
		return
	var i := maxi(list.find(selected_id()), 0)
	selected = list[posmod(i + d, list.size())]
	Audio.play("hover", -2.0, 1.2)
	EventBus.ability_selected.emit(selected)


func _unhandled_input(event: InputEvent) -> void:
	if not player.input_enabled:
		return
	for k in 6:
		if event.is_action_pressed("ability_%d" % (k + 1)):
			select_index(k)
			return
	if event.is_action_pressed("next_ability"):
		cycle(1)
	elif event.is_action_pressed("prev_ability"):
		cycle(-1)
	elif event.is_action_pressed("alt_cast"):
		_alt()
	elif event.is_action_pressed("thaw_sense"):
		if not Game.prog.has("thaw_sense"):
			_fail("thaw_sense", "Thaw Sense unlocks late in the game")
		elif not Game.use_thaw_sense(player.global_position):
			_fail("thaw_sense", "Thaw Sense is recharging")
		else:
			Audio.play("pulse", 0.0, 0.7)


func build_ctx() -> Dictionary:
	var origin := player.eye_position()
	var aim := player.aim_direction()
	var id := selected_id()
	var reach := maxf(Game.prog.cast_range_for(id) * 1.6, 60.0)
	var hit := player.terrain.raycast(origin, aim, reach)
	return {"origin": origin, "aim": aim, "target": hit["position"], "hit": hit["hit"],
		"feet": player.global_position}


func _process(_delta: float) -> void:
	var w := weather()
	if w == null or not player.input_enabled:
		player.targeting.hide_all()
		return
	var id := selected_id()
	last_ctx = build_ctx()
	last_preview = w.ability(id).preview(last_ctx)
	last_preview["ready"] = w.cooldown_remaining(id) <= 0.0
	player.targeting.show_preview(last_preview, id)
	if Input.is_action_pressed("cast"):
		var just := Input.is_action_just_pressed("cast")
		if w.cooldown_remaining(id) > 0.0:
			if just:
				_fail(id, "Recharging")
			return
		var r := w.try_cast(id, last_ctx)
		if r == "":
			_on_cast(id)
		elif just:
			_fail(id, r)


func _alt() -> void:
	var id := selected_id()
	var r := weather().try_alt(id, last_ctx)
	if r == "":
		Audio.play("cast_wind", -8.0, 1.3)
		player.targeting.flash()
	else:
		_fail(id, r)


func _on_cast(id: String) -> void:
	var target: Vector3 = last_ctx.get("target", player.global_position)
	var snd: String = CAST_SOUNDS.get(id, "cast_cloud")
	if id == "frost_front" or id == "arctic_wind":
		Audio.play(snd, -3.0, randf_range(0.95, 1.05))
	else:
		Audio.play_at(snd, target, 0.0, randf_range(0.95, 1.05))
	player.targeting.flash()


func _fail(id: String, reason: String) -> void:
	EventBus.ability_failed.emit(id, reason)
	Audio.play("error", -8.0)
