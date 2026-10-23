class_name GameBalance
extends RefCounted
## Single source of truth for every tunable number in WHITEOUT.
##
## STATS describe how a value scales with an upgrade level.
## UPGRADES describe what the shop sells; each repeatable upgrade drives
## exactly one stat, so the shop text and the gameplay value can never drift
## apart (both call stat_value()).

# ---------------------------------------------------------------- abilities
const ABILITY_ORDER: Array[String] = [
	"snow_cloud", "frost_front", "arctic_wind", "blizzard", "avalanche", "polar_vortex",
]

const ABILITIES := {
	"snow_cloud": {
		"name": "Snow Cloud",
		"desc": "Summon a small cloud that gently snows on the ground beneath it.",
		"icon": "cloud", "cooldown": 3.0, "range_mult": 1.0, "unlock": "",
		"alt": "Right mouse: beckon your active clouds toward the target.",
	},
	"frost_front": {
		"name": "Frost Front",
		"desc": "Launch a low wave of freezing air that rolls across the land, following the terrain.",
		"icon": "front", "cooldown": 6.0, "range_mult": 1.0, "unlock": "unlock_frost_front",
		"alt": "",
	},
	"arctic_wind": {
		"name": "Arctic Wind",
		"desc": "Release a cold gust that pushes clouds and storms, speeds up frost fronts and dusts the ground with frost.",
		"icon": "wind", "cooldown": 5.0, "range_mult": 1.0, "unlock": "unlock_arctic_wind",
		"alt": "Right mouse (Cyclonic Flow): a gust that circles the target point.",
	},
	"blizzard": {
		"name": "Blizzard",
		"desc": "Summon a great storm system that blankets whole fields while drifting with the wind.",
		"icon": "blizzard", "cooldown": 22.0, "range_mult": 2.0, "unlock": "unlock_blizzard",
		"alt": "Right mouse: steer your blizzards toward the target.",
	},
	"avalanche": {
		"name": "Avalanche",
		"desc": "Release a snowy slope. The avalanche pours downhill, widening and splitting as it goes.",
		"icon": "avalanche", "cooldown": 12.0, "range_mult": 2.5, "unlock": "unlock_avalanche",
		"alt": "",
	},
	"polar_vortex": {
		"name": "Polar Vortex",
		"desc": "Call down a colossal spiral of polar air that roams the world, pulling other storms into its orbit.",
		"icon": "vortex", "cooldown": 50.0, "range_mult": 3.0, "unlock": "unlock_polar_vortex",
		"alt": "Right mouse: steer the vortex toward the target.",
	},
}

