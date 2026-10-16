# Claude asset handoff: Deadbolt graphics to Blackjack quality

The user explicitly selected **Prepare a Claude handoff**. Claude is the configured
asset lead. Work in the attached asset worktree on `asset/deadbolt-graphics`, not the
main `codex/deadbolt-selection` checkout. Run `ak-lead` first and follow the supplied
agent-kit workflow. Do not mix further garage/code work into the asset branch.

## User goal

Make Deadbolt the next vehicle with graphics on par with Blackjack. The current
Deadbolt model is an early draft, not finished production art. Preserve the original
`80sFord.jpg` reversible Ford truck/Mustang concept; do not substitute a generic car.

The garage now has seven named chassis buttons and a **VIEW 3D // PAINT & PARTS**
button. Click **DEADBOLT**, then **VIEW 3D** to inspect it. Selection is retained when
returning from a race. Selector changes and tests belong to the Codex code lane.

## What is already preserved and integrated

- All prior work is in this repository; original `Whiplash Shift` and
  `Whiplash Shift - Deadbolt` folders are untouched.
- Original Deadbolt Blender source, builder, GLB, LODs and QA artifacts remain at
  `tools/vehicle_pipeline/blender/deadbolt_blueprint.blend`,
  `tools/vehicle_pipeline/blender/build_deadbolt_blueprint.py` and
  `godot/assets/vehicles/models/deadbolt/`.
- `godot/scripts/deadbolt_blueprint_vehicle.gd` adapts source wheel meshes to the
  existing physical wheels and aligns the rendered axles. Its factory dispatch,
  three paint channels, protected materials, garage and player/CPU paths work.
- The consolidated project runs on installed Godot 4.7.2 / Jolt / Forward+.

## Reference and quality authority

1. Shape: `tools/vehicle_pipeline/references/80sFord.jpg` (also packed in the blend).
2. Blackjack finish: `tools/vehicle_pipeline/BLACKJACK_BLUEPRINT.md`,
   `BLACKJACK_PAINT_DETAIL.md`, `BLACKJACK_FINAL_FINISH.md` and actual Blackjack
   in the Godot garage. Saved comparison renders are under
   `godot/assets/vehicles/models/blackjack/blackjack_blueprint_godot_*.png`.
3. Source quality patterns: `build_blackjack_blueprint.py`,
   `blackjack_blueprint_trace.py`, `blackjack_blueprint_geometry.py` and
   `blackjack_blueprint_wheels.py`, all under `tools/vehicle_pipeline/blender/`.
4. Claude's read-only architecture recommendation is in
   `.ai/escalations/20261016-142829-design-claude.md`.
5. Detailed acceptance gates: `.ai/plans/deadbolt-polish.md`.

The prior preview was visually compared with the actual Godot model. Its bad shape
and detached windows already exist in the source asset; runtime integration did not
create them. Numeric PASS in the old validator is not evidence of acceptable art.

## Required asset work

- Replace the pill-shaped, globally smoothed hull with a continuous, traced,
  hard-surface body. Preserve the upright boxy truck end and the low coupe wedge,
  cab roof, hood breaks, shoulder/beltline and convincing shared reversible cockpit.
- Add properly framed windshields on both ends. Recess and seat all side glass,
  doors, seals and trim flush to the shell. Remove the floating slab-like panels.
- Cut real wheel openings with seated fender lips. Integrate the pickup grille,
  sealed-beam lights, brush guard/bumper and the coupe lamps, intake and splitter.
- Bring panel seams, handles, mirrors, wipers, vents, trim, wheel depth and tire tread
  to Blackjack's visible level of finish. Preserve distinct truck/coupe wheel styles.
- Use clean UVs and semantic PBR surfaces: three customizable paint channels,
  reflective dark glass, rubber, protected metal and lamps. Compare final Godot
  paint under equivalent Blackjack studio lighting, not a flat clay render.
