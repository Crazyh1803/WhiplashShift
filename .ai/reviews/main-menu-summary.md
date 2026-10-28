# Main menu review disposition

The UI/data delegate was reviewed by Codex (`main-menu-data-codex.md`); lead integration and subsequent corrections were reviewed by Claude (`20261028-134328-claude.md`, `20261028-135508-claude.md`, `20261028-174514-claude.md`, `20261028-174856-claude.md`). Independent test code was reviewed by Codex (`race-mode-tests-codex.md`). The final lead-code verdict is APPROVE. Historical findings remain as audit records; this disposition records their current status.

## High and medium findings

- Session APIs, season progression, boot/return navigation and CPU setting persistence missing from the isolated data delegate checkout: implemented in the lead checkout. Runtime boot, mode flows, settings round trips, two-race scoring and final standings are covered by the integrated tests.
- Atomic writes: check the FileAccess error after flush, remove only the temporary file on failure and preserve the previous destination.
- Missing test registration: all four new suites are in the default runner; renderer captures are available with --menu-capture.
- Reverse null-course access: return safely to the main menu with a message, disabling physics/key processing before leaving the partially built world. Every currently built course is tested to have a safe reverse grid and to validate in both directions.
- Continue bypass in the original test: a dedicated race fixture now intercepts only scene navigation. Tests execute the production handler twice and verify one commit, one navigation and the next-race destination; a final-round test verifies the standings destination and repeated-final-Continue safety.
- CPU progress assertions before early player finish: the conditional 63-second observation is retained because both supported test cases run longer than that (74.38 and 146.93 seconds). The recorded acceptance run executes all four rival progress/recovery/wrong-way assertions, so no current catalog case skips that coverage. If a shorter circuit or faster test pilot is introduced, this observation window must be revised. Final finite/progress assertions also run for both rivals on every course.

## Low findings and limits

- Pending UI callbacks are guarded to prevent scoring multiple rounds. Roster/caption state is cleared or retained appropriately across retry and completed runs.
- The navigation latch remains set after a successful commit until scene replacement. Releasing it blindly after a hypothetical resource-load failure could double-score the old race. Both scene resources are present and loaded in tests; Escape remains a route to the main menu. A generalized failed-load recovery flow is outside this change.
- The direct legacy garage path still supports profile CPU preferences; normal menu launches preserve the authoritative menu/settings value and never overwrite selected course/laps/direction from a legacy profile. This compatibility behavior is deliberate.
- Headless layout checks passed (740); Vulkan captures passed (776). The layout suite works without requesting screenshots unless --capture is supplied.
- The handler regression intentionally uses private race state and a navigation test seam. It checks the actual production callback and model, rather than duplicating its code.
- Native file-dialog rendering is provided by Godot/Windows. Automated tests exercise selected-file import/export callbacks against scratch files, rather than driving an OS picker. Neither creator link is opened by automated tests; their exact supplied URLs are verified through explicit button callbacks.

No new assets were promoted to assets/final. No Gemini review was requested or run. Custom season definitions persist and can be shared; an in-progress championship is held only for the current application session, as documented in docs/game-modes/main-menu.md.
