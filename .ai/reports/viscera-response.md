# Vehicle terrain response — viscera, first layer

## Implementation

Each Vehicle now owns one VisceraResponse child. Real per-wheel MUD contact,
active end, speed, throttle and wheelspin drive a bounded organic spray, four wet
contact collars and a smoothed body-only bogging pose. Player and CPU cars use
the same implementation; no other terrain effects are enabled.

At matched inputs End A has a 4.8x per-contact emission coefficient, larger clumps,
higher/outward spray and deeper wet contact collars. Body-only sink is bounded
at 12 cm on A versus 2.5 cm on B, blended by wet-wheel coverage and throttle.
Pitch into the driven end is bounded at 1.5 degrees versus 0.2 degrees. These
are cosmetic signals of the existing handling penalties, not additional forces.
Rigid-body/collider transforms, wheel hardpoints, grip and tuning are unchanged.

A fixed 96-instance world-space MultiMesh pool prevents particle/node growth.
Motionless unspinning tyres do not spray; spinning bogged wheels can churn. Dry/
airborne tyres stop emitting, existing clumps expire and the visual pose eases
back. Freeze, explicit player/CPU recovery, retry and unexpected teleports clear
stale effects. Customization can rebuild the body root without stale offsets.
Local RNG does not consume gameplay randomness. No persistent body residue,
other-terrain responses, sound or handling changes in this layer.

## Verification and previews

- Godot Forward+ rendered successfully on AMD Radeon Graphics (RADV RENOIR),
  Vulkan 1.4.354. NVIDIA's driver probe fails, but AMD rendering is available.
- Focused GPU run: 24 checks passed, zero failures. Covers matched-input response,
  stationary/spinning/airborne/dry/seam behavior, bounded pool, physical transform
  invariance, decay, customization, freeze, teleport and player/CPU retry hooks.
  Log: `.ai/reports/viscera-response-rendered.log`.
- Production Blackjack physically drove both frame configurations on real MUD
  relief with identical initial 10 m/s speed and 0.8 throttle. Final snapshots:
  B 11.48 m/s, sink 0.022 m, 10 live clumps, 50 emitted;
  A 5.66 m/s, sink 0.108 m, 53 live clumps, 146 emitted.
  These are rendered fixture observations, not steady-state handling benchmarks.
- Twelve PNG frames per condition plus looping GIF previews in
  `.ai/captures/viscera-response/correct-B.gif` and `wrong-A.gif`.
  Animated previews assembled from actual GPU captures using bundled Pillow;
  the model did not visually inspect screenshots, per the project instructions.
- New scene `viscera_response_tests` added to the full ak-test harness.
- Full ak-test: PASS (exit 0), all 18 scenes, including 22 headless response
  checks and 73 CPU checks; no engine/script errors.
  Log: `.ai/reports/viscera-response-full-test.log`.
- git diff --check: pass.

## Independent review limitations

ak-escalate design failed because Claude OAuth authentication expired:
`.ai/escalations/20261021-153815-design-claude.md`. No design advice was returned.
The implementation follows the written plan in `.ai/plans/viscera-response.md`.

ak-review used an isolated pre-task baseline so unrelated pending branch work
was excluded. Code review and ak-look both failed because Gemini remains
RESOURCE_EXHAUSTED (429). Logs:
`.ai/reviews/viscera-response-20261021-154618-gemini.md.log` and
`.ai/looks/20261021-154618.md.log`. No independent approval or visual PASS is
claimed. Changes remain uncommitted; aesthetic acceptance is still open.