- Preserve the current saved draft under its existing filenames until the new
  candidate passes. Prefer new `deadbolt_hardsurface*` candidate files so the draft
  is not lost. Supply an editable native source, idempotent builder and LODs.

## Hard integration contracts

- Source frame is Blender X-long / Y-width / Z-up. Runtime rotates +90 degrees in
  Godot yaw. Coupe is source +X and must face game End A (-Z).
- Source wheel centers: coupe `(1.66, +/-0.91, 0.40)`, truck
  `(-1.72, +/-0.91, 0.43)`. Display tire radii are 0.40 / 0.43 m.
- Preserve mesh name prefixes `Wheel_Coupe_*` and `Wheel_Truck_*`; all copied wheel
  part origins must remain at their wheel hubs on the proper side. The adapter
  groups by prefix and transformed side, then offsets the rendered assembly only.
- Preserve materials `Deadbolt_Paint`, `Deadbolt_Secondary`, `Deadbolt_Stripe`.
  All other authored materials remain protected from paint overrides.
- Do not change `vehicle.gd`, `wheel.gd`, tuning, hardpoints, physical tire radii,
  collider, mass/inertia, swap mechanics or CPU logic to make the art fit.
- Current catalog points at `deadbolt_blueprint.glb`. Coordinate a narrow catalog
  path change in the code lane after the candidate is ready; do not silently leave
  the garage showing the old file. Export handoff metadata if dimensions change.
- Consolidation tests currently expect 13 mesh parts per coupe wheel and nine per
  truck wheel. Prefer joining tread/bolt details into their semantic meshes. If
  topology genuinely requires another structure, document the necessary test/code
  change for Codex rather than weakening those assertions without explanation.

## Suggested build approach and validation

Trace the actual reference stations, calibrated by the 3.38 m wheelbase; do not
stretch the drawing. Reuse Blackjack's methods, but not its module side effects or
coordinate frame: Blackjack uses another axis convention and a pose rake. Claude's
design memo notes that its image pixel calibration was unverified, so measure it.

Use a mirrored cage with local support loops/crease weights, restrained subdivision,
EXACT wheel-arch cuts and weld/manifold repairs. Seat glass against the evaluated
shell with numeric clearance checks, rather than placing rectangles by eye.

Run Blender headlessly through `ak-blender`; print `AK:` reports via `ak_util` and
use numbers before previews. No Blender GUI/MCP modeling or viewport screenshots.
Inspect/adjust the installed Blender path if the old documented binary is missing.

Validate shell closure/manifold/positive volume, UV/material coverage, reflection
symmetry, wheel centers/radii/orientation, positive arch clearance, glass-to-shell
clearance/no crossing, bounds and complete rendered-vehicle triangle count. Target
20–40k for the whole visible car, with meaningful lower-detail exports. Rebuild twice
and compare geometry/metadata for idempotence. Replace the old validator's fixed
95-object/18–20k gates deliberately with checks that measure the new design.

Render neutral side/top/both ends/three-quarter views and blueprint overlays; use
`ak-look` for visual QA. Do not accept the current high findings (pill body, missing
windshields, floating windows/doors/fenders). Run `ak-review codex/deadbolt-selection` and resolve findings
under the two-round cap. Keep a clear asset-only diff and coherent asset commit.

Codex will integrate the approved candidate and run `ak-test`: core handling, CPU,
Blackjack and consolidation suites, including independent-world Deadbolt physics
parity and real garage/player/CPU construction. Final GPU QA must exercise the
actual preview, all paint channels, suspension/steering, driving and end swapping.

## Delivery back to the user / code lead

Report the asset branch/commit, native source and GLB/LOD paths, coordinate and
material contracts, complete triangle counts, numeric validation, visual QA and
review verdicts, any narrow runtime/catalog/test updates required, and remaining
art limitations. Do not claim Blackjack parity from triangle counts alone.
