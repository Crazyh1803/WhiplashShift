# Complete single-course race — 2026-10-18

Branch: `codex/complete-race-loop` (based on `codex/blackjack-junction`).

Implemented a three-second grid countdown, three complete ordered-checkpoint laps,
player clock/position/wrong-way HUD, finish ordering, results and in-place retry.
R recovers only the player; finished CPUs cannot block the remaining field.
Checkpoint retreats reduce standings, preventing repeated recovery from inflating
race position. Results end the race on player finish and mark remaining rivals
UNFINISHED. Retrying preserves the selected vehicle, paint, callsign and CPU roster.

Validation:
- Full `ak-test`: all 11 suites passed (including original handling, CPU driving,
  vehicle assets and consolidation).
- Final focused race suite via `ak-test`: 37 passed, 0 failed.
- A physical test-only player driver finished three laps in 428.83 seconds,
  position 2, with zero recoveries; a subsequent retry drove successfully for
  another minute with a fresh race clock and progress.
- `git diff --check`: clean.

Independent review: `ak-review codex/blackjack-junction` could not complete.
Gemini returned RESOURCE_EXHAUSTED / individual quota reached (HTTP 429).
No current approval was produced; `.ai/reviews/latest.md` belongs to an older
change and must not be interpreted as approval of this branch.

Headless checks do not validate rendered layout, audio or human driving feel.
Those playtests remain pending while the Nvidia GPU is unavailable.

## Resumed verification — 2026-10-19

- Reconfirmed Codex as code lead and Gemini as the configured reviewer.
- Retried `ak-review codex/blackjack-junction`, then retried with
  `GEMINI_MODEL=gemini-4-argon-high` explicitly selected. Both requests returned
  RESOURCE_EXHAUSTED (HTTP 429), reporting approximately 122 hours until reset.
  The review helper uses Antigravity (`agy`); no separate `gemini` CLI is installed.
  No review approval or findings were produced. The previous approval in
  `.ai/reviews/latest.md` still concerns an older change.
- Re-ran full `ak-test` on the final implementation: all 11 suites passed,
  including all 37 race checks (4,818 checks overall). The physical player again
  finished in 428.83 seconds, position 2, with zero recoveries; physical retry
  also passed. No script errors were reported.
- `git diff --check` passed. No game code changed during this verification.

Remaining: independent Gemini review once this installation's quota is usable,
then address any findings; rendered layout/audio and human driving playtests.
