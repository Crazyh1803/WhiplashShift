# Deadbolt — direct Blender blueprint build

Deadbolt is the `80sFord.jpg` reversible vehicle: an upright 1980s Ford truck
front joined to a low Mustang-derived front. This pass skips the intermediate
image-generation stages and authors the production candidate directly in Blender.

The model preserves the blueprint's main read at gameplay distance: square truck
grille and brush bar, low coupe lights and splitter, distinct wheel styles, the
high-to-low roof transition, paired mirrors, and a continuous underbody. Ten named
PBR materials and complete UV channels are included. The original blueprint is
packed into the native source and hidden from export/render.

The builder defaults to the portable reference at `references/80sFord.jpg`. Pass
an alternate source image after `--` only when deliberately retracing a variant.

## Outputs

- Native source: `blender/deadbolt_blueprint.blend`
- Idempotent builder: `blender/build_deadbolt_blueprint.py`
- Validator: `blender/validate_deadbolt_blueprint.py`
- Gameplay mesh: `../../godot/assets/vehicles/models/deadbolt/deadbolt_blueprint.glb`
- LOD1/LOD2 and QA artifacts: `../../godot/assets/vehicles/models/deadbolt/`

## Rebuild and verification

Set `BLENDER_BIN` to Blender 5.2.2, then run:

```sh
ak-blender tools/vehicle_pipeline/blender/build_deadbolt_blueprint.py
ak-blender export_glb tools/vehicle_pipeline/blender/deadbolt_blueprint.blend -- --out godot/assets/vehicles/models/deadbolt/deadbolt_blueprint.glb
ak-blender lod tools/vehicle_pipeline/blender/deadbolt_blueprint.blend -- --ratios 0.55 0.25 --outdir godot/assets/vehicles/models/deadbolt/lod
ak-blender preview tools/vehicle_pipeline/blender/deadbolt_blueprint.blend -- --out godot/assets/vehicles/models/deadbolt/deadbolt_blueprint_preview.png --size 512 --engine eevee
ak-blender tools/vehicle_pipeline/blender/validate_deadbolt_blueprint.py tools/vehicle_pipeline/blender/deadbolt_blueprint.blend
```

The validator enforces the source object/material counts, UV coverage, evaluated
triangle budget, bounds, ground clearance, wheel orientation, packed reference,
and existence of the exported GLBs and preview.
