# Whiplash Shift — driving foundation and CPU drivers (Godot 4.7.2)

The original physics spike now opens through a native garage with seven selectable
chassis, persistent callsign entry, and a randomized CPU roster. Reusable course,
progress tracking, and vehicle-specific handling feed the proving-ground race.
Race countdowns, results, and the four-course arcade mode are the next phase.

The consolidated project also loads the saved Deadbolt truck/coupe model through
the same garage, player and CPU factory as Blackjack. Deadbolt retains its authored
glass, metal, tires and lights; the three paint channels remain customizable.
Its authored wheel meshes follow the original four physics wheels. The other five
chassis keep their greybox fallback until production models exist.

## Running it

Verified with Godot **4.7.2** (the original port used 4.6 and Jolt). Open `godot/`
as a project and press play, or:

```
godot --path godot
```

## Garage

The main scene is `scenes/garage.tscn`. Arrow keys or the on-screen controls cycle
through all seven technical blueprints; `Enter` or **IGNITE** starts the race. The
callsign is saved to `user://profile.cfg`. All seven chassis have named buttons,
including **DEADBOLT**. **VIEW 3D // PAINT & PARTS** opens the selected model preview.
Returning from a race keeps that chassis selected. Selection passes through the `GameSession`
autoload, which also assigns two unique CPU vehicles from the remaining roster.

Each chassis has bounded multipliers for top speed, drive, grip, mass, and braking.
`BLACKJACK X-17` is the 1.0 baseline, so the original handling and regression figures
remain unchanged. CPU speed planning reads the same modifiers as the physical car.

## Controls

Identical to the web prototype on purpose, so muscle memory transfers and a
side-by-side comparison isn't confounded by different bindings.

| | |
|---|---|
| `W` / `S` | throttle / brake (brake becomes reverse only at a standstill) |
| `A` `D` | steer |
| **`SPACE`** | **swap ends** |
| `SHIFT` | handbrake |
| `R` | respawn on the grid |
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
Recovery does not award distance or laps.

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
