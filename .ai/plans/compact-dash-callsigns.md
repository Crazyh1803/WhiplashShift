# Compact translucent dashboard and racer callsigns

User likes the HUD but wants less visual bulk, no advance terrain-change warnings, and cool random CPU callsigns shown on the minimap.

- Make the KITT dashboard roughly25% shorter and noticeably translucent while keeping text/segments readable. Preserve scanner, speed units, boost/bodywork, weapons and map.
- Remove player terrain-transition predictions/advice. Keep corner/braking advice and actual current low-grip/smoke effects. Reclaim route width if useful for named racer markers.
- Assign unique random callsigns to CPU drivers per new match (including Race Again); keep them stable throughout the match and use the same identity in HUD/results and minimap labels/key. Preserve player callsign. No new series mode.
- Put readable names next to minimap markers with bounds and overlap handling; color mapping stable. Test clustered/start-grid positions and long callsigns.

Split: Qwen drafts the name pool; Claude implements UI/layout, identity generation/wiring, tests and rendered QA in an isolated worktree. Codex integrates, inspects captures, runs scoped ak-test, independent ak-review, fixes findings and publishes the preview. No gameplay/AI changes or external dependencies.

Validation: reduced band height and effective alpha, readable 0/112/999 speed and active combat states, no panel overlap; no terrain predictions in real HUD but corner/current hazard advice retained; unique roster excluding player, stable within match, refreshed on retry; all minimap and results names agree; map labels inside viewport with clustered racers. Focused tests and deterministic1280x720 captures with bright road under the translucent dash.
