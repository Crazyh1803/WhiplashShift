# Knifeedge XR asset handoff

Branch `asset/knifeedge-graphics`. Commits (oldest first): `24acb29` unmodified renamed fork of the Boilerfang builder (**template
baseline only, not a delivery**; review scope is the delta against it); production/fix commits follow it; the final asset commit
hash is the last line of this file. Main checkout, Godot scripts/tests and every other vehicle's art/helpers are untouched; no
`.glb.import` files are generated here.

## Paths
- GLB `godot/assets/vehicles/models/knifeedge/knifeedge_blueprint.glb` (`res://assets/vehicles/models/knifeedge/knifeedge_blueprint.glb`);
  LODs `.../knifeedge/lod/knifeedge_blueprint_LOD{1,2}.glb`; `knifeedge_blueprint_qa.json`, `knifeedge_blueprint_build.json` (has `handoff`).
- Source `tools/vehicle_pipeline/blender/knifeedge_blueprint.blend`; builder `build_knifeedge.py` +
  `knifeedge_{trace,core,prims,forms,body,cage,mech,details,wheels,export,qa}.py`; `validate_knifeedge.py`,
  `check_knifeedge_idempotence.py`, `render_knifeedge_lods.py`, `knifeedge_refcrop.py`.
- Reference `tools/vehicle_pipeline/references/hot-wheels.jpg` (packed in the .blend); doc `tools/vehicle_pipeline/KNIFEEDGE_BLUEPRINT.md`;
  renders/overlays/LOD renders `tools/vehicle_pipeline/qa/knifeedge_blueprint/`, gridded crops `qa/knifeedge_ref/`;
  review verdicts `.ai/reports/knifeedge-source-review.md`.

## Contract for Codex
- Axes: supercar **End A +X**, sand rail **End B -X**, +/-Y width, +Z up, ground z=0; runtime yaw +90 deg, offset y -0.62. Body X
  -2.530..2.692 (5.22 m), width 2.24 m over the End-B tyres, height 1.756 m. Uniform scale 0.0111551 m/px from the side-elevation
  wheel centres (3.38 m wheelbase).
- Wheels: `Wheel_Coupe_*` (End A, 10-spoke alloy) and `Wheel_Truck_*` (End B, knobby beadlock); one `_Tire_` per wheel; **every wheel
  part's origin is the authored hub**.
  - End A hub x +1.66, y +/-0.90, z 0.390. End B hub x -1.72, y +/-0.93, z 0.446.
  - **`handoff.display_radii` = {A: 0.390, B: 0.446}**, **`display_half_track` = {A: 0.90, B: 0.93}**, `wheel_centres` in the build json.
    Visual only: physical tuning (collider, hardpoints, mass, drive) is unchanged and the model never asks for the old radii.
  - Parts per wheel: Truck 9 (Tire, Rim, Hub, Spoke_{side}_{0..5}); Coupe 15 (Tire, Rim, Hub, Spoke_{side}_{0..9}, Brake, Caliper).
    48 wheel objects, identical in all LODs (spokes are never decimated).
- Decorative machinery (body-mounted, **not wheels**, no physics; kept in all LODs, 17 objects): `Prop_Engine_{Block,Head_*,Barrel_*}`,
  `Prop_Transaxle`, `Prop_Transaxle_Bell`, `Prop_Exhaust_{Muffler,Header_*,Tailpipe}`, `Prop_Upright_*` (rear), `Prop_UprightA_*` (front hub
  carriers). No extra physical wheels.
- Materials: semantic `Knifeedge_Paint` (blue shell), `Knifeedge_Secondary` (ice white), `Knifeedge_Stripe` (orange cage + calipers);
  fixed `Knifeedge_Glass`, `_Rubber`, `_Steel`, `_Iron`, `_Lamp`. All eight are present in every LOD.
- Other nodes: `Body_Shell/Floor/Deck/TailPlate/Splitter/Cage{Roof,Rear,Bumper,Floor}`, `Glass_{Windshield,Roof_+1,Roof_-1}`, merged
  `Detail_<material>` hardware.

