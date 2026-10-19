# Driving jitter — 2026-10-19

Branch: `codex/smooth-driving`, based on `codex/track-readability`.

The real-time probe reproduced discrete vehicle positions between 120 Hz physics
updates. Physics interpolation was disabled and the frame-driven chase camera
sampled the raw physical pose for both following and aiming.

Changes:
- Enable built-in physics interpolation, preserving the 120 Hz simulation.
- Sample one interpolated vehicle pose per camera frame for position, heading,
  lookahead and aim; opt the camera branch out of double interpolation.
- Reset interpolation after player/CPU placements. Recovery and retry reset the
  camera at the destination. Swap orbit and snap modes remain available.
- Opt garage vehicles and their orbit camera out of interpolation because their
  transforms are changed directly by frame-driven UI input.
- Add camera regression tests and a real-time frame probe with a process-local
  interpolation-off control. Saved project settings are not changed by controls.

Controlled comparison: same AMD Radeon Graphics (RADV RENOIR), Forward+, same
Blackjack player/two CPU scene, 144 FPS cap. Measure seconds 1–7 of acceleration
after countdown; 865 rendered position samples per run, no `--fixed-fps`.

| Metric | Interpolation off | Interpolation on |
|---|---:|---:|
| Repeated rendered position samples | 16.65% | 0.00% |
| Frame interval, mean | 6.944 ms | 6.944 ms |
| Frame interval, p95 | 8.334 ms | 8.264 ms |
| Rendered step-speed standard deviation | 11.939 m/s | 8.536 m/s |

Repeated position means measured rendered-origin speed below 0.001 m/s during the
moving window. Step-speed variance also includes normal acceleration; it is not
a perceptual stutter score. Frame time remained similar while motion continuity
improved. JSON receipts are in `.ai/captures/smooth-driving/control144.json` and
`smooth144.json`. Uncapped before/after probes are also saved there.

Verification:
- Full `ak-test`: all 13 suites / 4,856 checks passed, including 12 new camera
  checks, original handling/momentum, CPU racing, complete race/retry and vehicles.
- Rendered race smoke test passed countdown, driving, swap, streaming audio,
  results, retry and actual garage return.
- Camera tests compare aim against the interpolated pose, exercise distinct
  physical/rendered poses, and check resets after the next render-cache update.
- `git diff --check` passed.

Independent review: `ak-review codex/track-readability` and framing `ak-look`
failed with Gemini quota exhaustion (HTTP 429). No approval was produced; the
older `.ai/reviews/latest.md` is not approval of this change. A read-only diagnosis
was obtained with `ak-escalate`; Codex applied and tested the implementation.

Remaining: human comparison on the user's display and independent code/framing
review when available. These measurements isolate temporal sampling in this run;
they do not rule out occasional driver or frame-time stalls elsewhere.

API guidance: [Godot manual camera interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html)
and [physics interpolation/reset setup](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html).
