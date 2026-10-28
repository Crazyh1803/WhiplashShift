# Whiplash Shift — driving foundation and CPU drivers (Godot 4.7.2)

The original physics spike now opens through a native garage with seven selectable
chassis, persistent callsign entry, and a randomized CPU roster. Reusable course,
progress tracking, and vehicle-specific handling feed the proving-ground race.
The single-course race now has a three-second countdown, three full laps, live
position and time, and results with same-roster retry or return to the garage.
The race ends when the player finishes; rivals still on course are marked
UNFINISHED. The four-course arcade mode remains future work. Combat uses a solo arcade item loop.

Gold pickup rows grant one random item. Press **E once** to activate it; holding
the key is unnecessary. The single slot stays occupied until the active timer ends.

| Item | Pickup chance | Active behavior |
|---|---:|---|
| Shield | 20% | Blocks weapon hits and oil for 5 seconds |
| Machine guns | 24% | Automatic fire every 0.15 seconds for 6 seconds |
| Rockets | 18% | Fires an explosive rocket every second for 5 seconds |
| Grenades | 12% | Lobs an explosive grenade every 1.2 seconds for 6 seconds |
| Smoke screen | 13% | Drops smoke every 0.5 seconds for 5 seconds |
| Oil slick | 12% | Drops oil every 0.65 seconds for 5 seconds |
| Homing missile | 1% | One missile; needs a visible target ahead, otherwise stays held |

Attacks fire from the active end; smoke and oil deploy behind it. Swapping redirects
subsequent shots and drops. Smoke clouds last 5 seconds and obscure sight, CPU
attack decisions and missile guidance. Oil patches last 7 seconds and reduce grip
to 35% while crossed, lingering 1.2 seconds after leaving. Shields clear oil effects.
Missiles keep their original target, turn gradually and collide with scenery.
Grenades arc and explode on impact or after a 1.5-second fuse. Scenery blocks blast
damage. Hits remove a bounded amount of speed; there is no health or elimination.

CPUs use the same odds, durations and physical effects. Countdown/results block
combat; retry clears everything; recovery clears owned projectiles, hazards and
active items and restores grip. Finished racers lose combat objects. No copilot or
second player is required. Pickups respawn after six seconds. The HUD shows the
held item or active countdown, smoke and low-grip status.


Driving rendering interpolates between the unchanged 120 Hz physics ticks.
The chase camera follows that rendered pose each frame; player/CPU recovery and
retry reset interpolation, and the camera snaps to recovered positions. Garage
turntables and their orbit camera remain frame-driven without interpolation.

The project loads the blueprint-traced Deadbolt hard-surface truck/coupe model through
the same garage, player and CPU factory as Blackjack. Deadbolt retains its authored
glass, metal, tires and lights; the three paint channels remain customizable.
Its authored wheel meshes follow the original four physics wheels, with steering
pivots derived from the visible tire hubs. Nightshift also uses its dedicated Chevy/Camaro production model and three
semantic paint channels through the same authored-hub adapter. Ramjet adds the
Dodge Ram / Conquest TSi blueprint model through that contract. Boilerfang adds
the steampunk plow truck / speedster and visible central drive machinery while
retaining four physical wheels. Helix adds the biomechanical `r-type.jpg` model;
Knifeedge adds the `hot-wheels.jpg` sand rail/supercar. All seven roster entries
now use production artwork in the garage, player and CPU paths. Display tire
radii and visual tracks follow the reference models independently of physical
tuning and hardpoints.

Terrain changes now have approach boards outside the guard rails and a lower HUD
callout with remaining distance and end advice. The HUD looks roughly four seconds
ahead (90–200 metres); rumble strips lead into the next meaningful surface rather
than becoming a separate destination. Ice and oil warn about low grip and advise
holding the current end. You decide when to brake or swap. Cues disappear while
off-course, travelling the wrong way, during countdown and on results. Board lead
distance is shortened where terrain boundaries are close together.

