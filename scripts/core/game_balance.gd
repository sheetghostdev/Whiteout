class_name GameBalance
extends RefCounted
## Single source of truth for every tunable number in WHITEOUT.
##
## You are a snow cloud. Everything you can become lives in one upgrade web
## (NODES). Design rules, drawn from what players praise and criticise in
## popular incrementals:
##   * one currency (Frost) - no collect-a-thon of resources;
##   * finishing a node reveals only its neighbours, so only a handful of
##     choices are ever on screen;
##   * few levels per node, each one a noticeable step - no "+4%" slogs;
##   * every branch ends in a keystone that changes how you play;
##   * active skills keep your input relevant until the very end.
## Each stat-driving node feeds exactly one stat, so shop text and gameplay
## values come from the same function and cannot drift apart.

# ------------------------------------------------------------------- stats
# mode "add": base + sum(per * level)      mode "mul": base * prod(per ^ level)
const STATS := {
	"radius": {"base": 2.5, "mode": "add", "fmt": "%.1f m", "name": "Cloud radius"},
	"speed": {"base": 2.7, "mode": "add", "fmt": "%.1f m/s", "name": "Flying speed"},
	"frost_mult": {"base": 1.0, "mode": "add", "fmt": "%.2fx", "name": "Frost per m²"},
	"companions": {"base": 0.0, "mode": "add", "fmt": "%d", "name": "Cloudlets"},
	"comp_size": {"base": 0.25, "mode": "add", "fmt": "%d%% of you", "pct": true, "name": "Cloudlet size"},
	"comp_leash": {"base": 14.0, "mode": "add", "fmt": "%d m", "name": "Cloudlet reach"},
	"drift": {"base": 3.0, "mode": "add", "fmt": "%d m", "name": "Gaps that drift shut"},
	"spread": {"base": 0.0, "mode": "add", "fmt": "%d m²/s", "name": "Spreading frost"},
	"ice_creep": {"base": 0.15, "mode": "add", "fmt": "%.2f /s", "name": "Ice creep"},
	"region_bonus": {"base": 1.0, "mode": "add", "fmt": "%.1fx", "name": "Milestone bonus"},
	"squall_radius": {"base": 1.4, "mode": "add", "fmt": "%.1fx your size", "name": "Squall reach"},
	"squall_cd": {"base": 12, "mode": "mul", "fmt": "%.1f s", "name": "Squall recharge"},
	"wave_length": {"base": 35, "mode": "add", "fmt": "%d m", "name": "Wave reach"},
	"wave_width": {"base": 0.6, "mode": "add", "fmt": "%.1fx your trail", "name": "Wave width"},
	"wave_cd": {"base": 10, "mode": "mul", "fmt": "%.1f s", "name": "Wave recharge"},
	"av_width": {"base": 8, "mode": "add", "fmt": "%d m", "name": "Avalanche width"},
	"av_cd": {"base": 20, "mode": "mul", "fmt": "%.1f s", "name": "Avalanche recharge"},
	"vortex_mult": {"base": 2.0, "mode": "add", "fmt": "%.1fx", "name": "Vortex size"},
	"vortex_time": {"base": 8.0, "mode": "add", "fmt": "%d s", "name": "Vortex duration"},
	"vortex_cd": {"base": 60.0, "mode": "mul", "fmt": "%d s", "name": "Vortex recharge"},
}

# ---------------------------------------------------------------- skills
# Active skills, bought in the web and fired with a key.
const SKILLS := {
	"squall": {"name": "Squall", "key": "Left Mouse", "action": "skill_squall", "icon": "snowflake", "cd_stat": "squall_cd",
		"desc": "A burst of snow rings out around you, scaled to your size."},
	"frost_wave": {"name": "Frost Wave", "key": "Right Mouse", "action": "skill_wave", "icon": "front", "cd_stat": "wave_cd",
		"desc": "Send a broad wave of frost rolling far across the land where you look; it scales with your size."},
	"vortex_form": {"name": "Vortex Form", "key": "R", "action": "skill_vortex", "icon": "vortex", "cd_stat": "vortex_cd",
		"desc": "Swell into a polar vortex for a few seconds, freezing a vast area."},
}
const SKILL_ORDER: Array[String] = ["squall", "frost_wave", "vortex_form"]