# ------------------------------------------------------------------- stats
# mode "add": base + per * level      mode "mul": base * per ^ level
const STATS := {
	# Snow Cloud
	"cloud_radius": {"base": 2.0, "per": 0.6, "mode": "add", "fmt": "%.1f m"},
	"cloud_rate": {"base": 0.34, "per": 1.18, "mode": "mul", "fmt": "%.2f /s"},
	"cloud_duration": {"base": 5.0, "per": 1.2, "mode": "add", "fmt": "%.1f s"},
	"cloud_count": {"base": 1.0, "per": 1.0, "mode": "add", "fmt": "%d"},
	"cloud_rebirth": {"base": 0.0, "per": 0.15, "mode": "add", "fmt": "%d%%", "pct": true},
	"cloud_thunder": {"base": 0.0, "per": 0.12, "mode": "add", "fmt": "%d%%", "pct": true},
	"cloud_division": {"base": 0.0, "per": 1.0, "mode": "add", "fmt": "%d generations"},
	# Frost Front
	"front_width": {"base": 4.0, "per": 1.2, "mode": "add", "fmt": "%.1f m"},
	"front_distance": {"base": 35.0, "per": 12.0, "mode": "add", "fmt": "%d m"},
	"front_speed": {"base": 9.0, "per": 2.0, "mode": "add", "fmt": "%d m/s"},
	"front_strength": {"base": 0.4, "per": 0.05, "mode": "add", "fmt": "%d%% per pass", "pct": true},
	"front_count": {"base": 1.0, "per": 1.0, "mode": "add", "fmt": "%d"},
	"front_branch": {"base": 0.0, "per": 0.07, "mode": "add", "fmt": "%d%%", "pct": true},
	"front_rebound": {"base": 0.0, "per": 1.0, "mode": "add", "fmt": "%d bounces"},
	"front_snowfield": {"base": 0.15, "per": 0.15, "mode": "add", "fmt": "+%d%% speed", "pct": true},
	# Arctic Wind
	"wind_strength": {"base": 7.0, "per": 1.5, "mode": "add", "fmt": "%.1f m/s"},
	"wind_width": {"base": 12.0, "per": 3.0, "mode": "add", "fmt": "%d m"},
	"wind_duration": {"base": 6.0, "per": 1.5, "mode": "add", "fmt": "%.1f s"},
	"wind_range": {"base": 45.0, "per": 15.0, "mode": "add", "fmt": "%d m"},
	"wind_streams": {"base": 1.0, "per": 1.0, "mode": "add", "fmt": "%d"},
	"wind_transport": {"base": 0.12, "per": 0.06, "mode": "add", "fmt": "%d%% per pass", "pct": true},
	"wind_snowfield": {"base": 0.0, "per": 0.35, "mode": "add", "fmt": "+%d%%", "pct": true},
	# Blizzard
	"bz_radius": {"base": 10.0, "per": 1.6, "mode": "add", "fmt": "%.1f m"},
	"bz_life": {"base": 18.0, "per": 4.0, "mode": "add", "fmt": "%d s"},
	"bz_rate": {"base": 0.15, "per": 1.11, "mode": "mul", "fmt": "%.2f /s"},
	"bz_speed": {"base": 2.0, "per": 0.6, "mode": "add", "fmt": "%.1f m/s"},
	"bz_count": {"base": 1.0, "per": 1.0, "mode": "add", "fmt": "%d"},
	"bz_wind": {"base": 0.4, "per": 0.2, "mode": "add", "fmt": "%d%%", "pct": true},
	"bz_cells": {"base": 0.0, "per": 1.0, "mode": "add", "fmt": "%d per 10 s"},
	# Avalanche
	"av_width": {"base": 6.0, "per": 1.2, "mode": "add", "fmt": "%.1f m"},
	"av_distance": {"base": 120.0, "per": 35.0, "mode": "add", "fmt": "%d m"},
	"av_speed": {"base": 12.0, "per": 2.0, "mode": "add", "fmt": "%d m/s"},
	"av_momentum": {"base": 0.55, "per": 0.05, "mode": "add", "fmt": "%d%%", "pct": true},
	"av_split": {"base": 0.08, "per": 0.05, "mode": "add", "fmt": "%d%% /s", "pct": true},
	"av_strength": {"base": 0.45, "per": 0.05, "mode": "add", "fmt": "%d%% per pass", "pct": true},
	"av_branches": {"base": 3.0, "per": 2.0, "mode": "add", "fmt": "%d"},
	"av_bounty": {"base": 0.0, "per": 0.15, "mode": "add", "fmt": "+%d%%", "pct": true},
	# Polar Vortex
	"pv_radius": {"base": 26.0, "per": 4.0, "mode": "add", "fmt": "%d m"},
	"pv_life": {"base": 45.0, "per": 12.0, "mode": "add", "fmt": "%d s"},
	"pv_speed": {"base": 3.0, "per": 0.6, "mode": "add", "fmt": "%.1f m/s"},
	"pv_rate": {"base": 0.1, "per": 1.1, "mode": "mul", "fmt": "%.2f /s"},
	"pv_orbit": {"base": 6.0, "per": 3.0, "mode": "add", "fmt": "%d storms"},
	"pv_attract": {"base": 1.6, "per": 0.25, "mode": "add", "fmt": "%.2fx radius"},
	"pv_pulse": {"base": 2.0, "per": 1.5, "mode": "add", "fmt": "%.1f /min"},
	"pv_absorb": {"base": 1.0, "per": 0.25, "mode": "add", "fmt": "%d%%", "pct": true},
	"pv_nav": {"base": 0.3, "per": 0.15, "mode": "add", "fmt": "%d%%", "pct": true},
	# General
	"move_speed": {"base": 6.0, "per": 0.6, "mode": "add", "fmt": "%.1f m/s"},
	"sprint_mult": {"base": 1.6, "per": 0.15, "mode": "add", "fmt": "%.2fx"},
	"cast_range": {"base": 15.0, "per": 9.0, "mode": "add", "fmt": "%d m"},
	"cooldown_mult": {"base": 1.0, "per": 0.92, "mode": "mul", "fmt": "%d%%", "pct": true},
	"frost_mult": {"base": 1.0, "per": 0.12, "mode": "add", "fmt": "%.2fx"},
	"duration_mult": {"base": 1.0, "per": 0.08, "mode": "add", "fmt": "%.2fx"},
	"efficiency_mult": {"base": 1.0, "per": 0.08, "mode": "add", "fmt": "%.2fx"},
	"region_bonus": {"base": 1.0, "per": 0.5, "mode": "add", "fmt": "%.1fx"},
	"storm_capacity": {"base": 0.0, "per": 2.0, "mode": "add", "fmt": "+%d clouds"},
	"storm_nav": {"base": 1.0, "per": 0.3, "mode": "add", "fmt": "%.1fx"},
	"guide_strength": {"base": 1.0, "per": 0.35, "mode": "add", "fmt": "%.2fx"},
	"flight_speed": {"base": 14.0, "per": 4.0, "mode": "add", "fmt": "%d m/s"},
}

