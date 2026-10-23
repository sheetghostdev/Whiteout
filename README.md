# WHITEOUT

A relaxing but increasingly spectacular incremental game about burying a
living green world under snow and ice. You *are* the snow cloud: snow falls
wherever you drift, and you grow into a storm as you go. Built with
**Godot 4.7** and GDScript.

Every visual and sound in the game is generated in code: terrain, trees,
rocks, grass, flowers, clouds, water, sky, particles, UI panels, icons and
all audio. The repository contains no images, models, fonts or audio files
(`res://scripts/tests/test_no_assets.gd` enforces this).

## Running

1. Install Godot **4.7** (standard build, not .NET).
2. Open `project.godot` in the editor and press Play, or run
   `godot --path .` from the repository root.

The first launch generates the world (a few seconds), then shows the title
screen over a flyover of your world.

## Controls

| Input | Action |
|---|---|
| WASD | Drift (relative to the camera) |
| Mouse | Look around the cloud |
| Mouse wheel | Zoom |
| Shift | Ride a gust (faster, thinner snow) |
| Left mouse | Squall (once unlocked) |
| Right mouse | Frost Wave (once unlocked) |
| R | Vortex Form (once unlocked) |
| Tab | Upgrade web |
| M | Overview map (after buying it) |
| Q | Thaw Sense (late game) |
| G | Field Guide |
| Esc | Pause / settings |

All bindings can be changed in Settings → Controls.

## The game in brief

- **Goal:** freeze 100% of the 512 × 512 m world. Green means unfinished,
  white means done; the landscape itself is the progress bar.
- **You are the cloud.** Snow falls under you continuously. Linger to freeze
  ground solid, drift on to fresh green. Each square metre pays **Frost**
  only once.
- **One currency, one upgrade web.** Frost buys nodes in a web of 47
  upgrades across seven branches: Size, Snowfall, Wind, Cloudlets, Storm
  skills, The Land and Polar. Finishing a node reveals only its neighbours,
  so a handful of choices are open at a time.
- **Keystones change how you play:** Deep Freeze, Tailwind, Snow Wake,
  Wanderers (cloudlets roam to green ground), Splintering Frost, Avalanche
  Rider (drift over snowy slopes to set them sliding), Mountain Air,
  Thunderhead, Absolute Zero, Thaw Sense.
- **Three active skills** keep your hands busy to the end: Squall (a ring of
  snow), Frost Wave (a rolling strip of frost where you look) and Vortex
  Form (swell to several times your size for a few seconds).
- **Four regions:** Central Meadows, Woodland, Lake District, Highlands.
  Lakes and rivers freeze with spreading ice; rivers freeze fastest.
  Regional milestones pay Frost; world milestones bring new, bigger nodes
  within reach.
- **Ending:** when the world is frozen, a camera flight shows the ice age,
  and a statistics screen offers Keep Exploring or New Winter+ with
  optional modifiers.

## Design notes: the upgrade web

The upgrade system follows what players praise, and complain about, in
recent popular incrementals:

- **Nodebuster** (very positive on Steam) is loved for its upgrade web and
  for respecting your time. Reviews complain that most choices aren't real
  decisions, that extra currencies become useless, and that the last stretch
  plays itself. WHITEOUT therefore keeps a web with **one currency**, and
  makes every branch end in a keystone that changes play, not just numbers.
  Active skills keep input meaningful late.
- **Tower Wizard** and **Magic Archery** are praised because there is
  always something affordable, with only short waits. The bot test fails if
  a run ever goes long without an affordable purchase.
- **Empty the Lake** is criticised for unsatisfying "+x%" upgrades, an
  artificial bottleneck and a chore-like finish. Here every node is a step
  of at least 10%, nodes have at most five levels, nothing walls progress,
  and late nodes (Thunderhead, Sky Giant, Thaw Sense) make the final mop-up
  fast instead of tedious.
- **Choice overload** comes from the number of options faced at once, not
  the total. Revealing neighbours only when a node is finished keeps about
  six open nodes on screen on average (roughly one per branch), while the
  whole web still holds 47 nodes and over 110 levels.

## Project layout

```
project.godot            engine config, autoloads, global shader params
scenes/                  main.tscn (game), tests.tscn, visual_tour.tscn, load_all.tscn
shaders/                 terrain, water, foliage, tree, cloud, decal, effect, sky, backdrop, map
scripts/core/            balance tables, progression/economy, save, settings, input, game flow
scripts/world/           terrain data, snow coverage, regions, mesh factory, renderers, foliage
scripts/weather/         weather manager, the player cloud, skills' effects, FX helpers
scripts/player/          third-person cloud controller and camera
scripts/ui/              HUD, upgrade web, menus, map, guide, completion, procedural icons
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
- **WeatherManager** runs a fixed 30 Hz simulation. The player cloud moves
  every tick for crisp steering; other effects step every third tick,
  staggered by id, so heavy storms spread their cost across frames. Visuals
  interpolate and never feed back into the simulation (particle density
  cannot change snowfall or income).
- **PlayerCloud** takes plain data input (`move_input`, `dashing`), so the
  balancing bot flies it exactly like a player does.
- **GameBalance** holds every number. Each stat node drives exactly one
  stat, so the web's "current → next" preview and gameplay cannot drift
  apart (a test checks this).

## Tests and balancing

Headless test suite (coverage rules, upgrade-web integrity and economy
audit, the cloud and every skill and keystone, save/load round trips,
performance under extreme late-game load, asset audit, the real main scene,
and a full bot playthrough):

```
godot --headless --path . res://scenes/tests.tscn
godot --headless --path . res://scenes/tests.tscn -- balance        # all 5 bot strategies
godot --headless --path . res://scenes/tests.tscn -- only=cloud     # one suite
```

The balancing bot (`scripts/tests/balance_bot.gd`) plays the real
simulation: it flies the cloud to the nearest green ground, drifts slowly
over it to paint, gusts between patches, fires skills when they would hit
green ground, and shops by strategy (cheapest first, spread across
branches, random, saving up, skills last). With the current tuning every
strategy completes the world in about 18–23 bot-minutes. The first
purchase lands within seconds, and there is never more than about a minute
without an affordable upgrade. About 70–75% of the web gets bought, with
6 open choices on average (10 at most). The bot always knows where the
nearest green is and never pauses, so a person should take noticeably
longer (roughly 40–60 minutes); that still needs real playtesting to
confirm.

`scenes/visual_tour.tscn` boots the game, performs scripted actions and
saves screenshots to `user://tour/` (scenarios: `basic`, `fx`, `late`,
`ui`, `complete`).

## Performance notes

Simulation cost was measured headlessly: a maxed late-game cloud in Vortex
Form with every skill firing, a full set of wandering cloudlets and a long
wake averages well under 1 ms per frame, and the worst single frame stays
under 5 ms. Very large clouds update interleaved rows of the coverage grid
to keep that cost flat. Rendering was verified with software rasterizers
(Mesa llvmpipe); GPU frame times on real desktop hardware have not yet been
profiled. Quality presets, particle density, draw distance and shadow
settings are available for scaling.
