# Whiplash Shift

A bi-directional combat racer: one chassis, two ends, and a swap that hands the drive from
one to the other **without touching the body's momentum**.

| | |
|---|---|
| **`godot/`** | the game — Godot 4.6, 3D, where development happens now. See [godot/README.md](godot/README.md). |
| **`web/`** | the original 2D browser prototype. Kept alive deliberately: it's the reference for what the handling is *supposed* to feel like, and the Godot tests measure against it. |

---

## The web prototype (`web/`)

- **End A — Asphalt Racer.** Slicks, low clearance, aero downforce, ~180 km/h on tarmac.
  Effectively immobilised in a bog.
- **End B — Mud Brawler.** Knobbly treads, raised, locked 4WD, huge low-end torque.
  Tops out around 70 km/h on tarmac.

Solo mode, one mixed-surface circuit, an AI copilot on callouts and the tailgun, two rivals.

## Running it

ES modules need to be served, not opened from `file://`:

```sh
cd web && python3 -m http.server 8137
# then open http://127.0.0.1:8137/index.html
```

## Controls

Touch controls appear automatically on any device whose primary pointer is a finger.
Force them on desktop with `?touch=1`, or off with `?touch=0`.

**Touch** — left pad steers (relative, so a thumb landing never snaps to full lock);
right cluster is `GO` / `BRAKE` / `H-BRK`, with `SWAP` spanning the two buttons your
thumb was just on and `BOOST` beside it. `MENU` opens reset, camera, copilot and pause.
Landscape is strongly preferred; portrait shows a rotate prompt.

**Keyboard**

| | |
|---|---|
| `W` / `↑` | throttle |
| `S` / `↓` | brake · reverse (from near-standstill) |
| `A` `D` / `←` `→` | steer |
| **`SPACE`** | **swap ends** |
| `SHIFT` | handbrake |
| `E` | boost (earned from clean swaps) |
| `R` | recover to last checkpoint |
| `C` | camera: 180° swing vs. instant snap |
| `F` | copilot assist on/off |
| `T` | live tuning panel |
| `P` / `H` / `M` | pause / controls / mute |

On touch the HUD switches to a compact layout that lives entirely in the top strip, so the
bottom two thirds of the screen belong to your thumbs. That applies on tablets too, where
there is room for the wide layout but the bottom edge is still under a hand.

## What the prototype is actually testing

### The swap preserves the body state

`swapEnds()` in `src/vehicle.js` changes which pair steers and drives, and deliberately leaves
`vx`, `vy`, `av` and `ang` alone. Inertia carries through; the driver has to deal with it. A
headless check asserts exact equality across the swap.

### Both resolutions from the GDD are reachable

- **Vector Slide** — swap at speed and pull the handbrake. The handbrake locks the pair
  *trailing the velocity vector*, which straight after a swap is the newly active end, so the
  chassis snaps round ~180° and End B ends up facing the way you were already going. Measured
  at ~130° of rotation with ~78% of entry speed retained.
- **Pure Reversal** — swap, scrub the inherited vector on the brakes, then throttle. End B
  drives away down the opposite vector with the chassis barely rotated (<5°). The drive taper
  is computed against speed *in the direction being driven*, which is what makes pulling full
  torque against inherited momentum possible at all.

### Surface asymmetry is emergent, not scripted

Every wheel samples the surface under **its own** contact patch from a baked surface-id raster,
so half-on/half-off transitions, one end gripping while the other spins, and the whole feel of
crossing a boundary come out of the tyre model rather than a state machine. The GDD's headline
modifiers (A: +30% top speed on tarmac, −70% accel in mud; B: +40% traction in mud, −40% top
speed on tarmac) live in `END_MOD` in `src/surfaces.js`.

### The copilot never takes the wheel

`assistSteer` is only ever *added* to the driver's input, and is zeroed the instant the driver
steers against it. There is no control to hand back on a swap, so there is no hand-back latency.

## The track

Tarmac start/finish → rumble-strip warning → **induction gate (End B)** → mud sweeper → water →
boulders → ice → **tight 180° hairpin** (the backwards branch) → gravel return → rumble warning
→ **induction gate (End A)** → tarmac. 2.6 km, 3 laps.

Crossing a gate on the wrong end cuts power, force-swaps you and costs chassis damage.

## Tuning

Press `T`. Every slider writes straight into the live `T` object from `src/tuning.js`; changes
apply on the next physics step. That is the point — the swap is meant to be judged with the
numbers moving.

## Tests

```sh
node web/tests/headless.mjs            # 30 checks, headless Chromium
node web/tests/headless.mjs --shots    # also writes screenshots to shots/
```

The page exposes `window.__WS`, which steps the same fixed-timestep simulation the game loop
runs (`place`, `run(seconds)`, `sample()`, `autopilot()`), so the checks are deterministic and
independent of frame rate.

## Layout

| file | role |
|---|---|
| `src/vehicle.js` | rigid body, four wheels, the swap |
| `src/surfaces.js` | surface table + per-end modifiers |
| `src/track.js` | circuit authoring, surface-id raster, visual bake |
| `src/ai.js` | copilot: lookahead, callouts, slide assist, tailgun |
| `src/rivals.js` | pure-pursuit AI racers |
| `src/weapons.js` | missiles, interceptor fire, oil, particles |
| `src/render.js` | camera (the 180° swing), world draw |
| `src/hud.js` | screen-space HUD |
| `src/touch.js` | touch overlay: builds its own DOM and CSS, so both host pages stay in sync |
| `src/tuning.js` | every tunable number + the live panel |
| `src/main.js` | loop, laps, gates, collisions, test hook |

## Not in this pass

Co-op split-screen, more tracks, vehicle progression, enemy weak-point targeting, gamepad support.
