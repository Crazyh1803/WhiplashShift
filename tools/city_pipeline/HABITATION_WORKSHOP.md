# habitation_workshop (candidate benchmark)

**Status: candidate only.** Not part of the production City kit (`godot/assets/city/kit`), not in `assets/final`,
not placed in any level. It is a quality/budget benchmark for an inhabited, reusable workshop building.

## What it is
A single-mesh stepped building: a dark pressure-hull podium with two deep repair bays and a human airlock, three
stepped habitation modules above it, and service structure on the sides and rear.

- **Repair bays (A1, B2):** open shutters with real interiors: gantry, rails, workbench, racks, gas bottles, a
  cradled ribbed pod in bay A, hazard flooring, lamps.
- **Airlock:** ceramic collar, open outer hatch, dogged inner door, cyan strip light, hazard threshold.
- **Armour:** layered, chipped plate fields with missing patches, repair-tinted panels and stencils; a sparse sinew
  breach.
- **Habitation:** stepped modules with fitted windows (shutters, louvres, bars, slits, portholes, strips) over lit
  interiors, terraces, laundry lines, exterior stairs and a left stair tower.
- **Services:** rear service block, right alley, filter tower, tanks, conduit banks and pipe runs with flanges,
  tied into the wall stand-offs; roof landscapes (dish, chimney, HVAC, tank deck, skylights).

## Numbers (from `habitation_workshop_manifest.json`, verified against GLB bytes)
- Triangles: 26689 (prototype cap 30000). Single mesh, 8 semantic materials: steel, ceramic, cavity, machinery,
  sinew, glow_cyan, glow_amber, trim. `COLOR_0` carries grime, streaks and repair tint (multiplies albedo).
- Origin: foot-centred. Footprint centre at x/z 0, lowest point y = 0. Offset is baked into the mesh.
- Bounds (glTF space, metres): x -18.125..18.125, y 0..29.35, z -12.6..12.6 (36.25 wide, 25.2 deep, 29.35 tall).
- Facade faces -Z (Godot forward). `front_setback_m` = 2.2: distance from the footprint front extent
  (stairs, awnings, bollards at z = -12.6) back to the primary podium facade plane (z = -10.4).
- No cameras, lights, collision, animation or skins are exported.

## Human scale
`build_human` makes a 1.75 m blocky reference figure that is rendered only (never exported). Previews place it in
front of bay A/B, the airlock and the street view; bay opening is about 10 m wide and the airlock door about 2.4 m
high.

## Build and validate
Run from the repo root:

    ak-blender tools/city_pipeline/build_habitation_workshop.py                 # GLB, manifest, blend, previews
    ak-blender tools/city_pipeline/build_habitation_workshop.py -- --no-render  # export only
    ak-blender tools/city_pipeline/build_habitation_workshop.py -- --only-shots front_studio,closeup_airlock
    python tools/city_pipeline/validate_habitation_workshop.py                  # also run by ak-test

The build is deterministic: rebuilding gives a byte-identical GLB.

The validator (stdlib only) decodes the real POSITION bytes through node transforms and checks bounds against the
manifest, the 30000 triangle cap, at most 8 semantic materials, one mesh, finite `COLOR_0` with real variation,
grounded and centred origin, a positive setback, and no camera/light/collision/animation data.

Outputs: `godot/assets/city/candidates/habitation_workshop.{glb,_manifest.json}`,
`assets/generated/city_habitation/` (blend and qa.json), `assets/previews/city_habitation/*.png` (front, rear,
three-quarters, street human view, right alley, roof/service, bay A/B and airlock closeups).

Note: with `export_vertex_color="ACTIVE"` Blender 5 writes the active attribute as `COLOR_0` only when it is set
active and `export_all_vertex_colors=False`; otherwise `COLOR_0` is flat white and the wear lands in `COLOR_1`.

The Godot review scene preserves embedded PBR materials and enables vertex-color albedo on a local material
copy when an imported material has it disabled (observed on steel). This preserves the authored wear without
changing the GLB or shared material resources. The review uses neutral studio lighting and, separately, the
project's night environment with three local yard lamps and a camera headlight. It does not place the asset on
the track; production material integration and LODs remain a later step.

## Not yet built
LODs. Planned: mid LOD drops interiors, stencils, rails and window furniture (about 45 percent of triangles); far
LOD keeps podium, module and roof silhouettes only (about 5 percent). Neither exists yet.