The same HUD region now describes upcoming bends, tight turns and hairpins with
left/right direction and distance. It shows a rounded advisory entry speed based
on the current vehicle/end and the lowest grip through the bend. Braking prompts
account for approach speed, braking capability and approach grip; inside a bend
the cue changes to **EASE SPEED** when appropriate. Ice/oil turns show low-grip
advice instead of a numeric speed. Terrain advice stays visible alongside it.
These are conservative centreline estimates, not guaranteed speeds or automatic
controls. Turn shape is smoothed over metres and cached when the course loads.

## First track visual sample

The circuit now uses seamless procedural asphalt, gravel, mud, rock, ice and water
materials, with metre-spaced worn asphalt markings and animated water ripples.
A shared generated 256-pixel noise map and mipmaps provide detail at driving speed.
Road materials are reusable around the loop; the detailed scenery sample covers
the first 720 metres, including the opening straight and first mud corner.

That sample adds dirt shoulders, batched rail posts, scrub rocks, a service yard,
storage tanks, a corner industrial landmark and distant landforms. Warm daylight,
a cooler sky and light distance haze establish an industrial scrubland palette.
Scenery is visual-only, checked against every course branch and the proving ground.
All twelve road collision runs match the original renderer byte for byte.
This is a first material/scenery pass; the rest of the circuit is not yet dressed.

Capture overview and driver views with:

```sh
TEST_CMD='timeout 90 godot --fixed-fps 120 --path godot res://tests/track_visual_tests.tscn -- --capture' ak-test
```

Captures go to `.ai/captures/track-sample/`. Headless geometry and material checks
are included in the normal `ak-test` suite.

## Running it

Verified with Godot **4.7.2** (the original port used 4.6 and Jolt). Open `godot/`
as a project and press play, or:

```
godot --path godot
```

## Garage

The main scene is `scenes/main_menu.tscn`, offering season racing, configurable
single races, custom-season creation/sharing, settings and creator links. Modes
lead to `scenes/garage.tscn` for vehicle selection. Arrow keys or on-screen controls cycle
through all seven technical blueprints; `Enter` or **IGNITE** starts the race. The
callsign is saved to `user://profile.cfg`. All seven chassis have named buttons,
including **DEADBOLT**. **VIEW 3D // PAINT & PARTS** opens the selected model preview.
Returning from a race keeps that chassis selected. Selection passes through the `GameSession`
autoload, which also assigns two unique CPU vehicles from the remaining roster.

Each chassis has bounded multipliers for top speed, drive, grip, mass, and braking.
`BLACKJACK X-17` is the 1.0 baseline, so the original handling and regression figures
remain unchanged. CPU speed planning reads the same modifiers as the physical car.

## Controls

Core driving controls carry over from the web prototype; **E** now uses the held
arcade item. The Games launcher starts play, with an editor option in its context menu.

| | |
|---|---|
| `W` / `S` | throttle / brake (brake becomes reverse only at a standstill) |
| `A` `D` | steer |
| **`SPACE`** | **swap ends** |
| `SHIFT` | handbrake |
| `E` | activate held item; timed items then run automatically |
| `R` | recover the player to the last checkpoint during a race |
| `Enter` | race again from the results screen, keeping the same roster |
| `C` | camera: 180° swing vs. instant snap |
| `F1` | debug overlay — per-wheel load, slip, spin, and the force budget |
| `F2` | pause/resume both CPU cars |
| `Esc` | return to garage |

## What's here

The guarded greybox circuit (tarmac → rumble → mud sweeper → water → boulders → ice → hairpin →
gravel return → rumble → tarmac) and, off to the west at x ≈ −620, a flat **proving
ground**: strips of each surface plus a launch ramp. Use the circuit to judge the game
and the proving ground to isolate a handling problem when the circuit makes it ambiguous.

The vehicle audio is generated at runtime: engine load and pitch follow acceleration,
lift-off/braking brings in a deceleration whine, and swaps and rail impacts have distinct
synthesised one-shots. No external audio assets are required.

