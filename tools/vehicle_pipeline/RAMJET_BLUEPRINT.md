# Ramjet K-6 blueprint — Dodge Ram D150 truck / Dodge Conquest TSi reversible

Shape authority: `godot/assets/vehicles/dodge.jpg` (copy at `references/dodge.jpg`, packed in the .blend).
Truck end (End B) at source -X: upright boxy Ram hood, crosshair + egg-crate grille, single
rectangular sealed-beam lamps in chrome bezels, full-width chrome bumper with twin vertical
overriders and plate, raked tall cab with a long door window and a big chrome west-coast mirror.
Conquest end (End A) at +X: low wedge nose, closed pop-up headlamp doors outlined by shut lines,
power-bulge hood with a recessed scoop slot, bumper cover with fog/turn lamps and a wide lower
air dam (central intake, chin lip). The Ram cab roof (about 1.95 m) steps down through a sloped
wall with a cab-back window to the short Conquest roof (about 1.65 m). It is *not* a Charger or
Challenger. Built from a fork of the Nightshift methods (`ramjet_*.py`); Nightshift, Deadbolt and
Blackjack files are untouched.

## Outputs
| Item | Path |
| --- | --- |
| Native source | `blender/ramjet_blueprint.blend` |
| Idempotent builder | `blender/build_ramjet.py` (+ `ramjet_*.py`) |
| Validator / rebuild check / LOD renders | `blender/validate_ramjet.py`, `blender/check_ramjet_idempotence.py`, `blender/render_ramjet_lods.py` |
| Gameplay GLB | `godot/assets/vehicles/models/ramjet/ramjet_blueprint.glb` |
| LOD1 / LOD2 | `.../ramjet/lod/ramjet_blueprint_LOD{1,2}.glb` |
| QA json / build metadata | `.../ramjet/ramjet_blueprint_qa.json`, `_build.json` |
| Neutral renders, close-ups, overlays, LOD renders | `qa/ramjet_blueprint/*.png` |

## Rebuild
```sh
export BLENDER_BIN=/usr/bin/blender PYTHONPATH=$HOME/.cache/ak-pylibs    # numpy for glTF export
ak-blender tools/vehicle_pipeline/blender/build_ramjet.py                  # --no-renders / --no-export
ak-blender tools/vehicle_pipeline/blender/validate_ramjet.py tools/vehicle_pipeline/blender/ramjet_blueprint.blend
cp tools/vehicle_pipeline/blender/ramjet_blueprint.blend /tmp/build_a.blend   # then rebuild
ak-blender tools/vehicle_pipeline/blender/check_ramjet_idempotence.py /tmp/build_a.blend -- tools/vehicle_pipeline/blender/ramjet_blueprint.blend
ak-blender tools/vehicle_pipeline/blender/render_ramjet_lods.py            # gameplay/LOD1/LOD2 review renders
```
(`--shell-only` builds the shell, glass and wheels without hardware for silhouette work.)

## Contract
Axes: coupe +X, truck -X, +/-Y width, +Z up, ground z=0; runtime yaw +90 deg and offset y -0.62.
Wheel meshes `Wheel_Coupe_*` (13 parts/wheel: tire, rim, hub, 5 wide split spokes + 5 dark slot
inlays, R 0.40, W 0.35) and `Wheel_Truck_*` (11 parts: tire, rim, hub with hubcap ring and
beauty ring, 8 steel disc sectors, R 0.43, W 0.33). Tire objects contain `_Tire_` and every wheel
part has its origin at the hub (coupe x 1.66, truck x -1.72, visual y +/-0.86). The visual
half-track is 0.86 m, not Nightshift's 0.82: both front elevations put the tyre centres 75.5 px
(0.859 m) off the centre line. Physical wheels are unchanged. Semantic materials: `Ramjet_Paint`,
`Ramjet_Secondary`, `Ramjet_Stripe`; all other materials are fixed glass/lamp/hardware/rubber.

## Numeric gates (`validate_ramjet.py`)
Shell closed manifold; shell and whole-assembly mirror symmetry; silhouette top/sill/half-width vs
trace; wheel names, counts, radii, origins, tyre-under-fender, arch clearance >= 30 mm; glass
seated 0.5-6 mm off the shell, non-crossing, and covering every interior point of its window cut
(ray test against glass vs shell, so no see-through holes); mirrors/wipers/rails/trims never pierce
glass; every lamp, marker and reflector vertex within 35 mm (22 mm for thin markers) of the cut
shell and inside the envelope; *every* detail vertex inside an envelope derived from the authored
trace (nose stations, max half-width plus mirror allowance, roof height); UV/material completeness;
GLB re-import object/material/wheel counts; LOD envelope, wheels and paint channels preserved;
triangle budget 25k-45k and LOD monotonicity.
