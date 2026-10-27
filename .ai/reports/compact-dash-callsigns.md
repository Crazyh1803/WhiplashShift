# Compact translucent dash and match callsigns

Reduced the instrument band from210 to160 logical pixels and lowered the layered background opacity so scenery shows through. Kept speed digits, systems/bodywork, weapon readiness/ammo/timer and course map readable. Removed advance terrain-transition predictions from the HUD; corner guidance and actual low-grip/smoke effects remain.

CPU drivers draw unique random callsigns at match setup and Race Again, excluding the player and avoiding the previous roster when possible. Names stay fixed during the match and agree across CPU readout, results, minimap labels and legend. Clustered labels are bounded, distinct and linked to markers when displaced. Scene node names and chassis IDs are unchanged.

Delegated: Qwen name draft returned null; the lead supplied a reviewed24-name fallback pool. Claude implemented the feature and tests. Independent Codex review approved with no findings. Claude approved the lead's capture redraw/cleanup fixes. Review artifacts are intentionally tracked as validation evidence. The bounded300ms capture teardown delay is intentional for audio/render workers after scene removal, following the project's existing rendered-QA pattern.

ak-test: compact83, dashboard65, driving71, combat67, course cues26, corners25, camera12: 349 passed. Rendered Forward+ compact QA:11 passed, including image comparison against the bare road and clustered named-map captures at1280x720. Verified all36 registered test-scene paths. Godot import, whitespace checks and final rendered shutdown were clean. No open questions.
