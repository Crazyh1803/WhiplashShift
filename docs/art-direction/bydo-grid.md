# Bydo-Grid Cyberscape

Project art direction, supplied by the art director. Applies to roads, scenery,
lighting and future vehicle assets. Supersedes the industrial scrubland sample.

## Core vision

High-contrast biomechanical 16-bit arcade aesthetics (R-Type), combined with
chiseled 1980s homologation machinery. An industrial trench system corrupted by
parasitic flesh and deep-space military hardware. Hard silhouettes, heavy seams,
black cavities, mechanical ribs and sinew; no clean neon metropolis.

## Palette and response

| Element | Colors | Material response |
| --- | --- | --- |
| Void / deep steel | #050508–#181B22 | Matte, low specular, near-zero ambient bounce |
| Chitin / industrial cream | #D8D3C4–#A8A08E | Metallic 0.1, roughness 0.4–0.5, hard edge wear |
| Flesh / coral muscle | #9B2226–#E26D5C | Active SSS, roughness 0.1–0.25, dedicated sinew normal and roughness maps |
| Plasma cyan | #00F0FF | HDR emission, compact bright sources |
| Force amber | #FFB703–#E85D04 | Emissive accents and local directional highlights |

## Lighting and shading

Sharp diffuse bands and steep shadows. Zero directional sunlight; illuminate with
point-light beads, emissive markers and local spotlight cones. Void-black sky
and steep black distance fog. No colored atmospheric haze or muddy soft AO.
Selective high-threshold bloom on small guide spheres, sparks and thruster
nozzles; broad road panels must not glow. Black panel seams/cavity lines and
hard-edged wear preserve the graphic-novel/arcade character.

## Modular environment kit

- Interlocking ceramic road panels, heavy seams and worn diagonal bone/carbon
  hazard curbs. Recessed cyan center markers at regular distance intervals.
- Cylindrical conduit bundles with mechanical binding ribs. Coral tendons break
  through fractured dry-steel sleeves.
- Massive segmented vertical spine columns. Preserve opaque rib silhouettes at
  distance; no alpha-fade LOD or collapsing ribs.
- Spherical barrier-mounted or floating guide beads alternating cyan and amber,
  casting small pools of local light.

## Vehicle asset direction

Preserve angular 1980s hatchback, coupe and square-truck silhouettes: sharp
C-pillars, rally fenders, rear louvers. Retrofit heavy cylindrical afterburner
bells on reinforced external frames, cooling fins, bolted armor skirts and
roof/quarter sensor blocks in bone cream or gunmetal. Rectangular glass tail
arrays, segmented readouts and cyan status grids on rear fascia plates.

## Inhabited city refinement

The user-approved civilian-city direction is grounded, worn industrial science
fiction, with close-range people, storefronts and supports matching the vehicles'
construction and material credibility. Repaired machinery and small human comforts
sit inside the existing dark biomechanical world. The distant skyline remains the
reference for the far city. See [the vehicle-matched storefront benchmark](inhabited-city-benchmark.md)
for the next small candidate scene and its review criteria.

## Acceptance and current scope

Verify SSS plus dedicated normal/roughness maps for organics, no sun, and stable
ribbed tower silhouettes. Keep each physical driving surface recognizable and
preserve handling/collision IDs. The first implementation is procedural Godot
materials, a scenery sample and full-course guidance lighting. Vehicle geometry,
authored texture atlases, production LODs and further scenery coverage require
subsequent asset work; they are not implied complete by the environment pass.

## Secondary road surface identities

These are visual skins over the existing driving-surface contracts. HUD names,
collision metadata, grip, drag and preferred vehicle ends remain unchanged.

| Driving surface | Bydo-Grid appearance | Read at speed |
| --- | --- | --- |
| Gravel | Chitin rubble | Small dry angular bone chips in black carbon grit |
| Mud | Living viscera | Wet coral muscle ropes, dark branching vessels, pale scars |
| Boulders | Fractured spinal armor | Broad bone/gunmetal slabs, deep joints and bright chipped lips |
| Ice | Vitrified coolant | Glassy dark cyan, pale fractures, faint cyan capillaries |
| Water | Reactor effluent | Circulating dark teal coolant, cellular scum and dirty pale foam |
| Oil | Black ichor | Nearly black smooth membrane with restrained interference swirls |
| Off track | Carbon debris | Matte crushed understructure, sparse discarded chitin flakes |

