# WHITEOUT

A relaxing but increasingly spectacular incremental game about burying a
living green island under snow and ice. You *are* the snow cloud: snow falls
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

- **Goal:** freeze 100% of the island (about 174,000 m² of land in a wide
  sea). Green means unfinished, white means done; the landscape itself is
  the progress bar.
- **You are the cloud.** Everything along your path freezes in a single
  pass - there is no half-frozen ground to hunt for. Resting lays nothing
  and earns nothing. Each square metre pays **Frost** only once. Snow
  drifts into narrow gaps between your passes by itself (up to about 3 m,
  wider with Drifting Snow and Deep Freeze). What looks white is frozen and
  what looks green is not: the snow edge is a narrow soft band on the real
  boundary. A soft ring on the ground shows exactly how wide
  your snow falls (it can be hidden in Settings), and near the end the last
  green ground glows softly. The late Snow Compass upgrade adds an arrow to
  the nearest green ground when none is close.
- **One flying speed.** There is no sprint key: Breeze, Gale and Jet Stream
  raise your speed, and Tailwind makes you 30% faster while your whole cloud
  is over frozen ground (skimming the edge of your trail does not count).
- **One currency, one upgrade web.** Frost buys nodes in a web of 44
  upgrades across seven branches: Size, Snowfall, Wind, Cloudlets, Storm
  skills, The Land and Polar. Finishing a node reveals only its neighbours,
  so a handful of choices are open at a time. No two kinds of upgrade do
  the same thing: size nodes make your cloud (and so its snowfall) bigger,
  Drifting Snow seals the gaps you miss, Spreading Frost lets frozen ground
  creep into the green beside it, and so on. Later nodes of the same kind
  ("grow larger still") are simply more of it.
- **Keystones change how you play:** Deep Freeze, Tailwind,
  Wanderers (cloudlets roam to green ground), Splintering Frost, Avalanche
  Rider (drift over a snowy mountainside to set it sliding; small hills
  never slide), Mountain Air,
  Thunderhead, Absolute Zero, Thaw Sense.
- **Three active skills** keep your hands busy to the end, and all of them
  scale with your size so they never fall behind: Squall (a ring of snow
  1.4x as far as your own snowfall reaches), Frost Wave (a wave as wide as
  your trail that rolls 35 m or more where you look) and Vortex Form (swell
  to several times your size for a few seconds).
- **Cloudlets** fly beside you, just outside your own snowfall, so their
  snow widens your swath instead of landing behind you or where you are
  about to go.
- **The island:** Central Meadows, Woodland, Lake District and Highlands,
  ringed by beaches and rocky shores, with distant islands on the horizon.
  A mountain stream runs from a tarn down to the lake, and the lake drains
  to the sea through a river. Lakes and rivers freeze with spreading ice
  while you are out flying.
- **People:** a village with a church and a well, a lakeside hamlet with a
  pier, and a farm with a barn, fences, hay and fields of wheat, corn,
  cabbages and sprouts that grow and ripen as you play. Snow frosts them at
  once, then each plant slowly wilts, browns and slumps under it over about
  two and a half minutes (frozen fields pay extra Frost). Villagers stroll the
  roads; once snow settles around them they slow down, hug themselves,
  stamp their feet and shiver. Snow settles on roofs only where it has
  actually fallen, chimneys smoke, and your cloud eases up over rooftops as
  if they were gentle hills.
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
  whole web still holds 44 nodes and about 100 levels.

## Project layout

```
project.godot            engine config, autoloads, global shader params
scenes/                  main.tscn (game), tests.tscn, visual_tour.tscn, load_all.tscn
shaders/                 terrain, water, foliage, tree, cloud, decal, effect, sky, backdrop, map
scripts/core/            balance tables, progression/economy, save, settings, input, game flow
scripts/world/           island terrain, snow coverage, regions, renderers, foliage, settlements, villagers
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
  snow-mask function — so what looks frozen *is* frozen. Sea cells are
  "void": never counted, never paid, always drawn as open water. Shaders
  sample it with a cubic B-spline plus a gentle meandering warp (at most a
  couple of metres, so the drawn edge stays true to the real one), and the
  1 m grid never shows as squares or ruled lines.
- **TerrainData** shapes the island (coast distance, beaches, mountains that
  run down to the sea, a tarn-fed stream, the lake and its outlet) and
  levels pads for the **SettlementPlan**. The lake fills its basin from the
  middle and stops at its rim; the outlet river leaves at lake level and
  eases down to the sea between gently raised banks. Water is one mesh
  following the computed water level of every vertex, so it can never float
  over land. Trees and bushes are always drawn at full detail (no LOD
  swaps), so nothing pops in or out, even in the closing flyover.
- **WeatherManager** runs a fixed 30 Hz simulation. The player cloud moves
  every tick for crisp steering; other effects step every third tick,
  staggered by id, so heavy storms spread their cost across frames. Visuals
  interpolate and never feed back into the simulation (particle density
  cannot change snowfall or income).
- **PlayerCloud** takes plain data input (`move_input`), so the
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
over it in passes, fires skills when they would hit green ground, and shops by strategy (cheapest first, spread across
branches, random, saving up, skills last). With the current tuning every
strategy completes the island in about 10½–12½ bot-minutes. The first
purchase lands within seconds, and there is never much more than a minute
without an affordable upgrade. About two thirds of the web gets bought, with
about 5 open choices on average (9 at most), and the cloud ends at roughly a
16 m radius. The bot always knows where the nearest green is and never
pauses, so a person should take noticeably longer (roughly 25–35
minutes); that still needs real playtesting to confirm.

`scenes/visual_tour.tscn` boots the game, performs scripted actions and
saves screenshots to `user://tour/` (scenarios: `basic`, `fx`, `late`,
`ui`, `complete`, `island`, `snowcheck`, `round3`, `round4`, `edge`, `edgecloudlets`).

## Performance notes

Simulation cost was measured headlessly: a maxed late-game cloud in Vortex
Form with every skill firing, a full set of wandering cloudlets and
spreading frost averages well under 1 ms per frame, and the worst single frame stays
under 5 ms. Very large clouds update interleaved rows of the coverage grid
to keep that cost flat. Rendering was verified with software rasterizers
(Mesa llvmpipe); GPU frame times on real desktop hardware have not yet been
profiled. Quality presets, particle density, draw distance and shadow
settings are available for scaling.
