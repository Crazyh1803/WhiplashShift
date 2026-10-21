# Bydo-Grid first environment pass

## Implementation

Canonical direction: `docs/art-direction/bydo-grid.md`. Code-native environment
work on the existing `codex/track-visuals` feature branch; pending CPU/item and
other user work preserved.

- Tarmac becomes staggered 4 m ceramic panel rows, heavy black seams, edge wear,
  bone/carbon diagonal curbs and short recessed cyan center slots. Local diffuse
  lighting uses three bands; special physical surfaces retain their recognizable
  material responses and a very low emission signal below bloom threshold.
- Race environment has void background, no sky ambient/reflections, no sun,
  black depth fog from 110 to 280 m, filmic tonemapping and HDR-only restrained
  bloom (threshold 2.5). Two car-mounted spotlight cones support either driving
  direction. Garage/studio illumination is outside this pass.
- Cyan/amber emissive sphere batches and unshadowed point pools cover the whole
  loop at approximately 18 m intervals. Point lights fade beyond 95–120 m.
- Opening 720 m scenery sample uses bone armor, dry dark steel, opaque ribbed
  spines, bound conduits and exposed coral tendons. Flesh has active SSS, wet
  clearcoat and separate mipmapped procedural sinew normal/roughness maps;
  measured roughness stays within 0.1–0.25. Distant ribs use fixed opaque meshes
  with local uplights; production LOD simplification is not implemented.
- No new collision objects, handling changes, surface IDs or course edits.

## Checks

- Focused headless ak-test: 187 passed, 0 failed.
- Rendered Vulkan ak-test: 201 passed, 0 failed; six captures rendered without
  shader errors. Includes collider golden hashes, UV continuity, course and
  proving-ground clearance, SSS/maps, palette/environment state, opaque ribs,
  beacon spacing through loop closure and no race-scene directional light.
- Captures in `.ai/captures/track-sample/`: straight, straight-driver, mud-entry,
  mud-corner, mud-corner-driver, sample-overview. These replace the previous
  daylight sample captures. Driver capture opened in Codex for human inspection.
- git diff --check: pass.
- Full ak-test: PASS (exit 0), all 17 scenes. No engine/script errors.
  Log: `.ai/reports/bydo-grid-full-test.log`.

## Independent review blockers

Architecture consultation completed:
`.ai/escalations/20261019-210525-design-claude.md`.

ak-look failed because Gemini is RESOURCE_EXHAUSTED (429):
`.ai/looks/20261019-210757.md.log`. No visual PASS claimed.

ak-review could not run against the accumulated branch diff (40,285 lines).
A HEAD-scoped attempt also failed to launch the reviewer because the shell
argument list was too long: `.ai/reviews/20261019-210816-gemini.md.log`.
`.ai/reviews/latest.md` is an older blocked review, not a verdict for this pass.
No independent code approval claimed. Changes remain uncommitted.

## Remaining work

Human/independent visual inspection of darkness, beacon color wash and road
readability; production light-budget profiling; authored texture atlases;
full-course scenery dressing; vehicle retrofit geometry and production LODs.
SSS is configured and inspected numerically, but its perceptual quality still
needs visual approval. This is a first procedural implementation of the brief.
