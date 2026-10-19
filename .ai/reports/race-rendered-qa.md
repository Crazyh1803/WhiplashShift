# Rendered race-loop checks — 2026-10-19

Added `godot/tests/race_visual_qa.tscn` and its repeatable capture/check script.
No gameplay rules, handling, materials or graphics assets changed.

Renderer: Godot 4.7.2, Vulkan 1.4.354, Forward+, AMD Radeon Graphics
(RADV RENOIR). `nvidia-smi` could not communicate with the Nvidia driver;
these checks do not certify Nvidia rendering or performance.

Rendered verification:
- Countdown, GO, keyboard acceleration, end swap, results, same-roster retry,
  and actual scene transition back to the garage.
- 1600×900 and 1280×720 windows, using the production 1600×900 logical canvas.
  Captures verify actual PNG dimensions, UI bounds and clock/banner separation.
- Engine audio streaming, pitch increasing under acceleration, swap one-shot
  starting. This verifies runtime state, not audible quality.
- Fourteen screenshots under `.ai/captures/race-loop/`. The results captures use
  staged finish progress; they are not evidence of a complete rendered race.
- Fixed a capture-harness startup resize race: apply the requested size after
  the window manager maps the initial window, and assert every capture's size.

Regression verification: full `ak-test` passed all 11 suites / 4,818 checks,
including 37 race checks. The headless physical player completed three full laps
in 428.83 seconds, placed second with zero recoveries, and drove the retry.

Independent review remains blocked: `ak-look` and `ak-review` both returned
RESOURCE_EXHAUSTED (HTTP 429) from Gemini through Antigravity. No visual PASS or
code approval was produced; `.ai/reviews/latest.md` is an older approval.

Remaining acceptance: independent image/code review, human driving and listening
playtest, and Nvidia-specific checks once that device is accessible. Road textures
and extra gameplay systems remain outside this verification change.