# ---------------------------------------------------------------- upgrades
const CATEGORIES: Array[String] = [
	"snow_cloud", "frost_front", "arctic_wind", "blizzard", "avalanche", "polar_vortex", "general", "evolution",
]
const CATEGORY_NAMES := {
	"snow_cloud": "Snow Cloud", "frost_front": "Frost Front", "arctic_wind": "Arctic Wind",
	"blizzard": "Blizzard", "avalanche": "Avalanche", "polar_vortex": "Polar Vortex",
	"general": "General", "evolution": "Weather Evolutions",
}
const CATEGORY_ICONS := {
	"snow_cloud": "cloud", "frost_front": "front", "arctic_wind": "wind", "blizzard": "blizzard",
	"avalanche": "avalanche", "polar_vortex": "vortex", "general": "gear", "evolution": "spark",
}

# Each entry:
#   cat, name, desc, stat (optional), max, cost, growth, cores (one-off core price),
#   req: {"ability": id, "upgrades": {id: level}, "coverage": fraction}
#   unlocks: ability id (for ability unlock entries)
const UPGRADES := {
	# ----- Snow Cloud
	"cloud_radius": {"cat": "snow_cloud", "name": "Cloud Radius", "stat": "cloud_radius",
		"desc": "Wider clouds blanket more ground per cast.", "max": 14, "cost": 12, "growth": 1.8},
	"cloud_rate": {"cat": "snow_cloud", "name": "Snowfall Density", "stat": "cloud_rate",
		"desc": "Heavier snowfall freezes ground faster.", "max": 12, "cost": 18, "growth": 1.8},
	"cloud_duration": {"cat": "snow_cloud", "name": "Cloud Duration", "stat": "cloud_duration",
		"desc": "Clouds linger longer before dissipating.", "max": 12, "cost": 15, "growth": 1.7},
	"cloud_count": {"cat": "snow_cloud", "name": "Maximum Clouds", "stat": "cloud_count",
		"desc": "Keep more snow clouds in the sky at once.", "max": 9, "cost": 81, "growth": 2.4,
		"req": {"upgrades": {"cloud_radius": 1}}},
	"cloud_drift": {"cat": "evolution", "name": "Cloud Drift", "evo": true, "icon": "cloud",
		"desc": "Clouds wander slowly instead of hanging in place, painting a wider patch of snow.",
		"max": 1, "cost": 405, "growth": 1.0, "req": {"upgrades": {"cloud_radius": 2}}},
	"storm_chaser": {"cat": "evolution", "name": "Storm Chaser", "evo": true, "icon": "cloud",
		"desc": "Clouds actively seek out nearby uncovered ground.",
		"max": 1, "cost": 2700, "growth": 1.0, "req": {"upgrades": {"cloud_drift": 1}}},
	"cloud_division": {"cat": "snow_cloud", "name": "Cloud Division", "stat": "cloud_division", "evo": true,
		"desc": "When a cloud expires it splits into two smaller clouds.", "max": 2, "cost": 8100, "growth": 3.5,
		"req": {"upgrades": {"cloud_count": 3}}},
	"cloud_rebirth": {"cat": "snow_cloud", "name": "Snowstorm Rebirth", "stat": "cloud_rebirth",
		"desc": "A cloud that froze plenty of fresh ground may reform when it fades.", "max": 3, "cost": 20250, "growth": 2.4,
		"req": {"upgrades": {"cloud_division": 1}}},
	"cloud_thunder": {"cat": "snow_cloud", "name": "Thunder Snow", "stat": "cloud_thunder",
		"desc": "Clouds freezing fresh ground occasionally release a ring-shaped frost pulse.", "max": 3, "cost": 13500, "growth": 2.4,
		"req": {"upgrades": {"cloud_rate": 4}}},
	# ----- Frost Front
	"unlock_frost_front": {"cat": "frost_front", "name": "Unlock Frost Front", "unlocks": "frost_front",
		"desc": "A rolling wave of frost that travels across the land.", "max": 1, "cost": 300, "growth": 1.0, "cores": 1},
	"front_width": {"cat": "frost_front", "name": "Front Width", "stat": "front_width",
		"desc": "A broader wave covers a wider strip.", "max": 12, "cost": 486, "growth": 1.85,
		"req": {"ability": "frost_front"}},
	"front_distance": {"cat": "frost_front", "name": "Travel Distance", "stat": "front_distance",
		"desc": "The wave rolls farther before fading.", "max": 12, "cost": 405, "growth": 1.8,
		"req": {"ability": "frost_front"}},
	"front_speed": {"cat": "frost_front", "name": "Forward Speed", "stat": "front_speed",
		"desc": "The wave races ahead faster.", "max": 8, "cost": 364, "growth": 1.65,
		"req": {"ability": "frost_front"}},
	"front_strength": {"cat": "frost_front", "name": "Frost Strength", "stat": "front_strength",
		"desc": "Each pass of the wave deposits more snow.", "max": 10, "cost": 608, "growth": 1.9,
		"req": {"ability": "frost_front"}},
	"front_count": {"cat": "frost_front", "name": "Simultaneous Fronts", "stat": "front_count",
		"desc": "Launch a fan of several fronts with each cast.", "max": 4, "cost": 3375, "growth": 3.2,
		"req": {"ability": "frost_front", "upgrades": {"front_width": 2}}},
	"front_branch": {"cat": "frost_front", "name": "Branching Frost", "stat": "front_branch",
		"desc": "Fronts sometimes sprout a smaller side branch as they travel.", "max": 5, "cost": 4050, "growth": 2.0,
		"req": {"ability": "frost_front", "upgrades": {"front_distance": 3}}},
	"front_rebound": {"cat": "frost_front", "name": "Rebound", "stat": "front_rebound",
		"desc": "Fronts reflect off steep slopes and the edge of the world.", "max": 2, "cost": 6750, "growth": 3.0,
		"req": {"ability": "frost_front", "upgrades": {"front_distance": 4}}},
	"front_snowfield": {"cat": "frost_front", "name": "Snowfield Glide", "stat": "front_snowfield",
		"desc": "Fronts accelerate while gliding over existing snowfields.", "max": 4, "cost": 1620, "growth": 2.0,
		"req": {"ability": "frost_front"}},
	"splintering_frost": {"cat": "evolution", "name": "Splintering Frost", "evo": true, "icon": "front",
		"desc": "When a front finishes, smaller fronts splinter off sideways and keep going.",
		"max": 1, "cost": 10800, "growth": 1.0, "req": {"ability": "frost_front", "upgrades": {"front_distance": 3}}},
	"frozen_highway": {"cat": "evolution", "name": "Frozen Highway", "evo": true, "icon": "front",
		"desc": "Fronts travel much faster and farther across already-frozen ground and ice.",
		"max": 1, "cost": 18900, "growth": 1.0, "req": {"ability": "frost_front", "upgrades": {"front_speed": 2}}},
	# ----- Arctic Wind
	"unlock_arctic_wind": {"cat": "arctic_wind", "name": "Unlock Arctic Wind", "unlocks": "arctic_wind",
		"desc": "Cold gusts that push your weather around and dust the ground with frost.", "max": 1, "cost": 2025, "growth": 1.0, "cores": 1},
	"wind_strength": {"cat": "arctic_wind", "name": "Wind Strength", "stat": "wind_strength",
		"desc": "Gusts push clouds and storms faster.", "max": 10, "cost": 810, "growth": 1.7,
		"req": {"ability": "arctic_wind"}},
	"wind_width": {"cat": "arctic_wind", "name": "Gust Width", "stat": "wind_width",
		"desc": "Wider gusts catch more weather.", "max": 10, "cost": 729, "growth": 1.65,
		"req": {"ability": "arctic_wind"}},
	"wind_duration": {"cat": "arctic_wind", "name": "Gust Duration", "stat": "wind_duration",
		"desc": "Gusts keep blowing for longer.", "max": 10, "cost": 648, "growth": 1.65,
		"req": {"ability": "arctic_wind"}},
	"wind_range": {"cat": "arctic_wind", "name": "Gust Range", "stat": "wind_range",
		"desc": "Gusts reach farther across the land.", "max": 10, "cost": 891, "growth": 1.7,
		"req": {"ability": "arctic_wind"}},
	"wind_streams": {"cat": "arctic_wind", "name": "Multiple Streams", "stat": "wind_streams",
		"desc": "Each cast releases several parallel wind streams.", "max": 3, "cost": 6750, "growth": 3.4,
		"req": {"ability": "arctic_wind", "upgrades": {"wind_width": 2}}},
	"wind_transport": {"cat": "arctic_wind", "name": "Snow Transport", "stat": "wind_transport",
		"desc": "Gusts carry more snow and frost along their path.", "max": 8, "cost": 1215, "growth": 1.85,
		"req": {"ability": "arctic_wind"}},
	"wind_snowfield": {"cat": "arctic_wind", "name": "Snowfield Updraft", "stat": "wind_snowfield",
		"desc": "Gusts scoop up snow over snowfields and drop it on green ground ahead.", "max": 4, "cost": 2700, "growth": 2.1,
		"req": {"ability": "arctic_wind", "upgrades": {"wind_transport": 2}}},
	"wind_steering": {"cat": "arctic_wind", "name": "Steering Control", "evo": true,
		"desc": "Active gusts bend to follow the direction you are looking.", "max": 1, "cost": 3375, "growth": 1.0,
		"req": {"ability": "arctic_wind"}},
	"jet_stream": {"cat": "evolution", "name": "Jet Stream", "evo": true, "icon": "wind",
		"desc": "Gusts last far longer, and clouds riding them barely age - carrying snow across enormous distances.",
		"max": 1, "cost": 12150, "growth": 1.0, "cores": 1, "req": {"ability": "arctic_wind"}},
	"cyclonic_flow": {"cat": "evolution", "name": "Cyclonic Flow", "evo": true, "icon": "vortex",
		"desc": "Right-click with Arctic Wind to create a gust that curves around a central point.",
		"max": 1, "cost": 13500, "growth": 1.0, "req": {"ability": "arctic_wind", "upgrades": {"wind_range": 2}}},
	# ----- Blizzard
	"unlock_blizzard": {"cat": "blizzard", "name": "Unlock Blizzard", "unlocks": "blizzard",
		"desc": "A great drifting storm system that can blanket entire fields.", "max": 1, "cost": 16200, "growth": 1.0, "cores": 2},
	"bz_radius": {"cat": "blizzard", "name": "Storm Radius", "stat": "bz_radius",
		"desc": "Blizzards cover a much larger area.", "max": 12, "cost": 8100, "growth": 1.85,
		"req": {"ability": "blizzard"}},
	"bz_life": {"cat": "blizzard", "name": "Storm Lifetime", "stat": "bz_life",
		"desc": "Blizzards rage for longer.", "max": 10, "cost": 6750, "growth": 1.75,
		"req": {"ability": "blizzard"}},
	"bz_rate": {"cat": "blizzard", "name": "Snow Intensity", "stat": "bz_rate",
		"desc": "Heavier snowfall within the storm.", "max": 10, "cost": 9450, "growth": 1.85,
		"req": {"ability": "blizzard"}},
	"bz_speed": {"cat": "blizzard", "name": "Storm Speed", "stat": "bz_speed",
		"desc": "Blizzards travel faster across the land.", "max": 6, "cost": 6075, "growth": 1.7,
		"req": {"ability": "blizzard"}},
	"bz_count": {"cat": "blizzard", "name": "Maximum Blizzards", "stat": "bz_count",
		"desc": "Keep more blizzards active at once.", "max": 3, "cost": 29700, "growth": 3.0,
		"req": {"ability": "blizzard", "upgrades": {"bz_radius": 2}}},
	"bz_wind": {"cat": "blizzard", "name": "Wind Responsiveness", "stat": "bz_wind",
		"desc": "Blizzards respond more strongly to wind.", "max": 5, "cost": 6075, "growth": 1.7,
		"req": {"ability": "blizzard"}},
	"bz_cells": {"cat": "blizzard", "name": "Storm Cells", "stat": "bz_cells",
		"desc": "Blizzards periodically spawn small snow clouds around their edges.", "max": 4, "cost": 20250, "growth": 2.1,
		"req": {"ability": "blizzard", "upgrades": {"bz_life": 2}}},
	"superstorm": {"cat": "evolution", "name": "Superstorm", "evo": true, "icon": "blizzard",
		"desc": "Overlapping blizzards fuse into a single, larger and more efficient superstorm.",
		"max": 1, "cost": 36450, "growth": 1.0, "cores": 1, "req": {"ability": "blizzard"}},
	"roaming_winter": {"cat": "evolution", "name": "Roaming Winter", "evo": true, "icon": "blizzard",
		"desc": "Blizzards automatically prioritise nearby unfrozen territory.",
		"max": 1, "cost": 28350, "growth": 1.0, "cores": 1, "req": {"ability": "blizzard"}},
	# ----- Avalanche
	"unlock_avalanche": {"cat": "avalanche", "name": "Unlock Avalanche", "unlocks": "avalanche",
		"desc": "Release snow-covered slopes into thundering downhill avalanches.", "max": 1, "cost": 27000, "growth": 1.0, "cores": 2},
	"av_width": {"cat": "avalanche", "name": "Avalanche Width", "stat": "av_width",
		"desc": "Wider snow masses cover more ground.", "max": 10, "cost": 20250, "growth": 1.75,
		"req": {"ability": "avalanche"}},
	"av_distance": {"cat": "avalanche", "name": "Travel Distance", "stat": "av_distance",
		"desc": "Avalanches run out farther.", "max": 10, "cost": 17550, "growth": 1.7,
		"req": {"ability": "avalanche"}},
	"av_speed": {"cat": "avalanche", "name": "Avalanche Speed", "stat": "av_speed",
		"desc": "Higher top speed down the slopes.", "max": 8, "cost": 17550, "growth": 1.55,
		"req": {"ability": "avalanche"}},
	"av_momentum": {"cat": "avalanche", "name": "Momentum", "stat": "av_momentum",
		"desc": "Avalanches keep their speed longer, crossing shallow valleys and flats.", "max": 8, "cost": 20250, "growth": 1.6,
		"req": {"ability": "avalanche"}},
	"av_split": {"cat": "avalanche", "name": "Splitting", "stat": "av_split",
		"desc": "Avalanches split into more branches.", "max": 8, "cost": 24300, "growth": 1.75,
		"req": {"ability": "avalanche"}},
	"av_strength": {"cat": "avalanche", "name": "Snow Load", "stat": "av_strength",
		"desc": "Each pass deposits more snow.", "max": 8, "cost": 20250, "growth": 1.75,
		"req": {"ability": "avalanche"}},
	"av_branches": {"cat": "avalanche", "name": "Branch Capacity", "stat": "av_branches",
		"desc": "More simultaneous avalanche branches.", "max": 6, "cost": 28350, "growth": 2.0,
		"req": {"ability": "avalanche", "upgrades": {"av_split": 1}}},
	"av_bounty": {"cat": "avalanche", "name": "Cascade Bounty", "stat": "av_bounty",
		"desc": "Bonus Frost from ground frozen by avalanches.", "max": 5, "cost": 28350, "growth": 1.8,
		"req": {"ability": "avalanche"}},
	"snow_tsunami": {"cat": "evolution", "name": "Snow Tsunami", "evo": true, "icon": "avalanche",
		"desc": "Avalanches swell into a massive wave as they travel downhill.",
		"max": 1, "cost": 64800, "growth": 1.0, "cores": 1, "req": {"ability": "avalanche"}},
	"chain_avalanche": {"cat": "evolution", "name": "Chain Avalanche", "evo": true, "icon": "avalanche",
		"desc": "Avalanches passing snowy slopes can set off secondary avalanches.",
		"max": 1, "cost": 81000, "growth": 1.0, "cores": 1, "req": {"ability": "avalanche"}},
	# ----- Polar Vortex
	"unlock_polar_vortex": {"cat": "polar_vortex", "name": "Unlock Polar Vortex", "unlocks": "polar_vortex",
		"desc": "The ultimate weather power: a roaming spiral of polar air.", "max": 1, "cost": 42000, "growth": 1.0, "cores": 3},
	"pv_radius": {"cat": "polar_vortex", "name": "Vortex Radius", "stat": "pv_radius",
		"desc": "A wider vortex freezes a vast area.", "max": 10, "cost": 67500, "growth": 1.6,
		"req": {"ability": "polar_vortex"}},
	"pv_life": {"cat": "polar_vortex", "name": "Vortex Lifetime", "stat": "pv_life",
		"desc": "The vortex persists for longer.", "max": 10, "cost": 60750, "growth": 1.55,
		"req": {"ability": "polar_vortex"}},
	"pv_speed": {"cat": "polar_vortex", "name": "Vortex Speed", "stat": "pv_speed",
		"desc": "The vortex roams faster.", "max": 6, "cost": 48600, "growth": 1.4,
		"req": {"ability": "polar_vortex"}},
	"pv_rate": {"cat": "polar_vortex", "name": "Freezing Intensity", "stat": "pv_rate",
		"desc": "The vortex freezes ground faster.", "max": 10, "cost": 72900, "growth": 1.6,
		"req": {"ability": "polar_vortex"}},
	"pv_orbit": {"cat": "polar_vortex", "name": "Orbiting Storms", "stat": "pv_orbit",
		"desc": "More storms can orbit the vortex at once.", "max": 6, "cost": 56700, "growth": 1.5,
		"req": {"ability": "polar_vortex"}},
	"pv_attract": {"cat": "polar_vortex", "name": "Attraction Range", "stat": "pv_attract",
		"desc": "The vortex pulls in storms from farther away.", "max": 6, "cost": 48600, "growth": 1.45,
		"req": {"ability": "polar_vortex"}},
	"pv_pulse": {"cat": "polar_vortex", "name": "Frost Pulses", "stat": "pv_pulse",
		"desc": "The vortex releases frost pulses more often.", "max": 6, "cost": 60750, "growth": 1.5,
		"req": {"ability": "polar_vortex"}},
	"pv_absorb": {"cat": "polar_vortex", "name": "Storm Absorption", "stat": "pv_absorb",
		"desc": "Absorbed storms feed the vortex more strength.", "max": 6, "cost": 48600, "growth": 1.45,
		"req": {"ability": "polar_vortex"}},
	"pv_nav": {"cat": "polar_vortex", "name": "Vortex Navigation", "stat": "pv_nav",
		"desc": "The vortex steers itself toward uncovered territory more decisively.", "max": 5, "cost": 48600, "growth": 1.45,
		"req": {"ability": "polar_vortex"}},
	"absolute_zero": {"cat": "evolution", "name": "Absolute Zero", "evo": true, "icon": "vortex",
		"desc": "The vortex periodically unleashes a huge outward frost pulse.",
		"max": 1, "cost": 121500, "growth": 1.0, "cores": 1, "req": {"ability": "polar_vortex"}},
	"endless_winter": {"cat": "evolution", "name": "Endless Winter", "evo": true, "icon": "vortex",
		"desc": "The vortex persists far longer while hunting down unfrozen regions.",
		"max": 1, "cost": 162000, "growth": 1.0, "cores": 1, "req": {"ability": "polar_vortex"}},
	# ----- General
	"move_speed": {"cat": "general", "name": "Movement Speed", "stat": "move_speed",
		"desc": "Walk faster across the land.", "max": 8, "cost": 40, "growth": 1.9},
	"sprint_mult": {"cat": "general", "name": "Sprint Speed", "stat": "sprint_mult",
		"desc": "Sprint even faster.", "max": 6, "cost": 81, "growth": 1.9},
	"cast_range": {"cat": "general", "name": "Casting Range", "stat": "cast_range",
		"desc": "Place weather farther away. Large storms reach several times farther.", "max": 15, "cost": 40, "growth": 1.75},
	"cooldown_mult": {"cat": "general", "name": "Cooldown Reduction", "stat": "cooldown_mult",
		"desc": "Every ability recharges faster.", "max": 10, "cost": 162, "growth": 2.1,
		"req": {"upgrades": {"cloud_rate": 1}}},
	"frost_mult": {"cat": "general", "name": "Frost Income", "stat": "frost_mult",
		"desc": "Earn more Frost for newly frozen ground.", "max": 10, "cost": 540, "growth": 2.3,
		"req": {"upgrades": {"cloud_radius": 2}}},
	"duration_mult": {"cat": "general", "name": "Weather Duration", "stat": "duration_mult",
		"desc": "All weather lasts longer.", "max": 8, "cost": 1215, "growth": 1.9,
		"req": {"ability": "frost_front"}},
	"efficiency_mult": {"cat": "general", "name": "Weather Efficiency", "stat": "efficiency_mult",
		"desc": "All weather freezes ground faster.", "max": 8, "cost": 1620, "growth": 1.95,
		"req": {"ability": "frost_front"}},
	"region_bonus": {"cat": "general", "name": "Region Bonus", "stat": "region_bonus",
		"desc": "Bigger Frost rewards for regional milestones.", "max": 4, "cost": 2025, "growth": 2.3,
		"req": {"ability": "frost_front"}},
	"storm_capacity": {"cat": "general", "name": "Storm Capacity", "stat": "storm_capacity",
		"desc": "Raises the maximum number of active snow clouds.", "max": 4, "cost": 16200, "growth": 2.5,
		"req": {"upgrades": {"cloud_count": 5}}},
	"storm_nav": {"cat": "general", "name": "Storm Navigation", "stat": "storm_nav",
		"desc": "Self-steering weather homes in on green ground faster.", "max": 4, "cost": 10125, "growth": 2.1,
		"req": {"upgrades": {"storm_chaser": 1}}},
	"guide_strength": {"cat": "general", "name": "Storm Guidance", "stat": "guide_strength",
		"desc": "Right-click guidance pulls your storms harder and from farther away.", "max": 4, "cost": 1215, "growth": 2.1,
		"req": {"upgrades": {"cloud_count": 2}}},
	"overview_map": {"cat": "general", "name": "Overview Map", "icon": "map",
		"desc": "Press M to view a map of the world's frozen and unfrozen land.", "max": 1, "cost": 400, "growth": 1.0,
		"req": {"upgrades": {"cloud_radius": 2}}},
	"flight": {"cat": "general", "name": "Skyward Drift", "icon": "flight",
		"desc": "Press F to rise into the air and drift above the land. Space climbs, Ctrl descends.",
		"max": 1, "cost": 10125, "growth": 1.0, "cores": 1, "req": {"ability": "arctic_wind"}},
	"flight_speed": {"cat": "general", "name": "Drift Speed", "stat": "flight_speed",
		"desc": "Glide faster while airborne.", "max": 6, "cost": 12150, "growth": 1.7,
		"req": {"upgrades": {"flight": 1}}},
	"thaw_sense": {"cat": "general", "name": "Thaw Sense", "icon": "eye",
		"desc": "Press Q to pulse a sense across the world that highlights the remaining unfrozen patches.",
		"max": 1, "cost": 20250, "growth": 1.0, "req": {"coverage": 0.70}},
}

