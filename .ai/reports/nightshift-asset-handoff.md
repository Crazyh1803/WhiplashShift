# Nightshift asset handoff

Branch `asset/nightshift-graphics` (worktree `.codex/worktrees/deadbolt-graphics/Whiplash`). Commits: `035c127` (asset), `7578afc` (review fixes + this report). Main checkout and Godot scripts/tests untouched.

## Paths
- GLB: `godot/assets/vehicles/models/nightshift/nightshift_blueprint.glb`; LODs `.../nightshift/lod/nightshift_blueprint_LOD{1,2}.glb`; `nightshift_blueprint_qa.json`, `_build.json`.
- Source: `tools/vehicle_pipeline/blender/nightshift_blueprint.blend`, `build_nightshift.py` + `nightshift_*.py`, `validate_nightshift.py`, `check_nightshift_idempotence.py`; doc `tools/vehicle_pipeline/NIGHTSHIFT_BLUEPRINT.md`; reference `tools/vehicle_pipeline/references/80s.jpg`; renders/overlays `tools/vehicle_pipeline/qa/nightshift_blueprint/`.

## Contract
Coupe End A +X, truck End B -X, ±Y width, +Z up. `Wheel_Coupe_*` (13 parts, R .40) and `Wheel_Truck_*` (9 parts, R .43); tyre objects `_Tire_`, origins at hubs (x 1.66 / -1.72, y ±0.82). Materials `Nightshift_Paint/Secondary/Stripe` for customization; others fixed. Triangles 35,046 / 26,262 / 18,048.

## Checks
- `validate_nightshift.py`: PASS (shell manifold/symmetry/silhouette vs trace, wheels, arch clearance, glass seating incl. `Glass_CabRear`, lamp seating, UV/materials, GLB re-import, budgets). Bounds gate is derived from the authored trace (body length/width/roof + declared add-on allowances), not a hand-relaxed range: length 5.09–5.51 (actual 5.40), width 2.00–2.28 (2.234), height 1.585–1.665 (1.639).
- Rebuild idempotence: build A copied, rebuilt, `check_nightshift_idempotence.py` → idempotent, 196 objects, 0.0 mm vertex/surface deviation.
- Visual: 3 ak-look rounds (neutral renders). Reviewer: ak-review exceeded the argument limit on the full 143 KB diff (agy "Argument list too long"), so Gemini reviewed the 52 KB delta against the normalized Deadbolt fork source: APPROVE with 1 MED + 3 LOW, all fixed (`.ai/reviews/nightshift-r1.md`). One review round used.

## Remaining limits (not claimed away)
Third ak-look round (before the final geometry fixes) still reported, and I did not re-render-review after fixing: Camaro quad lamps judged "perched" on the sloped nose (fixed: bezel ribbons removed, lens thinned to 8 mm inside 40 mm pockets; lamp-seating numeric gate ≤35 mm); chin spoiler gap (now swept valance overlapping the nose); cab-back window gap (now thin glass 1.5 mm off wall); push guards shortened; bowtie reshaped. These are verified numerically only. Unresolved/unverified visually: soft shading across the roof-step wall (crease loops added, not re-judged), thin black pillar-seam strip reading as floating, pink stripe terminating at the Camaro intake corner, Camaro mirror stem thin. Interior is solid under dark glass. Wheel PBR is flat-colour materials (no textures). Silhouette is traced from an AI-generated sheet with approximate wheel centres (349/677 px).
