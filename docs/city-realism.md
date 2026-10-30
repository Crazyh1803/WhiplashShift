# Block Circuit city conversion

Block Circuit uses the converted city layer by default. The original tower skyline, window lights and communications crown continue behind the new frontages. The course and vehicle data are unchanged.

## City library

Eight reusable families: habitation workshop, market habitat, service tenement, freight depot, Redline Ramen shop, row workshops, utility substation and transit depot. Each has a detailed model and a lightweight distant silhouette. Construction includes structural steel and baseplates, cladding repairs, shutters, doors, loading equipment, ducts, roof tanks, laundry and shop signs with recognizable everyday icons.

Eight street pieces: sidewalk panels, curbs, drains, lamps, bollards, bench planters, refuse stations and alley conduits. The layout covers four route quarters: market boulevard, freight/service, utility works and housing/transit. Curved lots and nearby road segments are checked before placement. The two ramen shops reuse the approved vendor and customer, with matching counter, floor and light sockets.

Shared textures supply colour, surface roughness, metal response and normals. Vertex colour carries wear and occlusion. Only the sign atlas glyphs and lamp glass emit light. The 39-image library has a conservative 60 MiB RGBA8 estimate including mips; runtime imports use VRAM compression and share textures by resource path.

## Rendering

Near scenery is merged by material in 48m route chunks. Detailed chunks reach 140m; building silhouettes reach 450m. Both use 10m fade margins and paired culling bounds. Actors reach 60m. A camera-nearest pool provides nine local lights and two shadowed shop spots, plus the preserved crown beacon (12 city light nodes).

Runtime GLBs contain geometry and named material stubs. The textured source exports remain outside the Godot project in `assets/generated/city_realism/textured_exports/`. `CityRealismCatalog` binds the shared library by material name, preserving UV0, vertex colours and tangents. Scene import therefore has no image references to load or reimport; the shared PNGs keep their import settings and UIDs.

The converted source has 899,920 placed triangles, with quarter counts 236,420 / 224,152 / 200,556 / 238,792 before the separately budgeted people. There are 29 detailed buildings, 492 pavement/curb pieces and 178 other street pieces. The sampled conservative view peaks at 205,644 triangles and 113 material surfaces, including fading chunks; limits are 320,000 and 160. These are scenery geometry measurements, not a frame-rate guarantee.

## Review captures

`assets/previews/city_realism/in_game/` contains actual Godot captures: eight driver views, four sidewalk night views, four sidewalk neutral views and a ramen closeup. The driver/night views use the race environment with a QA camera headlight. Neutral views add a diagnostic directional light and ambient illumination. Blender source previews are kept separately in the parent directory.

## Validation and rebuilding

Use `ak-test` with the normal project command, which includes the asset validators and full-city regression scene. The source build is `ak-blender tools/city_pipeline/build_city_families.py -- --skip-tex`. See `tools/city_pipeline/CITY_REALISM.md` for asset conventions and texture recipes.

Converted assets remain candidates awaiting user art review. The approved original ramen benchmark is retained. People are static, distant LODs are simplified massing, and housing windows/depot bays have limited interiors. Street details are culled with the near chunks. The explicit `CityScenery.build(..., true, false)` mode retains the earlier scenery for comparison and regression coverage; unavailable converted assets use that fallback automatically.
