# Timed random arcade items

Approved direction: one random held item. E activates it once; offensive items auto-fire for a fixed window, smoke/oil auto-deploy behind the active end, shield protects for its full timer. Rare homing missile fires once.

- Add a small data catalog for seven items, durations, cadence, projectile behavior and weighted odds (homing 1%). No inventory stacking or second-player role.
- Extend the race-owned controller with held/active/timer state, automatic emission, timed shielding, swept projectiles, bounded homing, grenade explosions, smoke clouds and oil patches. Terrain remains authoritative; oil applies a bounded temporary grip multiplier, restored on expiry/recovery/finish/retry/scene exit.
- All racers share item odds, activation/expiry and hit rules. CPUs activate attacks with an opportunity and defensive items during racing. E never needs to be held or repeatedly pressed.
- HUD shows held item or active countdown and status effects. Distinct procedural visuals. Projectiles/explosions respect scenery; no permanent damage or elimination.
- Replace pulse-only item tests with deterministic coverage for random boundaries/rarity, timing, repeated emission, all seven item behaviors, collisions and complete lifecycle cleanup. Run ak-test and rendered checks, request ak-review and ak-look.
- Preserve pending CPU, first-item and launcher changes. Branch remains uncommitted while required independent review is unavailable.