# ---------------------------------------------------------------- the web
# Each node: name, desc, icon, pos (web layout units), links (any one owned
# maxed reveals this node), max, cost, growth, and either stat+per (+mode from the
# stat) or kind "keystone" / "skill". Optional "coverage": world fraction
# needed before it can be bought.
const BRANCH_COLORS := {
	"heart": Color(0.92, 0.97, 1.0), "size": Color(0.70, 0.86, 1.0), "snow": Color(0.80, 0.92, 1.0),
	"wind": Color(0.66, 0.95, 0.88), "companions": Color(0.86, 0.80, 1.0), "storm": Color(0.62, 0.80, 1.0),
	"land": Color(0.95, 0.88, 0.70), "polar": Color(0.80, 0.70, 1.0),
}

const NODES := {
	"heart": {"branch": "heart", "name": "Little Cloud", "icon": "cloud", "pos": Vector2(0, 0), "links": [],
		"max": 1, "cost": 0, "growth": 1.0, "kind": "keystone",
		"desc": "That's you. Snow falls wherever you drift."},
	# ----- Size (up)
	"billow": {"branch": "size", "name": "Billow", "icon": "cloud", "pos": Vector2(0, -1.6), "links": ["heart"],
		"max": 5, "cost": 12, "growth": 1.75, "stat": "radius", "per": 0.45,
		"desc": "A wider cloud blankets more ground."},
	"yield_sky": {"branch": "size", "name": "Crisp Air", "icon": "crystal", "pos": Vector2(-1.15, -2.6), "links": ["swell"],
		"max": 3, "cost": 32, "growth": 2.4, "stat": "frost_mult", "per": 0.12,
		"desc": "Earn more Frost for every square metre you freeze."},
	"swell": {"branch": "size", "name": "Swell", "icon": "cloud", "pos": Vector2(0, -3.1), "links": ["billow"],
		"max": 5, "cost": 174, "growth": 1.85, "stat": "radius", "per": 0.45,
		"desc": "Grow larger still."},
	"towering": {"branch": "size", "name": "Towering Cloud", "icon": "cloud", "pos": Vector2(0, -4.6), "links": ["swell"],
		"max": 4, "cost": 3500, "growth": 1.7, "coverage": 0.25, "stat": "radius", "per": 0.75,
		"desc": "Climb into a towering cumulus."},
	"thunderhead": {"branch": "size", "name": "Thunderhead", "icon": "spark", "pos": Vector2(0, -6.1), "links": ["towering"],
		"max": 1, "cost": 12000, "growth": 1.0, "coverage": 0.5, "kind": "keystone", "stat": "radius", "per": 2.5,
		"desc": "KEYSTONE: become a vast thunderhead (+2.5 m radius at once)."},
	"yield_high": {"branch": "size", "name": "Thin Air", "icon": "crystal", "pos": Vector2(-1.3, -5.2), "links": ["towering"],
		"max": 3, "cost": 3931, "growth": 1.8, "stat": "frost_mult", "per": 0.12,
		"desc": "Earn more Frost for every square metre you freeze."},
	"sky_giant": {"branch": "size", "name": "Sky Giant", "icon": "cloud", "pos": Vector2(1.3, -5.2), "links": ["towering"],
		"max": 3, "cost": 14000, "growth": 1.5, "stat": "radius", "per": 1.5, "coverage": 0.75,
		"desc": "The biggest cloud the valley has ever seen."},
	# ----- Snowfall (up-right)
	"drift_snow": {"branch": "snow", "name": "Drifting Snow", "icon": "snowflake", "pos": Vector2(1.4, -0.8), "links": ["heart"],
		"max": 2, "cost": 15, "growth": 2.2, "stat": "drift", "per": 2.0,
		"desc": "Snow drifts into the strips you miss between passes: gaps up to 2 m wider seal themselves, per level."},
	"spreading": {"branch": "snow", "name": "Spreading Frost", "icon": "crystal", "pos": Vector2(2.7, -1.5), "links": ["drift_snow"],
		"max": 3, "cost": 260, "growth": 2.3, "stat": "spread", "per": 4.0,
		"desc": "While you fly, frozen ground slowly creeps into the green ground next to it: +4 m² a second per level."},
	"deep_freeze": {"branch": "snow", "name": "Deep Freeze", "icon": "spark", "pos": Vector2(3.3, -2.8), "links": ["spreading"],
		"max": 1, "cost": 1457, "growth": 1.0, "kind": "keystone", "stat": "drift", "per": 4.0,
		"desc": "KEYSTONE: deep drifts seal gaps 4 m wider still, so even sloppy passes leave nothing behind."},
	"crystal": {"branch": "snow", "name": "Snow Crystals", "icon": "crystal", "pos": Vector2(4.4, -1.6), "links": ["spreading", "deep_freeze"],
		"max": 3, "cost": 4422, "growth": 1.8, "stat": "frost_mult", "per": 0.15,
		"desc": "Earn more Frost for every square metre you freeze."},
	# ----- Wind (down-right)
	"breeze": {"branch": "wind", "name": "Breeze", "icon": "wind", "pos": Vector2(1.4, 0.8), "links": ["heart"],
		"max": 5, "cost": 20, "growth": 1.8, "stat": "speed", "per": 0.4,
		"desc": "Your cloud flies faster: +0.4 m/s for each level."},
	"gale": {"branch": "wind", "name": "Gale", "icon": "wind", "pos": Vector2(2.7, 1.5), "links": ["breeze"],
		"max": 3, "cost": 148, "growth": 1.9, "stat": "speed", "per": 0.5,
		"desc": "Stronger winds carry you: +0.5 m/s for each level."},
	"tailwind": {"branch": "wind", "name": "Tailwind", "icon": "spark", "pos": Vector2(3.3, 2.8), "links": ["gale"],
		"max": 1, "cost": 1749, "growth": 1.0, "kind": "keystone",
		"desc": "KEYSTONE: you fly 30% faster while your whole cloud is over frozen ground, so getting back to fresh green is quick. Half on, half off does not count."},
	"jet_stream": {"branch": "wind", "name": "Jet Stream", "icon": "wind", "pos": Vector2(4.6, 3.3), "links": ["tailwind"],
		"max": 3, "cost": 15795, "growth": 1.6, "stat": "speed", "per": 0.8, "coverage": 0.5,
		"desc": "Ride the high winds: +0.8 m/s for each level."},
	# ----- Cloudlets (down)
	"cloudlet": {"branch": "companions", "name": "Cloudlet", "icon": "cloud", "pos": Vector2(0, 1.6), "links": ["breeze"],
		"max": 1, "cost": 565, "growth": 1.0, "stat": "companions", "per": 1.0,
		"desc": "A little cloud follows you around, snowing too."},
	"more_cloudlets": {"branch": "companions", "name": "Little Siblings", "icon": "cloud", "pos": Vector2(0, 3.1), "links": ["cloudlet"],
		"max": 2, "cost": 1629, "growth": 2.6, "stat": "companions", "per": 1.0,
		"desc": "More cloudlets join your entourage."},
	"cloudlet_size": {"branch": "companions", "name": "Puffy Cloudlets", "icon": "cloud", "pos": Vector2(-1.2, 2.7), "links": ["more_cloudlets"],
		"max": 2, "cost": 1899, "growth": 2.2, "stat": "comp_size", "per": 0.1,
		"desc": "Your cloudlets grow relative to you."},
	"wanderers": {"branch": "companions", "name": "Wanderers", "icon": "spark", "pos": Vector2(0, 4.6), "links": ["more_cloudlets"],
		"max": 1, "cost": 6314, "growth": 1.0, "kind": "keystone",
		"desc": "KEYSTONE: cloudlets roam to nearby green ground on their own, then drift back to you."},
	"long_leash": {"branch": "companions", "name": "Free Spirits", "icon": "eye", "pos": Vector2(1.3, 4.9), "links": ["wanderers"],
		"max": 3, "cost": 4858, "growth": 1.7, "stat": "comp_leash", "per": 9.0,
		"desc": "Cloudlets wander farther from you."},
	"flock": {"branch": "companions", "name": "Flock", "icon": "cloud", "pos": Vector2(-1.3, 4.9), "links": ["wanderers"],
		"max": 1, "cost": 14000, "growth": 1.75, "stat": "companions", "per": 2.0, "coverage": 0.5,
		"desc": "A whole flock of cloudlets."},
	# ----- Storm (down-left)
	"squall": {"branch": "storm", "name": "Squall", "icon": "snowflake", "pos": Vector2(-1.4, 0.8), "links": ["heart"],
		"max": 1, "cost": 30, "growth": 1.0, "kind": "skill",
		"desc": "SKILL (Left Mouse): a burst of snow rings out around you, 1.6x as far as your own snowfall reaches."},
	"squall_size": {"branch": "storm", "name": "Wide Squall", "icon": "snowflake", "pos": Vector2(-2.8, 0.7), "links": ["squall"],
		"max": 5, "cost": 121, "growth": 1.9, "stat": "squall_radius", "per": 0.2,
		"desc": "Your squall rings out farther: +0.25x your size per level."},
	"squall_cd": {"branch": "storm", "name": "Quick Squall", "icon": "snowflake", "pos": Vector2(-2.4, 1.8), "links": ["squall_size"],
		"max": 4, "cost": 162, "growth": 2.0, "stat": "squall_cd", "per": 0.88,
		"desc": "Your squall recharges faster."},
	"frost_wave": {"branch": "storm", "name": "Frost Wave", "icon": "front", "pos": Vector2(-3.7, 1.5), "links": ["squall_cd"],
		"max": 1, "cost": 1165, "growth": 1.0, "kind": "skill",
		"desc": "SKILL (Right Mouse): a wave of frost as wide as your trail rolls 40 m ahead of you. It grows as you do."},
	"wave_length": {"branch": "storm", "name": "Long Wave", "icon": "front", "pos": Vector2(-5.0, 1.0), "links": ["frost_wave"],
		"max": 4, "cost": 2429, "growth": 1.9, "stat": "wave_length", "per": 12,
		"desc": "Waves roll 15 m farther per level."},
	"wave_width": {"branch": "storm", "name": "Broad Wave", "icon": "front", "pos": Vector2(-4.6, 2.6), "links": ["wave_length"],
		"max": 4, "cost": 2429, "growth": 1.9, "stat": "wave_width", "per": 0.15,
		"desc": "Waves sweep a wider strip: +0.25x your trail width per level."},
	"wave_cd": {"branch": "storm", "name": "Quick Wave", "icon": "front", "pos": Vector2(-3.6, 2.9), "links": ["wave_width"],
		"max": 3, "cost": 2914, "growth": 1.9, "stat": "wave_cd", "per": 0.85,
		"desc": "Your waves recharge faster."},
	"splinter": {"branch": "storm", "name": "Splintering Frost", "icon": "spark", "pos": Vector2(-5.9, 2.4), "links": ["wave_length", "wave_width"],
		"max": 1, "cost": 11659, "growth": 1.0, "kind": "keystone",
		"desc": "KEYSTONE: every wave splinters into two more at its end."},
	# ----- Land (up-left)
	"ice_creep": {"branch": "land", "name": "Ice Creep", "icon": "crystal", "pos": Vector2(-1.4, -0.8), "links": ["squall"],
		"max": 4, "cost": 36, "growth": 2.0, "stat": "ice_creep", "per": 0.18,
		"desc": "Frozen water spreads faster across lakes and down rivers."},
	"region_bonus": {"branch": "land", "name": "Cartographer", "icon": "map", "pos": Vector2(-2.7, -0.5), "links": ["ice_creep"],
		"max": 3, "cost": 74, "growth": 2.4, "stat": "region_bonus", "per": 0.35,
		"desc": "Bigger Frost rewards when regions reach milestones."},
	"overview_map": {"branch": "land", "name": "Overview Map", "icon": "map", "pos": Vector2(-2.2, -1.6), "links": ["ice_creep"],
		"max": 1, "cost": 47, "growth": 1.0, "kind": "keystone",
		"desc": "Press M to see a map of the frozen and unfrozen land."},
	"snow_compass": {"branch": "land", "name": "Snow Compass", "icon": "eye", "pos": Vector2(-2.3, -3.0), "links": ["overview_map"],
		"max": 1, "cost": 1600, "growth": 1.0, "kind": "keystone", "coverage": 0.6,
		"desc": "Once you are surrounded by snow, an arrow points the way to the nearest green ground left."},
	"avalanche": {"branch": "land", "name": "Avalanche Rider", "icon": "avalanche", "pos": Vector2(-3.2, -2.3), "links": ["region_bonus", "overview_map"],
		"max": 1, "cost": 3402, "growth": 1.0, "kind": "keystone",
		"desc": "KEYSTONE: drifting over a snowy slope sets off an avalanche that pours downhill."},
	"av_width": {"branch": "land", "name": "Snow Slide", "icon": "avalanche", "pos": Vector2(-4.6, -2.0), "links": ["avalanche"],
		"max": 3, "cost": 3885, "growth": 1.8, "stat": "av_width", "per": 4,
		"desc": "Wider avalanches."},
	"av_cd": {"branch": "land", "name": "Unstable Slopes", "icon": "avalanche", "pos": Vector2(-3.9, -3.5), "links": ["av_width"],
		"max": 3, "cost": 3885, "growth": 1.8, "stat": "av_cd", "per": 0.85,
		"desc": "Avalanches release more often."},
	"mountain_air": {"branch": "land", "name": "Mountain Air", "icon": "spark", "pos": Vector2(-5.2, -3.4), "links": ["av_width", "av_cd"],
		"max": 1, "cost": 14573, "growth": 1.0, "kind": "keystone",
		"desc": "KEYSTONE: over high ground your snow falls in a 30% wider swath."},
	# ----- Polar (outer ring, late game)
	"vortex_form": {"branch": "polar", "name": "Vortex Form", "icon": "vortex", "pos": Vector2(-7.0, 0.0), "links": ["heart"],
		"max": 1, "cost": 8189, "growth": 1.0, "kind": "skill", "coverage": 0.25,
		"desc": "SKILL (R): swell into a polar vortex for a few seconds, freezing a vast area."},
	"vortex_size": {"branch": "polar", "name": "Polar Reach", "icon": "vortex", "pos": Vector2(-8.3, -0.8), "links": ["vortex_form"],
		"max": 3, "cost": 11466, "growth": 1.6, "stat": "vortex_mult", "per": 0.5,
		"desc": "Your vortex grows larger."},
	"vortex_time": {"branch": "polar", "name": "Long Night", "icon": "vortex", "pos": Vector2(-8.3, 0.8), "links": ["vortex_size"],
		"max": 3, "cost": 11466, "growth": 1.6, "stat": "vortex_time", "per": 3.0,
		"desc": "Your vortex lasts longer."},
	"vortex_cd": {"branch": "polar", "name": "Polar Rhythm", "icon": "vortex", "pos": Vector2(-9.5, 0.0), "links": ["vortex_size", "vortex_time"],
		"max": 3, "cost": 5896, "growth": 1.6, "stat": "vortex_cd", "per": 0.8,
		"desc": "Your vortex recharges faster."},
	"absolute_zero": {"branch": "polar", "name": "Absolute Zero", "icon": "spark", "pos": Vector2(-10.7, -0.9), "links": ["vortex_cd"],
		"max": 1, "cost": 12285, "growth": 1.0, "kind": "keystone",
		"desc": "KEYSTONE: when your vortex ends it releases a huge ring of frost."},
	"thaw_sense": {"branch": "polar", "name": "Thaw Sense", "icon": "eye", "pos": Vector2(-10.7, 0.9), "links": ["vortex_form"],
		"max": 1, "cost": 2948, "growth": 1.0, "kind": "keystone", "coverage": 0.75,
		"desc": "Press Q to sense every remaining patch of green across the world."},
}

