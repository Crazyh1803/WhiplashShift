# Deadbolt finish — 2026-10-16

Delivered in the consolidated project `/home/crazyh/Documents/ChatGPT/Whiplash`, branch
`codex/deadbolt-finish`. Asset delivery `27a8731`, imported by `df61dc2`; runtime integration
`34a70e2`. Original folders and original `deadbolt_blueprint*` draft remain preserved.

## Result

Blueprint-traced hard-surface body replaces the rejected rounded draft. Blackjack's
station cage/support-loop/crease methods inform the new source, with real arches/recesses,
seated windshields and side glass, grille/lamps/trim/seams, distinct detailed wheels and PBR
materials. Catalog now loads `deadbolt_hardsurface.glb`; Deadbolt shares Blackjack's studio
lighting. Visible steering pivots derive from authored tire hubs, keeping the wheel fit
independent of physical hardpoints. All three paint channels and protected materials work.

Visual half-track 0.82 m; truck/coupe outer tire faces 0.99/0.965 m vs 1.00 m flares;
arch clearance 50/60 mm. Gameplay 32,587 triangles, LOD1 23,598, LOD2 16,596.
Native source: `tools/vehicle_pipeline/blender/deadbolt_hardsurface.blend`.
Rebuild/validation instructions and limitations: `tools/vehicle_pipeline/DEADBOLT_HARDSURFACE.md`.

## Verification

- Final imported asset: `ak-test` exit 0; core 61, CPU 17, refined Blackjack 670,
  blueprint Blackjack 3555, consolidation 71 = 4374 passed, zero failed.
- Independent final `ak-blender validate_deadbolt_hardsurface.py ...blend`: PASS;
  closed positive-volume shell, silhouette/UV/material/wheel/glass/export/LOD checks.
- Asset lead's two-build comparison: 184 meshes, matching object/material/topology counts;
  worst vertex distance 0.55 mm (1 mm limit), vertex-to-surface 0.00006 mm (0.01 mm limit).
  This is measured equivalence, not bit-exact reproduction.
- Source review: initial complete geometry text APPROVE; wheel HIGH/MED fixed;
  final asset delta APPROVE in `.ai/reviews/20261016-195124-gemini.md`.
- Runtime review: APPROVE, no findings in `.ai/reviews/20261016-194222-gemini.md`;
  second capture-test delta APPROVE in `.ai/reviews/20261016-195126-gemini.md`.
- Actual GPU Godot capture scene exit 0: 58.02 km/h under keyboard throttle;
  end B swap with finite position. All eight captures saved successfully.
  A first capture run emitted one shutdown ObjectDB warning; verbose rerun reproduced the
  successful drive/swap with no leak or project error reported.
- Final actual-game `ak-look`: PASS, no body/wheel/glass/missing-mesh/framing blockers,
  compared with `80sFord.jpg` and Blackjack. Text verdict preserved alongside this report.
  The extra garage view was renamed from misleading `_truck` to `_coupe` after reviewer
  identified the orientation; default `deadbolt_garage.png` faces the truck end.
- Godot editor and normal game launched on the consolidated project.

## Remaining limits

No cabin interior under dark glass. Faint coupe-handle shading pinch and close-up black
A-pillar seal aliasing remain. Final QA noted lower paint-button text contrast than Blackjack
(Deadbolt uses the unrestricted picker); deferred because changing picker behavior goes
beyond this body-art delivery. Rendered body extends beyond the simplified existing collider
near the noses. Physics/tuning remain unchanged. No claim of exact blueprint identity or
perfect Blackjack parity; both source and in-game visual comparisons passed.

## Inspect

In Godot's running garage select **DEADBOLT**, then **VIEW 3D // PAINT & PARTS**.
Drag to rotate. Choose **IGNITE** to drive; **Space** swaps ends; **Esc** returns.
Current captures are in `.ai/captures/` (ignored generated files).
