# CPU overtaking and racecraft

Added a CPU-local corridor planner on top of the existing difficulty work, on `codex/cpu-racecraft`.

- Slower traffic triggers assessment of both passing sides. Decisions account for vehicle dimensions, road width, bends, upcoming surface swaps, occupied corridors, rear closing speed and lateral drift.
- Once committed, the racer holds its chosen side. A blocked passing lane keeps normal traffic braking active; it does not trigger a swerve across the opponent.
- A racer merges only after clearing the opponent and checking the return corridor. Easy waits longer and leaves more clearance; Medium is balanced; Hard commits sooner to safe opportunities.
- Recovery/retry clears stale passing state. Removed, retired and freed opponents are safely ignored. The planner cannot move bodies, alter power/grip or award race progress.

## Validation

- Full `ak-test`: PASS, exit 0, including racecraft, all three difficulty simulations, complete race/retry integration, handling, garage and all seven vehicles. Full output: `.ai/reviews/cpu-racecraft-full-test.log`.
- Final focused `ak-test`: 37 racecraft checks passed, zero failures and no runtime errors. Output: `.ai/last-test.log`.
- Physical tests on Easy, Medium and Hard: each passes a slower moving production-model rival and merges back; zero vehicle contact and zero recovery events, with original power/grip/top-speed multipliers preserved.
- Decision regressions cover both-side obstruction, faster rear traffic, side-by-side holding, an interrupted opportunity, lateral drift, narrow roads, bends, surface changes, wrong-way/swap interruption, retirement, stale references and retry reset.
- The 420-second two-racer benchmark retains at least 5% distance separation per difficulty: Easy 12,722.95 m; Medium 14,425.87 m; Hard 15,215.05 m. Easy/Medium have zero recoveries; Hard has one checkpoint recovery across its two racers. Further swap/traffic tuning can reduce that remaining recovery.
- `git diff --check`: PASS.

## Review status

The required `ak-review codex/corner-guidance` is BLOCKED by Gemini's individual quota (RESOURCE_EXHAUSTED); there is no approval verdict. The scout was likewise unavailable. Changes remain uncommitted pending independent review.

`ak-escalate debug` assessed stale-node handling. Its proposed validity boundary/Variant iteration safeguards were applied and verified with a regression that requires valid traffic to remain actionable when a freed peer appears in the same array.
