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

Headless checks do not validate rendered layout, audio or human driving feel.
Those playtests remain pending while the Nvidia GPU is unavailable.
