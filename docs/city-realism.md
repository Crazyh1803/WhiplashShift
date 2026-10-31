# Block Circuit city conversion

Block Circuit uses the converted city layer by default. The original tower skyline, window lights and communications crown continue behind the new frontages. The course and vehicle data are unchanged.

## City library

Eight reusable families: habitation workshop, market habitat, service tenement, freight depot, Redline Ramen shop, row workshops, utility substation and transit depot. Each has a detailed model and a lightweight distant silhouette. Construction includes structural steel and baseplates, cladding repairs, shutters, doors, loading equipment, ducts, roof tanks, laundry and shop signs with recognizable everyday icons.

Eight street pieces: sidewalk panels, curbs, drains, lamps, bollards, bench planters, refuse stations and alley conduits. The layout covers four route quarters: market boulevard, freight/service, utility works and housing/transit. Curved lots and nearby road segments are checked before placement. The two ramen shops reuse the approved vendor and customer, with matching counter, floor and light sockets.

Shared textures supply colour, surface roughness, metal response and normals. Vertex colour carries wear and occlusion. Only the sign atlas glyphs and lamp glass emit light. The 39-image library has a conservative 60 MiB RGBA8 estimate including mips; runtime imports use VRAM compression and share textures by resource path.

## Rendering

Near scenery is merged by material in 48m route chunks. Detailed chunks reach 140m; building silhouettes reach 450m. Both use 10m fade margins and paired culling bounds. Actors reach 60m. A camera-nearest pool provides nine local lights and two shadowed shop spots, plus the preserved crown beacon (12 city light nodes).

Runtime GLBs contain geometry and named material stubs. The textured source exports remain outside the Godot project in `assets/generated/city_realism/textured_exports/`. `CityRealismCatalog` binds the shared library by material name, preserving UV0, vertex colours and tangents. Scene import therefore has no image references to load or reimport; the shared PNGs keep their import settings and UIDs.

The converted source has 887,544 placed triangles, with quarter counts 231,776 / 220,264 / 199,452 / 236,052 before the separately budgeted people. There are 29 detailed buildings, 294 pavement/curb pieces, 902 ground modules and 178 other street pieces. The sampled conservative view peaks at 223,986 triangles and 113 material surfaces, including fading chunks; limits are 320,000 and 160. These are scenery geometry measurements, not a frame-rate guarantee.

## Review captures

`assets/previews/city_realism/in_game/` contains actual Godot captures: eight driver views, four sidewalk night views, four sidewalk neutral views and a ramen closeup. The driver/night views use the race environment with a QA camera headlight. Neutral views add a diagnostic directional light and ambient illumination. Blender source previews are kept separately in the parent directory.

## Validation and rebuilding

Use `ak-test` with the normal project command, which includes the asset validators and full-city regression scene. The source build is `ak-blender tools/city_pipeline/build_city_families.py -- --skip-tex`. See `tools/city_pipeline/CITY_REALISM.md` for asset conventions and texture recipes.

Converted assets remain candidates awaiting user art review. The approved original ramen benchmark is retained. People are static, distant LODs are simplified massing, and housing windows/depot bays have limited interiors. Street details are culled with the near chunks. The explicit `CityScenery.build(..., true, false)` mode retains the earlier scenery for comparison and regression coverage; unavailable converted assets use that fallback automatically.


## Building conversion verification (previous delivery)

Final targeted `ak-test`: city realism 227/0 headless, original street block295/0, city kit383/0, Block Circuit97/0, ramen benchmark762/0 and menu746/0. The asset validators, 17 city-family Python tests and 13 benchmark Python tests pass. Python QA healthy/failure exit checks and timeout kill/reap self-test pass.

A separate actual Vulkan run of the city suite passes228/0, including a deliberately displaced MultiMesh instance. The rendering server defers buffer updates: that detector waits two frames and frame_post_draw after mutation/restoration. The Dummy headless server ignores instance-transform setters, so the renderer-specific mutation runs only with a real display driver. All other source-versus-merged vertex comparisons remain active headless.

The converted model/texture caches were removed and rebuilt successfully. A forced scene reimport and a newly generated row-workshop asset also imported successfully. Shared PNG sidecars have no diff after these checks. All17 final Godot captures save successfully and pass content checks. Independent runtime, asset, binding and test reviews are APPROVE; findings are resolved in `.ai/reviews/city-realism-disposition.md`.

## Connected street fabric

