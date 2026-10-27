# Combat HUD

Goal: native Godot HUD for weapon/ammo readiness, timed utility duration, cosmetic damage, and camera-relative attack direction.

- Claude via ak-delegate: implement compact HUD controls and attack event integration in hud.gd, race_items.gd, and a focused combat_hud control if useful. Add behavioral tests and a deterministic visual QA scene. No generated art, gameplay balance changes, dependencies, or web prototype changes.
- Codex lead: inspect and integrate the result, configure the test suite, run ak-test, inspect rendered HUD samples, address review findings, commit and publish the chat preview.
- Independent review via ak-review after integration.

Validation: HUD covers empty/held/firing/cooling/exhausted states, simultaneous held and active items, timed utility expiry, cosmetic damage recovery, directional hits/blocked hits, camera changes, countdown/results/retry clearing, and readable 1280x720 layout. Existing item, race, camera and vehicle tests remain green.

## Implementation notes (delegate)

- `RaceItems.attack_hit(victim, source_pos, blocked, weapon)` fires from `_apply_hit` for real hits and shield blocks; nothing during `HIT_PROTECTION`/recovery invulnerability. `source_pos` is the attacker's position at impact.
- `CombatHud` (child of `Hud`) holds pure state updated by `update()`; `_draw()` only paints. Weapon panel sits above the terrain cue at bottom right; bodywork bar sits under the boost line at left. Held/active/exhausted states derive from `RaceItems` arrays.
- Indicators store world source positions and recompute their angle from the viewport's current camera every frame, so they follow camera swings/swaps. They live 1.4s and fade linearly; `Hud.camera` overrides the camera for tests.
- Damage shows `Vehicle.damage` (cosmetic, recovering) with wording, never a health value.
- `Hud` clears the combat readout on every race-state change (countdown, racing, results, retry). The old held-item text label is reduced to LOW GRIP / SMOKE flags plus `items.feedback`.
- Tests: `tests/combat_hud_tests.tscn` (registered in `tools/vehicle_pipeline/test_blackjack_refinement.sh`). Visual QA: `tests/combat_hud_visual_qa.tscn` on a rendering display, writes `.ai/captures/combat-hud/*.png`.
