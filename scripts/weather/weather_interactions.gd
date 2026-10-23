class_name WeatherInteractions
extends RefCounted
## Explicit rules for how weather systems combine. Runs at the simulation
## rate over the (budget-limited) set of active effects.

const COMBOS := {
	"drifting_snow": {"name": "Drifting Snow", "pair": "Snow Cloud + Arctic Wind",
		"desc": "Wind carries snow clouds along, painting a trail of snow behind them."},
	"converging_clouds": {"name": "Converging Clouds", "pair": "Snow Cloud + Snow Cloud",
		"desc": "Overlapping clouds snow harder together."},
	"storm_feeding": {"name": "Storm Feeding", "pair": "Snow Cloud + Blizzard",
		"desc": "A blizzard swallows small clouds, growing larger and lasting longer."},
	"superstorm_fusion": {"name": "Superstorm Fusion", "pair": "Blizzard + Blizzard",
		"desc": "With the Superstorm evolution, overlapping blizzards fuse into one stronger storm."},
	"gale_front": {"name": "Gale Front", "pair": "Frost Front + Arctic Wind",
		"desc": "A tailwind drives frost fronts faster and farther."},
	"frost_burst": {"name": "Frost Burst", "pair": "Frost Front + Snow Cloud",
		"desc": "A front rolling under a cloud releases a burst of freezing intensity."},
	"whiteout_slide": {"name": "Whiteout Slide", "pair": "Avalanche + Blizzard",
		"desc": "Avalanches inside a blizzard grow wider and heavier."},
	"ice_shockwave": {"name": "Ice Shockwave", "pair": "Avalanche + Frozen Lake",
		"desc": "An avalanche striking frozen water sends a circular shockwave across the ice."},
	"vortex_orbit": {"name": "Vortex Orbit", "pair": "Polar Vortex + Snow Cloud",
		"desc": "Clouds are drawn into orbit around the vortex, then absorbed to feed it."},
	"vortex_amplify": {"name": "Polar Amplification", "pair": "Polar Vortex + Blizzard",
		"desc": "Blizzards caught in a vortex are greatly amplified."},
}


static func run(m: WeatherManager, dt: float) -> void:
	var clouds: Array = []
	var blizzards: Array = []
	var fronts: Array = []
	var vortices: Array = []
	var avalanches: Array = []
	for e in m.effects:
		if not e.alive:
			continue
		match e.kind:
			"snow_cloud":
				clouds.append(e)
			"blizzard":
				blizzards.append(e)
			"frost_front":
				fronts.append(e)
			"polar_vortex":
				vortices.append(e)
			"avalanche":
				avalanches.append(e)

	# Snow Cloud + Arctic Wind
	for c in clouds:
		if c.in_wind > 2.5 and c.vel.length() > 2.0:
			m.discover("drifting_snow", c.pos)

	# Snow Cloud + Snow Cloud
	for i in clouds.size():
		var a: SnowCloud = clouds[i]
		for j in range(i + 1, clouds.size()):
			var b: SnowCloud = clouds[j]
			var lim := (a.radius + b.radius) * 0.55
			if a.pos.distance_squared_to(b.pos) < lim * lim:
				a.overlap_boost = minf(a.overlap_boost + 0.25, 1.75)
				b.overlap_boost = minf(b.overlap_boost + 0.25, 1.75)
				m.discover("converging_clouds", (a.pos + b.pos) * 0.5)

	# Snow Cloud + Blizzard
	for bz in blizzards:
		var b: Blizzard = bz
		for c in clouds:
			var sc: SnowCloud = c
			if not sc.alive or sc.absorbed_target != Vector2.INF:
				continue
			if sc.pos.distance_to(b.pos) < b.radius * 0.75:
				b.absorb_cloud(sc)
				sc.absorbed_target = b.pos
				sc.life = sc.age + 1.0
				m.discover("storm_feeding", sc.pos)

	# Blizzard + Blizzard
	for i in blizzards.size():
		var a: Blizzard = blizzards[i]
		if not a.alive:
			continue
		for j in range(i + 1, blizzards.size()):
			var b: Blizzard = blizzards[j]
			if not b.alive:
				continue
			var d := a.pos.distance_to(b.pos)
			if d < (a.radius + b.radius) * 0.5:
				if m.prog.has("superstorm"):
					var big := a if a.radius >= b.radius else b
					var small := b if big == a else a
					big.merge_from(small)
					small.kill()
					m.discover("superstorm_fusion", big.pos)
					m.add_chain_link(big.root_id)
				else:
					a.overlap_boost = 1.2
					b.overlap_boost = 1.2
					m.hint_once("hint_superstorm", "The storms strain to merge...", "The Superstorm evolution lets overlapping blizzards fuse.")

	# Frost Front + Snow Cloud
	for f in fronts:
		var fr: FrostFront = f
		for c in clouds:
			var sc: SnowCloud = c
			if sc.bursts.has(fr.root_id):
				continue
			if fr.pos.distance_to(sc.pos) < sc.radius + fr.width * 0.5:
				sc.bursts[fr.root_id] = true
				m.spawn_pulse(sc.pos, sc.radius * 2.6, 0.55, fr.root_id, "burst")
				m.discover("frost_burst", sc.pos)

	# Avalanche + Blizzard
	for av in avalanches:
		var a: Avalanche = av
		for h in a.heads:
			if not h["alive"]:
				continue
			var hp: Vector2 = h["p"]
			for bz in blizzards:
				var b: Blizzard = bz
				if hp.distance_to(b.pos) < b.radius:
					h["boost"] = 1.35
					m.discover("whiteout_slide", hp)
					break

	# Polar Vortex + Snow Cloud / Blizzard
	for vx in vortices:
		var v: PolarVortex = vx
		var reach := v.radius * v.attract
		var n := 0
		var storms: Array = clouds + blizzards
		storms.sort_custom(func(x, y): return x.pos.distance_squared_to(v.pos) < y.pos.distance_squared_to(v.pos))
		for s in storms:
			if not s.alive or n >= v.orbit_cap:
				continue
			var rel: Vector2 = s.pos - v.pos
			var d := rel.length()
			if d > reach or d < 0.01:
				continue
			n += 1
			var tang := Vector2(-rel.y, rel.x) / d
			var inward := -rel / d
			var pull := clampf(1.0 - d / reach, 0.15, 1.0)
			if s is SnowCloud:
				var sc: SnowCloud = s
				sc.ext_v += (tang * 7.0 + inward * 3.5) * pull
				if d < v.radius * 0.3 and sc.absorbed_target == Vector2.INF:
					v.absorb_storm(0.03, 2.0)
					sc.absorbed_target = v.pos
					sc.life = sc.age + 1.0
				m.discover("vortex_orbit", sc.pos)
			else:
				var b: Blizzard = s
				b.ext_v += (tang * 4.0 + inward * 1.0) * pull
				b.boost = 1.6
				b.radius = minf(b.radius + 0.4 * dt, b.max_radius)
				m.discover("vortex_amplify", b.pos)
		v.orbiting = n
