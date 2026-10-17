# Ramjet K-6 asset handoff

Branch `asset/ramjet-graphics`. Commits: `8d2fcce` (unmodified renamed fork of the Nightshift builder, **template baseline only, not a delivery**) and `863fa32` (`asset(ramjet)`), which holds all Ramjet geometry, GLBs, builder, validator, QA and docs. Main checkout and Godot scripts/tests untouched.

## Paths
- GLB: `godot/assets/vehicles/models/ramjet/ramjet_blueprint.glb` (`res://assets/vehicles/models/ramjet/ramjet_blueprint.glb`); LODs `.../ramjet/lod/ramjet_blueprint_LOD{1,2}.glb`; `ramjet_blueprint_qa.json`, `ramjet_blueprint_build.json`.
- Source: `tools/vehicle_pipeline/blender/ramjet_blueprint.blend`; builder `build_ramjet.py` + `ramjet_{trace,core,prims,shell,cuts,cabin,details,wheels,export,qa}.py`; `validate_ramjet.py`, `check_ramjet_idempotence.py`, `render_ramjet_lods.py`.
- Reference `tools/vehicle_pipeline/references/dodge.jpg` (packed in the .blend); doc `tools/vehicle_pipeline/RAMJET_BLUEPRINT.md`; renders, close-ups, blueprint overlays, LOD renders `tools/vehicle_pipeline/qa/ramjet_blueprint/`.
- Godot `.glb.import` files are not generated here (Godot creates them on import).

## Contract
- Axes: coupe End A +X, truck End B -X, +/-Y width, +Z up, ground z=0; runtime yaw +90 deg, offset y -0.62. Body X -2.73..2.78 (5.52 m incl. bumper), width 2.36 (mirrors), height 1.957.
- Wheels: `Wheel_Coupe_*` 13 parts/wheel (tire, rim, hub, 5 wide spokes, 5 slot inlays; R 0.40, W 0.35), `Wheel_Truck_*` 11 parts (tire, rim, hub with hubcap + beauty ring, 8 steel-disc sectors; R 0.43, W 0.33). Tire objects contain `_Tire_`; every part's origin is the hub: coupe x +1.66, truck x -1.72, z = radius.
- Visual half-track **0.86 m** (not 0.82): both front elevations put tyre centres 75.5 px (0.859 m) off centre. Outer tyre faces 1.025 / 1.035 stay under flares (1.06). Physical wheels unchanged. Display radii 0.40 / 0.43, as requested.
- Materials: semantic `Ramjet_Paint` (red), `Ramjet_Secondary` (silver), `Ramjet_Stripe` (orange); fixed: Glass, Rubber, BrushedMetal, Gunmetal, Grille, Headlight, Marker, Amber.
- Features: pop-up headlamp doors (modelled closed, as drawn: shut lines + lens strip; not animated), Conquest wedge nose, hood bulge with recessed scoop slot, bumper cover with fog/turn lamps, wide air dam with intake and chin lip; Ram upright hood, crosshair/egg-crate grille, rectangular lamps, chrome bumper with two vertical guards and plate; stepped roof (Ram ~1.95 m to Conquest ~1.65 m) with cab-back glass; two mirror sets, two wiper sets; 8-slot steel Ram wheels, 5-spoke Conquest alloys.

## Triangles
Gameplay 33,932 (66 objects) / LOD1 27,034 / LOD2 20,568.

## Evidence
- `validate_ramjet.py`: PASS, 85 pass/fail checks. Shell closed, shell symmetry max 1.96 mm, assembly symmetry max 1.76 mm (Boolean tessellation limited); silhouette vs trace top max 3.2 px, sill 0.7 px, half-width 0.6 px; arch clearance 74.7 mm truck / 64.6 mm coupe; glass seated 3.2-4.9 mm with 0 shell crossings and 100% of cut interior covered (no holes); hardware does not pierce glass; every lamp/marker vertex within limit of the shell and every detail vertex inside the trace-derived envelope; L/R cutter pairs applied equally (8/8); wheel wells closed (610 rays, 0 escaped); UV/material complete; GLB re-import and wheel counts OK; LOD envelopes (<=4.9 mm) and wheels/paint preserved; budget 25k-45k and LOD monotonic.
- Rebuild: build A copied, rebuilt in a separate Blender process, `check_ramjet_idempotence.py` -> idempotent, 183 objects, 0.0 mm vertex and 0.0 mm surface deviation; gameplay GLB md5 identical across the two builds.
- Visual (ak-look): blueprint overlays PASS (side/top/both fronts within ~8 px); neutral full-body views and close-ups PASS with LOW only; LOD renders PASS (LOD2 grille collapse fixed by raising shell decimation ratios); after the final glass-seating correction a targeted glass/cabin look: PASS, none.
- Code review (Gemini via `ak-review 8d2fcce`, file-only prompt kit, diff vs the renamed Nightshift fork because the full copy exceeds agy's argument limit): round 1 APPROVE, findings none (`.ai/reviews/ramjet-r1.md`); round 2 on the final tree (1,560-line delta) APPROVE, findings none (`ramjet-r2.md`). Both verdicts were terse; no HIGH/MED existed to fix or dispute, so no tiebreak.

## Remaining limits
- Silhouette traced from an AI-generated sheet; scale from approximate wheel centres (363/660 px). The sheet draws the Ram cab ~1.95 m tall, kept as traced.
- Coupe side glass is the small triangle in the sheet; the mirror overlaps it in side view as drawn (no 3D intersection, validator-checked).
- ak-look is noisy: it flagged an "open wheel well/see-through" and glass clipping that numeric ray tests disproved. LOW notes left: shading pinch at the roof step, boxy air-dam profile, wiper blades sit ~4 mm over the glass, bezel bar corners overlap slightly.
- Materials are flat PBR colours (no textures). Interior is solid under dark glass. Exact-Boolean can silently drop an operand at a ring-station coincidence (a truck handle pocket did once); `cutter_pairs_applied_equally` guards it.
