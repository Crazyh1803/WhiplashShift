# Whiplash Shift

A solo arcade combat racer: one chassis, two ends, and a swap that hands the drive from
one to the other **without touching the body's momentum**.

Development uses one chat, branch and worktree per focused change. Start with
`$whiplash <request>`; tested corrections are pushed to that branch and selected
for the Windows desktop preview. Main changes only after an explicit
`$whiplash merge <branch>` instruction. See [the chat workflow](docs/chat-workflow.md).

## Consolidated project — 2026-10-16

This folder brings forward the saved gameplay and Blackjack work from `Whiplash Shift`
and the Deadbolt asset branch from `Whiplash Shift - Deadbolt`. Both original folders
are preserved. The earlier Git history and local gameplay changes are committed here.

Open `godot/project.godot` in Godot 4.7.2 and press **F5** for the project.
The garage offers seven named chassis buttons, including **DEADBOLT**;
**VIEW 3D // PAINT & PARTS** opens the rotatable 3D preview. Left/right arrows also
cycle the roster, and returning from a race keeps the selected chassis.
All seven vehicles use authored models with their saved handling and blueprint
images. Enter a callsign and choose
**IGNITE** to race two CPU opponents over three full laps after a countdown.
Choose **CPU DIFFICULTY** in the garage: **Easy** gives a relaxed pace with earlier
braking and more space in traffic; **Medium** gives a balanced racing pace;
**Hard** carries more speed, brakes later and commits sooner to clear passes. Medium is the
default. The selection is saved and retained for retries. All levels use the same
vehicle physics, with no power/grip bonuses or catch-up speed boosts.
CPU racers assess both passing sides, hold their line alongside another car, and
merge back after clearing it. Easy waits longer and leaves more room; Hard commits
sooner to clear opportunities. They follow traffic when both sides are occupied,
check approaching cars before merging, and avoid starting passes near tight bends
or surface swaps. Hard can also pass on clear, wide rough-surface straights.
Racers plan braking distance instead of adopting a distant corner's speed for the
whole approach. They prepare end swaps before the boundary and keep the maneuver
committed until they reach the new surface. Difficulty changes requested pace,
cornering confidence, braking and overtaking decisions.
Floating armored gold crates with holographic question marks grant one random item.
Collected crates leave a pad with a respawn countdown. Weapon visuals include metal
missiles, grenade models, tracers, muzzle flashes, exhaust, sparks and textured
fire/smoke explosions. See `godot/assets/vfx/ATTRIBUTION.md` for texture licenses.
Item effects have positional audio: gun bursts, rocket/homing launches, grenade
launches, explosions, oil deployment and smoke hiss, plus pickup and hit confirmations.
Shield activation, sustain, blocked hits and expiry have distinct cues. The shield
uses a pulsing hexagonal field that flashes on impact; smoke billows use textured
clouds, and oil forms a shimmering surface slick. Machine guns show twin tracers,
muzzle flashes, ejected casings and a mount on the active driving end. Smoke/shield
loops stop on expiry, recovery or race exit. A dedicated limited audio bus keeps
overlapping effects bounded without changing the vehicle audio.

Gold pickup boxes grant one random item. Press **E** once to activate it: machine
guns, rockets and grenades fire automatically for a short timer; shields protect
for their full timer; smoke and oil deploy behind the active end. The **1% rare homing
missile** locks a visible racer ahead and fires once. Swapping redirects subsequent
shots and drops. CPU racers use the same item odds and rules. No second player or
copilot is required.
The HUD shows the held item or active timer, lap, position and race time; finishing opens results with **RACE AGAIN**
(`Enter`) or **BACK TO GARAGE**. Retry keeps the same vehicles. `R` recovers only
the player to the last checkpoint; `Esc` returns to the garage.

Run `ak-test` for core handling, CPU driving, all seven vehicles and consolidation checks. Set
`GODOT_BIN` to use another installed executable. For rendered garage and driving
captures, run:

```sh
godot --path godot --fixed-fps 120 res://tests/consolidation_visual_qa.tscn
```

Append `-- --nightshift` to capture Nightshift, including both ends, custom paint, driving and swapping.
Use `-- --ramjet` for Ramjet or `-- --boilerfang` for Boilerfang.
Use `-- --helix` or `-- --knifeedge` for the remaining vehicles.
Add `--keep-open` after the vehicle flag to leave
its garage preview open after successful captures.
Captures go to `.ai/captures/`. Historical reports live separately under
`.ai/history/whiplash-shift/`; they are not current verification results.

Deadbolt now uses `deadbolt_hardsurface.glb`, rebuilt from the Ford/Mustang
blueprint with controlled body creases, recessed glazing, panel details and distinct
truck/coupe wheels. Its native source, builder and LODs are documented in
`tools/vehicle_pipeline/DEADBOLT_HARDSURFACE.md`. The earlier draft remains under
its original filenames.

Nightshift uses `nightshift_blueprint.glb`, based on the saved `80s.jpg` sheet:
a square-body Chevy truck end joined to a low Camaro end with a stepped twin roof.
Its three paint channels use the same authored-hub adapter as Deadbolt.

