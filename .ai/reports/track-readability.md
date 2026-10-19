# Advance terrain cues — 2026-10-19

Branch: `codex/track-readability`, based on `codex/complete-race-loop`.

Implemented:
- A read-only CourseCues cache built after the configured course is assembled.
  It collapses rumble into the next meaningful terrain change, including across
  the finish seam, and preserves course geometry/checkpoints.
- Paired, collision-free approach boards beyond the rails. Text faces approaching
  traffic and is single-sided. Placement checks all course branches for clearance.
  Warnings lead by up to 80 metres, shortened at closely spaced boundaries.
- A lower HUD cue naming the upcoming surface, remaining distance and end advice.
  Lookahead is four seconds of travel, clamped to 90–200 metres. Advice is hidden
  off-course, going the wrong way, during countdown and on results.
- Mud/gravel recommend B, tarmac A. Ice/oil warn of low grip and advise holding the
  active end, matching existing CPU strategy. No forced swaps, penalties, handling
  changes, new road geometry, textures or changes to CPU driving policy.
- Streamed audio teardown stops the engine, releases its stream and playback,
  and the short capture fixture disposes the scene before letting its mixer finish.

Verification:
- Full `ak-test`: all 12 suites / 4,844 checks passed, including 26 new cue checks,
  the physical three-lap race and retry, CPU driving and all vehicle regressions.
- Focused cue suite after strengthened assertions: 26 passed, 0 failed.
- Rendered mud/ice/tarmac approaches at 1600×900 and 1280×720: correct surfaces
  announced, captions fit above controls, capture dimensions correct. Final verbose
  runs: zero fixture failures, script errors or leaked-object warnings.
- Existing rendered race-loop smoke test: passed countdown, driving, swapping,
  audio state, results, retry and actual garage return after audio teardown changes.
- Rendering used AMD Radeon Vulkan / Forward+. Captures are staged approaches,
  not a human handling test; images live under `.ai/captures/terrain/`.
- `git diff --check` passed.

Independent review is still unavailable. Gemini scout, `ak-look`, and both
`ak-review codex/complete-race-loop` attempts returned quota exhaustion (HTTP 429).
No current visual PASS or code approval was produced. The approval in
`.ai/reviews/latest.md` predates this change. Design and audio-lifetime diagnoses
were obtained read-only through `ak-escalate`; Codex applied the changes.

Remaining: independent image/code review when available and a human playtest of
warning timing/readability. Assess corner/braking cues and swap balance next using
that feedback; final texture work remains a later step.
