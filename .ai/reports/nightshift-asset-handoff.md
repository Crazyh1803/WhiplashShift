# Nightshift asset handoff

Branch `asset/nightshift-graphics` (worktree `.codex/worktrees/deadbolt-graphics/Whiplash`). Commits: `035c127` (asset), `7578afc` (review-1 fixes + report), `4e00d9b` (hashes), `e430222` (final visual fixes); this report update is the following docs commit. Main checkout and Godot scripts/tests untouched.

## Paths
- GLB: `godot/assets/vehicles/models/nightshift/nightshift_blueprint.glb`; LODs `.../nightshift/lod/nightshift_blueprint_LOD{1,2}.glb`; `nightshift_blueprint_qa.json`, `_build.json`.
- Source: `tools/vehicle_pipeline/blender/nightshift_blueprint.blend`, `build_nightshift.py` + `nightshift_*.py`, `validate_nightshift.py`, `check_nightshift_idempotence.py`; doc `tools/vehicle_pipeline/NIGHTSHIFT_BLUEPRINT.md`; reference `tools/vehicle_pipeline/references/80s.jpg`; renders/overlays `tools/vehicle_pipeline/qa/nightshift_blueprint/`.

## Contract
Coupe End A +X, truck End B -X, ±Y width, +Z up. `Wheel_Coupe_*` (13 parts, R .40) and `Wheel_Truck_*` (9 parts, R .43); tyre objects `_Tire_`, origins at hubs (x 1.66 / -1.72, y ±0.82). Materials `Nightshift_Paint/Secondary/Stripe` for customization; others fixed. Triangles 35,140 / 26,366 / 18,158 (gameplay / LOD1 / LOD2).

## Checks
- `validate_nightshift.py`: PASS (shell manifold/symmetry/silhouette vs trace, wheels, arch clearance, glass seating incl. `Glass_CabRear`, lamp seating, UV/materials, GLB re-import, budgets). Bounds gate is derived from the authored trace (body length/width/roof + declared add-on allowances), not a hand-relaxed range: length 5.09–5.51 (actual 5.40), width 2.00–2.28 (2.234), height 1.585–1.665 (1.639).
- Rebuild idempotence: build A copied, rebuilt, `check_nightshift_idempotence.py` → idempotent, 196 objects, 0.0 mm vertex/surface deviation.
- Visual: 3 ak-look rounds during modelling, then targeted final verification on current renders (below). The stepped roof is deliberate source geometry and was never smoothed. Reviewer: ak-review exceeded the argument limit on the full 143 KB diff (agy "Argument list too long"), so Gemini reviewed the 52 KB delta against the normalized Deadbolt fork source: APPROVE with 1 MED + 3 LOW, all fixed (`.ai/reviews/nightshift-r1.md`). Round 2: `ak-review 035c127` on the corrective commits only (21 KB): APPROVE, 1 LOW (stale report numbers, fixed here) (`.ai/reviews/nightshift-r2.md`).

## Final targeted visual verification (current renders)
- Camaro quad lamps seated in the nose buckets: OK. Chin spoiler/valance continuous, no shelf gap: OK.
- Cab-back glass: now a projected `Glass_CabRear` panel seated 2.7–2.8 mm off the wall (validator `glass_seated`), trim ribbon same plane; glass enlarged to fill frame. Residual sliver reported once as LOW, fixed, not re-looked at.
- Push guards: shortened to bumper height (0.15 m), moved to y ±0.60; verified OK in the follow-up look.
- Defect found and fixed: Camaro chin/corner amber lamps sat at y ±0.76, beyond the 0.60 m nose half-width (HIGH). Moved to y ±0.50 with the intake narrowed to ±0.40; follow-up look no longer reports it.
- Reviewer-reported HIGH "see-through gap at coupe side-window front-bottom corner": dismissed with evidence. Ray grid over that region hits body/glass/mirror everywhere below the roof line; a dedicated close-up (`qa/nightshift_blueprint/nightshift_blueprint_coupe_window.png`) shows only dark recess trim and A-pillar, no background. A LOW belt-trim z-fight there was fixed by lifting the ribbon 1.5 mm.
- Final numeric: validate PASS; rebuild idempotent (196 objects, 0.0 mm deviation).

## Remaining limits
- Pink stripe row meets the Camaro nose cap/bumper edge abruptly (LOW, design stripe is the shell accent row; not changed).
- Thin black pillar-seam groove may read as a floating strip (LOW). Roof-step shading was hardened with crease loops; final looks did not flag it.
- Camaro mirror stem is thin (LOW). Interior is solid under dark glass. Materials are flat PBR colours (no textures). Silhouette traced from an AI-generated sheet with approximate wheel centres (349/677 px).
- ak-look is a vision model; its verdicts are noisy (it flagged the coupe window gap twice; geometry disproved it). Final visual state is judged by the last look plus numeric gates, not a flawless-render guarantee.
