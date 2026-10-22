# Solo arcade items and Games launcher

Implemented on `codex/arcade-items`. Existing uncommitted CPU difficulty/racecraft changes were preserved.

## Player behavior

- Gold rows of three pickups grant one PULSE per racer. Six-second pickup respawn; a full slot leaves pickups available.
- E fires a straight pulse from the active end. Swapping changes firing direction. Same inventory, projectiles and hit rules for CPU racers; CPUs wait briefly and require a clear opportunity.
- A hit removes 25% of horizontal speed, capped at 8 m/s. Two seconds of protection prevent repeated hit disruption. No health, elimination, copilot or second-player requirement.
- Swept ray collision stops pulses on scenery and guardrails. Route proximity prevents hits across distant adjacent course sections. Shots expire after 1.4 seconds.
- Item state appears below the menu. Procedural gold boxes, cyan projectiles, impact flashes and short HUD messages provide feedback.
- Countdown/results block combat. Retry clears state. Recovery clears the recovering racer's item/projectiles and grants protection. CPU recovery signals apply this immediately. Finished owners lose airborne shots. F2 debug freeze also disables those CPU racers' combat.

## Launcher

Installed `~/.local/share/applications/whiplash-shift.desktop`, executable, categorized Game. Main action starts play through Godot; context-menu action opens the project in Godot Editor. Repository sources: `tools/launcher/whiplash-shift` and `tools/launcher/whiplash-shift.desktop`. Launcher resolves the project relative to its executable and supports GODOT_BIN.

## Validation

- Targeted `ak-test`: 23 item checks pass without runtime errors, including real impulse slowdown, swept collisions, wall blocking, CPU use/recovery and lifecycle locks.
- Rendered Vulkan run through `ak-test`: same 23 checks pass; capture `.ai/captures/item-ready.png`.
- Launcher headless startup smoke: exit 0, no errors (`.ai/reports/arcade-launcher-smoke.log`). Desktop entry validates; shell syntax and diff whitespace checks pass.
- Full `ak-test`: PASS (exit 0), all 16 scenes, no engine/script errors. Includes 23 item, 59 CPU, 46 racecraft and 37 race integration checks plus handling, guidance, camera and all seven vehicles. Saved log: `.ai/reviews/arcade-items-full-test.log`.
- Test runner now treats engine/script errors as failures even when Godot exits 0.

## Architecture and independent review

Claude design review recommended the race-owned controller and identified lifecycle/track-section concerns. Addressed immediate CPU recovery signals, effect cleanup at results, repeatable setup, level firing direction and section gating. See `.ai/escalations/20261019-185643-design-claude.md`.

`ak-review HEAD` was attempted with the new files included. Gemini is unavailable due to RESOURCE_EXHAUSTED (429), so no independent approval was obtained. `ak-look` was also quota-blocked; the capture remains available for human visual inspection. See `.ai/reviews/20261019-185833-gemini.md.log` and `.ai/looks/20261019-185851.md.log`. Changes remain uncommitted pending required review.