Organic road uses the same dedicated sinew normal/roughness maps as the scenery
flesh, active SSS and wet clearcoat. Other surfaces use shader relief normals;
none displaces vertices or adds rocks/colliders. Cyan coolant fractures remain
below the bloom threshold. Side-by-side material captures use the same neutral,
cyan and amber local lights; verify alongside actual driver-height track views.

## Terrain depth and frame legibility

Texture alone is insufficient to explain a frame change. B-preferred rough/soft
runs now use tessellated shared visual/collision relief: chitin ballast up to
3 cm, muscle/rut beds 5 cm, fractured armor 8 cm, static coolant ripples 2 cm.
Relief stays above the global floor, fades to exactly flat joins and edges, and
uses conservative slopes for the existing single-ray suspension. Rendered mesh
normals follow the geometry. Smooth ceramic, ice and ichor retain their original
flat colliders. Neither frame's tyre/suspension or surface coefficients changed.

Much larger faceted chitin/armor heaps, wet tendon banks and effluent deposits
stand outside the guardrails at entries and through rough runs. These provide
visible silhouettes and parallax before a driver reaches the hazard. They are
batched, decorative and clear of every course branch. The driveable bumps use
real collision; large decorative heaps remain beyond the racing boundary.

Judge the result from the low driving camera, including the approach to a
transition. Material-swatch renders alone cannot establish frame legibility.

## Vehicle response, layer 1: viscera

MUD contact now throws wet coral clumps from each contacting tyre. End B uses a
restrained low spray. End A uses 4.8 times the per-contact emission coefficient,
larger clumps and higher outward spray. Emission
scales with actual speed and wheelspin, so bogged driven wheels can churn while
a stationary unspinning car does not spray. Airborne/dry wheels stop emitting.

The body visual eases into shallow immersion on B (up to 2.5 cm) or deeper
bogging on A (up to 12 cm), with a small pitch into the driven end. This is a
cosmetic representation of the existing terrain penalties: physical body,
colliders, wheel hardpoints, tyre grip and handling are unchanged. Rigid-body
suspension remains physical.

Each car owns a shared fixed 96-piece world-space pool across the cached organic mesh
variants: folded tissue shreds (55%), narrow curved entrails with cut ends (35%),
and tiny jointed appendage fragments with a pale bone tip (10%). Pieces tumble
independently. Wet vertex-colored surfaces preserve muscle, fat, cut and bone
accents; keep fragments small relative to the car, with thin elongated strands.
Do not use uniform sphere/ellipsoid blobs. Mix short-lived, low irregular
ejecta with taller thrown spray; never use continuous tyre-surrounding meshes,
which read as hover discs from the chase camera. Stationary tyres leave no
standing effect geometry. Judge the result using the actual gameplay CameraRig.
Leaving the surface stops spray and returns the pose smoothly. Freeze,
teleport/recovery and retry clear old effects; model customization remains safe.
Viscera is the first organic response layer. Persistent residue, further terrain
responses and audio require later art passes.


## Vehicle response, layer 2: chitin rubble

GRAVEL contact scatters dry chipped armor/chitin plates, dark carbon grit and
occasional angular chunks. Each piece tumbles, lands with one small visual bounce,
and expires. Use opaque irregular fragments; no hovering discs or haze blankets.
The wet and dry mesh batches share the same 96-live-piece budget. Per-wheel
surface selection allows organic and dry debris together on mixed-contact seams.

End B has a low controlled spray and slight body rattle. End A has over four
times the per-contact emission coefficient, larger/higher debris and a stronger
bounded cosmetic chassis shudder. Rubble adds no sinking: the dry response uses
vertical/pitch/roll vibration instead. The existing single visual-pose writer
blends rattle with viscera's bogging at seams, then returns smoothly to neutral.
No forces, grip/drive modifiers, collider/wheel transforms or camera shake change.
Stationary unspinning/airborne tyres do not produce a rubble response. Existing
freeze/recovery/retry/customization cleanup applies to both layers.
