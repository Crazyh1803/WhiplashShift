# Deadbolt hard-surface candidate

Replaces the rounded, globally smoothed `deadbolt_blueprint` draft (kept untouched under its
own filenames) with a traced, hard-surface rebuild of the `80sFord.jpg` reversible vehicle:
upright 1980s Ford truck nose at source -X, low Fox-body Mustang nose at source +X.
Method follows Blackjack (station-traced mirrored cage with support loops and creases, real
Boolean arches and recesses, seated glass, modular lamps/guards, lathed wheels) but is a
fresh Z-up, X-long implementation with no module side effects.

## Outputs

| Item | Path |
| --- | --- |
| Native source (editable) | `blender/deadbolt_hardsurface.blend` |
| Idempotent builder | `blender/build_deadbolt_hardsurface.py` (+ `deadbolt_hardsurface_*.py` modules) |
| Gameplay GLB | `godot/assets/vehicles/models/deadbolt/deadbolt_hardsurface.glb` |
| LOD1 / LOD2 | `godot/assets/vehicles/models/deadbolt/lod/deadbolt_hardsurface_LOD{1,2}.glb` |
| Validation report | `godot/assets/vehicles/models/deadbolt/deadbolt_hardsurface_qa.json` |
| Build / handoff metadata | `godot/assets/vehicles/models/deadbolt/deadbolt_hardsurface_build.json` |
| QA renders + blueprint overlays | `qa/deadbolt_hardsurface/*.png` |

## Rebuild

Blender 4.0.2 is what is installed here. Its glTF exporter needs numpy, which the distro
Blender lacks; point `PYTHONPATH` at any numpy install (here `~/.cache/ak-pylibs`).

```sh
export BLENDER_BIN=/usr/bin/blender PYTHONPATH=$HOME/.cache/ak-pylibs   # numpy for glTF export
ak-blender tools/vehicle_pipeline/blender/build_deadbolt_hardsurface.py            # --no-renders / --no-export
ak-blender tools/vehicle_pipeline/blender/validate_deadbolt_hardsurface.py \
    tools/vehicle_pipeline/blender/deadbolt_hardsurface.blend
python3 tools/vehicle_pipeline/blender/check_deadbolt_idempotence.py qa_a.json qa_b.json
```

## Construction

* `deadbolt_hardsurface_trace.py`: pixel tables measured from the sheet (column edge scans);
  one uniform scale from the wheel centres (321 px = 3.38 m, 0.01053 m/px); drawing lifted
  0.051 m so the drawn axle line meets the physical 0.43 m axle.
* `..._shell.py`: 54 stations x 15-vertex half rings, mirrored, subsurf level 1, crease
  weights on rocker/belt/roof rails, flat planar end caps. Lower rocker panel is inset 8 mm.
* `..._cuts.py` / `..._cabin.py`: exact-Boolean cutters, axis-parallel depth: wheel arches,
  side-window and windshield recesses (16 mm deep, black seal border), lamp/grille/intake
  pockets, door/hood/rocker shut-line grooves, handle pockets, hood vents, cowl vents. Every
  cutter is asserted closed with outward normals before the Boolean. Glass is projected onto
  the cut recess floor 4.5 mm off it.
* `..._details.py`: truck egg-crate grille, sealed-beam lamps, bezels, chrome bumper,
  push-bar, plate; coupe wraparound lamps, grille slot, intake, fog lamps, splitter; mirrors,
  handles, wipers, markers, fender lips, rocker mouldings.
* `..._wheels.py`: truck 6-slot steel wheel (9 meshes per wheel), coupe 10-spoke turbine
  wheel (13 meshes per wheel), block/ribbed tread, rotor, caliper, lug nuts.
* `..._export.py`: merges small details per material for export, builds LOD1/LOD2, renders.

## Contracts kept

Source axes X long / Y width / Z up; wheel hubs (coupe 1.66, truck -1.72, y +/-0.91, z 0.40 /
0.43); tyre 0.80 / 0.86 m dia and 0.29 / 0.34 m wide; mesh prefixes `Wheel_Coupe_*` /
`Wheel_Truck_*` with origins at the hubs; materials `Deadbolt_Paint`, `Deadbolt_Secondary`,
`Deadbolt_Stripe` plus protected glass/rubber/metal/lamp materials. Verified by swapping the
catalog scene path in a throw-away copy of the project: `consolidation_tests` 59/59.

## Known limits

* Numbers prove geometry contracts only; the visual verdict comes from renders (ak-look).
* The cabin is a solid body under dark glass (no modelled interior).
* The wheel track is fixed by the physics (outer tyre face 1.08 m) so tyres stand about 7 cm
  proud of the 1.01 m flared fenders, wider than the drawing shows.
* The model is 5.33 m long, 2.23 m wide, 1.82 m high (the draft was ~5.16 x 2.06 x 1.65):
  the traced truck cab is 1.8 m tall and the coupe nose overhangs the front wheel by 1.08 m.
  Garage/preview camera framing may need a look.
* Booleans are not bit-reproducible: rebuilds agree to micrometres and topology; LOD triangle
  counts can differ by one.
