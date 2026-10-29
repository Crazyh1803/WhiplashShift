# City neighbourhood kit (candidate review)

Inhabited-city buildings at the approved `habitation_workshop` quality bar. Status: `candidate-review`; nothing here is
wired into runtime City worlds yet. Production placement, LODs and district budgets are separate work.

| id | read | key features |
|---|---|---|
| `market_habitat` | broad low corner arcade, ~34 x 22 m, 15 m tower | recessed stalls (counter, shelves, dispenser, lamp, occupant, cloth canopy), colonnade, deep residential gallery with laundry/tables/planters, communal terrace + cisterns, corner oriel on corbels, rear cistern bank and service platform, roof tanks |
| `service_tenement` | narrow tall block, ~24 x 21 m, 37 m with mast | stacked rooms with alternating deep recessed galleries, segmented life-support spine, open lift core with car, rear filtration bank under a braced deck, exterior maintenance tower with stair/ladders, trunk mains, roof cisterns |

Both: metres, foot-centred at y=0, Godot -Z front, one combined mesh, 8 shared semantic materials (steel, ceramic, cavity,
machinery, sinew, glow_cyan, glow_amber, trim), real `COLOR_0` wear/tint (market dusty oxide, tenement faded blue/teal),
near-review cap 35,000 triangles each (currently ~34k / ~33k). No lights, cameras, collision, animation or extras.

## Files
- `build_city_neighborhood.py` — shared builder. Imports the workshop module (its `main()` now sits behind an import guard,
  geometry and export unchanged) and reuses Kit / Wall / fits / stairs / rails / pipes / colour / export helpers.
  Adds `bays`, `shell` (per-side wall thickness, repair patches), `fit_stall`, `person`, `awning`, `ladder`, `laundry`,
  `cistern`, `tendon`, `gallery`, `sign_plate`. Buildings register with `@building(...)`; `main()` builds each from a clean
  scene and snapshots/restores the workshop globals (`ASSET_ID`, `OFFSET`).
- `validate_city_neighborhood.py` — stdlib validator (wired into `tools/workflow/test_season.py`): reuses the workshop
  validator's decoders/checks at the 35k cap, plus exact ID set, plain filename paths, no extras, review-target envelope,
  honest LOD note, minimum-detail floor, distinct GLBs.
- Outputs: `godot/assets/city/candidates/neighborhood/{market_habitat,service_tenement}.glb`, `neighborhood_manifest.json`;
  sources/QA `assets/generated/city_neighborhood/<id>/` (`.blend`, `qa.json`); views `assets/previews/city_neighborhood/<id>/`.

## Build
```
ak-blender tools/city_pipeline/build_city_neighborhood.py -- [--no-render] [--size 1.0] [--only <id>] [--only-shots a,b]
```
`--size` is a resolution scale (0.25-2.0), never a pixel width. Review views per building: front studio, three-quarter,
street-human entry (1.75 m non-runtime reference figure), activity, rear/service, roof, flank/maintenance and a close-up.

## Adding freight_depot (next pass)
Create `city_neighborhood_depot.py` with `register(nb)`: use `nb.building("freight_depot", cls=..., parts=[...], facade=(box, y),
tint=..., identity=..., brief=...)` on a targets function returning design-space `entry/activity/service` points, add
`nb.SHOTS["freight_depot"]`, then append the id to `EXPECTED_IDS` in the validator. Per-asset globals are reset by the shared
`build_one`.

## Lessons carried over
Per-asset globals are snapshot/reset; shared semantic materials avoid `.001` suffixes; active `Col` only becomes COLOR_0;
render size is a scale and oversized values fail fast; previews are isolated per model.
