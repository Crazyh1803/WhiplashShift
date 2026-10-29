# City neighbourhood kit (candidate review)

Inhabited-city buildings at the approved `habitation_workshop` quality bar. Status: `candidate-review`; nothing here is
wired into runtime City worlds yet. Production placement, LODs and district budgets are separate work.

| id | read | key features |
|---|---|---|
| `market_habitat` | broad low corner arcade, ~34 x 22 m, 15 m tower | recessed stalls (counter, shelves, dispenser, lamp, occupant, cloth canopy), colonnade, deep residential gallery with laundry/tables/planters, communal terrace + cisterns, corner oriel on corbels, rear cistern bank and service platform, roof tanks |
| `service_tenement` | narrow tall block, ~24 x 21 m, 37 m with mast | stacked rooms with alternating deep recessed galleries, segmented life-support spine, open lift core with car, rear filtration bank under a braced deck, exterior maintenance tower with stair/ladders, trunk mains, roof cisterns |

| `freight_depot` | long low logistics hall, 40 x 13 m hall in a ~63 x 36 m yard, 13.5 m with roof mast | covered raised loading dock (canopy on columns, undercroft, bumpers, levelers, two stairs), five big ribbed bays onto working conveyor / rack / hoist interiors, glazed control booth with desk and screens, monorail hoist with slung pod, forklift and staged pallets / crates, rear rail spur with flat car, containers and portal gantry, transfer door and upper door platform, power-cell bank, lockers, transformer, roof clerestory with HVAC, tank, skylights and mast, sparse tendon breaches |

All: metres, foot-centred at y=0, Godot -Z front, one combined mesh, 8 shared semantic materials (steel, ceramic, cavity,
machinery, sinew, glow_cyan, glow_amber, trim), real `COLOR_0` wear/tint (market dusty oxide, tenement faded blue/teal, depot
faded ochre/oxide), near-review cap 35,000 triangles each (currently ~34k / ~33k / ~29k). Depot manifest bounds: 62.6 x 13.5 x
35.6 m AABB, 12.2 m front setback (dock, canopy and apron ahead of the facade plane). No lights, cameras, collision, animation
or extras. No mid/far LODs exist for any of the three.

## Files
- `build_city_neighborhood.py` — shared builder. Imports the workshop module (its `main()` now sits behind an import guard,
  geometry and export unchanged) and reuses Kit / Wall / fits / stairs / rails / pipes / colour / export helpers.
  Adds `bays`, `shell` (per-side wall thickness, repair patches), `fit_stall`, `person`, `awning`, `ladder`, `laundry`,
  `cistern`, `tendon`, `gallery`, `sign_plate`. Buildings register with `@building(...)`; `main()` builds each from a clean
  scene and snapshots/restores the workshop globals (`ASSET_ID`, `OFFSET`).
- `validate_city_neighborhood.py` — stdlib validator (wired into `tools/workflow/test_season.py`): reuses the workshop
  validator's decoders/checks at the 35k cap, plus exact ID set, plain filename paths, no extras, review-target envelope,
  honest LOD note, minimum-detail floor, distinct GLBs.
- `city_neighborhood_depot.py` — `register(nb)` hook for `freight_depot` (imported at the bottom of the builder): own
  `fit_bay` / `fit_control` openings, dock / canopy / rear-yard / roof parts, review targets and 8 shots.
- Outputs: `godot/assets/city/candidates/neighborhood/{market_habitat,service_tenement,freight_depot}.glb`, `neighborhood_manifest.json`;
  sources/QA `assets/generated/city_neighborhood/<id>/` (`.blend`, `qa.json`); views `assets/previews/city_neighborhood/<id>/`.

## Build
```
ak-blender tools/city_pipeline/build_city_neighborhood.py -- [--no-render] [--size 1.0] [--only <id>] [--only-shots a,b]
```
`--size` is a resolution scale (0.25-2.0), never a pixel width. Review views per building: front studio, three-quarter,
street-human entry (1.75 m non-runtime reference figure), activity, rear/service, roof, flank/maintenance and a close-up.

## Adding another building
Follow `city_neighborhood_depot.py`: `register(nb)` uses `nb.building(id, cls=..., parts=[...], facade=(box, y), tint=...,
identity=..., brief=...)` on a targets function returning design-space `entry/activity/service` points, adds `nb.SHOTS[id]`,
and the id is appended to `EXPECTED_IDS` in the validator. Per-asset globals are reset by the shared `build_one`. Use
`--only <id>` so the other approved GLBs stay byte-identical. Author every `Kit.box` with ordered (min, max) bounds, as
reversed extents are silently dropped.

## Lessons carried over
Per-asset globals are snapshot/reset; shared semantic materials avoid `.001` suffixes; active `Col` only becomes COLOR_0;
render size is a scale and oversized values fail fast; previews are isolated per model.
