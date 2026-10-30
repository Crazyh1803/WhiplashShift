# City realism library (candidate, not promoted)

Eight street-building families (+LOD1) and eight street pieces in the approved worn-industrial style, built for the frozen contract in
`.ai/plans/city-realism-conversion.md`. Nothing in the skyline, old kit/streets/neighborhood, benchmark, vehicles or Godot runtime was touched
(the manifest records sha256 of the legacy files and the validator re-checks them).

## Outputs
| Path | What |
|---|---|
| `godot/assets/city/realism/<id>.glb`, `<id>_lod1.glb` | 8 buildings (LOD0 + LOD1) and 8 street pieces (LOD0). One static mesh each, no cameras/lights/animation/colliders |
| `godot/assets/city/realism/textures/*.png` | shared PBR library: 14 materials, 39 images, bound by exact material name (`extras.library_binding`) from the manifest library; runtime GLBs are geometry-only with no images/textures/samplers. Full textured exports are kept in `assets/generated/city_realism/textured_exports/` (`city_realism_bind.py convert` re-derives the pair) |
| `godot/assets/city/realism/city_families_manifest.json` | version 2: library, per-asset tris/AABB/footprint/protrusions/entrances/light anchors/ordered surfaces/costs |
| `assets/generated/city_realism/` | source textures, `.blend` per asset, `build_records.json` |
| `assets/previews/city_realism/` | re-imported GLB renders: `<id>_{front,street,night}.png`, `lineup_buildings{,_b}_{neutral,night}.png`, `lineup_streets_{neutral,night}.png` |

## Rebuild
```
ak-blender tools/city_pipeline/build_city_families.py [-- --only id,id --skip-tex --manifest-only]
ak-blender tools/city_pipeline/city_realism_preview.py -- --set all|assets|lineups
ak-blender tools/city_pipeline/build_city_families.py -- --manifest-only      # refresh preview lists
ak-blender tools/city_pipeline/validate_city_families.py                       # or: python ...validate_city_families.py
```

## Conventions
- glTF Y-up, metres, front faces -Z. Buildings: origin front-centre foot (facade plane z=0, lot extends to +Z). Streets: foot-centred (as the old kit).
- Frontage 12/18/24 m, depth <= 22, height <= 18. AABB includes protrusions; `protrusions` and `front_setback_m` (= front protrusion + 0.3, rounded up) are measured.
- Materials (library, `emission_whitelist` = `sign_atlas`, `lamp_glass` only): steel_structure, cladding_corrugated, cladding_patch, concrete, brick, render_plaster, roof_membrane,
  paving, equipment_steel, glass_window, fabric_awning, plastic_rubber, sign_atlas, lamp_glass. Foliage colour is carried in COLOR_0 on render_plaster.
- Textures: albedo/ORM/normal 512 px (ORM R=occlusion, G=roughness, B=metallic; normals OpenGL +Y); sign_atlas albedo + emissive 1024, ORM 512, no normal. 39 images, 60 MiB with mips (RGBA8, no compression).
- Vertex data: TEXCOORD_0 = world-projected box UV (tiles per metre in `uv_per_m`; atlas tiles explicit for signs), COLOR_0 = AO x wear (splash band, rain streaks, use-point grime, polished contacts, sun fade). TANGENT is computed and written by the build (Blender 5.2 does not export it): t = dP/du, bitangent = cross(n, t) * w follows increasing exported V (unmirrored +X/-V quad with +Z normal: w = -1; mirrored U: w = +1).
- Sockets (glTF coordinates): `entrances` (kind, position, width, height), `light_anchors` (street / fixture / shop_spot / sign / window / service with direction, colour, range, energy hint, shadow flag; data only).
- `redline_shop.actor_sockets` (glTF coordinates, shop frame): `vendor`/`customer` `position` = floor point between the actor's feet (the actor GLB origin), `yaw_degrees` about +Y (vendor 0 faces the street, customer 180), same convention as benchmark_manifest placements. Both stand on a 0.15 m floor (kitchen floor + customer apron), `counter_top_y` 1.2 (1.05 m above the feet), `bowl` = hand-off point, `light` = the `service` light anchor aimed at it. Vendor works in a 1.5 m bay of the counter. Closeups with the real actor GLBs: `ak-blender tools/city_pipeline/city_realism_actor_shots.py` -> `assets/previews/city_realism/redline_shop_actors_*.png`.
- Sign text is a mundane word list drafted with ak-qwen; one letter is dead on a few signs on purpose (e.g. GAR GE).

## Measured costs
Building LOD0 tris: habitation_workshop 18,704; market_habitat 19,358; service_tenement 15,978; freight_depot 18,314; redline_shop 9,888; row_workshop 10,076;
utility_substation 11,342; transit_depot 14,842 (sum 118,502). LOD1 332-860 tris each, 3 surfaces. Streets 6,474 tris total (bench_planter 1,236 ... bollard 312). Unique source geometry 124,976 tris.
GLB sizes 0.8-1.8 MB (LOD0), 31-56 KB (LOD1). Shared textures 60.0 MiB regardless of instance count. LOD0 surface counts 10-13 per building.

## Limitations
Procedural numpy textures; box-projected UVs repeat on very large faces; no real interiors (dark hulls behind windows, short tunnels at depot bays, a hollow kitchen in redline_shop);
vertex wear is per vertex on 1.7-8 m cells (sloped roofs unrefined); LOD1 is a three-material massing proxy; chain-link/gates are thin geometry that reads from a distance only as mesh;
the preview lighting is Blender-diagnostic. `redline_shop` is a new lower-cost conversion, the approved benchmark stays separate. Human art approval is pending.
