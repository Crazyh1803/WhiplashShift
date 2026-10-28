# City scenery kit and opening-quarter review

## Authorized outcome
Create impressive, distinct City buildings alongside a reusable modular building/prop library, then populate only the first quarter of Block Circuit for review. The driving layout is approved and must not change. Preserve first-quarter scope as 0 <= forward route distance < total_length * 0.25 (about 520 m); remaining circuit keeps its current lighter treatment. The same physical district must stay in place in reverse races.

## Art target
Bydo-Grid remains authoritative: chiseled industrial masses, ceramic/bone ribs, deep steel cavities, exposed machinery and sparse sinew; small cyan/amber light sources, void sky, no clean neon metropolis. Real silhouette and facade depth rather than rectangular towers with a new texture. Strong street-level composition with space around hero buildings. Props must work across worlds where practical.

## Proposed kit
- Three landmarks: relay/spine tower, stepped exchange/workshop hall, cylindrical pumping/utility citadel. Each needs a different skyline, recognizable street facade and secondary machinery.
- Three reusable buildings: shuttered workshop, utility mid-rise, ribbed stack block. Modular dimensions and shared palette, multiple rotations/arrangements.
- Eight reusable props: pipe rack, vent/exhaust stack, service cabinet, transformer/generator, cargo container/crate, barrier segment, beacon fixture, conduit/pillar module. More than one world can reuse industrial props.
- Retain source Blender file, deterministic generator and numeric manifest with asset IDs, mesh bounds, triangles, material semantics, dimensions and intended reuse. No assets/final writes.

## Ownership
- Claude asset lead via ak-delegate: the WHOLE authored asset task, including Blender modeling/build/export/QA studio renders; use ak-blender headless, numeric checks first, inspect results, one heavy local job at a time. No bitmap generation needed for geometry-led assets.
- Codex lead: design/clearance/material integration decisions, reusable Godot asset loader/batching and first-quarter placement, engine capture/verification and publishing on this chat branch. Project chat workflow is the delivery/integration branch; authored assets stay isolated in the delegate checkout until integration.
- Claude read-only design escalation: GLB coordinate/material/bounds contract and clearance/performance risks.
- Independent reviewer: ak-review, with separate author scopes. No Gemini unless user requests it.

## Integration constraints
Assets: Blender +Z up, +Y front (Godot Y up, -Z front), metres, foot-centred origin, transforms applied, no collisions/cameras/lights embedded in runtime GLBs. One combined mesh per asset with <=8 shared semantic material slots preferred. Landmarks <=18k tris each, reusable buildings <=8k, props <=2k; budget justified in manifest. Runtime geometry is decorative. Shader/readability adaptation must preserve semantic palette and relief; local lights capped, no directional/ambient changes. Keep road, rails, handling, cues, spawn/grid, items and checkpoints unchanged. Full-course mesh/world bounds clearance, not only root-origin checks, including ground footprints and corner cantilevers. Avoid overhead road crossings for this slice. Batch repeated pieces; deterministic placements with authored per-asset footprint. No unsupported test assertions based on dummy-renderer MultiMesh reads: retain transforms and compare independently.

## Sequence and acceptance
1. Build asset kit; inspect neutral studio hero renders and a library board, then refine if necessary before dressing.
2. Integrate approved-quality kit and compose opening boulevard + first sweeper + quarter exit, with distinctive near/mid/far layers. Replace the procedural placeholder towers in that district so there is no overlap; keep later scenery light.
3. Capture asset gallery plus start, mid-boulevard, corner approach/apex/exit, quarter boundary, reverse views and actual gameplay camera. Deliver useful review images and a playable preview.
4. Test GLB budgets/bounds/materials, exact first-quarter routing and no later population, no scenery collision, road geometry unchanged, deterministic instancing and reverse-world invariance. Run relevant ak-test checks, ak-review, fix findings and publish only passing work. Report asset count, extent, checks, branch/commit and desktop preview status.

## Delivered review slice
Fourteen reusable GLBs, retained Blender source and generator, individual studio views and three boards. The first quarter contains 63 instances: three landmarks, sixteen reusable buildings and forty-four service props. Placed geometry totals 147,232 triangles in fourteen batches with 64 material surfaces. The remaining loop retains its prior treatment, and the physical world is identical in reverse.

Verification: seven relevant suites passed (CityKit, Block Circuit, course cues, camera, track visuals, season courses and reverse races). City physical pilot completed three forward laps without recovery and a reverse lap without recovery. Forty-six rendered gallery/route/landmark/gameplay views were captured with no reported failures; gallery lighting is explicitly inspection-only. Asset validator plus pristine-copy/eight corruption checks passed. Review disposition is recorded in `.ai/reviews/city-kit-resolution.md`.
