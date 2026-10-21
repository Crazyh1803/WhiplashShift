# Vehicle terrain response — chitin rubble

## Result

GRAVEL now throws dry chipped armor/chitin plates, dark carbon grit and angular
chunks from actual tyre contacts. End B gets restrained debris and subtle body
rattle. Wrong End A throws more/higher/larger pieces and has a much stronger
bounded cosmetic chassis shudder. Dry rubble never sinks the body.

The existing response component remains the single visual-pose writer. It blends
viscera bogging with rubble rattle at mixed-contact seams and selects wet/dry
particles per wheel. Six cached meshes and separate dry/wet materials share the
same 96-live-piece simulation pool. Dry fragments tumble and have one short
visual ground bounce. No dust blanket, glowing debris or tyre-surrounding mesh.
No physical body/collider/wheel transforms, forces, grip/drive coefficients or
camera shake changed. Existing reset/recovery/freeze/model-rebuild hooks apply.

## Validation

- Initial combined headless ak-test: rubble 18 and viscera 25 checks pass.
  `.ai/reports/chitin-rubble-focused.log`.
- Initial combined GPU ak-test: rubble 22 and viscera 29 checks pass. Actual
  CameraRig and AMD Forward+ used. `.ai/reports/chitin-rubble-rendered.log`.
- Full default ak-test: PASS, all 19 scenes, including 73 CPU checks and complete
  physical races; no engine/script errors. `.ai/reports/chitin-rubble-full-test.log`.
- Final cosmetic motion polish removes a master-phase wrap so mixed-frequency
  body oscillation cannot snap between cycles. A new step-continuity regression
  passes. After that polish: rubble 19 and viscera 25 headless checks; rubble 23
  GPU checks pass. `.ai/reports/chitin-rubble-final-checks.log`. The long race
  suite was not repeated after the phase-only visual polish.
- Rubble checks cover frame differences, stationary/spin/airborne gating,
  wet/dry isolation, all dry kinds, shared capacity, dry materials, bounce,
  bounded/continuous shudder, unchanged physical transforms, mixed seams,
  decay/recovery/retry and one combined response controller per car.
- Captured with the same 10 m/s initial speed and 0.8 throttle:
  correct B: 13.95 m/s, no sink, rattle 0.18, 10 live pieces, 70 emitted;
  wrong A: 11.47 m/s, no sink, rattle 1.00, 80 live pieces, 250 emitted.
  These are short rendered fixture observations, not steady-state benchmarks.
- Viscera capture remains B 11.48/A 5.66 m/s and the prior 0.022/0.108 m visual
  sink, with identical emission totals. Approved organic shapes are unchanged.
- Twelve gameplay-camera PNGs per condition and refreshed looping GIFs at
  `.ai/captures/chitin-rubble-response/correct-B.gif` and `wrong-A.gif`.
- git diff --check passes.

## Independent review

Scout/visual/code helpers were attempted. Gemini remains RESOURCE_EXHAUSTED 429;
no independent approval or visual PASS was produced. Final code review log:
`.ai/reviews/chitin-rubble-final-20261021-172803-gemini.md.log`.
Visual log: `.ai/looks/20261021-172140.md.log`.
Architecture escalation returned only an expired OAuth error:
`.ai/escalations/20261021-171526-design-claude.md`.

Changes remain uncommitted. Visual acceptance remains open. Other terrain
responses, audio and accumulated residue are outside this layer.
