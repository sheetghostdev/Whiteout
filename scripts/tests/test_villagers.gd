class_name TestVillagers
extends RefCounted
## The islanders' little simulation, run headlessly on the real towns:
## ordinary summer life, the first snow sending everyone home cold, fires
## being lit, people coming back out bundled up, and winter fun.


func _tick(v: Villagers, seconds: float) -> void:
	for k in int(seconds * 10.0):
		v._process(0.1)


func _count(census: Dictionary, keys: Array) -> int:
	var n := 0
	for k in keys:
		n += int(census.get(k, 0))
	return n


func run(t, _full: bool) -> void:
	var terrain: TerrainData = t.shared_terrain()
	var cov := SnowCoverage.new()
	cov.setup(terrain)
	var sb := SettlementBuilder.new()
	(t as Node).add_child(sb)
	sb.build(terrain, cov)
	var v := sb.villagers
	t.check(v.people.size() >= 50, "the island has a real population (%d people)" % v.people.size())
	var roles := {}
	for p in v.people:
		roles[p.role] = int(roles.get(p.role, 0)) + 1
	t.check(roles.has("farmer") and roles.has("fisher") and roles.has("woodcutter") and roles.has("trader") and roles.has("kid"),
		"farmers, fishers, woodcutters, traders and children all live here (%s)" % str(roles))
	# Every home is reachable along the roads from the village square.
	var unreachable := 0
	for bi in v._door:
		var path := v._route(SettlementPlan.SQUARE, v._door[bi], v._door_node[bi])
		if path.size() < 2 and SettlementPlan.SQUARE.distance_to(v._door[bi]) > 30.0:
			unreachable += 1
	t.check(unreachable == 0, "every door can be reached by road (%d cannot)" % unreachable)
	# Summer: people work, chat and play; nobody is cold; no fires.
	_tick(v, 90.0)
	var c := v.census()
	print("    summer: ", c)
	t.check(_count(c, ["work"]) >= 5, "in summer people go to work (%d)" % _count(c, ["work"]))
	t.check(_count(c, ["chat", "sit", "play", "idle", "walking", "work"]) > v.people.size() / 2, "most people are out and about")
	var cold := 0
	for p in v.people:
		if p.cold > 0.3:
			cold += 1
	t.check(cold == 0 and sb.fires_lit() == 0.0, "nobody is cold and no fire is lit in summer")
	sb._process(1.0)
	# First snow: everyone heads home, shivering on the way; children stare.
	for k in 3:
		cov.apply_disc(0, 0, 600.0, 1.0)
	_tick(v, 6.0)
	c = v.census()
	print("    first snow: ", c)
	var cold_out := 0
	for p in v.people:
		if not (p.mode == "do" and p.act == "inside") and p.cold > 0.3 and not p.bundled:
			cold_out += 1
	t.check(cold_out > 5, "the first snow catches people out in the cold (%d shivering)" % cold_out)
	t.check(_count(c, ["work", "play", "sit"]) <= 2, "work and play stop when the snow comes")
	_tick(v, 25.0)
	c = v.census()
	t.check(_count(c, ["inside"]) > v.people.size() / 2, "people take shelter at home (%d inside)" % _count(c, ["inside"]))
	for k in 30:
		sb._process(1.0)
	t.check(sb.fires_lit() > 0.4, "they light their fires (%d%% of homes)" % int(sb.fires_lit() * 100.0))
	var smoking := 0
	for h in sb.homes:
		if (h["smoke"] as GPUParticles3D).emitting:
			smoking += 1
	t.check(smoking > 0, "chimneys smoke once the fires are lit")
	# Later they adapt: back out in winter gear, then winter fun.
	_tick(v, 160.0)
	var bundled := 0
	for p in v.people:
		if p.bundled:
			bundled += 1
	t.check(bundled > v.people.size() * 0.7, "people adapt and come out bundled up (%d of %d)" % [bundled, v.people.size()])
	c = v.census()
	print("    deep winter: ", c, "  snowmen ", v.snowmen_built())
	var fun := _count(c, ["snowball", "snowman", "skate", "sled", "campfire", "carol", "icefish"])
	t.check(fun >= 8, "winter fun: snowball fights, snowmen, skating, sledding (%d people)" % fun)
	_tick(v, 120.0)
	t.check(v.snowmen_built() >= 2, "snowmen get built (%d)" % v.snowmen_built())
	var seen := {}
	for k in 60:
		_tick(v, 2.0)
		for key in v.census():
			seen[key] = true
	t.check(seen.has("snowball") and seen.has("skate") and seen.has("sled"), "snowball fights, skating and sledding all happen (%s)" % str(seen.keys()))
	cold = 0
	for p in v.people:
		if p.cold > 0.5:
			cold += 1
	t.check(cold <= 2, "bundled-up villagers are no longer freezing (%d)" % cold)
	var t0 := Time.get_ticks_usec()
	for k in 120:
		v._process(1.0 / 60.0)
	var per_frame := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	print("    villagers: %.2f ms per frame for %d people" % [per_frame, v.people.size()])
	t.check(per_frame < 6.0, "the whole island's villagers cost little per frame (%.2f ms)" % per_frame)
	sb.queue_free()
	# Songbirds stay all summer and fly south once their ground is snowed over;
	# gulls stay at the harbour.
	var cov2 := SnowCoverage.new()
	cov2.setup(terrain)
	var wl := Wildlife.new()
	(t as Node).add_child(wl)
	wl.setup(terrain, cov2)
	for k in 100:
		wl._process(0.1)
	var home := wl.flocks_home()
	t.check(home == 4, "the songbirds are home in summer (%d flocks)" % home)
	for k in 2:
		cov2.apply_disc(0, 0, 600.0, 1.0)
	for k in 700:
		wl._process(0.1)
	t.check(wl.flocks_home() == 0, "in winter the songbirds fly south")
	var gulls_left := 0
	for f in wl.flocks:
		if f["spec"]["kind"] == "gull" and f["state"] != "circle":
			gulls_left += 1
	t.check(gulls_left == 0, "the gulls stay at the harbour")
	wl.queue_free()
