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
