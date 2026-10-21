# First road and scenery visual sample

Implemented on `codex/track-visuals`, preserving pending CPU, combat and launcher work.

## What changed

- Shared seamless procedural road materials replace flat colors: worn asphalt aggregate/repairs and markings, gravel, muddy ruts/wet patches, rough rock, ice cracks, animated water and off-track scrub/soil.
- One generated 256x256 seamless noise map, mipmaps and anisotropic sampling serve the materials. World-space coordinates keep texture scale consistent through curves; longitudinal metre UVs keep painted markings continuous between surface runs. The start/finish line hides the loop UV wrap.
- Detailed dressing covers the first 720 m: dirt shoulders, instanced rail posts, scattered rocks, a service yard, storage tanks, a tall corner landmark and distant landforms. Every freestanding prop is checked against every course branch and the separate proving ground.
- Warm daylight, a cooler sky and light distance haze establish an industrial scrubland palette. Directional shadows have a 160 m distance limit. No volumetric fog, screen-space reflections or external art assets were introduced.
- Surface materials apply around the loop; scenery beyond the sample remains future work. Existing warning signs and road boundaries remain legible goals for the pending visual review.

## Scope and physics

This is rendering code in the code lane: no Blender/ComfyUI or authored raster assets. All new scenery is MeshInstance3D/MultiMeshInstance3D; it adds no collision objects. No surface modifiers, handling, road width or checkpoint data changed.

The golden collision fixture was generated with the original TrackBuilder from commit `e2cebac9bfe97934230aa00a02b35722278b3c49`, using the same shifted course as the game. All twelve surface runs retain identical SHA-256 hashes of collider vertex bytes, metadata and heights. The temporary fixture-generation scripts were removed; `godot/tests/fixtures/track_collision.json` preserves the baseline.

Architecture advice: `.ai/escalations/20261019-204131-design-claude.md`. The existing per-run renderer was retained to minimize changes and keep visible transitions aligned with physical surface boundaries. Materials are shared by surface, rather than duplicating and crossfading a second whole-course ribbon. This retains the original draw-call structure and exact collider data.

## Verification

- Headless focused ak-test: 139 checks pass. Covers collision hashes, UV continuity, material sharing, visual-only scenery, full-course/proving-ground clearance, prop/post budgets and nondegenerate shoulders.
- Rendered Vulkan ak-test: 152 checks pass; all six captures saved without shader/engine errors. The fixture waits for asynchronous noise generation before capture.
- Captures: `.ai/captures/track-sample/straight.png`, `straight-driver.png`, `mud-entry.png`, `mud-corner.png`, `mud-corner-driver.png`, `sample-overview.png`.
- Full ak-test: PASS (exit 0), all 17 scenes, no engine/script errors. Includes the full physical race/retry, CPU difficulty, items, all vehicles, handling and guidance checks. Log: `.ai/reviews/track-visuals-full-test.log`.
- git diff --check passes.

## Independent review

ak-review and ak-look were attempted. Gemini remains RESOURCE_EXHAUSTED (429), so no independent approval or completed visual QA is claimed. Logs: `.ai/reviews/20261019-204739-gemini.md.log` and `.ai/looks/20261019-204739.md.log`. The working changes remain uncommitted. The sample is ready for player visual feedback before extending scenery around the loop.
