# Full-course city infill review

Root QA reviews: 20261031-085504-claude and 20261031-085702-claude APPROVE. Capture expectations derive from loop bounds; missing quarters are diagnosed; each overview must frame a frontage and five background pieces. The overview camera was subsequently centred over the road after actual renders exposed a tower intersecting its original lateral position.

The mixed-author ak-review wrapper selected an optional reviewer automatically, then failed locally with Argument list too long before any provider review. No approval resulted. A separate read-only Codex review of the Claude-only seven-file diff found no production defects and one MED test gap: compare actual MultiMesh transforms and deliberately corrupt one to prove detection. That fix is pending the scoped follow-up below.

First-pass actual Vulkan checks: audio46/0, backdrop55/0, 21 captures saved/content/framing checks passed. Ground192/0, city227/0 headless and physical season-course33/0 passed in the delegated run. Its broad test was repeatedly cut off by the tool execution timer, including at the audio heading; this was not an audio assertion failure. Audio was independently rerun in both the baseline and integrated worktree and passes.

Actual images require dimmer backdrop facades/trim so they support the detailed frontage at night. Follow-up: shader/trim exposure only, plus actual-renderer transform comparison and displacement detector. Placement, densities and shared assets stay fixed.

## Final disposition

Independent Codex review round2 found the detector meaningful and requested one initial await _settle() before reading fresh renderer transforms. Root added that exact wait. Both requested MED fixes are now verified: actual 1,438-instance matching, deliberate displacement rejection and restoration pass under Vulkan. No production-code findings or HIGH findings were raised. Review was not submitted for a third round.

The visual follow-up keeps all placement and geometry identical. Body/roof/patch exposure is0.22, trim(0.045,0.043,0.040), sparse window albedo0.3 and emission0.2. Root renamed the exposure constant to BACKDROP_EXPOSURE after the focused run caught a reserved Godot identifier collision; the corrected shader compiles and runs successfully. One-off .ai/backdrop_focus.py was removed; the normal runner remains wired to the dedicated scene.

Final ak-test exit0: backdrop57/0 headless, backdrop60/0 Vulkan, QA0failures/all21captures, audio46/0. All actual-renderer transforms match with zero mismatches. All four route quarters were inspected in actual driver/sidewalk/overview captures. Ground/building source assets, textures/import sidecars, course and vehicle data have no changes in this pass. No new lights or colliders. Delegate worktrees and redundant broad test jobs were cleaned; task branches preserved.

The helper timeout and inherited TEST_CMD issue explain the interrupted broad runs; they are not claimed as a full default-suite pass. No unresolved review findings remain. Final approval of the artistic direction remains the user review of the preview.
