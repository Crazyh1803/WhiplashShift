# CPU overtaking and racecraft

- Preserve the existing difficulty work and shared vehicle physics on codex/cpu-racecraft.
- Add a local CPU racecraft planner: choose a clear passing corridor, retain that side while alongside, and merge only after clearance. Check both sides, closing traffic, road edges, bends and impending surface swaps.
- Give Easy more deliberation/space, Medium balanced choices, and Hard earlier commitment with safe clearance.
- Keep normal collision avoidance active while changing lines; cancel/reset stale maneuvers on recovery/retry and swaps.
- Add deterministic traffic decision tests and a real-physics moving-opponent pass fixture. Run targeted ak-test, then full ak-test and ak-review; document unavailable helpers and any unresolved findings.
