# Weapon attachments and smoke ownership

The detailed standard gun, Helix gun and launcher are Blender-generated candidates in `assets/generated/weapons/`, with runtime GLBs in `godot/assets/items/weapons/`. Rebuild using `ak-blender .ai/blender/build_item_weapons.py`. No asset is promoted to `assets/final/`.

`ItemWeaponMounts` places assemblies in chassis space, facing -Z at end A and +Z at end B. Offsets use the production models rather than the shared physics body dimensions. The attachment base seats approximately 1–2 cm into the measured centerline deck at the chosen longitudinal station. Runtime scale/offset/yaw are included in these measurements.

| Vehicle | Measured deck Y A/B | Mount Z A/B |
|---|---|---|
| Blackjack | 0.106 / 0.743 | -1.55 / 1.50 |
| Deadbolt | 0.526 / 0.675 | -1.55 / 1.50 |
| Nightshift | 0.304 / 0.504 | -1.55 / 1.50 |
| Ramjet | 0.587 / 0.734 | -1.55 / 1.50 |
| Boilerfang | 0.034 / 0.475 | -1.55 / 1.45 |
| Knifeedge | 0.374 / 0.697 | -1.50 / 1.40 |
| Helix | 0.292 / 0.582 | -1.35 / 1.15 |

Projectile origins and firing flashes come from the imported `MuzzleLeft`, `MuzzleRight` and `Muzzle` nodes. A swept ray from the car to the muzzle prevents relocating a projectile across a nearby wall. Straight weapons converge from their elevated sockets onto an eligible target in the existing firing lane, with a bounded lead estimate. Blind rockets settle over 14 m to the original chassis +0.35 m firing plane; collision checks split the descending and level segments, including large timesteps. Homing steering and grenade lob rules are unchanged. Attachments follow the active end and inventory; expired items, recovery and race teardown hide/free them through the existing item lifecycle.

Smoke remains a world hazard for other racers. Its owner does not receive the smoke status or lose targeting through their own trail. Render layer 11 is reserved for solo player smoke cloud meshes and stream particles; the chase camera excludes that layer. Rival smoke stays on layer 1 and still blocks the player, including targeting. This preserves smoke during an end swap without moving the camera or changing its smoothing. A cinematic camera can include layer 11 to inspect the complete trail. A future multiplayer camera would need a separate owner mask per view.

Rendered QA: use `ak-test` with `TEST_CMD` selecting the `item_presentation_qa.tscn` scene and append `-- --helix` for Helix. Captures include both ends with guns and launcher under `.ai/captures/item-effects/<vehicle>/`.

## Validation (2026-10-25)

- Standard `ak-test`: 24 suites, 6,399 passed, 0 failed; no Godot parse/script/engine errors. Includes the three-lap race/retry, all CPU difficulty tiers, surface responses, racecraft, camera, all vehicle adapters, 181 item checks and 860 attachment checks.
- Rendered/audio QA: Helix 42 passed, 0 failed, covering both gun/launcher ends, smoke mesh/particle ownership masks, stereo pickup audio and effect teardown. Blackjack also rendered successfully with both attachment ends. Owner and rival smoke views were inspected visually.
- Blender numeric QA: all three assemblies report zero errors (standard gun 3,452 triangles; Helix gun 4,852; launcher 2,520). A forced-invalid build exits 1 before touching outputs.
- Independent asset and test reviews: APPROVE, no findings in final reports. Runtime review findings are resolved, with HIGH findings fixed and applicability explanations recorded in `.ai/reviews/rebuttal.md`; no additional approval is claimed after the two-round limit.
- Physics, handling tuning, collider geometry, pickup odds, item ammunition and recent stereo/audio changes are preserved. Blind rockets use the bounded launch correction described above.

Delegated: Claude authored the Blender models and independent attachment/smoke tests, supplied smoke/physics diagnoses, and fixed asset review findings. Codex reviewed the asset/test changes independently and integrated runtime changes. Qwen was asked to draft the routine log summary; the authoritative results above are computed directly from the suite summaries.
