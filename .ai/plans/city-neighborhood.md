# Inhabited City neighborhood kit

## Authorized outcome
The user approved the detailed habitation workshop and asks for more models at that standard: believable places where people live and work, with interesting details racers would want to stop and inspect. Build three complementary reusable buildings and show all four together in a street study. This is the next model-library/art-review milestone; production placement/LODs remain separate from this review scene, and the approved road/handling stay intact.

## New buildings
1. `market_habitat`: broad, low, asymmetric corner arcade. Recessed street stalls with service counters, shelves, dispensers and human entrances; upper residential galleries, different shutters/curtains, communal terrace, laundry and water storage. Dusty oxide/cloth accents and warm occupied windows. Distinct from the workshop's three-step silhouette.
2. `service_tenement`: narrow/tall inhabited block wrapped around a substantial life-support spine. Stacked rooms, deep access galleries, a believable lift/service shaft, pipe/filtration banks, supported platforms and maintenance access. Faded blue/teal repair panels, bone armor, dark recesses. Strong silhouette, furnished glimpses rather than every hidden room modeled.
3. `freight_depot`: long, lower working structure with a covered loading dock, gantry/handling hardware, sorting counters, lockers/crates and sheltered staff rooms. Large ribbed/segmented machinery, purposeful utility connections and repaired cladding. Faded industrial ochre accents. A workaday logistical counterpart to the residential buildings.

Every model needs a different front, useful side/rear/roof views, coherent circulation and services, and details at silhouette/secondary/close scales. Use layered chipped ceramic armor, dark pressure structure, restrained organic breaches, small cyan/amber lights, and real occupied/workshop recesses. No broad emissive surfaces, clean glass towers, random bolt scatter or copies of the workshop shell. Reuse the approved component vocabulary, not its complete building layout.

## Ownership and sequence
- Claude asset lead via ak-delegate: first the market and tenement plus shared builder/validator/presentation; then a separate focused depot addition. One delegation at a time. Use ak-blender headless, numeric checks and inspected studio views. Read-only design escalation checks the shared source/export/capture contract.
- Codex lead: engine capture selection and material compatibility, a street-study scene using the actual exported models, test entry integration, checks/review/publication. Preserve existing runtime City kit and approved workshop GLB byte-for-byte.
- Independent ak-review scopes: Codex reviews Claude-authored asset source; Claude reviews lead integration. Fix HIGH/MED, up to two review rounds. No Gemini without user request.

## Asset contract
New files: `tools/city_pipeline/build_city_neighborhood.py`, `validate_city_neighborhood.py`, `CITY_NEIGHBORHOOD.md`, optional `city_neighborhood_depot.py`; `godot/assets/city/candidates/neighborhood/<id>.glb` and `neighborhood_manifest.json`; sources in `assets/generated/city_neighborhood/`, views in `assets/previews/city_neighborhood/<id>/`.

Reuse the approved workshop's Kit, wall/opening assemblies, stairs, rails, plumbing, color wear and export helpers. It is acceptable to change its unconditional final `main()` call to an import guard; no change to approved geometry or exports. The existing candidate validator is already importable and its real vertex/accessor checks can be reused.

Each building: metres, foot-centred at y=0, Godot -Z front, one combined static mesh, <=8 semantic material surfaces, nontrivial finite `COLOR_0` variation, no camera/light/collision/animation. Near-review cap 35,000 triangles each; target around 20–30k while prioritizing meaningful form and detail. This does not change production district budgets. Maintain corrected lathe winding and ordered primitive bounds. Render scale is a factor (normally 1.0), never a pixel width; reject oversized scale inputs before allocation. Keep generation deterministic.

Manifest: version 1, status `candidate-review`, assets with stable id/class/glb/tris/aabb/footprint/front_setback_m/surfaces/reuse_worlds/vertex_colors/budget_note/lod_strategy. Include `review_targets` (`entry`, `activity`, `service` finite [x,y,z] in grounded Godot coordinates) and describe each building's functional identity. First pass lists exactly the two finished IDs; depot pass adds its third ID and updates validator expectations. Paths are filenames relative to the manifest directory. LOD strategy must be honest about what exists; no implied production optimization.

## Acceptance
- Preserve approved workshop and old fourteen-piece kit exports. Inspect new front/rear/roof, street human-scale and activity/entry detail views, at least five per asset. Include a non-runtime 1.75 m human reference in a street/detail image. Shared neutral lighting must not hide blank surfaces; inspect actual geometry and color in Godot as well.
- Run new decoded-vertex validator through ak-test and wire it into the normal runner. Verify cap, grounded/centred origins, actual/declared bounds, color data and semantics, path/ID completeness and absence of runtime extras. Reuse existing low-level checks rather than another unchecked reader.
- Engine capture per model: neutral front/rear/roof, entry/activity and driver-height views; separate night lighting study using local lamps and no sun/ambient. Honor vertex-color albedo as in the approved capture setup. Produce a coherent street-study overview and low-camera views with clear road envelopes.
- Run relevant original City/Block Circuit regressions, independent review, resolve findings, commit and publish to this chat branch. Deliver three new models, a useful neighborhood image and honest review/production status.

## Delivered and verified (2026-10-29)
All three models built, regenerated after geometry fixes, and inspected in Blender studio renders and Godot. Final triangles: market 33,781; tenement 33,216; depot 29,317. Eight semantic materials each. The approved workshop and all fourteen production-kit GLBs remain byte-identical to 45547eb (git diff verified).

`ak-test` ran the three decoded-geometry validators and CityKit/BlockCircuit suites: 338 + 73 assertions passed. Final Vulkan captures: ten per new asset, zero failures each. Street study: four buildings plus eight props, all twelve bounds checked, no overlaps, building clearance 12 m and prop clearance >=6.84 m, six captures, zero failures. Studio and night images inspected; the study is intentionally sparse to review the models, not a finished race district.

Independent review dispositions:
- Claude integration reviews 082945 and 084640: APPROVE. Added all-four requirement, early track failure, validated bounds, clear directory names and secondary shadow limits. The target-presence invariant already determines neighborhood mode; no extra state needed. Depot completeness resolved by final delivery. Task provenance artifacts intentionally tracked.
- Codex first-assets review 083947: APPROVE; all three MED fixed: removed duplicate gallery deck, horizontal supported terrace canopy, elevated cistern legs attached to their platforms. Regenerated all outputs.
- Codex depot review 085212: APPROVE; MED dock-leveler facade-local coordinate conversion fixed using HB[0], then regenerated. Final depot bounds are 53 x 13.5273 x 35.6 m. Inspected levelers now aligned with bays.

Delegations: Claude first two assets, Claude depot, Claude read-only design escalation and integration review, Codex independent asset reviews; ak-blender generated all models and studio renders; Qwen drafted the initial capture commit subject. No main merge; publish tested chat preview only.