# Nodes removed in later versions: [cost, growth]. Old saves get the Frost
# they spent on them back.
const RETIRED_NODES := {
	"dense_core": [60, 2.0], "flurry": [15, 1.8], "heavy_snow": [322, 2.4], "blanket": [11662, 2.4],
	"snow_wake": [2429, 1.0], "long_wake": [3885, 1.8],
}


static func retired_refund(id: String, level: int) -> float:
	if not RETIRED_NODES.has(id):
		return 0.0
	var c: Array = RETIRED_NODES[id]
	var total := 0.0
	for k in level:
		total += ceil(float(c[0]) * pow(float(c[1]), k))
	return total


# ------------------------------------------------------------ world & economy
const WORLD_SIZE := 512           # metres along one side, 1 coverage cell per metre
const WORLD_HALF := 256.0
const CHUNK := 16                 # coverage chunk size in cells

const REGION_NAMES: Array[String] = ["Central Meadows", "Woodland", "Lake District", "Highlands"]
const REGION_SHORT: Array[String] = ["THE MEADOWS", "THE WOODLAND", "THE LAKE DISTRICT", "THE HIGHLANDS"]
const REGION_REWARD: Array[float] = [1.0, 1.25, 1.5, 1.6]
const WATER_REWARD := 1.8
# One pass freezes any ground completely (no half-done ground to hunt for).
const REGION_EXPOSURE: Array[float] = [1.0, 1.0, 1.0, 1.0]
const WATER_EXPOSURE := 1.0
const FIELD_REWARD := 1.5          # frozen crops are worth extra
const REGION_MILESTONES: Array[int] = [25, 50, 75, 100]
const REGION_MILESTONE_FRACTION := {25: 0.015, 50: 0.025, 75: 0.04, 100: 0.06}
const WORLD_MILESTONES: Array[float] = [0.05, 0.1, 0.25, 0.5, 0.75, 0.9]

# Completion tolerance: the world counts as finished once no chunk holds more than
# MAX_PATCH_CELLS unfrozen cells and fewer than MAX_REMAINING_CELLS remain overall.
const MAX_REMAINING_CELLS := 60
const MAX_PATCH_CELLS := 10

# Simulation budgets.
const MAX_CLOUDS := 48
const MAX_FRONTS := 24
const MAX_PULSES := 16
const MAX_AVALANCHE_HEADS := 40
const CLOUD_ALTITUDE := 9.0


static func node(id: String) -> Dictionary:
	return NODES[id]


static func node_cost(id: String, level: int) -> float:
	var n: Dictionary = NODES[id]
	return ceil(float(n["cost"]) * pow(float(n["growth"]), level))


static func stat_nodes(stat_id: String) -> Array[String]:
	var out: Array[String] = []
	for id in NODES:
		if NODES[id].get("stat", "") == stat_id:
			out.append(id)
	return out


static func format_stat(stat_id: String, value: float) -> String:
	var s: Dictionary = STATS[stat_id]
	var fmt: String = s["fmt"]
	if s.get("pct", false):
		return fmt % int(round(value * 100.0))
	if fmt.contains("%d"):
		return fmt % int(round(value))
	return fmt % value
