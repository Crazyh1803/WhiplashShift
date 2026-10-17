# Nightshift regression follow-up

The full suite passes 4,428 checks: core 61, CPU 17, Blackjack refined 670,
Blackjack blueprint 3,555, consolidation 79 and Nightshift 46.

The Blackjack factory test now recognizes Nightshift's dedicated authored adapter.
The CPU integration test pins Blackjack player / Deadbolt and Nightshift opponents,
rather than choosing a random roster on every execution. Gameplay roster selection
remains random and no AI or physics code changes were made.

The first full run randomly selected Boilerfang / Knifeedge. Knifeedge stalled with
26 recoveries and no completed lap. A baseline run using the pre-Nightshift scripts
in the asset worktree with that same roster reproduced both failures. See
nightshift-baseline-knifeedge.log. This existing Knifeedge course-handling weakness
remains outside the Nightshift artwork work. No thresholds were relaxed.
