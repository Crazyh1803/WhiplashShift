# Helix Wraith blueprint — R-9 style hovering nose / biomechanical tracked claw rig (reversible)

Shape authority: `godot/assets/vehicles/r-type.jpg` (copy `references/r-type.jpg`, packed in the .blend).
The sheet is a bi-directional "R-type inspired" ship. End A (+X) is the sleek hovering interceptor: lofted
fuselage, two glazed canopies, swept delta wings, twin nacelles with cyan lenses, wing-tip weapon pods with twin barrels.
End B (-X) is the heavy biomechanical rig: a segmented chitin carapace (eight overlapping bone plates over a dark
spine), bulbous shoulder lobes with slatted radiator fins, tendon cords, twin serrated pincer claws per flank,
four ribbed conduits per flank sweeping into the collar, and an armoured sponson over each caterpillar track.
Nothing is reused from other vehicles' artwork (only generic primitives of the proven Boilerfang fork,
baseline commit `8f03f5e`; review scope is the delta against it).

## Outputs
| Item | Path |
| --- | --- |
| Native source | `blender/helix_blueprint.blend` |
| Idempotent builder | `blender/build_helix.py` (+ `helix_{trace,core,prims,body,organic,tracks,details,export,qa}.py`) |
| Validator / rebuild check / LOD renders / reference crops | `blender/validate_helix.py`, `check_helix_idempotence.py`, `render_helix_lods.py`, `helix_refcrop.py` |
| Gameplay GLB / LOD1 / LOD2 | `godot/assets/vehicles/models/helix/helix_blueprint.glb`, `lod/helix_blueprint_LOD{1,2}.glb` |
| QA json / build metadata (`handoff`) | `.../helix/helix_blueprint_qa.json`, `_build.json` |
| Renders, overlays, LOD renders, reference crops | `qa/helix_blueprint/*.png`, `qa/helix_ref/*.png` |

## Rebuild
```sh
export BLENDER_BIN=/usr/bin/blender PYTHONPATH=$HOME/.cache/ak-pylibs
ak-blender tools/vehicle_pipeline/blender/build_helix.py -- --no-renders      # --no-export, --views=a,b
ak-blender tools/vehicle_pipeline/blender/validate_helix.py tools/vehicle_pipeline/blender/helix_blueprint.blend
cp tools/vehicle_pipeline/blender/helix_blueprint.blend /tmp/build_a.blend    # then rebuild in a new process
ak-blender tools/vehicle_pipeline/blender/check_helix_idempotence.py /tmp/build_a.blend -- tools/vehicle_pipeline/blender/helix_blueprint.blend
ak-blender tools/vehicle_pipeline/blender/render_helix_lods.py
```

## Contract
- Axes: hovering nose **End A +X**, claws/tracks **End B -X**, +/-Y width, +Z up, ground z=0; runtime yaw +90 deg, offset y -0.62.
  Uniform scale 0.0080128 m/px from the **overall side-elevation length** (claw tips px 226 to nose tip px 850 = 5.0 m):
  the sheet has no usable wheelbase. Length -2.47..2.50 m, width 1.61 m over the sponsons, height 1.22 m (carapace crown).
- **No wheels are authored.** The sheet has a wheel-less hovering nose and tracks under End B. The four physical wheels stay
  authoritative for gameplay; the game adapter hides their visuals/axles. Nothing is named `Wheel_*`, `*_Tire_*` or has a hub.
- **Tracks** (decorative body nodes, no physics), per flank `+1/-1`, track centre y = +/-0.625, width 0.30 m:
  `Prop_Track_Belt_*`, `Prop_Track_Cleats_*` (62 pads + guide horns, tips touch z=0), `Prop_Track_SprocketRear_*`,
  `Prop_Track_SprocketFront_*` (14 teeth, bolted hubs), `Prop_Track_Rollers_*` (3), `Prop_Track_Bogie_*` (pivots, swing arms,
  frame bar). 12 objects, 6,424 triangles, present and identical in every LOD. Sprocket axles x -1.490 / -0.753 at z 0.168,
  cleat radius 0.168, loop x -1.659..-0.585 (sheet px 334..467), flat contact patch x -1.516..-0.733 at z=0 (`handoff.track_contact`).
- Materials: semantic `Helix_Paint` (steel blue airframe), `Helix_Secondary` (bone carapace, claws, collar, fenders),
  `Helix_Stripe` (hull nose stripe, wing tips, pod bands); fixed `Helix_Rubber` (belts, hoses, tendons), `Helix_Glass`,
  `Helix_Hardware` (sprockets, cleats, flanges, dark inter-segment flesh), `Helix_Light` (lenses, sensor blister).
- Prefixes: `Body_*` main masses (Hull, Plate_0-7, Collar, Maw, Fender_*, Shoulder_*, Wing_*, Nacelle_*, Pod_*, Claw{Up,Low}_*,
  Hose{0-3}_*, Tendon{0,1}_*), `Glass_*` + `Frame_*`, `Fine_*`/`Trim_*` small hardware (merged by material in LODs), `Prop_Track_*`.
- LODs: LOD1 drops teeth, gills, slots, flanges, bolts and decimates body masses to ~60 %; LOD2 drops all other `Fine_`
  parts except lenses and decimates to ~35 %. Thin paint-channel bands (stripes) are split into separate undecimated objects so
  the Stripe channel survives. Claws, hoses, canopies and tracks are present in all LODs.

## Interpretation of source ambiguities
- Side and top views are proportion authority; the front elevations only place features (lens positions, vents, claw cant).
- The sheet's upper side silhouette is the glass, so the hull line under each canopy is lowered by the dome rise (18 px aft, 14 px forward).
- Claw pairs read as vertically opposed in the side view and splayed in the top view: built as upper + lower serrated jaw per
  flank, tips at y +/-0.34 (top-view 44 px), vertical jaw gap 0.51 m.
- The inner "nacelle" lenses (front A, 43 px off-centre) are twin nacelles on the fuselage flanks; the outer lenses are the pod noses.
- The rear mid-body hoses (4-5 per side) are built as four per flank; the bogie interior (pivots, 3 rollers) is read from
  ak-look crops (+/-2 px) and simplified to the visible parts.
- Fins are splayed radiator slats on the shoulder lobes (not the sheet's exact count); tendon cords are authored cable ribs.

## Numeric gates (`validate_helix.py`, 39 checks)
No `Wheel_*`/tyre/hub objects; every object in a legal group; all 12 track parts; closed positive-volume masses; whole-assembly
mirror symmetry (<1.5 mm); length/width/height vs sheet; top silhouette vs traced table (worst 7.3 px, mean 1.1 px), belly line
(<1 px), top-view hull half-width (<0.1 px); track contact z=0 within 2 mm, flat patch spans sprockets, loop extent vs sheet,
sprocket teeth 7 mm inside the belt, rollers 10 mm above it, fenders clear of the hull; ground clearance >= 180 mm; canopy glass
and bows buried >= 15 mm in the hull with no plan overhang; no part floats (<=8 mm to a neighbour); claws reach the sheet tip
with open jaws; pods, barrels and lenses at sheet positions; UVs; exact material set; triangle budget and LOD monotonicity;
GLB re-import (materials, tracks identical in all LODs, claws/hoses/canopies, envelope <=30 mm).
