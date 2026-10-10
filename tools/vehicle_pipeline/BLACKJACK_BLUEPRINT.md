# Blackjack X-17 — blueprint rebuild, 2026-10-10

The working catalog now uses `blackjack_blueprint.glb`. Existing production,
production-v2 and refined GLBs/blends are preserved. The requested v2 filename
already contained the prior active candidate; a distinct name avoids overwriting
that work. This revision was compared directly with `SpyHunter.jpg` and all three
approved side/front references, not accepted solely on automated test results.

## Shape and seating

The previous reference calibration stretched the side view vertically by 37.36%.
The new packed orthographic planes preserve the sheet's aspect ratio. Hand-traced
stations define a mirrored, continuous cage with a shallow compound-curved hood,
low coupe greenhouse, tapered drivetrain transition and folded armored cabin.
Subdivision, longitudinal support topology, controlled creases, bevels, normals
and genuine shell arch/recess Booleans replace the earlier block/soft-blob shape.
The editable source retains its control cage, cutters, high-detail modules, UVs,
gameplay bake and body LOD. It is native Blender geometry, not image-to-3D output.

Gameplay-shell surface measurements versus the drawing: maximum roof/hood error
2.182 pixels, maximum half-width error 0.948 pixels, principal sills below three
pixels. The extreme nose's separate air dam/intake is excluded from the sill gate.
Wire overlays and neutral side, top, both front and three-quarter renders provide
the visual comparison; the sheet's side/top proportions take priority where
perspective front references differ.

Details include inset front lamps and bored weapon pockets, raised hood covers,
five-spoke coupe wheels, eight-opening rugged rims, tread/beadlock detail, protected
glass, door seams, handles, rivets, vents, mirrors, brush-guard seats and bent exhaust
stacks. Glass is reprojected onto the optimized shell, with independent triangle
interior/edge clearance checks on gameplay and LOD meshes; it no longer intersects
the paintable body in the livery render.

Four physical wheel hardpoints/radii, collision shapes, mass, suspension, steering,
grip and drivetrain are unchanged. The existing `vehicle.gd` and `wheel.gd` are
byte-identical to their already-dirty versions at task start. Assembly scaling and
offsets affect rendered parts only. The visual middle pair follows the existing
contact plane and is now centered at the traced Z=0.82032 m, not the old 0.66 m.
Axles and support links follow the displayed wheel centers. Frozen garage wheels
use generated arch coordinates without changing physical wheel state. Garage-only
pitch/height reproduce the level drawing while no physics is simulated.

## Counts and materials

| Asset | Triangles |
| --- | ---: |
| Gameplay body GLB | 16,830 |
| Body LOD1 GLB | 8,823 |
| Aero rim, each | 792 |
| Rugged rim, each | 1,334 |
| Tire, each | 1,536 |
| Native optional supercharger | 2,280 |
| Complete assembled stock vehicle, measured in Godot | 37,286 |
| Complete vehicle with supercharger, measured in Godot | 39,630 |
| Complete stock assembly using body LOD1, arithmetic estimate | 29,279 |

The 20–40k budget applies to the complete six-wheel rendered vehicle, including
runtime brakes, axles and links, not just the body file. LOD1 is supplied as a
separate body asset; automatic distance switching has not been added.

Eleven semantic materials: `Paint_Primary`, `Paint_Secondary`, `Paint_Accent`,
`Glass`, `Mirror`, `Rubber`, `Grille`, `Lights`, `Gunmetal`, `BrushedMetal`,
`ArmorProtected`. Only designated painted panels receive channel overrides.
Export copies are split by semantic instance so real Godot Decals can exclude
protected materials with their cull mask. The editable shell remains continuous.
Paint/decal persistence is tested across garage vehicle and wheel-style changes.

The four existing native Material Maker graphs and ORM maps provide protected
metal/rubber/grille/wear PBR. Krita's native `.kra` contains the regenerated UV
paint-channel guide, not a finished logo/label/livery atlas. UV median angular
anisotropy is approximately 1.03 and the 95th percentile 1.16. Tiny sliver triangles
retain high angular outliers (maximum approximately 1193); these are disclosed in
the topology report rather than represented as perfectly distortion-free UVs.
World-projected checker Decal and RGB renders verify the principal livery surfaces.

