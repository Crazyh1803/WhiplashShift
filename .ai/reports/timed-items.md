# Timed random arcade items

## Behavior

Gold pickups now give one weighted-random item. E activates once. The slot stays occupied during the active timer; no repeated presses or holding E are needed.

| Item | Chance | Duration | Behavior |
|---|---:|---:|---|
| Shield | 20% | 5 s | Blocks all weapon hits and oil throughout the timer |
| Machine guns | 24% | 6 s | Fires every 0.15 s |
| Rockets | 18% | 5 s | Explosive rocket every 1 s |
| Grenades | 12% | 6 s | Arcing grenade every 1.2 s; 1.5 s fuse or impact explosion |
| Smoke screen | 13% | 5 s | Drops a 5 s cloud every 0.5 s |
| Oil slick | 12% | 5 s | Drops a 7 s patch every 0.65 s |
| Homing missile | 1% | One shot | Locks visible racer ahead, steers gradually, expires after 3.5 s |

Homing without a visible target remains held. It never retargets. Smoke obscures sight, CPU target selection and missile guidance. Oil reduces whole-car grip to 35% and lingers 1.2 s after leaving the patch. Shield clears oil. Items use the active end for firing and the opposite direction for drops, so swaps redirect subsequent emissions.

Hits remove a bounded amount of speed with 0.4 s hit protection; no health or elimination. Scenery stops projectiles and blast propagation. Route proximity rejects hits and targets on distant adjacent track sections. CPUs use the same inventory, weights, timers and projectiles. Emissions are capped per tick to avoid long-frame barrages; hazards have a global count cap.

HUD shows held item/E prompt or active name/countdown, plus smoke and low-grip status. Procedural translucent shield, clouds, flat oil patches and colored projectiles use no new external assets. The existing Games launcher opens the updated game.

## Architecture and lifecycle

ItemCatalog owns labels, weights and timing. RaceItems owns active/held state, projectiles, hazards and protection. Vehicle adds a bounded, temporary item_grip_multiplier in the existing tyre friction calculation; persistent tuning and spec grip are unchanged.

Countdown/results, retry, recovery, finishing, debug freezes, repeat setup and scene exit clear the appropriate timers, objects and grip effects. Recovery also clears owned deployed hazards; finish/CPU freeze removes them on the next combat tick. A shield lasts its full time rather than disappearing after one hit.

Claude architecture advice covered keeping oil separate from persistent grip, deterministic swept collision/blast visibility and explicit cleanup. See `.ai/escalations/20261019-202622-design-claude.md`.

## Verification

- Focused ak-test: 59 checks pass, including exact weighted odds, automatic cadence, expiry, large-tick cap, all seven behaviors, real speed-loss impulse, wall-blocked explosions, smoke lock denial, oil cleanup, CPU parity and lifecycle reset.
- Rendered Vulkan ak-test: same 59 checks pass. Seven captures: `.ai/captures/timed-*.png`.
- Full ak-test: PASS (exit 0), all 16 scenes, no engine/script errors. Includes 59 item, 59 CPU, 46 racecraft and 37 race checks plus all vehicle, handling, camera and guidance regressions. Log: `.ai/reviews/timed-items-full-test.log`.
- Diff whitespace check passes.

## Review status

ak-review HEAD and ak-look were attempted. Both Gemini calls failed with RESOURCE_EXHAUSTED (429). No independent approval or completed visual QA is claimed. See `.ai/reviews/20261019-203058-gemini.md.log` and `.ai/looks/20261019-203115.md.log`. Changes remain uncommitted.

Work continues on codex/timed-items, preserving all pending CPU, initial item and launcher changes. An empty branch ref from interrupted creation was restored to the verified previous branch commit without changing the index or working files.
