# Driving HUD additions

Scope: resume the combat HUD branch with a prominent digital speedometer, saved mph/km/h setting reachable through settings, and a full-course minimap with live racer markers. Keep speed units consistent across the player display, CPU readout, and corner advisories. Preserve race controls and existing combat feedback.

Split:
- Claude via ak-delegate: driving HUD Control, saved speed-unit preference and garage settings UI, Hud integration, focused behavioral tests and rendered QA captures.
- Codex lead: inspect existing damage behavior and visual pipeline, integrate and verify the delegated implementation, inspect rendered layouts at 1280x720, independent review via ak-review, commit and publish.
- Damage presentation: user preference is pending. Existing bodywork damage is cosmetic/recovering; weapon impacts separately apply immediate speed loss. Prefer clearer visible vehicle wear with a compact meter, without adding handling penalties. Any implementation remains code-based and receives separate focused validation.

Validation: 0/known-speed/reverse unit conversion; preferences survive reload and invalid values fall back; settings UI is usable; map fits course aspect ratios, tracks player and opponents, distinguishes player and start/finish, handles reset/results and overlapping positions; no combat/terrain layout overlaps; no new dependencies, generated assets, or gameplay balance changes. Use scoped ak-test runs, avoid duplicate long CPU suites.
