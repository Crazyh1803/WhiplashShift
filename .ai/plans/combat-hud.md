# Combat HUD

Goal: native Godot HUD for weapon/ammo readiness, timed utility duration, cosmetic damage, and camera-relative attack direction.

- Claude via ak-delegate: implement compact HUD controls and attack event integration in hud.gd, race_items.gd, and a focused combat_hud control if useful. Add behavioral tests and a deterministic visual QA scene. No generated art, gameplay balance changes, dependencies, or web prototype changes.
- Codex lead: inspect and integrate the result, configure the test suite, run ak-test, inspect rendered HUD samples, address review findings, commit and publish the chat preview.
- Independent review via ak-review after integration.

Validation: HUD covers empty/held/firing/cooling/exhausted states, simultaneous held and active items, timed utility expiry, cosmetic damage recovery, directional hits/blocked hits, camera changes, countdown/results/retry clearing, and readable 1280x720 layout. Existing item, race, camera and vehicle tests remain green.
