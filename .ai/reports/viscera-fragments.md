# Viscera anatomical fragment mix

Replaced the uniform sphere clump with three cached code-native meshes: closed
folded tissue shreds (55%), thin curved entrails with recessed dark cut ends
(35%), and small jointed appendage fragments with exposed pale bone (10%). Each
piece has independently seeded initial orientation and angular motion. Geometry
encodes muscle, cut, fatty and bone color accents; neutral instance tints retain
those details. Wet clearcoat/specular response adds local highlights.

The three MultiMesh batches share the existing 96-live-piece simulation pool.
Smaller shreds/jointed pieces and narrow cords keep scale appropriate to the
vehicle. Gravity, spawn/contact rules, emission coefficients, wrong-end bogging,
reset behavior and all handling remain unchanged. No tyre-surrounding meshes,
new colliders, authored art assets or other-terrain effects were introduced.

Verification:
- Focused headless ak-test: 25 passed, 0 failed.
  `.ai/reports/viscera-fragments-focused.log`.
- AMD Forward+ gameplay-camera ak-test: 29 passed, 0 failed; no engine/script
  errors. `.ai/reports/viscera-fragments-rendered.log`.
- New checks cover all fragment kinds appearing over a sequence, shared live
  budget across batches, nondegenerate geometry/triangle budgets and a narrow
  elongated entrail silhouette. Existing no-hover, physics-invariance and
  lifecycle checks continue to pass. Initial silhouette check caught excessive
  lateral width in the entrail curve; the curve was narrowed before final checks.
- Captured performance remains B 11.48 m/s, 0.022 m visual sink, 50 emitted;
  A 5.66 m/s, 0.108 m sink, 146 emitted. New live counts are B 8, A 37.
- Actual CameraRig captures and looping GIFs in
  `.ai/captures/viscera-fragments-chase/` (`correct-B.gif`, `wrong-A.gif`).
- git diff --check passes. This mesh/appearance-only revision ran focused and
  rendered checks; the long full-race suite was not repeated.

Independent ak-review and ak-look failed due to Gemini's exhausted individual
quota (RESOURCE_EXHAUSTED 429). Logs:
`.ai/reviews/viscera-fragments-20261021-170045-gemini.md.log` and
`.ai/looks/20261021-170045.md.log`. No independent approval or visual PASS was
produced. Changes remain uncommitted and aesthetic acceptance is open.