## Validation and review

Latest complete `ak-test`: exit 0; core 61/0, CPU 17/0, earlier refined-candidate
checks 670/0, new blueprint checks 2773/0. New tests cover all material slots/UVs,
protected paint, budget/LOD, idempotent wheel installs, actual frozen garage arch
and ground seating, native engine seating, decal retention, all vehicle/style
factory paths and strict physics parity through settling, driving, braking and
end swapping in independent worlds at identical coordinates.

There is still a preexisting unseeded CPU-roster flake: some Knifeedge-in-slot-two
runs stalled with zero laps and 26 recoveries (15/17 checks passed). Two latest
complete runs passed; this art task neither changes nor hides that unrelated issue.

Blender BMesh and actual MeshLab 2025.07 filters agree on the gameplay shell:
2,250 vertices, 4,496 triangles, one connected component, closed two-manifold,
zero holes/non-manifold edges/vertices, positive volume. Decorative surface patches
are intentionally separate and are not all closed solids. All four wheel/tire
modules independently pass closed/manifold/positive-volume checks. MeshLab's report
is hash-bound to the current GLB and Blender-exported shell PLY.

Both allowed Claude review rounds returned APPROVE. Medium issues about numerical
shape/budget gates and per-frame link updates were fixed, as were trivial basis,
child removal and dependency issues. A diff-scoping error excluded the preexisting
garage/catalog integration files from those reviews. Their new hooks and the final
glass/frozen-preview changes have regression/visual coverage, but not another
Claude review. The two-round cap is respected; permission for one extra focused
review was requested and remains unanswered. Do not describe integration as fully
reviewed. Radius constants used as fixed expected blueprint values in tests are
retained; runtime dimensions come from the generated ResourceLoader dependency.

## Rebuild and inspect

Run from the project root using the installed native toolchain:

```sh
/home/crazyh/.local/share/blender-bin/blender-5.2.2-linux-x64/blender -b --python-exit-code 1 --python tools/vehicle_pipeline/blender/build_blackjack_blueprint.py
/home/crazyh/.local/share/blender-bin/blender-5.2.2-linux-x64/blender -b tools/vehicle_pipeline/blender/blackjack_blueprint.blend --python-exit-code 1 --python tools/vehicle_pipeline/blender/validate_blackjack_blueprint.py
```

Then run `validate_blackjack_meshlab.py` with isolated Python bindings pinned to
`pymeshlab==2025.7.post1`. Blender validation MUST precede it; stale GLB/PLY hashes
are rejected. This task used `/tmp/blackjack-meshlab.mU3MwL/bin/python`; no project
dependencies were altered. Run `ak-test` for the full regression wrapper.
`blackjack_blueprint_visual_qa.tscn` captures neutral gameplay views, protected
paint/checker and engine views, plus the actual disabled garage preview. Use
Godot Forward+ to verify Decals, not the headless renderer.

The builder reuses only helper definitions from the immutable previous v2 script.
References are portable under `tools/vehicle_pipeline/references/` and packed in
the source; procedural maps remain under the existing `refined_materials/` folder.
The final source opens in its canonical pose with aligned reference planes and a
three-quarter studio camera.

Task-owned changes: `blackjack_blueprint*` Blender scripts/source, reference copy,
Krita guide, GLBs/texture dependencies/renders/reports/PLY, generated dimensions,
production visual rig/spec/factory, blueprint fixtures/tests/QA scenes, regression
wrapper, plan and this report. Narrow integration edits are in the preexisting
`godot/scripts/vehicle_catalog.gd`, `garage.gd`, and `proving_ground.gd`. They remain
unstaged with the user's other pending work; this task's asset/code commit does not
claim or commit those unrelated files. The catalog now selects the new asset,
and the player/CPU/garage construction paths use the scoped visual factory.