Two CPU cars start ahead of the player in separate lanes. They use identical tuning
and physical inputs, plan speed from upcoming curvature and surface grip, perform
swaps through physical turns, and brake for cars ahead. The top-right HUD shows each
CPU's speed, active end, and lap. `R` resets the player and CPU drivers together.
The current drivers keep End B over the short ice patch to avoid two consecutive
turnarounds, while still slowing for its low grip.

Off-course, stuck, or overturned CPUs recover to their last valid checkpoint.
Recovery does not award distance or laps. Standings move back with a checkpoint
recovery, so driving the recovered stretch again cannot improve position for free.
Every lap requires the ordered course checkpoints. All racers start behind the
white start/finish stripe; the first crossing begins lap one. Finished CPU cars
leave the collision field so they cannot block the line. Swapping and recovery
are locked during countdown and results; suspension settles during the countdown.

## Tuning

`resources/default_tuning.tres` is a Resource. Open it in the inspector, press play, and
move values **while it runs**. That's the point of the spike — findings are much more
useful as numbers than as adjectives. If something feels wrong, open `F1` first: "it feels
floaty" is hard to act on, "wheel loads drop 40% over crests" isn't.

## Production vehicle assets

`../tools/vehicle_pipeline/run_pipeline.py` batches the seven blueprints through the
local ComfyUI img2img and Hunyuan3D workflows. It installs a body, aerodynamic End A
wheel, rugged End B wheel, and manifest under `assets/vehicles/models/<vehicle-id>/`.
Until a body GLB exists, the runtime keeps the current primitive fallback. Imported art
is visual-only: `scripts/vehicle.gd` retains the tuned rigid-body force model, applies
the selected paint through a flat material override, and uses catalog-owned collision
boxes and four independent wheel hardpoints.

## Tests

```
godot --headless --fixed-fps 120 --path godot res://tests/test_main.tscn
```

45 checks. Exits non-zero on failure. `--fixed-fps` decouples from wall clock, so
~4 minutes of simulated driving runs in seconds. No addon — just a scene and
`await get_tree().physics_frame`, so the tests read as straight-line code.

They cover the thesis (a swap changes no velocity component and no basis), the axis-change
sign traps, suspension behaviour, and **faithfulness to the web prototype**: terminal speed
on each surface for each end, measured against the 2D model at matched duration. Every case
lands within 8%.

CPU integration checks:

```sh
godot --headless --fixed-fps 120 --path godot res://tests/cpu_main.tscn
```

17 checks, including 420 seconds of simulated two-car driving. Both drivers must
complete at least two laps with bounded recoveries. The suite also checks swap
momentum, real off-course recovery, braking for stopped peers, and progress
accounting around the finish line and checkpoint resets.

`ak-test` runs all suites, including the race rules and scene integration checks.
The race suite covers input locks, ordered laps, recovery accounting, finish
ordering, result buttons and retry. A test-only CPU also drives the player through
an entire three-lap race, then drives the first minute of the retry, using the real
vehicle physics and race scene. These checks run headlessly without the Nvidia GPU;
rendered layout, audio and human handling assessment still require a playtest.

For a short rendered race-loop smoke test, run
`godot --path godot --fixed-fps 120 res://tests/race_visual_qa.tscn` from the
repository root. Add `-- --small` to use a 1280×720 window instead of 1600×900.
It captures countdown, GO, driving, swapping, results, retry and garage return
under `.ai/captures/race-loop/`, checks UI bounds and clock/banner overlap, and
checks engine streaming/pitch response and the swap sound starting. Results use
staged finish progress; the full physical three-lap race is the headless suite.
Human assessment of handling feel and audio quality is still required.

