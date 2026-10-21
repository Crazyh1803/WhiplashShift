# Viscera: remove tyre hover-disc appearance

Removed the persistent four wet contact ellipsoids, which surrounded each tyre
and read as hover platforms from the driving camera. The fixed 96-clump pool
now mixes small short-lived low ejecta with the existing taller thrown spray.
All fragments move independently and expire; no tyre-surrounding geometry remains.
Wrong-end spray intensity and bounded body-only bogging are retained unchanged.
No handling, collider, wheel hardpoint, camera gameplay or lifecycle changes.

The capture fixture now uses the actual CameraRig, including the 72-degree FOV,
normal 4.2 m chase height, speed-adjusted distance and follow behavior. The prior
diagonal showcase camera did not expose the reported problem well enough.

Verification:
- Focused headless ak-test: 22 passed, zero failures.
  `.ai/reports/viscera-chase-focused.log`.
- AMD Forward+ GPU ak-test: 26 passed, zero failures, no shader/script errors.
  `.ai/reports/viscera-chase-rendered.log`.
- Regression check: stationary wet tyres produce no standing effect geometry.
- Actual captures retain the prior speeds/visual sink: B 11.48 m/s, 0.022 m;
  A 5.66 m/s, 0.108 m. Live clumps: B 6, A 37.
- Gameplay-angle PNG sequences and animated previews in
  `.ai/captures/viscera-response-chase/` (`correct-B.gif`, `wrong-A.gif`).
- git diff --check passes. The full 18-scene suite passed immediately before
  this visual-only correction; this correction ran focused contact/lifecycle/
  physical-invariance checks and GPU captures rather than repeating long races.

ak-review and ak-look were attempted with only this task's diff/captures. Both
failed due to Gemini's individual quota (RESOURCE_EXHAUSTED 429). Logs:
`.ai/reviews/viscera-chase-20261021-165245-gemini.md.log` and
`.ai/looks/20261021-165245.md.log`. No new independent verdict or visual PASS.
Changes remain uncommitted; visual acceptance is still open to the user.
