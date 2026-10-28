# Season City review record

## Ownership and scoped independent review

- Initial layout / City kit: Claude delegate, independently reviewed by Codex in the delegate worktree (`season-city-layout-codex.md`). APPROVE with a medium request to wire the new test suite into the standard runner. Resolved: the Python runner preserves all 36 previous default scenes and adds both season suites (38 verified scene files).
- Garage / session / catalog / race integration: Codex lead, independently reviewed by Claude (`20261028-124930-claude.md`). APPROVE. Low findings addressed: preserve the saved callsign when the input is blank and give the physical season race a 900 second timeout. Strict engine error detection is retained because a shader compile error can coexist with passing GDScript assertions; no benign error allowlist is needed in passing checks.
- Facade / actual placement follow-up: Claude delegate, independently reviewed by Codex (`season-city-facade-codex.md`). Requested changes for invalid shader constant syntax. Both `:=` declarations were corrected to `=`; headless shader checks and Vulkan rendering then passed.
- Final lead corrections and expanded validation: Claude review (`20261028-125650-claude.md`). APPROVE. The callsign comparison now uses the same normalization as saving. The complete baseline regression list is intentional, all scene paths exist, and the item RNG / reset members are confirmed in RaceItems. Review/escalation records are intentionally tracked as project audit material.

No Gemini call was made. Independent review scopes avoid asking an author to review their own implementation.

## Validation notes

Initial dummy-renderer MultiMesh reads returned identity, producing a misleading 127.5 m minimum scenery clearance. City batches now retain source transforms for headless checks. Tests independently transform primitive bounds corner-by-corner and compare against centreline sampling. Actual minimum clearance is 3.8 m beyond the rail envelope; synthetic near-road cases verify the boundary.

An early unseeded test-only autopilot run did not finish before its time cap, while another completed with no recoveries. Read-only debug escalation recommended instrumenting both progress trackers and making combat rolls reproducible. The acceptance test now seeds and resets items before driving, logs both trackers, and requires a physical three-lap finish, agreement between trackers and a clean retry. No physics or checkpoint logic was changed speculatively. Both the original proving ground and the City course retain ordered-checkpoint and three-lap rule coverage.

Visual inspection uses driver-height views and the actual garage / gameplay camera. The overview alone uses neutral QA lighting; it is not evidence of the race lighting. Detailed scenery is the opening district; the rest remains lighter dressing for layout iteration.

Final layout regression: a new course row increased the dossier height enough to clip Next. A one-line separation change from 6 px to 4 px fixed it; consolidation now passes all 111 checks, the garage capture was visually checked, and Claude approved the correction in `20261028-131412-claude.md`. See `season-city-validation.md` for the complete run accounting.
