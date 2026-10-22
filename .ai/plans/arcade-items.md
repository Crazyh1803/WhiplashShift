# Solo arcade items

Direction: Whiplash is a solo arcade combat racer. No second-player/copilot role is required. Approved first slice: one held item per racer, track pickup rows, one projectile attack, one use button, identical CPU rules.

- Add a race-owned item controller, isolated from vehicle handling and race standings. Track pickup cooldowns, one-item inventory, swept projectile/world collision, brief speed disruption and hit protection. No health, elimination or permanent upgrades.
- Use active-end direction for firing; avoid firing across adjacent track sections and through guardrails. CPUs use the same inventory/projectiles and fire only with a clear opportunity. Lock combat during countdown/results, retire finished racers, clear state on retry/recovery.
- Add readable procedural pickup/projectile/impact visuals, held-item HUD and keyboard control. Keep item visuals code-native in the code lane.
- Add deterministic lifecycle, collision and CPU parity tests and race integration coverage; register via ak-test. Update current Godot documentation and distinguish legacy web prototype.
- Validate with ak-test; obtain independent ak-review and address findings. Existing CPU difficulty changes are pre-existing and must be preserved.