For real-time motion diagnostics, run
`godot --path godot --max-fps 144 res://tests/driving_frame_probe.tscn -- --label=smooth144`.
The test holds throttle after countdown and writes frame-time and raw/rendered
movement samples under `.ai/captures/smooth-driving/`. Add `--no-interpolation`
for a process-local control run. Do not use `--fixed-fps` for this measurement;
it disables real-time synchronization. `camera_tests` checks camera pose sampling,
swap framing, recovery/retry reset and garage interpolation exceptions headlessly.

Add `-- --terrain` to the rendered smoke-test command to capture staged mud, ice
and tarmac approaches; combine with `--small` for the smaller window. Captures go
to `.ai/captures/terrain/`. The headless `course_cues_tests` suite checks seam
wrapping, rumble collapse, advice, sign orientation and HUD suppression.

Use `-- --corners` (optionally `--small`) for staged right/left entry and in-hairpin
captures under `.ai/captures/corners/`. The `corner_tests` suite covers geometry,
sampling density, braking/grip response, seam handling and combined HUD layout.

## Structure

| file | role |
|---|---|
| `scenes/garage.tscn`, `scripts/garage.gd` | login, blueprint carousel, stats and ignition flow |
| `scripts/vehicle_catalog.gd`, `scripts/game_session.gd` | chassis data and cross-scene selection state |
| `scripts/vehicle.gd` | the thesis: rigid body, four wheels, the swap |
| `scripts/wheel.gd` | suspension raycast and what it found |
| `scripts/surfaces.gd` | surface table + per-end modifiers |
| `scripts/tuning.gd` | every tunable number |
| `scripts/course_definition.gd` | reusable course identity, laps, length, checkpoints and start transform |
| `scripts/track_progress.gd` | centreline projection, measured travel, laps and recovery anchors |
| `scripts/race_director.gd` | countdown, race clock, standings, finish order and results state |
| `scripts/cpu_driver.gd` | pursuit steering, speed planning, swaps, traffic braking and recovery |
| `scripts/track_data.gd` | the first circuit, ported from the web build's authoring |
| `scripts/track_builder.gd` | extrudes it into a ribbon with surface metadata |
| `scripts/vehicle_audio.gd` | procedural engine, deceleration, swap, and rail-impact audio |
| `scripts/camera_rig.gd` | the 180° swing |
| `scripts/hud.gd`, `debug_overlay.gd` | readouts |
| `scripts/proving_ground.gd` | scene assembly and input |

## Notes on the port

Axis mapping from the 2D original: web body `+x` (End A / forward) → body `-Z`; web `+y`
(right) → `+X`; web `v.ang`/`v.av` → `basis`/`angular_velocity.y`. The friction circle,
`tanh` lateral saturation, direction-aware drive taper, trailing-pair handbrake rule and
standstill-gated reverse all carry over unchanged — none were 2D-specific.

**Suspension is the one genuinely new system.** The 2D model gave every wheel a fixed
normal load with all four always planted. Per-wheel spring/damper is what produces body
roll, pitch under braking, load transfer off the driving end, and wheels leaving the
ground. End A rides 0.58 m, End B 0.87 m, so the chassis sits at a permanent ~5° rake —
the asymmetry is now visible rather than just a number.

Four bugs the headless tests caught, recorded because they'd be easy to reintroduce:

1. **Anti-roll bar sign.** Signed the wrong way it *subtracts* roll stiffness; End B's went
   negative and the car rolled over on a straight road.
2. **`linear_damp_mode` defaults to COMBINE**, so the project-wide default of 0.1 is added
   to the body's — about 4.6 kN of invisible drag at 120 km/h.
3. **Ground reaction must act along the contact normal**, not the body's up axis. Along
   `basis.y` at a 5° rake it injects ~1.3 kN of phantom horizontal force, which shoved End
   A along and held End B back.
4. **Collision triangle winding**, which a downward ray passes straight through if reversed.

The debug overlay shows predicted acceleration (from the force budget) against measured.
If those two ever disagree, something is applying a force the model doesn't know about —
that's how (2) and (3) were found.
