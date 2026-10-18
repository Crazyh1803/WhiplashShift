# Complete single-course race

Goal: garage → stationary grid/countdown → three-lap race with two CPUs → player results → same-roster retry or garage. GPU-independent rules and integration tests; visual and handling approval remains pending.

1. Add a small RaceDirector rules object owning countdown, elapsed time, standings and finish order. The driving scene owns player progress and ticks rules after CPU drivers. Disable controls during countdown while suspension settles; freeze entrants at results. Finished CPUs leave the collision field. Results appear on player finish, unfinished rivals marked UNFINISHED; no invented finish times.
2. Integrate in proving_ground, with checkpoint recovery for R during racing, guarded inputs, in-place retry and a start/finish marker. Recoveries never award progress; order unfinished cars by unwrapped route position, deducting checkpoint retreats. Require ordered checkpoints for lap awards. Keep finish order immutable; interpolate crossings within a tick. Exact ties use entrant order.
3. Extend HUD with race status, clock, lap/position, wrong-way cue, results and retry/menu buttons. Retain vehicle diagnostics and swap feedback.
4. Add deterministic rules tests and real scene integration for grid locks, recovery, finish, retry, button wiring and selection retention. Adapt existing CPU/visual fixtures to wait out countdown; add suite to ak-test's existing runner. Run ak-test and ak-review, address findings, update docs.

Scope excludes combat, extra courses, graphics assets, saved records and new handling tuning. R recovers while racing; Enter/button retries after finish. All entrants start behind the finish line and need three complete laps. Spawn offsets must not grant a short first lap.
