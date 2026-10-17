# Boilerfang 88 blueprint — Victorian steam speedster / boiler off-road truck (reversible)

Shape authority: `godot/assets/vehicles/steam-punk.jpg` (copy at `references/steam-punk.jpg`, packed in the .blend).
End A (+X) is the ornate speedster: pointed iron prow with a brass shield grille, pontoon fenders over
narrow wire wheels, a three-pipe side exhaust bank, twin mushroom roof vents, raked split windshield.
End B (-X) is the heavy truck: copper boiler barrel with riveted brass bands, steam dome + gauge, tall
flared smokestack, smokebox door, twin brass headlamps on arms, cowcatcher plow on a push frame, and
spiked knobby wheels under arch mudguards. The high curved cab roof carries three brass skylight hatches
and steps down through the cockpit into the speedster hood. Not a car-body palette swap: nothing is
reused from Ramjet/Nightshift/Deadbolt/Blackjack artwork (only the generic primitives of the proven fork).

## Outputs
| Item | Path |
| --- | --- |
| Native source | `blender/boilerfang_blueprint.blend` |
| Idempotent builder | `blender/build_boilerfang.py` (+ `boilerfang_{trace,core,prims,forms,body,cab,machinery,details,wheels,export,qa}.py`) |
| Validator / rebuild check / LOD renders / reference crops | `blender/validate_boilerfang.py`, `check_boilerfang_idempotence.py`, `render_boilerfang_lods.py`, `boilerfang_refcrop.py` |
| Gameplay GLB | `godot/assets/vehicles/models/boilerfang/boilerfang_blueprint.glb` |
| LOD1 / LOD2 | `.../boilerfang/lod/boilerfang_blueprint_LOD{1,2}.glb` |
| QA json / build metadata | `.../boilerfang/boilerfang_blueprint_qa.json`, `_build.json` (`handoff` block) |
| Renders, overlays, LOD renders, reference crops | `qa/boilerfang_blueprint/*.png`, `qa/boilerfang_ref/*.png` |

## Rebuild
```sh
export BLENDER_BIN=/usr/bin/blender PYTHONPATH=$HOME/.cache/ak-pylibs    # numpy for glTF export
ak-blender tools/vehicle_pipeline/blender/build_boilerfang.py -- --no-renders   # --no-export, --views=a,b
ak-blender tools/vehicle_pipeline/blender/validate_boilerfang.py tools/vehicle_pipeline/blender/boilerfang_blueprint.blend
cp tools/vehicle_pipeline/blender/boilerfang_blueprint.blend /tmp/build_a.blend   # then rebuild in a new process
ak-blender tools/vehicle_pipeline/blender/check_boilerfang_idempotence.py /tmp/build_a.blend -- tools/vehicle_pipeline/blender/boilerfang_blueprint.blend
ak-blender tools/vehicle_pipeline/blender/render_boilerfang_lods.py
```

## Contract
- Axes: speedster **End A +X**, truck **End B -X**, +/-Y width, +Z up, ground z=0; runtime yaw +90 deg, offset y -0.62.
  Body X -2.571..2.377, width 1.61 over the truck tyre studs, height 1.53 (stack). Uniform scale 0.0071008 m/px from the
  side-elevation wheel centres (px 348 / 824 = 3.38 m wheelbase).
- Wheels (the four physical wheels stay authoritative; these are visual): `Wheel_Truck_*` (End B) and
  `Wheel_Coupe_*` (End A, the speedster; the prefix is the shared vehicle-pipeline name for End A). One `_Tire_` object per
  wheel; every part's origin is the hub. Hubs: End A x +1.66, y +/-0.50, z 0.256; End B x -1.72, y +/-0.66, z 0.348.
  **Display radii (blueprint-derived, visual only): A 0.256, B 0.348**; display half-tracks A 0.50, B 0.66
  (`handoff.display_radii`, `handoff.display_half_track`). Truck wheel: tyre + rim + hub + 8 cast spokes, 22 radial studs and
  14 sidewall studs. Speedster wheel: tyre + rim + hub + 36 laced wire spokes (one object).
- Central mid-drive (decorative, body-mounted, **not** wheels, no physics): per flank `Prop_MidDrive_Flywheel_<+1|-1>`
  (centre x 0.346, y +/-0.55, z 0.291, R 0.178), `Prop_MidDrive_Belt_*`, `Prop_MidDrive_Guard_*`,
  `Gear_MidDrive_Pulley_*`, `Gear_MidDrive_Pinion_*`, `Gear_MidDrive_Shaft_*`. They give the six-circle side silhouette
  (4 wheels + 2 flywheels) with no extra physical wheel.
- Materials: semantic `Boilerfang_Paint` (green), `Boilerfang_Secondary` (cream), `Boilerfang_Stripe` (oxblood); fixed
  `Boilerfang_Brass`, `_Copper`, `_Iron`, `_Glass`, `_Rubber`, `_Dial`, `_Lamp`, `_Amber`.
- Object prefixes: `Body_*` main masses, `Glass_*`, `Frame_*` (glass retainers), `Trim_*`, `Fine_*` (small hardware; LOD2 drops them
  except lamps), `Wheel_*`, `Prop_MidDrive_*`, `Gear_*`. LODs merge `Trim_/Fine_` by material into `Detail_<material>`.

## Interpretation of source ambiguities
- Middle flywheel housing is drawn longer/stepped on one flank in the top view: built as a **mirrored pair** (the side view
  fixes the flywheel at (639,244) r25 px, belt tangents to a pulley at (583,241) r10 px).
- Front A twin roof domes: two symmetric brass mushroom vents on the cockpit roof, 0.16 m either side of centre.
- Front B vertical side tubes and the lower-side stack seen in the top view: the sheet's front/top views disagree on scale and
  placement, so side/top proportions rule: one central stack on the boiler (front B and side view agree), paired tanks and
  cylinders at the flanks. The front elevations were used only for feature placement (lamps, domes, track).
- Windows: flush glass slabs seated 2 mm off flat flank/slope panels inside brass frames (no Boolean cuts).

## Numeric gates (`validate_boilerfang.py`, 44 checks)
Main masses closed and positive-volume; whole-assembly mirror symmetry; silhouette top/sill/half-width vs the traced tables
(px); overall length/height; four wheels, one `_Tire_` each, origins at hubs, tyre radius = display radius, ground contact,
fender clearance >= 30 mm, hull clearance, rims inside tyres; mid-drive pieces present, paired, never `Wheel_*`, matching the
trace; glass seated 0.5-7 mm, never crossing the shell, covering every sampled interior point of each opening; no hardware pierces
glass or wheels; no floating hardware (12 mm); every lamp lens vertex within 6 mm of its housing; UV and exact material set;
triangle budget and LOD monotonicity; GLB re-import counts, materials, hubs, mid-drive preservation, LOD envelope and tyre
radius.
