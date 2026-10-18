# Knifeedge XR blueprint — supercar nose / sand-rail spaceframe (reversible)

Shape authority: `godot/assets/vehicles/hot-wheels.jpg` (copy at `references/hot-wheels.jpg`, packed in the .blend).
End A (+X) is the wedge supercar nose: V-creased hood with two triangular vents, angled LED slits, side intakes, splitter,
open wheel arches over 10-spoke alloys with calipers. The cabin is an open orange roll cage with a windshield, two roof glass
panels, bucket seats and a five-pod light bar. End B (-X) is the sand-rail tail: triangulated tube truss, sloped louvred
deck, exposed rear engine / transaxle / muffler, coilover shocks on A-frame towers, wishbones, driveshafts, a quad-lamp
tail plate with mesh grille, winch and tubular bumper hoop, on knobby beadlock wheels. Nothing is reused from other
vehicles' artwork (only the generic primitives of the proven fork, baseline commit `24acb29`).

## Outputs
| Item | Path |
| --- | --- |
| Native source | `blender/knifeedge_blueprint.blend` |
| Idempotent builder | `blender/build_knifeedge.py` (+ `knifeedge_{trace,core,prims,forms,body,cage,mech,details,wheels,export,qa}.py`) |
| Validator / rebuild check / LOD renders / reference crops | `blender/validate_knifeedge.py`, `check_knifeedge_idempotence.py`, `render_knifeedge_lods.py`, `knifeedge_refcrop.py` |
| Gameplay GLB | `godot/assets/vehicles/models/knifeedge/knifeedge_blueprint.glb` |
| LOD1 / LOD2 | `.../knifeedge/lod/knifeedge_blueprint_LOD{1,2}.glb` |
| QA json / build metadata | `.../knifeedge/knifeedge_blueprint_qa.json`, `_build.json` (`handoff` block) |
| Renders, overlays, LOD renders, reference crops | `qa/knifeedge_blueprint/*.png`, `qa/knifeedge_ref/*.png` |

## Rebuild
```sh
export BLENDER_BIN=/usr/bin/blender PYTHONPATH=$HOME/.cache/ak-pylibs
ak-blender tools/vehicle_pipeline/blender/build_knifeedge.py -- --no-renders   # --no-export, --views=a,b
ak-blender tools/vehicle_pipeline/blender/validate_knifeedge.py tools/vehicle_pipeline/blender/knifeedge_blueprint.blend
cp tools/vehicle_pipeline/blender/knifeedge_blueprint.blend /tmp/build_a.blend   # then rebuild in a new process
ak-blender tools/vehicle_pipeline/blender/check_knifeedge_idempotence.py /tmp/build_a.blend -- tools/vehicle_pipeline/blender/knifeedge_blueprint.blend
ak-blender tools/vehicle_pipeline/blender/render_knifeedge_lods.py
```

## Contract
- Axes: supercar **End A +X**, sand rail **End B -X**, +/-Y width, +Z up, ground z=0; runtime yaw +90 deg, offset y -0.62.
  Body X -2.530..2.692 (5.22 m), width 2.24 m over the truck tyres, height 1.756 m (light bar). One uniform scale
  0.011155 m/px from the side-elevation wheel centres (px 360.5 / 663.5 = 3.38 m wheelbase).
- Wheels (the four physical wheels stay authoritative; these are visual): `Wheel_Truck_*` (End B) and `Wheel_Coupe_*` (End A;
  `Coupe` is the shared End-A prefix). One `_Tire_` object per wheel; every part's origin is the hub.
  End A hub x +1.66, y +/-0.90, z 0.390; End B hub x -1.72, y +/-0.93, z 0.446.
  **Display radii: A 0.390, B 0.446; display half-tracks A 0.90, B 0.93** (`handoff.display_radii`, `display_half_track`).
  Truck wheel (14 parts): tyre, rim, hub (boss + 16 beadlock bolts) and 6 spokes. Coupe wheel (15 parts): tyre, rim, hub,
  10 spokes, brake rotor, caliper. 48 wheel objects in all, identical in every LOD.
- Decorative machinery (body-mounted, **not wheels**, no physics): `Prop_Engine_{Block,Head_*,Barrel_*}`, `Prop_Transaxle(_Bell)`,
  `Prop_Exhaust_{Muffler,Header_*,Tailpipe}`, `Prop_Upright_*` (15 objects, preserved in all LODs).
- Materials: semantic `Knifeedge_Paint` (blue shell), `Knifeedge_Secondary` (ice white), `Knifeedge_Stripe` (orange cage); fixed
  `Knifeedge_Glass`, `_Rubber`, `_Steel`, `_Iron`, `_Lamp`.
- Prefixes: `Body_*` main masses (shell, floor, deck, tail plate, splitter, `Body_Cage*` tube groups), `Glass_*`, `Trim_*`/`Fine_*`
  hardware (merged into `Detail_<material>` in the GLBs), `Prop_*`, `Wheel_*`.

## Interpretation of source ambiguities
- Wheel radii/centres: the first and second ak-look reads disagreed (r 39 vs 44 px); the thresholded top-view tyre extents
  (x 320..401 / 628..696) decided: B r 40 px, A r 35 px.
- Track: the end elevations are drawn at a different scale; the top view (tyres outer +/-98 px) rules. A half-track 0.90 sits in the
  fender shell (+/-1.07 m).
- Roof light bar: the top-view text read put it at x 450..471, but a pixel scan shows the 5-pod bar at x 556..572 on the windshield
  header (matches the side view); lamps face End B as in the end-B elevation.
- Rear quarter: the diagonal "door" cutline (459,113)->(490,162)->(452,186) is a real cut of the shell so the engine shows behind it.
- The sheet draws a steering wheel in the end-B elevation on one seat: kept as the only asymmetric part.
- Wing tips seen behind the cabin in the end-A elevation are not placed (no counterpart in the side/top views).

## Numeric gates (`validate_knifeedge.py`, 47 checks)
Masses closed/positive volume; whole-assembly mirror symmetry (exempt: steering wheel + column, helical shock springs which are
chiral, and the badge on the tessellated hood crease); shell top/sill/half-width vs the traced tables (px); overall length, height,
cage roof, tail hoop; four wheels, one `_Tire_` each, hub origins, tyre radius, ground contact; supercar tyres outside the solid
shell (no surface overlap, ray-parity inside test) with >= 50 mm arch clearance; suspension clear of truck tyres; nothing but axles
touches a wheel; glass seated in cage tubes, never crossing or touching the shell, full ray coverage of roof and windshield; no
floating parts (12 mm); lamps on housings; UV and exact material set; triangle budget and LOD monotonic; GLB re-import counts,
materials, props, wheel parts, envelope, hubs and tyre radius.
