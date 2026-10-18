# Helix Wraith asset handoff

Branch `asset/helix-graphics`. Commits: `8f03f5e` renamed generic helper fork (template baseline, review scope is the delta against it),
`d12d1dc` builder/blend/GLB/LODs/validator/QA renders, `d09f7c7` review-driven fixes + docs, final commit = the one adding this file.
Main checkout, Godot scripts/tests and other vehicles' art/helpers are untouched. No `.glb.import` files generated here.

## Paths
- GLB `godot/assets/vehicles/models/helix/helix_blueprint.glb`; LODs `.../helix/lod/helix_blueprint_LOD{1,2}.glb`; `helix_blueprint_qa.json`, `helix_blueprint_build.json` (`handoff` block).
- Source `tools/vehicle_pipeline/blender/helix_blueprint.blend`; builder `build_helix.py` + `helix_{trace,core,prims,body,organic,tracks,details,export,qa}.py`; `validate_helix.py`, `check_helix_idempotence.py`, `render_helix_lods.py`, `helix_refcrop.py`.
- Reference `tools/vehicle_pipeline/references/r-type.jpg`; doc `tools/vehicle_pipeline/HELIX_BLUEPRINT.md`; renders/overlays/LOD renders `tools/vehicle_pipeline/qa/helix_blueprint/`, gridded crops `qa/helix_ref/`; review verdicts `.ai/reviews/helix-source-review.md`.

## Contract for Codex
- Axes: hovering nose End A **+X**, claw/track End B **-X**, +/-Y width, +Z up, ground z=0, runtime yaw +90 deg, offset y -0.62. X -2.47..2.50 (4.97 m), width 1.61 m, height 1.22 m. Uniform scale 0.0080128 m/px from the 5.0 m sheet length (no wheelbase on the sheet).
- **No wheel/tire/hub objects exist** (no `Wheel_*`, no `*_Tire_*`); the four physical wheels and axles are hidden by the adapter; nothing is a fake wheel.
- Tracks (decorative, body-mounted, no physics): 12 objects `Prop_Track_{Belt,Cleats,SprocketRear,SprocketFront,Rollers,Bogie}_{+1,-1}`, 6,424 triangles, identical in all LODs.
  Contact: z = 0 (min -0.35 mm), loop x -1.659..-0.585, flat patch x -1.516..-0.733, y centres +/-0.625, width 0.30, sprocket axles x -1.490/-0.753 at z 0.168, outer radius 0.168 (`handoff.track_contact`).
- Materials: semantic `Helix_Paint`, `Helix_Secondary`, `Helix_Stripe`; fixed `Helix_Rubber`, `Helix_Glass`, `Helix_Hardware`, `Helix_Light` (7 total, all present in the gameplay GLB; LOD1/2 contain the same set because stripe bands are split out of the decimated hulls).
- Other nodes: `Body_*` (Hull, Plate_0-7, Collar, Maw, Fender/Shoulder/Wing/Nacelle/Pod_*, Claw{Up,Low}_*, Hose0-3_*, Tendon0-1_*), `Glass_Canopy{Aft,Fwd}`, `Glass_SensorBlister`, `Frame_Canopy*`, merged `Detail_<material>`.

## Triangles
Gameplay 35,576 (60 objects, 1.4 MB) / LOD1 25,678 / LOD2 20,050. Within the 30-50k target. LODs decimate body masses and drop small hardware; claws, hoses, canopies, lenses and tracks remain.

## Evidence
- Numeric: `validate_helix.py` PASS, 39 checks (no wheels authored, closed positive-volume masses, mirror symmetry 1.16 mm, top silhouette vs trace worst 7.3 px / mean 1.1 px, belly <1 px, top-view hull half-width <0.1 px, length/width/height, track contact/patch/extent/sprocket and roller clearance, glass buried >=15 mm with no overhang, no floating part >8 mm, claw tips and jaw gap 0.51 m, pods/barrels/lenses, UVs, exact materials, triangle monotonic, GLB re-import with tracks identical across LODs).
- Rebuild: build A copied, rebuilt in a separate Blender process; `check_helix_idempotence.py` idempotent, 79 objects, 0.0 mm vertex and surface deviation; all three GLB md5 identical.
- Visual (ak-look): full-body set (side, top, 3/4 x3, front, overlays) PASS; close-ups (hoses, underside, canopy, claws, track, track_low, nose, pod) PASS after fixes; LOD gameplay/LOD1/LOD2 PASS none; final re-look of changed views PASS none.
- Source review: Gemini file-only prompts in three chunks, round 1 three APPROVE (cleat spacing MED, mesh-leak LOW fixed), round 2 changed chunks APPROVE none. See `.ai/reviews/helix-source-review.md`.

## Source ambiguities
Documented in `HELIX_BLUEPRINT.md`: glass defines the sheet's upper silhouette so the hull is lowered under canopies; claws read vertical in side and splayed in top view (upper+lower jaw per flank); inner nacelle lenses built as nacelles; hose/fin counts approximate; bogie interior simplified from +/-2 px crops.

## Remaining LOW limits
- Silhouette traced from an AI-generated sheet; ak-look is noisy on close-ups (claw "wrong curvature" disproved numerically).
- Hose flanges slightly overhang the carapace bevel; carapace/hull seam is a straight material split (stair-stepped quads); hoses shorter than the sheet's.
- Wing root and pod meet without a fairing; fins are 6-slat boxes; materials are flat PBR colours with auto-projected UVs.
