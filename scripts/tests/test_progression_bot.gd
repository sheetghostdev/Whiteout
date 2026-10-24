class_name TestProgressionBot
extends RefCounted
## Runs complete playthroughs with the balance bot. The standard suite runs one
## strategy; `-- balance` runs the whole strategy matrix and prints a table.

const MAX_TIME := 150.0 * 60.0


func run(t, full: bool) -> void:
	var list: Array = BalanceBot.STRATEGIES if full else ["standard"]
	for s in list:
		var bot := BalanceBot.new()
		bot.setup(t, t.shared_terrain(), s, 2024)
		var t0 := Time.get_ticks_msec()
		var res := bot.run(MAX_TIME)
		bot.dispose()
		res["wall"] = (Time.get_ticks_msec() - t0) / 1000.0
		_print_row(res)
		if "log" in OS.get_cmdline_user_args():
			var left: Array[String] = []
			for id in GameBalance.NODES:
				var lv := bot.prog.level(id)
				if lv < int(GameBalance.NODES[id]["max"]):
					left.append("%s %d/%d (%s)" % [id, lv, int(GameBalance.NODES[id]["max"]), UIKit.fmt(bot.prog.cost_of(id))])
			print("        unbought: ", ", ".join(left))
			print("        peak choices at %s: %s" % [UIKit.fmt_time(bot.choice_peak_t), ", ".join(bot.choice_peak)])
		if "buys" in OS.get_cmdline_user_args():
			for e in bot.purchase_log:
				print("        %s  %s %d" % [UIKit.fmt_time(e[0]), e[1], e[2]])
		var name: String = res["strategy"]
		t.check(res["completed"], "%s: the world reaches 100%% (got %.1f%% after %s)" % [name, float(res["fraction"]) * 100.0, UIKit.fmt_time(res["time"])])
		var first_limit := 25.0 if name == "saver" else 15.0
		t.check(float(res["first_purchase"]) >= 0.0 and float(res["first_purchase"]) <= first_limit, "%s: first upgrade within %d s (%.1f s)" % [name, int(first_limit), float(res["first_purchase"])])
		var gap_limit := 6.0 * 60.0 if name != "saver" else 8.0 * 60.0
		t.check(float(res["longest_gap"]) < gap_limit, "%s: never long without an affordable purchase (%s)" % [name, UIKit.fmt_time(res["longest_gap"])])
		# Roughly one open node per branch: a handful of clear choices, never a wall.
		t.check(float(res["choices_avg"]) <= 8.0, "%s: few choices on screen at once (avg %.1f)" % [name, float(res["choices_avg"])])
		t.check(int(res["choices_max"]) <= 12, "%s: never a wall of choices (max %d)" % [name, int(res["choices_max"])])
		if name == "standard":
			var sk: Dictionary = res["skills"]
			t.check(sk.has("squall") and float(sk["squall"]) < 60.0, "standard: first skill within a minute")
			t.check(sk.has("frost_wave"), "standard: unlocks Frost Wave")
			t.check(sk.has("vortex_form") and float(sk["vortex_form"]) < float(res["time"]) * 0.8, "standard: Vortex Form arrives with real work left")
			# The bot always flies straight to the nearest green ground and never
			# pauses; ~12 bot-minutes is roughly 25-35 minutes for a person.
			t.check(float(res["time"]) > 9.0 * 60.0 and float(res["time"]) < 35.0 * 60.0, "standard: bot completion time in the tuned window (%s)" % UIKit.fmt_time(res["time"]))
			t.check(float(res["spent_fraction"]) > 0.5, "standard: most of the web is bought by the end (%d%%)" % int(float(res["spent_fraction"]) * 100.0))
			t.check(float(res["radius"]) >= 12.0, "standard: you grow into a big cloud before the end (%.0f m)" % float(res["radius"]))


func _print_row(r: Dictionary) -> void:
	var sk: Dictionary = r["skills"]
	var m: Dictionary = r["milestones"]
	var parts: Array[String] = []
	for a in GameBalance.SKILL_ORDER:
		parts.append("%s %s" % [a, UIKit.fmt_time(sk[a]) if sk.has(a) else "-"])
	var ms: Array[String] = []
	for k in [0.01, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]:
		ms.append("%d%% %s" % [int(k * 100), UIKit.fmt_time(m[k]) if m.has(k) else "-"])
	print("    [%s] %s  done=%s  time=%s  first=%.0fs  gap=%s  buys=%d  choices avg %.1f max %d  web %d%%  r=%.0f  (%.0fs wall)" % [
		r["strategy"], "%.1f%%" % (float(r["fraction"]) * 100.0), r["completed"], UIKit.fmt_time(r["time"]),
		float(r["first_purchase"]), UIKit.fmt_time(r["longest_gap"]), int(r["purchases"]), float(r["choices_avg"]),
		int(r["choices_max"]), int(float(r["spent_fraction"]) * 100.0), float(r["radius"]), float(r["wall"])])
	print("        skills: ", "  ".join(parts))
	print("        coverage: ", "  ".join(ms))
	var src: Dictionary = r.get("sources", {})
	var tot := 0.0
	for k in src:
		tot += float(src[k])
	var sp: Array[String] = []
	for k in src:
		sp.append("%s %s" % [k, UIKit.fmt(float(src[k]))])
	print("        frozen by (m²): ", "  ".join(sp), "  drifts+ice ", UIKit.fmt(float(r.get("land", 0.0)) - tot), "  of ", UIKit.fmt(float(r.get("land", 0.0))))
