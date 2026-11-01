# Resume here: dense roadside city, war damage, and water-building overhaul

Status: planning only, saved 2026-11-01 at the user's request to conserve credits. Do not begin game implementation, asset generation, implementation delegation, game testing, or a new art investigation until the user resumes the work. This document is the next-pass brief; older plans describe completed work and are background, not an outstanding task list.

## User direction and acceptance

- The generic buildings behind the detailed buildings now look good throughout the course. Preserve that arrangement and its appearance.
- The water building (`pump_citadel`, the domed building with cylindrical silos) still looks generic and does not match the gritty, highly detailed buildings. Its previous detail pass is technically complete but artistically insufficient. It needs a substantial visible upgrade, not another small seam/rivet overlay.
- Too much roadside frontage remains empty. One short bend on one side could reasonably be open; long/repeated empty stretches around the course are unacceptable. Fill the street as a city, not just a scattering of landmarks.
- Add more detailed buildings if reuse alone is insufficient. Apartment buildings are specifically appropriate, alongside the existing shops and industrial buildings.
- Reuse existing detailed models both intact and as visibly different damaged variants. This world has suffered a war with aliens: charred buildings, partly collapsed buildings, and recognizable structural remains should tell that story.
- One or two entire blocks can be war ruins. Place more camp structures, belongings and burning barrels in those ruined blocks so they feel inhabited after the destruction. Ruins are authored scenery, not an excuse for another empty lot.
- No further clarification is needed to start these priorities when credits return. Start with the frontage audit, not a rehash of the previous conversation.

## Exact starting point and completed work

Current tested/published game baseline: `1fdb7d40bbf8cbd900a86a382b5fffeb3d7839f6`, branch `chat/gritty-city-density-eeeef781a662`. This plan is a later documentation-only commit on that branch. No game changes have been merged to main by this chat.

Same-chat worktree: `C:/Users/dwhit/Documents/ChatGPT/.whiplash-worktrees/gritty-city-density-eeeef781a662`. Reuse it for this chat; do not run chat start again inside it. In a genuinely new chat, follow the project chat workflow and use this branch as the explicitly named dependency, rather than starting from main and losing the city work. The user already selected this city work as the dependency in this conversation; do not ask again in the same chat.

Already implemented: 66 original detailed frontages, two shop actor pairs, four detailed roadside tower placements (two tower families), eight boarded hosts, four camps, eight burning barrels, and detail overlays/weathering for both pump citadel and exchange hall. Nineteen roadside library assets share existing PBR textures. Reuse the existing camps, barrels, building components and materials rather than rebuilding these systems.

Background layering is accepted: generic full footprints are at least 50 m from the rail (measured minimum about 50.2 m), behind the original detailed rear faces. Converted city no longer emits legacy generic roadside towers/decks/walls. Background rows retain depth and height variation; 299 buildings / 1894 box instances / 22728 triangles. Do not move these buildings back to the road, brighten them, replace their shader, or redo this accepted stage.

Important distinction: placement counts and passing tests did NOT establish adequate city density or water-building visual quality. The user's latest feedback supersedes the previous visual acceptance on those two points.

## Read only these entry points first

- `godot/scripts/city_realism_layout.gd`: existing detailed building distribution, solids and reservations.
- `godot/scripts/city_roadside_layout.gd`: towers, boarded hosts, camps, barrels and landmark placement. Current quotas are sparse (one tower, two boarded hosts, one camp and two barrels per quarter); simply retaining these quotas will not fill the street.
- `godot/scripts/city_roadside.gd`, `city_roadside_catalog.gd`, `city_roadside_fx.gd`: assembly, shared resources, visibility and measured costs.
- `tools/city_pipeline/city_roadside_landmarks.py`: pump/exchange overlays; `city_roadside_towers.py`, `city_roadside_boards.py`, `city_roadside_dressing.py`, `city_roadside_common.py`, `build_city_roadside.py`: reusable asset pipeline.
- `godot/scripts/city_scenery.gd`: assembly/backdrop reservations. Preserve the accepted generic setback/shader behavior.
- `godot/tests/city_roadside_tests.gd`, `city_roadside_qa.gd`, `city_roadside_probe.gd`; `godot/scripts/city_roadside_views.gd`; `tools/workflow/test_season.py`: existing checks and capture harness.
- `assets/previews/city_roadside/`: actual baseline captures, especially `landmark-pump_citadel-front.png`, `landmark-pump_citadel-street.png`, tower/podium and driver views. Compare the water building against the detailed shop fronts, not just against its own previous version.
- `.ai/reviews/roadside-resolution.md`: completed review fixes and exact constraints. Older failure plans are historical; do not redo already-fixed bugs.

