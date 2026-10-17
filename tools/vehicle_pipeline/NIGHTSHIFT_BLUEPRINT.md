# Nightshift blueprint — Chevy square-body truck / Camaro reversible

Shape authority: `godot/assets/vehicles/80s.jpg` (copy at `references/80s.jpg`, packed in the .blend).
Truck end (End B) at source -X: tall boxy hood, egg-crate grille + bowtie, stacked dual rectangular
lamps, chrome wrap bumper, twin vertical push guards. Camaro end (End A) at +X: low wedge nose,
recessed quad rectangular lamps, grille slot, air dam, chin spoiler, louvered hood vents. The
truck cab roof (≈1.60 m) steps down to the Camaro roof (≈1.30 m) through a vertical wall with a
cab-back window. Built from forked Deadbolt methods (`nightshift_*.py`); Deadbolt files are untouched.

## Outputs
| Item | Path |
| --- | --- |
| Native source | `blender/nightshift_blueprint.blend` |
| Idempotent builder | `blender/build_nightshift.py` (+ `nightshift_*.py`) |
| Validator / rebuild check | `blender/validate_nightshift.py`, `blender/check_nightshift_idempotence.py` |
| Gameplay GLB | `godot/assets/vehicles/models/nightshift/nightshift_blueprint.glb` |
| LOD1 / LOD2 | `godot/assets/vehicles/models/nightshift/lod/nightshift_blueprint_LOD{1,2}.glb` |
| QA json / build metadata | `.../nightshift/nightshift_blueprint_qa.json`, `_build.json` |
| Neutral renders + blueprint overlays | `qa/nightshift_blueprint/*.png` |

## Rebuild
```sh
export BLENDER_BIN=/usr/bin/blender PYTHONPATH=$HOME/.cache/ak-pylibs   # numpy for glTF export
ak-blender tools/vehicle_pipeline/blender/build_nightshift.py            # --no-renders / --no-export
ak-blender tools/vehicle_pipeline/blender/validate_nightshift.py tools/vehicle_pipeline/blender/nightshift_blueprint.blend
cp tools/vehicle_pipeline/blender/nightshift_blueprint.blend /tmp/build_a.blend   # then rebuild
ak-blender tools/vehicle_pipeline/blender/check_nightshift_idempotence.py /tmp/build_a.blend -- tools/vehicle_pipeline/blender/nightshift_blueprint.blend
```

## Contract
Axes: coupe +X, truck -X, ±Y width, +Z up. Wheel meshes `Wheel_Coupe_*` (13 parts/wheel, 5-star
twin-line spokes, R 0.40) and `Wheel_Truck_*` (9 parts, steel rally disc, R 0.43); tire objects
contain `_Tire_` and every wheel part has its origin at the hub (coupe x 1.66, truck x -1.72,
visual y ±0.82). Semantic materials: `Nightshift_Paint`, `Nightshift_Secondary`, `Nightshift_Stripe`;
all other materials are fixed hardware/glass/rubber/lamps.

## Numeric gates
Shell closed manifold; mirror symmetry; silhouette top/sill/half-width vs trace; wheel names, counts,
radii, origins, tyre-under-fender, arch clearance ≥30 mm; glass seated and non-crossing; lamp lenses
within 35 mm of the cut shell; UV/material completeness; bounds derived from the authored trace
(body length/width/roof from `nightshift_trace.py` plus declared add-on allowances); GLB re-import
object/material/wheel counts; triangle budget and LOD monotonicity.