# ------------------------------------------------------------ world & economy
const WORLD_SIZE := 512           # metres along one side, 1 coverage cell per metre
const WORLD_HALF := 256.0
const CHUNK := 16                 # coverage chunk size in cells

const REGION_NAMES: Array[String] = ["Central Meadows", "Woodland", "Lake District", "Highlands"]
const REGION_SHORT: Array[String] = ["THE MEADOWS", "THE WOODLAND", "THE LAKE DISTRICT", "THE HIGHLANDS"]
const REGION_REWARD: Array[float] = [1.0, 1.25, 1.5, 1.6]
const WATER_REWARD := 1.8
const REGION_EXPOSURE: Array[float] = [1.0, 0.8, 1.0, 1.0]  # woodland canopy catches snow
const WATER_EXPOSURE := 0.55
const REGION_MILESTONES: Array[int] = [25, 50, 75, 100]
const REGION_MILESTONE_FRACTION := {25: 0.02, 50: 0.03, 75: 0.05, 100: 0.08}
const WORLD_CORE_MILESTONES: Array[float] = [
	0.01, 0.03, 0.06, 0.10, 0.15, 0.21, 0.28, 0.36, 0.45, 0.55, 0.65, 0.75, 0.85,
]

# Completion tolerance: the world counts as finished once no chunk holds more than
# MAX_PATCH_CELLS unfrozen cells and fewer than MAX_REMAINING_CELLS remain overall.
const MAX_REMAINING_CELLS := 60
const MAX_PATCH_CELLS := 10