## Implementation sequence and team split (when resumed)

1. LEAD runs `ak-lead`, verifies the branch/worktree and working-tree state, then performs a bounded frontage audit. Map actual road-facing occupied intervals against course distance on BOTH sides; include setbacks, bends, occlusion and rejected placement reasons. Record the longest gaps and a compact per-quarter/side coverage table. Existing broad AABBs, ground paving, far skyline and a building's rear face must not falsely count as an occupied street frontage. Capture representative empty stretches at driving height. Do not spend a generation pass before locating the gaps.

2. LEAD turns that audit into a deterministic block layout and one bounded asset-lead brief. Keep dense intact neighborhoods, damaged transitions and one or two recognizable ruined blocks. Place ruins deliberately rather than scattering every damaged model uniformly. Existing intact buildings can be reused with alternate signage, shutters, boarded openings, roof equipment and material variation. Break repeated silhouettes with different heights and mixed frontage widths. Preserve road clearance, readable corners and the accepted rear layer.

3. Claude asset lead through `ak-delegate` owns authored 3D/model changes and headless `ak-blender` exports. Start with existing detailed families. Add a small reusable set of apartment/mixed-use midrises if the audit shows missing height/width/type coverage (initial design scope: roughly two or three families, not a separate unique mesh for every lot). Apartment detail must read at street level: actual entrances, recessed windows, ledges/balconies where suitable, pipes, AC units, fire escapes, patched walls and lived-in ground floors. Share materials/textures and reusable modules. Generate only requested assets, not the whole library.

4. Asset lead makes the water building a proper gritty municipal water/pumping facility. Preserve its recognizable dome and silo silhouette, but break up the large smooth surfaces with substantial maintenance architecture: service annex or entrance surround, convincing industrial doors/grilles, exposed pipe runs/valves, pump equipment, catwalks/ladders, patched panels, water/rust streaks, damaged plaster or masonry and grime concentrated at joints/ground. Use the established detailed-building palette, scale and texture quality. Detail must be visible in the front and road-height views, not mostly hidden behind the tanks or confined to roof rails. Avoid covering the whole facade with uniform noise or adding polygons that produce no visible improvement. The exchange hall already has a completed pass; it is not a primary target for another rebuild.

5. Asset lead derives war-damaged variants from selected intact sources: scorched facade/window bays, broken glazing and rooflines, exposed floor slabs/structure, partial collapse, rubble piles and a few standing walls/columns. Use geometry damage as well as material changes. Keep a recognizable relationship to the source building, but distinguish damaged copies from intact copies at driving distance. No need for new alien creatures, combat mechanics, people models, or a separate destruction simulation.

6. LEAD integrates block placement; asset lead supplies the ruin modules and dressing. Ruined blocks should retain a readable building footprint/street edge through surviving walls, burned structural frames and debris. Cluster tarp shelters, bedrolls, belongings, improvised screens and existing burning barrels in sheltered pockets. Keep the treatment grounded and human; do not turn camps into caricatures. Reuse current flame/smoke effects and share geometry/materials. Camp props alone do not replace the missing architecture along a long road segment.

7. LEAD audits coverage again and verifies driver-height captures around the whole lap in both directions. Fix the actual remaining gaps before declaring density complete. Run focused checks, independent `ak-review`, address findings, commit and publish the tested chat preview through `python tools/workflow/chat.py publish`. Do not merge to main without an explicit merge request.

Only one delegation/heavy local generation job at a time. LEAD owns integration/layout decisions and verification; asset lead owns 3D authoring. Escalate a cross-system visibility/budget design once if necessary, not a fresh architecture debate for every model. Work in small batches with one specific brief and one targeted correction per batch. Read compact results and selected images; do not dump large logs or repeatedly review thousands of unchanged lines.

## Performance and correctness constraints to carry forward

