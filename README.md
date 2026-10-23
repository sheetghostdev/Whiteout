# WHITEOUT

A relaxing but increasingly spectacular incremental game about burying a
living green world under snow and ice. Built with **Godot 4.3** and GDScript.

Every visual and sound in the game is generated in code: terrain, trees,
rocks, grass, flowers, clouds, water, sky, particles, UI panels, icons and
all audio. The repository contains no images, models, fonts or audio files
(`res://scripts/tests/test_no_assets.gd` enforces this).

## Running

1. Install Godot **4.3** (standard build, not .NET).
2. Open `project.godot` in the editor and press Play, or run
   `godot --path .` from the repository root.

The first launch generates the world (a few seconds), then shows the title
screen over a flyover of your world.

## Controls

| Input | Action |
|---|---|
| WASD / Mouse | Move / look |
| Shift | Sprint |
| Space | Jump (climb while flying) |
| Ctrl | Descend while flying |
| Left mouse (hold) | Cast the selected weather ability |
| Right mouse | Alternate action (guide clouds/blizzards/vortex, Cyclonic Flow) |
| 1–6 / Mouse wheel | Select ability |
| Tab | Upgrade shop |
| M | Overview map (after buying it) |
| F | Skyward Drift flight (after buying it) |
| Q | Thaw Sense (late game) |
| G | Weather Guide |
| Esc | Pause / settings |

All bindings can be changed in Settings → Controls.

## The game in brief

- **Goal:** freeze 100% of the 512 × 512 m world. Green means unfinished,
  white means done; the landscape itself is the progress bar.
- **Frost** is earned only for *newly* frozen ground (each square metre pays
  out once), and is spent on upgrades.
- **Winter Cores** come from world-coverage milestones and completed regions,
  and unlock new weather powers and major evolutions.
- **Six abilities:** Snow Cloud, Frost Front, Arctic Wind, Blizzard,
  Avalanche, Polar Vortex, each with repeatable upgrades and evolutions
  that change behaviour (drifting/seeking/dividing clouds, splintering
  fronts, jet streams, superstorm fusion, snow tsunamis, chain avalanches,
  absolute-zero pulses...).
- **Ten weather combinations** (e.g. cloud + wind = moving snowfall,
  avalanche + frozen lake = ice shockwave) are discovered through play and
  recorded in the Weather Guide.
- **Four regions:** Central Meadows, Woodland, Lake District, Highlands.
  Lakes and rivers freeze with spreading ice; rivers freeze fastest.
- **Ending:** when the world is frozen, storms calm, a camera flight shows the
  ice age, and a statistics screen offers Keep Exploring or New Winter+ with
  optional modifiers.

## Project layout

```
project.godot            engine config, autoloads, global shader params
scenes/                  main.tscn (game), tests.tscn, visual_tour.tscn, load_all.tscn
shaders/                 terrain, water, foliage, tree, cloud, decal, effect, sky, backdrop, map
scripts/core/            balance tables, progression/economy, save, settings, input, game flow
scripts/world/           terrain data, snow coverage, regions, mesh factory, renderers, foliage
scripts/weather/         weather manager, effects, abilities, interaction rules, FX helpers
scripts/player/          first-person controller, ability input, targeting previews
scripts/ui/              HUD, shop, menus, map, guide, completion, procedural icons
scripts/audio/           synthesized sound effects and generative music
scripts/cinematic/       ending camera flight
scripts/tests/           test suites, balancing bot, visual tour
```

Key systems:

- **SnowCoverage** (`scripts/world/snow_coverage.gd`) is the single source of
  truth: a 1 m grid of 0..1 coverage with per-region sums, per-chunk
  incomplete counts (fully frozen chunks are skipped), one-time rewards, and
  a dirty-chunk GPU texture that every shader samples through one shared
  snow-mask function — so what looks frozen *is* frozen.
- **WeatherManager** runs a fixed 30 Hz simulation; each effect steps every
  third tick, staggered by id, so heavy storms spread their cost across
  frames. Visuals interpolate and never feed back into the simulation
  (particle density cannot change snowfall or income).
- **GameBalance** holds every number. Each repeatable upgrade drives exactly
  one stat, so shop text and gameplay values cannot drift apart (a test
  checks this).

## Tests and balancing

Headless test suite (coverage rules, economy audit, every ability and
combination, save/load round trips, performance under extreme storm load,
asset audit, and a full bot playthrough):

```
godot --headless --path . res://scenes/tests.tscn
godot --headless --path . res://scenes/tests.tscn -- balance            # all 10 bot strategies
godot --headless --path . res://scenes/tests.tscn -- only=interactions  # one suite
```

The balancing bot (`scripts/tests/balance_bot.gd`) plays the real simulation
at accelerated time: it walks at player speed, picks targets, casts twice a
second, saves up for unlocks and shops by strategy (cloud focus, front focus,
wind combos, multipliers first, inefficient scattering, deliberate storm
combining, expensive-first, saver, region-by-region). With the current
tuning every strategy completes the world in roughly 22–27 bot-minutes,
never waits more than about two minutes between affordable purchases, and
unlocks abilities in order (Frost Front ≈3.5 min, Arctic Wind ≈6.5–7.5,
Blizzard ≈12–14, Avalanche ≈14–17, Polar Vortex ≈16–21). Because the bot
aims and reacts far faster than a person, a first human playthrough should
take considerably longer; that still needs real playtesting to confirm.

A power benchmark (`scripts/tests/power_bench.gd`) checks that every new
ability feels stronger than what the player already has: using the bot's
actual upgrade levels at the moment each power unlocks, it measures each
ability's sustained freeze rate on fresh ground next to the Snow Cloud's.
Each must be at least 1.3× the cloud (currently 1.8–3×).

`scenes/visual_tour.tscn` boots the game, performs scripted actions and
saves screenshots to `user://tour/` (scenarios: `basic`, `fx`, `late`,
`ui`, `complete`).

## Performance notes

Simulation cost was measured headlessly: under an extreme load (40 clouds,
4 maxed blizzards, 2 vortices, fronts and winds) the weather simulation
averages about 1–1.3 ms per frame with the worst single frame near 10 ms.
Rendering was verified with software rasterizers (Mesa llvmpipe for both
Forward+ and Compatibility); GPU frame times on real desktop hardware have
not yet been profiled. Quality presets, particle density, draw distance and
shadow settings are available for scaling.
