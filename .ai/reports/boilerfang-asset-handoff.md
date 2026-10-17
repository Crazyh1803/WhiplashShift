# Boilerfang 88 asset handoff

Branch `asset/boilerfang-graphics`. Commits (oldest first):
- `eb49d0a` unmodified renamed fork of the proven Ramjet builder (**template baseline only, not a delivery**; code review is a delta against it).
- `c3e907a`, `8769d18`, `6b3e233`, `c73bc24` Boilerfang geometry, builder, validator, LOD export, docs, QA renders (iterative, all asset lane).
- `40c7f49` review-round-1 fixes; final asset commit is the one recorded in the last line of this file.
Main checkout, Godot scripts/tests and every other vehicle's art/helpers are untouched. No `.glb.import` files are generated here.

## Paths
- GLB `godot/assets/vehicles/models/boilerfang/boilerfang_blueprint.glb` (`res://assets/vehicles/models/boilerfang/boilerfang_blueprint.glb`); LODs `.../boilerfang/lod/boilerfang_blueprint_LOD{1,2}.glb`; `boilerfang_blueprint_qa.json`, `boilerfang_blueprint_build.json` (contains `handoff`).
- Source `tools/vehicle_pipeline/blender/boilerfang_blueprint.blend`; builder `build_boilerfang.py` + `boilerfang_{trace,core,prims,forms,body,cab,machinery,details,wheels,export,qa}.py`; `validate_boilerfang.py`, `check_boilerfang_idempotence.py`, `render_boilerfang_lods.py`, `boilerfang_refcrop.py`.
- Reference `tools/vehicle_pipeline/references/steam-punk.jpg` (packed in the .blend); doc `tools/vehicle_pipeline/BOILERFANG_BLUEPRINT.md`; renders/overlays/LOD renders `tools/vehicle_pipeline/qa/boilerfang_blueprint/`, gridded reference crops `qa/boilerfang_ref/`, raw measurements `.ai/reports/boilerfang-ref-measure1.md`.

## Contract for Codex
- Axes: speedster **End A +X**, truck **End B -X**, +/-Y width, +Z up, ground z=0; runtime yaw +90 deg, offset y -0.62. Body X -2.571..2.377 (4.95 m), width 1.61 m over the truck tyre studs, height 1.53 m (stack).
- Scale: one uniform 0.0071008 m/px from the side-elevation wheel centres (3.38 m wheelbase).
- Wheels: embedded meshes `Wheel_Truck_*` (End B, spiked knobby) and `Wheel_Coupe_*` (End A, wire speedster wheel; `Coupe` is the shared End-A prefix). One `_Tire_` object per wheel (`Wheel_Truck_Tire_{+1,-1}`, `Wheel_Coupe_Tire_{+1,-1}`); **every wheel part's origin is the authored hub**.
  - End A hub: x +1.66, y +/-0.50, z 0.256. End B hub: x -1.72, y +/-0.66, z 0.348.
  - **`handoff.display_radii` = {A: 0.256, B: 0.348}** (blueprint-derived: tyres 36 px / 49 px). **`handoff.display_half_track` = {A: 0.50, B: 0.66}**. These are visual only; physical tuning (collider, hardpoints, mass, drive, 0.91 half-track hardpoints) is unchanged and the model never asks for the old 0.40/0.43 radii.
  - Truck wheel parts: Tire, Rim, Hub, Spoke_{side}_{0..7} (11 per wheel). Speedster: Tire, Rim, Hub, Wires (4 per wheel). 30 wheel objects in total, identical in all LODs.
- Central mid-drive (decorative, body-mounted, **not wheels**, no physics): per flank `Prop_MidDrive_Flywheel_{+1,-1}` (centre x 0.346, y +/-0.55, z 0.291, R 0.178), `Prop_MidDrive_Belt_*`, `Prop_MidDrive_Guard_*`, `Gear_MidDrive_Pulley_*`, `Gear_MidDrive_Pinion_*`, `Gear_MidDrive_Shaft_*`. Together with the four wheels they give the six-circle side silhouette; they are preserved in every LOD.
- Materials: semantic `Boilerfang_Paint` (green), `Boilerfang_Secondary` (cream), `Boilerfang_Stripe` (oxblood). Fixed: `Boilerfang_Brass`, `_Copper`, `_Iron`, `_Glass`, `_Rubber`, `_Dial`, `_Lamp`, `_Amber`. LOD2 drops small `Dial`/`Amber` parts, so those two may be absent there.
- Other nodes: `Body_*` main masses, `Glass_*` + `Frame_*`, merged `Detail_<material>` hardware.

