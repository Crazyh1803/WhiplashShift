# Corner and braking guidance

Added cached, distance-smoothed corner detection and a combined terrain/corner
HUD. It identifies left/right bends, tight turns and hairpins, keeps the label
through each bend, and estimates advisory speed and braking lead from current
vehicle/end, grip, mass and brakes. Ice/oil turns show low-grip advice without a
numeric speed. Guidance never changes controls, handling, CPU policy or race
progress. Advisory speeds are conservative centreline estimates, not guarantees.

Design consultation: `.ai/escalations/20261019-115435-design-claude.md`.

Validation:
- `ak-test`: all 14 suites passed, 4,881 checks, including 25 new corner tests.
  Coverage includes direction, hairpins, seam crossings, sampling/noise,
  grip/braking/end changes, read-only behavior and HUD integration.
- Rendered assertion checks: six staged views at 1600×900 and 1280×720 passed,
  covering left/right entry and inside-hairpin guidance with terrain text.
  Captures are under `.ai/captures/corners/`.
- Native 144-FPS-limited frame probe on AMD RADV RENOIR: 865 frames,
  mean 6.944 ms, p95 8.052 ms, p99 8.219 ms; zero repeated interpolated
  position samples. This limited probe shows no return of the previous jitter.
- `git diff --check` passed. Render runs only logged the existing XIM warning.

Independent review remains incomplete. Default Gemini review and `ak-look` hit
HTTP 429 quota exhaustion. A second review using Gemini Flash produced no output
because headless command permission was automatically denied. Neither returned
an approval or findings. No permissions/configuration were changed to bypass it.
The earlier `latest.md` approval belonged to a previous task and does not apply.

Open item: Gemini code review and visual QA once its quota/permissions permit.
