# Full-course city infill review

Root QA reviews: 20261031-085504-claude and 20261031-085702-claude APPROVE. Capture expectations derive from loop bounds; missing quarters are diagnosed; each overview must frame a frontage and five background pieces. The overview camera was subsequently centred over the road after actual renders exposed a tower intersecting its original lateral position.

The mixed-author ak-review wrapper selected an optional reviewer automatically, then failed locally with Argument list too long before any provider review. No approval resulted. A separate read-only Codex review of the Claude-only seven-file diff found no production defects and one MED test gap: compare actual MultiMesh transforms and deliberately corrupt one to prove detection. That fix is pending the scoped follow-up below.

First-pass actual Vulkan checks: audio46/0, backdrop55/0, 21 captures saved/content/framing checks passed. Ground192/0, city227/0 headless and physical season-course33/0 passed in the delegated run. Its broad test was repeatedly cut off by the tool execution timer, including at the audio heading; this was not an audio assertion failure. Audio was independently rerun in both the baseline and integrated worktree and passes.

Actual images require dimmer backdrop facades/trim so they support the detailed frontage at night. Follow-up: shader/trim exposure only, plus actual-renderer transform comparison and displacement detector. Placement, densities and shared assets stay fixed.