## Triangles
Gameplay 48,116 (75 objects, 2.1 MB) / LOD1 35,492 / LOD2 17,842. Budget gate 35k-60k. The count sits in the upper band because of the rivet rows, wire/stud wheels and machinery; LOD1 drops fender/hood/door/plow rivets, hinges, clamps and springs and decimates body/tyres/trim, LOD2 also drops all small hardware except lamps.

## Evidence
- Numeric: `validate_boilerfang.py` PASS, **44 checks**. Highlights: main masses closed with positive volume; whole-assembly mirror symmetry max 1.28 mm (p99 0.0, no intentional asymmetry); silhouette vs traced tables top max 1.71 px, sill 0.53 px, half-width 1.05 px; overall length within 1.5 mm/0 of trace; tyre radii equal display radii (0.256 / 0.348), tyres touch z=0 within 3 mm (tread tessellation), fender clearance 40.3 mm coupe / 39.5 mm truck, hull clearance >=132 mm; glass seated 0.7-2.0 mm, never crossing the shell, 385 interior samples all covered (0 holes); no hardware pierces glass or wheels; no hardware floats (12 mm); lamp lenses within 6 mm of housings; smokestack clears glass by 129 mm; roof fittings sunk into the crowned roof; UV and exact material set; GLB re-import counts/materials/hubs, mid-drive in all LODs, LOD envelope <=14 mm, per-wheel tyre radius deficit <=1.05 mm.
- Rebuild: build A copied, rebuilt in a separate Blender process, `check_boilerfang_idempotence.py` -> idempotent, 287 objects, 0.0 mm vertex and surface deviation; all three GLB md5 sums identical (no Booleans in this build).
- Visual (ak-look, files in `.ai/reports/boilerfang-visual-final.md`): full-body set vs the sheet PASS (LOW: skylight boxes level on a falling roof, speedster pontoons wider than the thin wheels), close-ups (cab, truck/speedster noses, both wheels, mid-drive, flywheel, cockpit) PASS none, LOD gameplay/LOD1/LOD2 PASS none. Earlier rounds' HIGH/MED were fixed (nose hardware pins, window frame corners, pulley web, pipe collisions, fender width, lamp seating) or disproved numerically (smokestack vs windshield, "floating" roof fittings: sink check).
- Code review (Gemini, `ak-ask` file-only prompt kit, because the full delta exceeds agy's 128K argument limit): scope = delta against `eb49d0a` in five coherent chunks: core/forms/trace; body/cab; machinery/details; wheels/export/qa/build; validator/idempotence/refcrop. The four deleted baseline modules (`boilerfang_shell/cuts/cabin.py`, old `details`) are pure removals and not reviewed. Round 1 (tree `c73bc24`): core, body, machinery APPROVE none; wheels/export two MED + one LOW; validator one MED + three LOW. Fixes in `40c7f49`: `--stage` flag and dead `surf` removed, export drops are applied before copying, validator now asserts every mesh is in a checked group, signed hub X/Z in GLB check, robust material slots, repo-relative refcrop path. The "wire spokes are not decimated at LOD2" MED was a real name mismatch but is **intentionally not fixed**: decimating wires/spokes lost a wheel part at LOD2 (the 29/30 failure), so the dead branch was removed and the numeric gate keeps them whole. Round 2 (changed chunks only; unchanged chunks keep their round-1 verdict): wheels/export APPROVE none; validator APPROVE with one MED (LOD tyre-radius check used the smallest tyre for all four) and one LOW, both fixed afterwards (per-wheel check, `min z` in the envelope) and re-validated PASS. No tiebreak needed.

## Interpretation of source ambiguities
Documented in `BOILERFANG_BLUEPRINT.md`: the flywheel pair is mirrored (the top view draws a stepped housing on one flank only); Front A's twin roof domes are two symmetric brass vents on the cockpit roof; the single lower-flank stack of the top view is read as one central stack (front B and side view agree); the front elevations' scale is inconsistent with the side/top, so side/top rule and fronts only place features.

## Remaining LOW limits
- Silhouette traced from an AI-generated sheet; scale from approximate wheel centres (px 348/824) measured through gridded crops read by ak-look (about +/-2 px). The truck tyre radius (0.348) and speedster (0.256) follow that sheet, not the old 0.43/0.40.
- Windows are flush glass slabs in brass frames (no recessed cuts); skylight hatches are level boxes on a falling roof; interior is solid under glass.
- The speedster pontoon fenders are wider than the thin wire wheels; their tail is a running board.
- Materials are flat PBR colours with no textures; UVs are auto-projected for later livery work only.
- ak-look is noisy on close-ups (it called valid touching parts "floating"); the numeric gates above are authoritative for seating/clearance.
- Hub z equals each display radius, so the two ends sit at different hub heights (0.256 / 0.348): the rig must place wheels from the authored hub origins, not one shared height.
Final asset commit: `50a004d` (QA json, validator, handoff). Handoff doc itself lives in this commit.