Ramjet uses `ramjet_blueprint.glb`, traced from `dodge.jpg`: a Dodge Ram D150
truck end joined to the low Conquest TSi coupe, with pop-up lamps and a wedge nose.
Its paint, glass and wheel integration follows the same authored-hub contract.

Boilerfang uses `boilerfang_blueprint.glb`, based on `steam-punk.jpg`: a plow truck
and ornate speedster with boilers, brass machinery and a central flywheel drive.
The middle mechanism is visible body artwork; four physical wheels retain the saved
handling. Display tire radii are independent of the tuning-owned physics radii.

Helix uses `helix_blueprint.glb`, based on `r-type.jpg`, for its biomechanical
racer body. Knifeedge uses `knifeedge_blueprint.glb`, based on `hot-wheels.jpg`,
for its sand rail/supercar body. Helix retains the reference's tracked rear and
wheel-less hover nose, with hidden physics wheels. Knifeedge uses authored hubs
and measured visual tire radii. Both retain three paint channels. Their native
sources, builders and LODs are documented under `tools/vehicle_pipeline/`.

Rendered wheel assemblies pivot around their authored hubs and follow the existing
suspension and steering. Their visual offsets are independent of the physical wheel
hardpoints. Only the three paint materials are customized; glass and hardware retain
their authored surfaces. Handling, physical tire radii and the tuning-owned collider
are preserved. The body artwork extends beyond the simplified collider near the noses.

| | |
|---|---|
| **`godot/`** | the game — Godot 4.6, 3D, where development happens now. See [godot/README.md](godot/README.md). |
| **`web/`** | the original 2D browser prototype. Kept alive deliberately: it's the reference for what the handling is *supposed* to feel like, and the Godot tests measure against it. |

---

## Bydo-Grid roads and terrain feedback

Roads use procedural ceramic armor, chitin rubble, viscera, spinal armor, vitrified
coolant, reactor effluent and black ichor materials. Rough surfaces have bounded
real relief. Each special terrain has contact-driven spray/debris and a distinct
body response, exaggerated with the wrong frame. Void lighting uses localized
beacons and headlights on the active driving end. See
[the terrain implementation guide](docs/art-direction/terrain-responses.md).

## Launch from Games

The installed **Whiplash Shift** entry in your desktop’s **Games** category starts the
game through Godot. Its context menu also offers **Open in Godot Editor**. The executable
`tools/launcher/whiplash-shift` accepts Godot arguments, including `--editor`.

The launcher pulls updates from GitHub's `main` branch before each launch and
imports assets when the revision changes. Offline or conflicting updates leave
the current copy available; local changes are never discarded. Update checks
time out after 15 seconds. Set `WHIPLASH_AUTO_UPDATE=0` to skip them while developing.
Diagnostics are saved to `~/.local/state/whiplash-shift/launcher.log`
(or under `XDG_STATE_HOME` when set).

To enable this on an existing installation, run once on that desktop:

```sh
git -C /home/crazyh/Documents/ChatGPT/Whiplash pull --ff-only origin main
```

After that, the same Games shortcut fetches published changes automatically.

### Windows shortcut and updates

Windows installations under `%LOCALAPPDATA%\WhiplashShift` use
`tools/launcher/whiplash-shift.ps1`. To upgrade an existing version-pinned shortcut,
run this once in **PowerShell**:

```powershell
$installer = Join-Path $env:TEMP 'Install-WhiplashShift.ps1'
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Crazyh1803/WhiplashShift/main/tools/launcher/whiplash-shift.ps1' -OutFile $installer
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Install
```

This reuses the existing Godot engine, updates existing Whiplash Shift shortcuts
in the user's Desktop and Start Menu, and creates a desktop shortcut if needed.
The shortcut defaults to the selected chat preview on each launch. A new release downloads
the source archive, extracts only the game, and imports its assets before activating
it. The first download can take several minutes. Existing installations and saves
are retained. An unavailable update launches the current working version. Logs are
in `%LOCALAPPDATA%\WhiplashShift\launcher.log`. No Git installation is required.

After testing and committing a correction in its chat worktree, run
`python3 tools/workflow/chat.py publish`. This pushes that branch and updates the
manifest on `desktop-preview`, without merging main. The most recent preview
selection wins; `python3 tools/workflow/chat.py preview <branch>` selects another.
Merged releases remain on the stable channel (`-Install -Channel stable`).
See [the chat workflow](docs/chat-workflow.md) for the one-time preview launcher
upgrade, project commands, checks and the merge process.

## The web prototype (`web/`)

The following describes the historical prototype, including its old copilot concept.
Current development follows the solo arcade item-combat direction above.

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


Item presentation checks:

```sh
godot --headless --fixed-fps 120 --path godot res://tests/item_tests.tscn
godot --path godot res://tests/item_presentation_qa.tscn
```

The rendered check activates every item through the game, verifies positional
audio and sustain loops, captures the new materials/effects, and checks audio
voice limits and cleanup. Captures and sample WAVs go to
`.ai/captures/item-effects/`. A `Dummy` audio driver can verify routing without speakers.