# Global weather budgets (simulation objects, not visuals).
const MAX_CLOUDS := 48
const MAX_FRONTS := 24
const MAX_PULSES := 16
const MAX_BLIZZARDS := 8
const MAX_AVALANCHE_HEADS := 40
const MAX_VORTICES := 2
const MAX_WINDS := 12


static func stat_value(stat_id: String, level: int) -> float:
	var s: Dictionary = STATS[stat_id]
	if s["mode"] == "mul":
		return float(s["base"]) * pow(float(s["per"]), level)
	return float(s["base"]) + float(s["per"]) * level


static func format_stat(stat_id: String, value: float) -> String:
	var s: Dictionary = STATS[stat_id]
	var fmt: String = s["fmt"]
	if s.get("pct", false):
		return fmt % int(round(value * 100.0))
	if fmt.contains("%d"):
		return fmt % int(round(value))
	return fmt % value


static func upgrade_cost(upgrade_id: String, level: int) -> float:
	var u: Dictionary = UPGRADES[upgrade_id]
	return ceil(float(u["cost"]) * pow(float(u["growth"]), level))


static func upgrade_core_cost(upgrade_id: String) -> int:
	return int(UPGRADES[upgrade_id].get("cores", 0))


static func ability_unlock_upgrade(ability_id: String) -> String:
	return ABILITIES[ability_id]["unlock"]