- Current measured peak: base 319710 triangles / 150 surfaces; roadside additions 160100 / 79; combined 576502 / 254. Current caps: base 320000 / 160, additions 175000 / 80, combined 625000 / 265. The additions are already close to the surface cap. Do not blindly multiply all high-detail placements or silently raise caps; plan useful near/mid/far representations and measure the dense result. If a budget change is necessary, justify it with measured render costs and actual desktop performance, and record it explicitly.
- Godot visibility ranges apply to the whole GeometryInstance/MultiMesh bounds, NOT each contained transform. Preserve per-placement culling or deliberately local spatial batches. Never regroup distant buildings/fires into a single short-range MultiMesh. Charge every instance of an active node in budget measurements; count unrestricted landmark nodes without invented distance cutoffs.
- Existing environment disables ambient/reflection. New tower material variants already have small textured fill; do not globally change the environment to solve one new asset's readability.
- Preserve shared PBR albedo/normal/ORM resources, UVs, vertex colors and tangents. Validate all retained textured-export URIs relative to the export file. Keep original assets immutable; add variants rather than destructively replacing their sources. No assets/final promotion.
- Preserve the 12-light limit; barrel effects currently add no light nodes. Keep full flame/pool/smoke bounds within their reservations. Keep hollow barrel hoops and tubular handrails; capped cylinders previously occluded interiors/platforms.
- Keep real podium openings. Solid hulls in front of recessed doors/windows were a previous defect. Preserve optional-asset fallback, deterministic placement and the course/road/collision behavior.
- Existing QA now measures real with/without-subject pixel differences, with separate barrel-body and flame-only checks. Use captured Image dimensions for projected screen regions. Do not replace this with a nonblank-frame or metadata-only check. Healthy scenes must pass, deliberately hidden subjects must fail. Capture isolation/temporary overrides must not mutate shared live materials.

## Completion criteria for the next pass

- Water building clearly belongs to the same gritty visual world as the detailed shops in matched front/street screenshots. The user specifically rejected the previous generic appearance; a passing numeric mesh check is insufficient.
- A full-lap frontage audit and driver captures demonstrate a substantially continuous detailed street on both sides. Plan for near-continuous occupancy, with at most one deliberately short open bend on one side; determine its exact length from course geometry rather than inventing a building count now. No repeated long blank stretches. Ruined blocks count as occupied only when visible structural remains and dressing actually read as a destroyed city block.
- Apartments and reused intact/damaged buildings provide a believable mix of heights, uses and conditions. One or two ruin blocks contain coherent charred remains and sheltered camps/barrels. Avoid obvious identical sequences and isolated props in huge empty plazas.
- All new footprints/ruins/rubble/effects clear the drivable road and respect intended reservations. Accepted background layering remains unchanged. Source meshes remain reusable; new assets are validated numerically and visually.
- Measured dense-scene triangles/surfaces, culling/LOD, lights and desktop performance stay within justified limits. Capture near, transition and distant views so detail does not disappear prematurely or pop into coarse roadside proxies.
- Relevant `ak-test` checks and independent review complete; record review findings/resolution honestly. Update the coverage table and selected before/after captures, then publish the tested branch preview.

## Resume commands and known environment facts

PowerShell; `python` works, whereas `python3` is a Windows Store stub on this machine. Use `ak-test`, not raw test commands. `.agent.env` already supports an inherited `TEST_CMD`; do not rewrite it just to select focused scenes.

Known Godot executable (verify it still exists): `C:/Users/dwhit/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe`.

Useful focused test command to set as `TEST_CMD`: `python tools/workflow/test_season.py --scenes city_roadside_tests city_backdrop_tests`. Actual capture command, also through `ak-test`: `"$GODOT_BIN" --path godot res://tests/city_roadside_qa.tscn -- --capture`. The Windows roadside runner already tests intentionally hidden bodies/flames. Add coverage/ruin-specific tests when implementing the new layout rather than rerunning unrelated suites repeatedly.

Baseline results, already recorded (not re-run for this plan): roadside 191 passed; backdrop 70 headless / 73 Vulkan passed; 38 real captures passed; hidden-body and hidden-flame checks each correctly failed their eight intended cases. Earlier core city suites: realism 227, density 46, kit 383, ground 192 passed. These are historical results, not proof of future modifications.

Temporary old delegate folders may remain because cleanup was blocked by policy. They are not the authoritative worktree or unfinished feature work. Do not spend the next art pass re-investigating that housekeeping issue.