Four reusable ground modules extend the city beyond its sidewalks: patched road aprons, service lanes, loading yards and utility verges. They reuse the same 14 materials and 39 textures, with no extra light nodes or colliders. The apron subdivides at tight bends, checks a 5 cm minimum clearance outside the rail, and fills the rail-to-sidewalk gap. All other ground and solid placements retain the 3.5 m setback. Building models, people, course points and driving behavior remain unchanged.

The layout keeps all 29 buildings, 134 props and 44 details. Replacing most repeated curb segments pays for the new ground: total scenery geometry falls by 12,376 triangles. A missing or invalid optional ground pack falls back atomically to the original pavement/curb layout. The runtime never exposes a partial ground kit.

Ground sources and reproducible build records are in `assets/generated/city_ground/`; rebuild with `ak-blender tools/city_pipeline/build_city_ground.py`. Runtime GLBs are geometry-only, and textured source exports reference the existing shared library. Source validation checks tangents, material bindings, budgets, footprint dimensions and deterministic rebuilds. Ground preview renders remain separate from the actual Godot captures.

## Street fabric delivery verification

Final ground `ak-test`: 192 passed, 0 failed. This includes independent mesh and rail-envelope measurements, actual source-versus-merged vertices, atomic invalid/missing-pack fallback, null material rejection, cache restoration and a second course scaled 20 percent longer. That stress case retains 25 buildings against 23 in its baseline, 158 props against 158 and 52 details against 52, within the unchanged caps. The ground suite has a bounded 900-second allowance after its expanded exhaustive geometry checks exceeded the old 300-second limit.

The broader targeted regression matrix passed: city realism 227/0 headless, street block 295/0, city kit 383/0, Block Circuit 97/0, ramen benchmark 762/0 and menu 746/0. All source validators and 5 ground, 17 city-family and 13 benchmark Python regressions pass, along with QA exit-code and timeout kill/reap self-tests. Independent asset, runtime, test and final-fix reviews approve; disposition is recorded in `.ai/reviews/city-street-fabric-disposition.md`.

All 17 final Godot captures were refreshed and pass save/content checks. The shared texture import sidecars remain unchanged.

The final Vulkan city suite passes 228/0, including actual merged-geometry checks and the deliberately displaced MultiMesh detector.

## Full-course city layers

The original tower vocabulary supplies inexpensive midground behind the eight detailed building families. The converted city adds a deterministic backdrop after the detailed lots and district landmarks have reserved their space. It reuses stepped tower bodies, pilasters and roof equipment with five muted facade tones, grime, rain streaks, repair patches and sparse stable warm/cool window emission. The distant skyline and communications crown remain unchanged. No new texture images, light nodes or collision objects are required.

The backdrop uses one body MultiMesh and one trim MultiMesh. It has separate hard caps of 420 buildings, 1,900 box instances and 22,800 triangles, while the detailed-city geometry budgets remain unchanged. All emitted original-kit structures now respect detailed-lot reservations. The added backdrop also avoids existing towers, landmarks and the crown footprint. Tests independently reconstruct transformed corners, check road and lot clearance, all-quarter coverage, source course stability, determinism and fallback behavior.

Godot review capture coverage now includes four city overviews as well as eight driver views, eight sidewalk views and the ramen closeup (21 total). Each overview must frame at least one detailed frontage and five original/background pieces. Neutral overviews use diagnostic lighting to show layout and surface detail; driver/night views use the race environment and a QA camera headlight.

Block Circuit emits 227 added backdrop buildings: 71 / 47 / 55 / 54 across the four quarters. Their 1,438 box instances total 17,256 triangles across two material batches. Final dedicated backdrop checks pass 57/0 headless and 60/0 with Vulkan. The existing detailed-city total remains 887,544 triangles with 29 buildings.

Final Vulkan readback verifies all 1,438 actual MultiMesh transforms against stored placements, deliberately displaces one instance, proves rejection and restores it. Reads wait two process frames and frame_post_draw, including the initial comparison. Dummy headless mode retains geometry checks and explicitly skips renderer readback. Final QA refreshes all 21 images with save/content/framing checks; audio passes 46/0. The shader uses BACKDROP_EXPOSURE 0.22, with trim albedo (0.045,0.043,0.040), so the infill supports the lit detailed frontages. This is a geometry/material verification, not a frame-rate guarantee.

The delegate full run was cut off by execution limits, so it is not reported as a completed full default matrix. Relevant ground 192/0, city 227/0 headless, physical season-course 33/0, asset validators and dedicated backdrop checks passed. The physical City pilot completed three laps in 215.28 simulated seconds with zero recoveries. Final integration uses explicit targeted TEST_CMD values to avoid an inherited broad test command. No vehicle or course data changed.
