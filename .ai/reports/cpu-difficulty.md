# CPU difficulty

Added a saved garage selector for Easy, Medium (default) and Hard. Presets change requested speed, corner preview and traffic following distance; vehicle power, grip, swap momentum and recovery progress rules remain shared.

## Verification

- CPU suite: 55 passed, zero failed. Two fixed-roster rivals per tier run for 420 simulated seconds; every tier completes multiple laps, swaps correctly, brakes for stopped traffic and has zero unforced recoveries.
- Combined distance: Easy 12,722.95 m; Medium 14,425.87 m (+13.4%); Hard 15,623.78 m (+8.3%). The regression requires at least 5% separation between adjacent tiers.
- Garage tests cover selection, saved reload, missing/legacy/invalid profile values and control bounds. The selector reuses the existing CPU panel; descriptions appear as tooltips to keep long vehicle names and navigation inside the viewport.
- Rendered race-loop checks pass at 1600×900 and 1280×720. Garage captures are in `.ai/captures/race-loop/`.
- Full `ak-test`: PASS (exit 0), including the garage layout regression, race loop, handling and all seven vehicles; see `.ai/last-test.log`.

## Review limitation

`ak-review codex/corner-guidance` could not run: Gemini returned RESOURCE_EXHAUSTED (individual quota reached). No independent approval verdict exists. Changes remain uncommitted pending the required review. `ak-scout` and `ak-look` were also unavailable. Automated layout checks pass; visual review remains outstanding.

An `ak-escalate debug` diagnosis identified that the existing speed planner applies the slowest previewed limit immediately. A braking-distance experiment increased recovery events in simulation and was discarded. The final change keeps the existing planner and uses measured pace/preview settings.
