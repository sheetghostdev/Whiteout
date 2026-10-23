class_name TestProgressionBot
extends RefCounted
## Runs complete playthroughs with the balance bot. The standard suite runs one
## strategy; `-- balance` runs the whole strategy matrix and prints a table.

const MAX_TIME := 150.0 * 60.0


func run(t, full: bool) -> void:
	var list: Array = BalanceBot.STRATEGIES if full else ["standard"]
	var rows: Array = []
	for s in list:
		var bot := BalanceBot.new()
		bot.setup(t, t.shared_terrain(), s, 2024)
		var t0 := Time.get_ticks_msec()
		var res := bot.run(MAX_TIME)
		bot.dispose()
		res["wall"] = (Time.get_ticks_msec() - t0) / 1000.0
		var levels: Dictionary = bot.unlock_levels.duplicate(true)
		rows.append(res)
		_print_row(res)
		var name: String = res["strategy"]
		t.check(res["completed"], "%s: the world reaches 100%% (got %.1f%% after %s)" % [name, float(res["fraction"]) * 100.0, UIKit.fmt_time(res["time"])])
		t.check(float(res["first_purchase"]) >= 0.0 and float(res["first_purchase"]) <= 30.0, "%s: first upgrade within 30 s (%.1f s)" % [name, float(res["first_purchase"])])
		t.check(float(res["longest_gap"]) < 12.0 * 60.0, "%s: never more than 12 minutes without an affordable purchase (%s)" % [name, UIKit.fmt_time(res["longest_gap"])])
		if name == "standard":
			var u: Dictionary = res["unlocks"]
			t.check(u.has("frost_front") and float(u["frost_front"]) < 9.0 * 60.0, "standard: first new ability within ~5-9 minutes")
			t.check(u.has("polar_vortex"), "standard: reaches the Polar Vortex")
			# The bot aims and reacts far faster than a person; ~30 bot-minutes
			# corresponds to roughly an hour of human play.
			t.check(float(res["time"]) > 22.0 * 60.0 and float(res["time"]) < 60.0 * 60.0, "standard: bot completion time in the tuned window (%s)" % UIKit.fmt_time(res["time"]))
			t.check(u.has("polar_vortex") and float(u["polar_vortex"]) < float(res["time"]) * 0.85, "standard: Polar Vortex arrives with real work left")
			_power_check(t, levels)


func _print_row(r: Dictionary) -> void:
	var u: Dictionary = r["unlocks"]
	var m: Dictionary = r["milestones"]
	var parts: Array[String] = []
	for a in ["frost_front", "arctic_wind", "blizzard", "avalanche", "polar_vortex"]:
		parts.append("%s %s" % [a.substr(0, 5), UIKit.fmt_time(u[a]) if u.has(a) else "-"])
	var ms: Array[String] = []
	for k in [0.1, 0.25, 0.5, 0.75, 0.9, 1.0]:
		ms.append("%d%% %s" % [int(k * 100), UIKit.fmt_time(m[k]) if m.has(k) else "-"])
	print("    [%s] %s  done=%s  time=%s  first=%.0fs  gap=%s  buys=%d  (%.0fs wall)" % [r["strategy"], "%.1f%%" % (float(r["fraction"]) * 100.0),
		r["completed"], UIKit.fmt_time(r["time"]), float(r["first_purchase"]), UIKit.fmt_time(r["longest_gap"]), int(r["purchases"]), float(r["wall"])])
	print("        unlocks: ", "  ".join(parts))
	print("        coverage: ", "  ".join(ms))


## Each new power should feel clearly stronger than the Snow Cloud the player
## already has at the moment it unlocks (measured on fresh ground).
func _power_check(t, levels: Dictionary) -> void:
	for a in GameBalance.ABILITY_ORDER:
		if not levels.has(a):
			continue
		var me := PowerBench.measure(t, t.shared_terrain(), levels[a], a)
		var cloud := PowerBench.measure(t, t.shared_terrain(), levels[a], "snow_cloud")
		var ratio := me / maxf(cloud, 0.01)
		print("        at %-12s unlock: %7.1f m²/s   vs Snow Cloud %6.1f m²/s   (%.1fx)" % [a, me, cloud, ratio])
		t.check(ratio >= 1.3, "%s is clearly stronger than the cloud when it unlocks (%.1fx)" % [a, ratio])