## Triangles
Gameplay 35,186 (83 objects, 1.62 MB) / LOD1 25,068 / LOD2 14,542. Budget gate 30k-60k. LOD1 drops tessellated small hardware and
decimates shell/tyres/rims (0.70/0.50); LOD2 drops all small hardware except lamps, decimates the cage tubes and machinery.

## Evidence
- Numeric: `validate_knifeedge.py` PASS, **51 checks** (`knifeedge_blueprint_qa.json`). Highlights: shell top vs trace 0.24 px, sill 0.0 px,
  half-width 3.4 px max; length within 1 mm; tail hoop and roof heights within trace; tyre radii 390/446 mm, hub origin error 0, tyres touch
  z=0; supercar tyres outside the solid shell (0 overlaps, ray-parity inside test) with 69 mm arch clearance; rear suspension >= 94 mm from
  the knobby tyres; nothing but axles touches a wheel; glass seated in cage tubes (<= 2 mm), no glass/shell overlap, ray coverage of roof
  and windshield complete; every one of the 206 parts is chained to the shell within 12 mm (or interpenetrates); shocks clear of cage tubes;
  truss feet inside the floor pan; pillars sunk 18-35 mm into the shell; hood vents conform to the hood (0 mm); lamps on housings; UV and exact
  material set; GLB re-import: wheel parts 48/48/48, props 17/17/17, envelope, hubs, tyre radius deficit 0/0/2.3 mm.
- Mirror symmetry max 0.04 mm (p99 0.0) over 16.7k vertices; exempt by name: `Fine_SteeringWheel`/`Fine_SteeringColumn` (drawn on one seat in
  the sheet), `Fine_ShockSpring_*` (chiral helix) and `Fine_Badge` (4 mm tessellation difference on the hood crease).
- Rebuild: build A copied, rebuilt in a separate Blender process, `check_knifeedge_idempotence.py` -> idempotent, 206 objects,
  0.0 mm vertex and surface deviation, and all three GLB md5 sums identical (exact Booleans are deterministic here).
- Visual (ak-look, numeric gates are authoritative): earlier rounds found and fixed real defects: Boolean wheel arches were no-ops (inverted
  cutter winding; wheels were inside the shell), pillar tubes ended 25 mm above the shell, shock spring crossed a tower leg, steering column
  floated, End-A wheels had no hub carrier, hood vents were flat plates standing up to 60 mm off the curved hood, truss feet and LED slits
  were oriented wrongly. LOD set (gameplay/LOD1/LOD2, both ends) PASS none. Remaining ak-look HIGH/MED items are false positives
  disproved numerically or source-correct (see below).
- Code review (Gemini, file-only prompts, `.ai/reports/knifeedge-source-review.md`): round 1 two chunks APPROVE none; round 2 two chunks
  APPROVE none. No tiebreak needed.

## Interpretation of source ambiguities
In `KNIFEEDGE_BLUEPRINT.md`: wheel radius/centre reads (pixel scan decided), track from the top view (end elevations at another scale), the
light bar at x 556..572 not 450..471, the rear-quarter cut line, one steering wheel, wing tips not placed. The sloped rear deck, the tail plate
with grille/quad lamps and the white roof strips are drawn in the sheet's top/end-B views, so ak-look's "remove the solid deck/bulkhead"
suggestions were not taken.

## Remaining LOW limits
- Silhouette traced from an AI-generated sheet through gridded crops read by ak-look (+/-2-3 px); half-width gate allows 4 px.
- Windows are open (cage); interior beneath the cockpit well is a solid pocket; no dashboard instruments.
- The End-A front suspension is only a hub carrier, axle and two arms inside the arch; no springs/dampers there (not visible in the sheet).
- Roof glass can render grey in the neutral studio (reflection of the bright sky), it is the same dark material as the windshield.
- The underside QA camera is a low side view, not a true underbody shot.
- ak-look stays noisy on close-ups: it repeatedly calls touching/embedded parts (mirror stalk, truss feet, steering column) "floating"; the
  chain/embedding gates above are authoritative.
- Legacy Knifeedge handling has unrelated recovery/stall behaviour; per instruction physics and CPU AI were not touched, report to Codex.
Final asset commit: `ce154eb` (handoff text itself may be amended by a later docs-only commit).
