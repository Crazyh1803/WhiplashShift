# Combat HUD validation

Implemented weapon/ammo/readiness status, timed utility bars, recovering cosmetic bodywork severity, and fading camera-relative attack markers. Shield blocks use blue outlined markers; landed attacks use red filled markers. Readiness includes deployment, queued fire, cooling, active-utility restrictions, and homing lock.

Delegated: Claude implemented the feature and a targeted follow-up in isolated worktrees. Codex independently reviewed Claude's implementation; Claude reviewed the lead's fixture corrections. Reviews returned APPROVE. Medium findings were fixed: the exhausted visual fixture now actually exhausts a weapon, and the homing test now proves an eligible live target returns READY and fires. Low fixture findings were addressed. Review files are intentionally tracked as validation evidence.

Final ak-test coverage:
- Combat HUD: 67 passed.
- Items: 194 passed.
- Weapon attachments: 864 passed.
- Deployment/oil: 88 passed.
- Camera: 12 passed.
- Rendered Forward+ QA at 1280x720: 16 passed; four captures inspected; no errors or shutdown leak warnings in the final run.
- Godot import and git diff --check passed.

The full baseline suite passed before changes. Delegate broad runs were interrupted after duplicate test processes appeared; final validation used the focused integration suites above. No known failing checks remain. No main merge was requested.
