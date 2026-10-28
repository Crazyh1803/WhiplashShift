# City kit (authored 3D)

Rebuild: `ak-blender tools/city_pipeline/build_city_kit.py -- [--no-render] [--only id,id] [--size 1100]`
QA: `python tools/city_pipeline/validate_city_kit.py` (also `ak-test` in this branch).

Outputs: `assets/generated/city_kit/city_kit.blend` (source), `godot/assets/city/kit/<id>.glb` + `city_kit_manifest.json`,
`assets/previews/city_kit/` (per-asset 3/4 renders, `_back` views, `board_landmarks|buildings|props.png`, `qa.json`).
`--only` still builds all 14 into the .blend but exports/renders/updates manifest entries for the listed ids only.

## Contract
- Blender +Z up, +Y front -> Godot +Y up, -Z front (facade). Metres, transforms applied, origin = footprint centre at y=0.
- One mesh, one node per GLB; no cameras/lights/collision/animation/textures/UVs. Normals baked (flat bevels, smooth cylinders).
- Surfaces are semantic material names only: steel, ceramic, cavity, machinery, sinew, glow_cyan, glow_amber, trim. Glow surfaces use emissive factor + `KHR_materials_emissive_strength` (2.0); other surfaces have no emission.
- Manifest `aabb`/`footprint` are in Godot axes and include cantilevers (aerials, canopies). `front_setback_m` = distance from the footprint's front edge to the primary facade plane.
- Props and buildings drop unused semantic names (see `REMAP`) so all 14 assets total 64 surfaces.

## Assets (tris / surfaces / dims W x H x D m)
Landmarks: relay_tower 11.9k/7/22.7x81.4x18.8, exchange_hall 10.5k/7/57.6x23.2x28.2, pump_citadel 10.4k/7/34.4x33.5x35.8.
Buildings: shutter_workshop 3.1k/5/18x12.3x16.5, utility_midrise 7.6k/5/14.8x31.5x14.9 (above the 5k target, under 8k cap), ribbed_stack 4.2k/6/12.7x38.2x12.7.
Props (200-2000): pipe_rack 1.5k, exhaust_stack 0.8k, service_cabinet 0.5k, transformer 1.3k, cargo_crate 1.1k, barrier_segment 0.4k, beacon_post 0.5k, conduit_pillar 0.6k.
Total 54.4k tris. Exact values live in the manifest.
