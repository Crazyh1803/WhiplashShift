# City street kit

Eight small reusable static models for the finished Block Circuit block, built at the approved habitation-workshop quality bar
and consumed by the street-block builder. Output: `godot/assets/city/streets/<id>.glb` plus `street_kit_manifest.json`
(`version` 1, `assets[]`).

All: metres, one static mesh per file, foot-centred (xz footprint centre at the origin, lowest point at y=0), Godot -Z front,
<= 8 shared semantic materials (`steel`, `ceramic`, `cavity`, `machinery`, `sinew`, `glow_cyan`, `glow_amber`, `trim`), flat
normals, real `COLOR_0` grime / scuffs / repair tints. No lights, cameras, collision, animation or extras. No mid/far LODs exist.

| id | measured size x / y / z (m) | tris / cap | surfaces (manifest order) | read |
|---|---|---|---|---|
| `sidewalk_panel` | 6.00 / 0.18 / 4.00 | 366 / 450 | steel, ceramic, cavity, machinery, trim | six inset chamfered slabs on a dark sub-base with settled heights, hairline cracks, bolted expansion strip, bright replacement slab with a teal service plate, tactile studs along the kerb edge |
| `curb_segment` | 6.00 / 0.22 / 0.22 | 118 / 180 | ceramic, cavity, trim | four 1.5 m chamfered kerb stones with cut joints, faded ochre hazard dashes, chips |
| `drain_cover` | 1.20 / 0.066 / 0.70 | 184 / 300 | steel, cavity, machinery, trim | flanged cast frame, eleven slotted bars over a sump, four bolts |
| `street_lamp` | 0.60 / 7.88 / 3.76 | 702 / 1600 | steel, ceramic, cavity, machinery, glow_cyan, glow_amber, trim | octagonal plinth with service hatch, tapered pole with collars and riser conduit, gooseneck arm and hooded amber luminaire (+Y/front, over the road), balancing banner boom with a faded banner so the pole stays at the origin |
| `bollard` | 0.34 / 1.115 / 0.34 | 260 / 300 | steel, cavity, machinery, glow_cyan, glow_amber, trim | octagonal steel post, flange with anchor bolts, dome cap, glowing amber band, worn collar, dents, cyan pip |
| `bench_planter` | 3.81 / 1.50 / 1.20 | 852 / 1800 | steel, ceramic, machinery, glow_cyan, glow_amber, trim | slatted bench with backrest/armrests and under-seat cyan strip beside a raised planter (rim, bolt rows, soil, drip line, tree and ground cover) |
| `refuse_station` | 3.00 / 2.20 / 1.50 | 936 / 1800 | steel, ceramic, cavity, machinery, glow_cyan, glow_amber, trim | open-fronted sorting shelter: floor plate, posts, back wall with A/B/C chutes, canopy with drip lip, three wheeled bins (oxide, teal, gray), indicators, tag |
| `alley_conduit` | 8.00 / 4.50 / 1.01 | 1442 / 1800 | steel, cavity, machinery, glow_cyan, glow_amber, trim | three braced portal frames carrying two large and one small flanged pipe on strap hangers, a cable tray with sagging cables, junction box with amber/cyan lights, hazard tag |

Exact surfaces, bounds, footprints, tris and provenance are in the manifest (measured from the built mesh, not copied from this
table). Kit total 4,860 tris. `front_setback_m` is the front half-depth of the footprint (every model is foot-centred).

## Limits that matter downstream
- Panel <= 450 and curb <= 180 triangles so they can be batched many times along the block; every other model has its own cap
  (validator table). The lamp's amber lens is an emissive material only; the block builder adds any real lights (budget <= 8).
- Placement: lamp arm points to +Y (Godot -Z front); plan for the arm to face the road. Bench/planter, refuse station and
  conduit are symmetric about their footprint centres, drain and panel are flat decals-in-geometry sitting on the paved plane.
- Heights above 0.18 m for the panel/drain are fixed; the block builder raises paving by 0.18 m, so place drains at the paved
  level.

## Files
- `build_city_streets.py` - builder. Imports the workshop module by path (never edited) and reuses Kit, colour, materials,
  export and Studio helpers. Adds `street_grime` (positional mottling plus gutter dirt on COLOR_0, idempotent), `slab`, `plant`,
  `crack`. Models register with `@street(...)`; `main()` builds each from a clean scene, **exports the GLB before
  `wire_vertex_colors`**, writes `qa.json`, saves the source `.blend`, then renders.
- `validate_city_streets.py` - stdlib validator (runs through `ak-test`): reuses the workshop validator's GLB decoder
  and checks at each ID's own cap, then NORMAL decoding (unit length, count), plan dimensions with per-model tolerance, ordered
  semantic surfaces, minimum detail, path hygiene, no extras, provenance files, >= 2 preview images, byte-distinct GLBs.
- Sources and QA: `assets/generated/city_streets/<id>/{<id>.blend,qa.json}`. Views: `assets/previews/city_streets/<id>/*.png`
  (3-4 neutral studio views each incl. a 1.75 m non-runtime reference figure).

## Build
```
ak-blender tools/city_pipeline/build_city_streets.py -- [--no-render] [--size 1.0] [--only a,b] [--only-shots x,y]
python tools/city_pipeline/validate_city_streets.py
```
`--size` is a resolution **scale** (0.25-2.0), never pixels; anything else fails fast. `--only` rebuilds a subset and merges
into the existing manifest. Author every `Kit.box` with ordered (min, max) bounds: reversed extents are silently dropped.
The builder also fails if a measured size misses the plan table or a model exceeds its cap.
