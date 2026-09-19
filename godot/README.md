# Whiplash Shift — M0 physics spike (Godot 4.6)

One question: **does the swap still feel right in 3D?** No networking, no weapons, no
bots, no round structure. Handling and nothing else.

## Running it

Godot **4.6** or newer (Jolt is the default 3D physics engine from 4.6). Open `godot/`
as a project and press play, or:

```
godot --path godot
```

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
| `Esc` | quit |

## What's here

The greybox circuit (tarmac → rumble → mud sweeper → water → boulders → ice → hairpin →
gravel return → rumble → tarmac) and, off to the west at x ≈ −620, a flat **proving
ground**: strips of each surface plus a launch ramp. Use the circuit to judge the game
and the proving ground to isolate a handling problem when the circuit makes it ambiguous.

## Tuning

`resources/default_tuning.tres` is a Resource. Open it in the inspector, press play, and
move values **while it runs**. That's the point of the spike — findings are much more
useful as numbers than as adjectives. If something feels wrong, open `F1` first: "it feels
floaty" is hard to act on, "wheel loads drop 40% over crests" isn't.

## Tests

```
godot --headless --fixed-fps 120 --path godot res://tests/test_main.tscn
```

35 checks, ~30 s. Exits non-zero on failure. `--fixed-fps` decouples from wall clock, so
~4 minutes of simulated driving runs in seconds. No addon — just a scene and
`await get_tree().physics_frame`, so the tests read as straight-line code.

They cover the thesis (a swap changes no velocity component and no basis), the axis-change
sign traps, suspension behaviour, and **faithfulness to the web prototype**: terminal speed
on each surface for each end, measured against the 2D model at matched duration. Every case
lands within 8%.

## Structure

| file | role |
|---|---|
| `scripts/vehicle.gd` | the thesis: rigid body, four wheels, the swap |
| `scripts/wheel.gd` | suspension raycast and what it found |
| `scripts/surfaces.gd` | surface table + per-end modifiers |
| `scripts/tuning.gd` | every tunable number |
| `scripts/track_data.gd` | the circuit, ported from the web build's authoring |
| `scripts/track_builder.gd` | extrudes it into a ribbon with surface metadata |
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
