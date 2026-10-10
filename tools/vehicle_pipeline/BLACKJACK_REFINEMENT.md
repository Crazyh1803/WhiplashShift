# Blackjack X-17 — candidate refinement, 2026-10-10

This is an incremental art revision, **not an approved production replacement**.
The active catalog, existing production/v2 GLBs, physics scripts and collision
shapes have not been changed. New outputs use `blackjack_refined` names because
`blackjack_production_v2.glb` was already the active, unapproved asset at restart.

## Changes from the blockout / first refinement

- Mirrored, supported longitudinal control cage, genuine Boolean wheel openings,
  recessed lights/grille/weapons, surface-seated glass, panel seams and hardware.
- A flatter interceptor hood, with a restrained crown and supported shoulder
  curvature instead of the earlier steep downward wedge.
- Deeper rugged lower body and inner wheel housings, frame rails and clevises.
  The candidate-only Godot rig adds moving, purely visual suspension links.
- Separate flatter-sided, treaded tires and vented beadlock truck rims; separate
  open-spoke interceptor rims. Editable high-detail parts remain in the blend.
- Four native Material Maker graphs feed protected metal/rubber/grille/wear
  roughness/metallic maps. The Krita document is a UV paint-channel ID guide,
  not a completed livery/label atlas.

## Art acceptance — not passed

Directly compared neutral side, three-quarter and both front renders to the
approved side, rugged-front and interceptor-front images, plus `SpyHunter.jpg`.
The supported silhouette, smoother transition, shallower hood and wheel seating
are improved. The interceptor's vertical front fascia remains too generic and
the armor/accessory detailing does not yet match the reference richness.
Do not promote the candidate on automated test success alone.

Additional gates still open: artist approval, full decal-projection/stretch
inspection, manual MeshLab topology/filter checks, wheel-module optimization and
an assembled-vehicle LOD strategy. MeshLab loaded the exported closed shell;
its GUI filters were not verified. Blender's independent BMesh report is the
topology evidence below, not a claim of completed MeshLab validation.

## Counts and semantics

Body gameplay GLB: **35,684 triangles**; body LOD1: **17,158**.
Per-instance modules: aero rim 5,532; rugged rim 9,953; each tire 3,008.
Body plus two aero/four rugged wheel modules is **104,608 triangles minimum**,
before runtime brakes, axles, engine and suspension links. The body meets the
requested 20–40k range, but the complete assembled vehicle does **not**. Wheel
exports currently preserve high-detail topology; optimization is pending.

All eleven semantic material names are present: `Paint_Primary`,
`Paint_Secondary`, `Paint_Accent`, `Glass`, `Mirror`, `Rubber`, `Grille`,
`Lights`, `Gunmetal`, `BrushedMetal`, `ArmorProtected`. Protected surfaces retain
their source materials through RGB paint-channel customization tests. The
candidate test fixture uses the existing customization API; it is not integrated
into the active garage catalog.

Closed gameplay shell: 7,994 vertices / 7,708 polygon faces; zero boundary edges,
zero non-manifold non-boundary edges, zero zero-area faces, positive signed
volume 0.57534665 source units³. Decorative surface patches are intentionally
separate meshes, so this closed-shell assertion is not applied to every patch.

## Rebuild / verify locally

The pipeline uses the installed Blender 5.2.2 LTS, Material Maker 1.7, Krita
6.0.4 and Godot 4.6.3. Native graph sources live in `materials/`; their exported
ORM maps live in `godot/assets/vehicles/models/blackjack/refined_materials/`.
Material Maker's exported `.tres` templates required a Godot 4 syntax correction;
the checked-in resources load successfully in the candidate tests. If exporting
again, retain their `Texture2D`/`res://`/string-ID syntax instead of replacing
them with the tool's legacy template. Blender reads the ORM PNGs directly.
Build after exporting those graphs:

```sh
/home/crazyh/.local/share/blender-bin/blender-5.2.2-linux-x64/blender -b --python-exit-code 1 --python tools/vehicle_pipeline/blender/build_blackjack_refined.py
/home/crazyh/.local/share/blender-bin/blender-5.2.2-linux-x64/blender -b tools/vehicle_pipeline/blender/blackjack_refined.blend --python-exit-code 1 --python tools/vehicle_pipeline/blender/validate_blackjack_refined.py
ak-test
```

The runner reuses helper/export definitions from the immutable previous
`build_blackjack_production_v2.py`, without executing its original body creation
or overwriting its outputs. Approved image references and the local blueprint
are packed into the saved editable blend. Regeneration also requires the three
existing approved reference files and the blueprint at the report's path.

`blackjack_refined_visual_qa.tscn` produces the two in-engine captures. Adding
`-- --inspect` leaves that **candidate studio preview**, not the integrated game,
running. The middle contact-plane correction is confined to the test-only
`blackjack_refined_preview_vehicle.gd`, following the Claude escalation proposal.
No raycasts, physical wheel states, suspension parameters or forces are added.

Task-owned files are the refined Blender builder/geometry/rim/validation scripts
and blend, four material graphs, Krita guide, refined model outputs and reports,
candidate fixture/tests/preview/capture scenes, this note, the task plan, and
the `ak-test` wrapper/configuration. Unrelated existing dirty files are excluded
from staging and the Claude review diff.

## Test and review record

Core Godot checks: 61 passed. Candidate checks (paint protection, eleven semantic
names, UV channel presence, body/LOD counts, four physical wheels, unchanged
collisions/mass/hardpoints/socket, authored tires, repeatable tire installation,
six visual supports, settled middle contact and inactive-candidate guard):
**670 passed / 0 failed** on the final run.

CPU regression: passing samples are 17/17, but random rosters including Knifeedge
in slot two produced **15 passed / 2 failed** (Knifeedge zero laps, 26 recoveries).
The final full `ak-test` run is therefore **exit 1**, not green. An intervening
Boilerfang/Ramjet draw passed. Claude's read-only
diagnosis attributes the variation to the existing unseeded CPU roster and
suspects a swap/recovery loop; the exact trigger is not confirmed. This task did
not fix or hide that failure and made no CPU/physics edits. Do not describe the
full regression suite as consistently green.

Claude review returned APPROVE in both allowed rounds. Medium findings about
legacy resource syntax, import-log checking, material null handling and parent
callback behavior were addressed. `Vehicle` has no `_process` callback, verified
in the existing source; the test-only override now documents that fact. Review
approval concerns code, not art acceptance or the complete triangle budget.
